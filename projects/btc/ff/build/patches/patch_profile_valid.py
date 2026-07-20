#!/usr/bin/env python3
"""
patch_profile_valid.py — Diagnose + fix the "failed to update app profile"
grant rejection on POCO X2 (CAF 4.14, KSU Next v3.3.0 legacy, CONFIG_KSU_DISABLE_POLICY=y).

ROOT CAUSE (verified by source trace):
  When the KSU Manager grants an app root, it issues the SET_APP_PROFILE
  supercall (dispatch.c:do_set_app_profile -> ksu_set_app_profile). The very
  first gate in ksu_set_app_profile is profile_valid() (allowlist.c:158).

  Under CONFIG_KSU_DISABLE_POLICY=y, every *substantive* check inside
  profile_valid() is already compiled out behind
  `#ifndef CONFIG_KSU_DISABLE_POLICY` EXCEPT the version check:

      if (profile->version != KSU_APP_PROFILE_VER) {        // allowlist.c:166
          pr_info("Unsupported profile version: %d\n", ...);
          return false;
      }

  And ksu_set_app_profile(), immediately after profile_valid() succeeds,
  DISCARDS the entire profile under DISABLE_POLICY:

      #ifdef CONFIG_KSU_DISABLE_POLICY
          if (profile->allow_su) {
              profile->rp_config.use_default = true;
              memset(profile->rp_config.template_name, 0, ...);
              memset(&profile->rp_config.profile, 0, ...);
          } else { ... nrp_config cleared ... }
      #endif

  So the `version` field is NEVER consumed under DISABLE_POLICY — the kernel
  never reads it, the grant always uses default_root_profile. Enforcing an
  exact version match there is therefore meaningless, yet it is the ONLY check
  left that can reject a live grant. If the Manager APK transmits a version
  other than the kernel's KSU_APP_PROFILE_VER (4 on legacy; the Manager v3.3.0
  APK was published 2026-07-03, two days BEFORE the legacy uapi sync that
  carried the bump on 2026-07-05), profile_valid() returns false ->
  ksu_set_app_profile() returns -EINVAL -> the Manager shows
  "failed to update app profile for <app>". That is precisely the symptom.

TWO-PART FIX (rigorous: fix + proof):
  1. GATE the version check behind `#ifndef CONFIG_KSU_DISABLE_POLICY`, exactly
     mirroring the already-gated groups_count/selinux_domain checks. Under
     DISABLE_POLICY the version field is never used, so this is semantically
     correct and removes the only rejection path for live grants.
  2. INSTRUMENT profile_valid() + ksu_set_app_profile() with a persistent
     file-logger (TWRP-readable at /data/adb/ksu/ksun_diag.log) so the EXACT
     version the Manager sends, the kernel's expected version, and the precise
     rejection branch are captured and survive a reboot. This gives ground
     truth regardless of which check fired.

  The logger is DEBUG-ONLY: it never changes functional logic, writes at most
  a few lines per grant attempt, and no-ops safely if /data is unmounted
  (early boot) since filp_open failing just skips the write.

Usage:
  python3 patch_profile_valid.py [path/to/policy/allowlist.c]
"""

import sys
import os

MARKER = "KSUN_PROFILE_DIAG"

ALLOWLIST_C_PATH = "KernelSU-Next/kernel/policy/allowlist.c"

HELPER_BLOCK = r'''/* ''' + MARKER + r''' */
#include <linux/fs.h>
#include <linux/err.h>
#include <linux/cred.h>
#include <linux/string.h>
#include <linux/types.h>

/* ksu_cred + ksu_manager_appid are provided by the KSU core.
 *   - ksu_cred is `extern struct cred* ksu_cred;` in kernel/include/ksu.h
 *     (NON-const). We MUST match that exactly, or the build fails with a
 *     "conflicting types for 'ksu_cred'" error (a const-qualified extern
 *     redeclaration of a non-const symbol is a hard conflict).
 *   - ksu_manager_appid is `extern uid_t` in manager/manager_identity.h, which
 *     allowlist.c already includes (line 30) — match that type too. */
extern struct cred *ksu_cred;
extern uid_t ksu_manager_appid;

/* Non-variadic: avoids <stdarg.h> (absent on CAF 4.14 in the usual place) and
 * any va_list portability pitfalls. Callers snprintf into a local buffer. */
static void ksu_profile_diag_log(const char *msg)
{
	struct file *fp;
	loff_t pos = 0;
	const struct cred *saved;

	saved = override_creds(ksu_cred);
	fp = filp_open("/data/adb/ksu/ksun_diag.log",
			O_WRONLY | O_CREAT | O_APPEND, 0644);
	if (!IS_ERR(fp)) {
		vfs_llseek(fp, 0, SEEK_END);
		kernel_write(fp, msg, strlen(msg), &pos);
		filp_close(fp, NULL);
	}
	revert_creds(saved);
}
/* end ''' + MARKER + r''' */
'''

# Injected at the very top of profile_valid(), before any check — captures the
# received vs expected version every time the Manager sends a profile. This is
# the definitive "what version did the Manager transmit" signal.
PROFILE_VALID_ENTRY = (
    '\t{\n'
    '\t\tchar _pdbuf[160];\n'
    '\t\tsnprintf(_pdbuf, sizeof(_pdbuf),\n'
    '\t\t\t"KSU_DIAG profile_valid: key=%s uid=%d allow_su=%d '
    'recv_version=%d expected_ver=%d\\n",\n'
    '\t\t\tprofile->key, (int)profile->current_uid,\n'
    '\t\t\t(int)profile->allow_su, (int)profile->version,\n'
    '\t\t\t(int)KSU_APP_PROFILE_VER);\n'
    '\t\tksu_profile_diag_log(_pdbuf);\n'
    '\t}\n'
)

