#!/usr/bin/env python3
"""
patch_manager_diag.py — Kernel-side persistent-logger for the [ksu_driver]
manager-fd delivery path (task #132 diagnostics).

WHY A FILE LOGGER (not just pr_info):
  On POCO X2 (CAF 4.14) this kernel has no ramoops, so /proc/last_kmsg is
  empty, and the booted ROM's adb is unprivileged (uid 2000) so we cannot read
  the live ring buffer. The only place we CAN read kernel runtime state is
  TWRP recovery (adb = root) with /data mounted. So we append a few key events
  to a file under /data/adb/ksu/ that survives reboot and is readable from TWRP.

WHAT IT LOGS (setuid_hook.c):
  1. ksu_handle_setresuid(): when is_uid_manager(new_uid) is TRUE — the exact
     moment the manager-fd install decision is made. Logs new_uid, the current
     ksu_manager_appid, and whether the task_work was queued.
  2. ksu_install_manager_fd_tw_func(): after ksu_install_fd() succeeds — confirms
     the [ksu_driver] fd actually landed in the manager process (pid).

This is a DEBUG-ONLY instrument. It never changes functional logic and writes
at most a handful of lines per boot (only on manager-uid setresuid events).

Safety:
  - Runs in process context (syscall handler / task_work at resume) — safe for
    filp_open + kernel_write.
  - Writes with ksu_cred (root) overridden so it can create the file under the
    0700 /data/adb/ksu dir. If /data is not yet mounted (early boot), filp_open
    fails and we simply skip — no crash, no block.
  - O_APPEND|O_CREAT, 0644. Idempotent via a unique marker.

Usage:
  python3 patch_manager_diag.py [path/to/hook/setuid_hook.c]
"""

import sys
import os

MARKER = "KSUN_MANAGER_DIAG"

HELPER_BLOCK = r'''/* ''' + MARKER + r''' */
#include <linux/fs.h>
#include <linux/err.h>
#include <linux/cred.h>
#include <linux/string.h>
#include <linux/types.h>

/* Provided by the KSU core; declared here so this debug patch does not
 * depend on setuid_hook.c's specific include set. NOTE: ksu_manager_appid is
 * a uid_t (unsigned int on arm64), NOT int — the kernel's own declaration is
 * in manager/manager_identity.h, so we must match that type or the build
 * fails with "conflicting types for 'ksu_manager_appid'". */
extern const struct cred *ksu_cred;
extern uid_t ksu_manager_appid;

/* Non-variadic on purpose: avoids pulling <stdarg.h> (absent on CAF 4.14 in
 * the usual place) and any va_list portability pitfalls. Callers snprintf into
 * a local buffer and pass the finished line. */
static void ksu_manager_diag_log(const char *msg)
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

# Injected at the top of the manager branch, right after the
# `if (unlikely(is_uid_manager(new_uid)))` opening brace.
MANAGER_BRANCH_LOG = (
    '\t\t{\n'
    '\t\t\tchar _kdbuf[128];\n'
    '\t\t\tsnprintf(_kdbuf, sizeof(_kdbuf),\n'
    '\t\t\t\t"KSU_DIAG setresuid->manager: new_uid=%d appid=%d '
    'task_work_queued=1\\n",\n'
    '\t\t\t\t(int)new_uid, (int)ksu_manager_appid);\n'
    '\t\t\tksu_manager_diag_log(_kdbuf);\n'
    '\t\t}\n'
)

# Injected at the end of ksu_install_manager_fd_tw_func, after ksu_install_fd().
TASKWORK_LOG = (
    '\t{\n'
    '\t\tchar _kdbuf[128];\n'
    '\t\tsnprintf(_kdbuf, sizeof(_kdbuf),\n'
    '\t\t\t"KSU_DIAG fd_installed: pid=%d appid=%d\\n",\n'
    '\t\t\tcurrent->pid, (int)ksu_manager_appid);\n'
    '\t\tksu_manager_diag_log(_kdbuf);\n'
    '\t}\n'
)

# ── supercall.c (reboot-magic install path) ──
# Injected in the KSU_INSTALL_MAGIC2 branch, AFTER ksu_install_fd() returns,
# so we capture the actual fd value that landed in the caller. fd >= 0 means
# the [ksu_driver] fd was successfully installed into the calling process
# (the Manager). This is the definitive "did the fd land" signal.
SUPERCALL_BRANCH_LOG = (
    '\t{\n'
    '\t\tchar _kdbuf[128];\n'
    '\t\tsnprintf(_kdbuf, sizeof(_kdbuf),\n'
    '\t\t\t"KSU_DIAG reboot_install: pid=%d caller_uid=%d appid=%d '
    'fd=%d\\n",\n'
    '\t\t\tcurrent->pid, (int)current_uid().val, (int)ksu_manager_appid, fd);\n'
    '\t\tksu_manager_diag_log(_kdbuf);\n'
    '\t}\n'
)

# Injected in ksu_handle_sys_reboot entry: log EVERY reboot-magic call (any
# magic2) with pid + caller uid, so we see all Manager/libkernelsu supercalls.
SUPERCALL_ENTRY_LOG = (
    '\t{\n'
    '\t\tchar _kdbuf[128];\n'
    '\t\tsnprintf(_kdbuf, sizeof(_kdbuf),\n'
    '\t\t\t"KSU_DIAG reboot_magic: pid=%d caller_uid=%d magic1=0x%x '
    'magic2=0x%x\\n",\n'
    '\t\t\tcurrent->pid, (int)current_uid().val, magic1, magic2);\n'
    '\t\tksu_manager_diag_log(_kdbuf);\n'
    '\t}\n'
)


def find_file():
    # Prefer the path the Kbuild actually compiles (drivers/kernelsu/...).
    # On this build drivers/kernelsu is a symlink -> KernelSU-Next/kernel, so
    # either resolves to the same inode, but preferring drivers/kernelsu avoids
    # editing a decoy copy if setup ever materialises it as a real directory.
    candidates = [
        "drivers/kernelsu/hook/setuid_hook.c",
        "KernelSU-Next/kernel/hook/setuid_hook.c",
        "kernel/hook/setuid_hook.c",
        "drivers/kernelsu/supercall/supercall.c",
        "KernelSU-Next/kernel/supercall/supercall.c",
        "kernel/supercall/supercall.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def patch(path):
    with open(path) as f:
        content = f.read()

    if MARKER in content:
        print("OK: manager diag already present — skipping")
        return True

    base = os.path.basename(path)
    if base == "supercall.c":
        return patch_supercall(path, content)
    return patch_setuid_hook(path, content)


def patch_supercall(path, content):
    """Instrument the reboot-magic [ksu_driver] fd-install path with the file
    logger (the path that actually delivers a surviving fd in a running app)."""
    lines = content.splitlines(keepends=True)

    # ── 1. helper after last #include ──
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

    # ── 2. entry log (every reboot magic) ──
    entry_idx = None
    for i, line in enumerate(lines):
        if line.strip().startswith("int ksu_handle_sys_reboot("):
            entry_idx = i
            break
    if entry_idx is None:
        print("ERROR: ksu_handle_sys_reboot not found")
        return False
    brace = None
    for i in range(entry_idx, min(entry_idx + 15, len(lines))):
        if "{" in lines[i]:
            brace = i
            break
    if brace is None:
        print("ERROR: no brace in ksu_handle_sys_reboot")
        return False
    lines.insert(brace + 1, SUPERCALL_ENTRY_LOG)

    content = "".join(lines)
    lines = content.splitlines(keepends=True)

    # ── 3. install-branch log (KSU_INSTALL_MAGIC2) AFTER ksu_install_fd() ──
    # NOTE: the log line references `fd`, which is declared by the
    # `int fd = ksu_install_fd();` call. So we MUST insert it *after* that
    # call (not before), or the build fails with "fd undeclared".
    inst_branch = None
    for i, line in enumerate(lines):
        if "magic2 == KSU_INSTALL_MAGIC2" in line:
            inst_branch = i
            break
    if inst_branch is None:
        print("ERROR: KSU_INSTALL_MAGIC2 branch not found")
        return False
    # find the ksu_install_fd() call (the `int fd = ksu_install_fd();` line)
    fd_call = None
    for i in range(inst_branch, min(inst_branch + 20, len(lines))):
        if "ksu_install_fd()" in lines[i]:
            fd_call = i
            break
    if fd_call is None:
        print("ERROR: ksu_install_fd() call not found in install branch")
        return False
    # insert immediately AFTER the ksu_install_fd() call so `fd` is in scope
    lines.insert(fd_call + 1, SUPERCALL_BRANCH_LOG)

    new = "".join(lines)
    with open(path, "w") as f:
        f.write(new)

    if MARKER in new and "KSU_DIAG reboot_install" in new and \
            "KSU_DIAG reboot_magic" in new:
        print("OK: instrumented supercall.c with manager-fd file logger")
        return True
    print("ERROR: supercall.c diag insertion incomplete")
    return False


def patch_setuid_hook(path, content):
    lines = content.splitlines(keepends=True)

    # ── 1. Insert the helper after the last #include ──
    ins_idx = None
    for i, line in enumerate(lines):
        if line.strip().startswith("#include"):
            ins_idx = i
    if ins_idx is None:
        print("ERROR: no #include found in %s" % path)
        return False
    lines.insert(ins_idx + 1, HELPER_BLOCK)
    content = "".join(lines)
    lines = content.splitlines(keepends=True)

    # ── 2. Locate ksu_handle_setresuid ──
    hr_idx = None
    for i, line in enumerate(lines):
        if line.strip().startswith("int ksu_handle_setresuid("):
            hr_idx = i
            break
    if hr_idx is None:
        print("ERROR: ksu_handle_setresuid not found in %s" % path)
        return False

    # find the manager branch `if (unlikely(is_uid_manager(new_uid))) {`
    branch_idx = None
    for i in range(hr_idx, min(hr_idx + 40, len(lines))):
        if "is_uid_manager(new_uid)" in lines[i]:
            branch_idx = i
            break
    if branch_idx is None:
        print("ERROR: manager branch not found in ksu_handle_setresuid")
        return False
    # find its opening brace
    brace = None
    for i in range(branch_idx, min(branch_idx + 5, len(lines))):
        if "{" in lines[i]:
            brace = i
            break
    if brace is None:
        print("ERROR: no brace after manager branch")
        return False
    lines.insert(brace + 1, MANAGER_BRANCH_LOG)

    content = "".join(lines)
    lines = content.splitlines(keepends=True)

    # ── 3. Locate ksu_install_manager_fd_tw_func and log after ksu_install_fd() ──
    tw_idx = None
    for i, line in enumerate(lines):
        if line.strip().startswith("static void ksu_install_manager_fd_tw_func"):
            tw_idx = i
            break
    if tw_idx is None:
        print("ERROR: ksu_install_manager_fd_tw_func not found")
        return False
    tw_end = None
    for i in range(tw_idx, min(tw_idx + 30, len(lines))):
        if lines[i].strip().startswith("}"):
            tw_end = i
            break
    if tw_end is None:
        print("ERROR: no closing brace for task_work func")
        return False
    # insert before the closing brace, after ksu_install_fd() call line
    # place right before the final '}'
    lines.insert(tw_end, TASKWORK_LOG)

    new = "".join(lines)
    with open(path, "w") as f:
        f.write(new)

    if MARKER in new and "KSU_DIAG setresuid->manager" in new and \
            "KSU_DIAG fd_installed" in new:
        print("OK: instrumented setuid_hook.c with manager-fd file logger")
        return True
    print("ERROR: manager diag insertion incomplete")
    return False


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0] if args else find_file()
    if not path or not os.path.exists(path):
        print("ERROR: setuid_hook.c not found at %s" % (path or "(none)"))
        sys.exit(1)
    if not patch(path):
        sys.exit(1)