# Injected at the rejection point of ksu_set_app_profile() (right after the
# profile_valid() failure check) so we also catch the -EINVAL return even if
# profile_valid()'s internal log is skipped.
SET_APP_PROFILE_REJECT = (
    '\t{\n'
    '\t\tchar _pdbuf[160];\n'
    '\t\tsnprintf(_pdbuf, sizeof(_pdbuf),\n'
    '\t\t\t"KSU_DIAG set_app_profile_rejected: key=%s uid=%d '
    'recv_version=%d expected_ver=%d\\n",\n'
    '\t\t\tprofile->key, (int)profile->current_uid,\n'
    '\t\t\t(int)profile->version, (int)KSU_APP_PROFILE_VER);\n'
    '\t\tksu_profile_diag_log(_pdbuf);\n'
    '\t}\n'
)


def find_file():
    candidates = [
        "KernelSU-Next/kernel/policy/allowlist.c",
        "kernel/policy/allowlist.c",
        "drivers/kernelsu/policy/allowlist.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def patch(path):
    with open(path) as f:
        content = f.read()

    if MARKER in content:
        print("OK: profile diag already present — skipping")
        return True

    # ── 1. helper after last #include ──
    lines = content.splitlines(keepends=True)
    ins_idx = None
    for i, line in enumerate(lines):
        if line.strip().startswith("#include"):
            ins_idx = i
    if ins_idx is None:
        print("ERROR: no #include in %s" % path)
        return False
    lines.insert(ins_idx + 1, HELPER_BLOCK)
    content = "".join(lines)
    lines = content.splitlines(keepends=True)

    # ── 2. instrument profile_valid() entry ──
    pv_idx = None
    for i, line in enumerate(lines):
        if line.strip().startswith("static bool profile_valid("):
            pv_idx = i
            break
    if pv_idx is None:
        print("ERROR: profile_valid() not found")
        return False
    brace = None
    for i in range(pv_idx, min(pv_idx + 8, len(lines))):
        if "{" in lines[i]:
            brace = i
            break
    if brace is None:
        print("ERROR: no brace in profile_valid")
        return False
    lines.insert(brace + 1, PROFILE_VALID_ENTRY)

    content = "".join(lines)
    lines = content.splitlines(keepends=True)

    # ── 3. GATE the version check behind #ifndef CONFIG_KSU_DISABLE_POLICY ──
    # Find the exact block:
    #   \tif (profile->version != KSU_APP_PROFILE_VER) {
    #   \t\tpr_info("Unsupported profile version: %d\n", profile->version);
    #   \t\treturn false;
    #   \t}
    ver_if = None
    for i, line in enumerate(lines):
        if "if (profile->version != KSU_APP_PROFILE_VER)" in line:
            ver_if = i
            break
    if ver_if is None:
        print("ERROR: version-check block not found in profile_valid")
        return False
    # The block is 4 lines: if / pr_info / return / closing brace. Find the
    # closing brace line (the first '}' at the same indent as the 'if').
    end = None
    for i in range(ver_if, min(ver_if + 6, len(lines))):
        if lines[i].rstrip() == "\t}":
            end = i
            break
    if end is None:
        print("ERROR: closing brace of version-check block not found")
        return False
    gated = (
        "#ifndef CONFIG_KSU_DISABLE_POLICY\n"
        + "".join(lines[ver_if:end + 1])
        + "#endif\n"
    )
    lines[ver_if:end + 1] = [gated]
    # normalize the list back to lines (the replacement is a single string)
    content = "".join(lines)
    lines = content.splitlines(keepends=True)

    # ── 4. instrument ksu_set_app_profile() rejection point ──
    sap_idx = None
    for i, line in enumerate(lines):
        if line.strip().startswith("int ksu_set_app_profile("):
            sap_idx = i
            break
    if sap_idx is None:
        print("ERROR: ksu_set_app_profile() not found")
        return False
    # Locate the rejection: `if (!profile_valid(profile)) {` ... the pr_err
    # "Failed to set app profile: invalid profile!" line.
    rej = None
    for i in range(sap_idx, min(sap_idx + 20, len(lines))):
        if 'Failed to set app profile: invalid profile!' in lines[i]:
            rej = i
            break
    if rej is None:
        print("ERROR: rejection pr_err not found in ksu_set_app_profile")
        return False
    # Insert the diag log right before the pr_err line.
    lines.insert(rej, SET_APP_PROFILE_REJECT)

    new = "".join(lines)
    with open(path, "w") as f:
        f.write(new)

    if (MARKER in new and "KSU_DIAG profile_valid" in new
            and "KSU_DIAG set_app_profile_rejected" in new
            and "#ifndef CONFIG_KSU_DISABLE_POLICY\n\tif (profile->version"
            in new):
        print("OK: instrumented profile_valid + gated version check")
        return True
    print("ERROR: profile_valid insertion incomplete")
    return False


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0] if args else find_file()
    if not path or not os.path.exists(path):
        print("ERROR: allowlist.c not found at %s" % (path or "(none)"))
        sys.exit(1)
    if not patch(path):
        sys.exit(1)
