#!/usr/bin/env python3
"""
patch_setresuid.py — Deliver the [ksu_driver] fd to the KernelSU-Next Manager
app by hooking SYSCALL_DEFINE3(setresuid, ...) WITHOUT kprobes.

Background / task:
  Fix #1 (task #132): make the KernelSU Manager show "Working" by getting the
  per-process [ksu_driver] anonymous-inode fd. The ioctl path the Manager uses
  needs that fd, which is O_CLOEXEC and per-process.

  On CAF 4.14 we are in MANUAL_HOOK mode (kprobes are forbidden below 5.10), so
  we inject a call directly into the syscall body. When the process performing
  setresuid adopts the manager's app uid, we call ksu_install_fd() to install
  the [ksu_driver] fd into the current process — exactly the call upstream's
  own ksu_install_manager_fd_tw_func() task_work callback makes.

Why call ksu_handle_setresuid() directly (and not a hand-rolled ksu_install_fd gate):
  The upstream KSU-Next setuid hook (kernel/hook/setuid_hook.c) is the proven
  fd-delivery path. It is declared non-static with a THREE-arg uid_t prototype
  (ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid)) in setuid_hook.h on
  the legacy branch we build, and it performs:
      - is_uid_manager(new_uid) gate  (ksu_manager_appid == uid % 100000)
      - task_work_add(current, &cb, TWA_RESUME) -> ksu_install_fd() at resume
      - disable_seccomp() so the Manager's reboot-magic fd request succeeds
      - allow_uid handling + kernel umount
  A prior revision inlined only ksu_install_fd() behind a (ksu_manager_appid != 0)
  gate, which is wrong: ksu_manager_appid starts at KSU_INVALID_APPID (-1) and is
  only populated when the Manager registers itself, and the synchronous call missed
  the task_work deferral that makes the fd land in the right process. Calling the
  upstream handler verbatim is the faithful, working fix. The handler is linked into
  the KSU built-in (CONFIG_KSU=y) so the extern decl resolves at compile time.

Injection point:
  Function entry of SYSCALL_DEFINE3(setresuid, uid_t, ruid, uid_t, euid,
  uid_t, suid) — the three params are raw uid_t (not kuid_t), so no
  make_kuid/from_kuid wrapping is required. We inject immediately after the
  opening '{' of the body, before any cred work, matching KSU-Next's own
  convention of observing the raw syscall args.

32-bit / compat variant:
  CAF 4.14 also defines a legacy 16-bit sys_setresuid16, but it is ONLY used by
  the ancient 16-bit-uid ABI. On arm64 / AOSP android-4.14 (tillua467 v2.4) the
  32-bit uid_t SYSCALL_DEFINE3(setresuid) is the ONLY path. We therefore do NOT
  hook sys_setresuid16 (a diagnostic note is printed if it is present).

Idempotency:
  Guarded by a unique marker comment; re-running skips injection.

Usage:
  python3 patch_setresuid.py [path/to/kernel/sys.c]
  If no path is given, searches for kernel/sys.c in the cwd (build.yml invokes
  it with NO file argument, run from the kernel source root).
"""

import sys
import os

# Unique marker used both for the idempotency guard and the post-write verify.
MARKER = "KSUN: deliver [ksu_driver] fd to the Manager app on setresuid"

# Block to inject right after the opening brace of SYSCALL_DEFINE3(setresuid).
# We use '\t'/'\n' escapes (Python collapses to real tabs/newlines at runtime)
# exactly like the other patchers (patch_fs_exec.py INSERT_BLOCK).
#
# We call the STOCK ksu_handle_setresuid(ruid, euid, suid) directly.  This is the
# exact primitive the upstream KSU-Next setuid hook invokes from its kprobe/tracepoint,
# and it contains the proven fd-delivery logic:
#   - gates on is_uid_manager(new_uid)  (== ksu_manager_appid == uid % 100000)
#   - defers ksu_install_fd() via task_work_add(current, ..., TWA_RESUME) so the
#     [ksu_driver] fd lands in the Manager process at resume (not mid-syscall)
#   - disables seccomp so the Manager's subsequent reboot-magic fd request works
#   - handles allow_uid + kernel umount
# Replicating it inline (as a prior revision did) duplicated the gate incorrectly and
# missed the task_work deferral; calling the upstream handler is the faithful fix.
INSERT_BLOCK = (
    '\t/* ' + MARKER + ' (manual hook, no kprobes) */\n'
    '#if IS_ENABLED(CONFIG_KSU)\n'
    '\t{\n'
    '\t\textern int ksu_handle_setresuid(uid_t ruid, uid_t euid, uid_t suid);\n'
    '\t\t(void)ksu_handle_setresuid(ruid, euid, suid);\n'
    '\t}\n'
    '#endif\n'
)


def find_sys_c():
    """Find kernel/sys.c relative to the current directory."""
    candidates = [
        "kernel/sys.c",
        "KernelSU-Next/kernel/sys.c",  # fallback, should not happen
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def find_syscall_defn_line(lines, defn_name="setresuid"):
    """
    Find the line index of SYSCALL_DEFINE3(setresuid, ...).
    Returns (line_idx, line) or (None, None).
    """
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith(f"SYSCALL_DEFINE3({defn_name},"):
            return i, line
        if f"SYSCALL_DEFINE3({defn_name}" in stripped:
            return i, line
        if stripped.startswith(f"asmlinkage long sys_{defn_name}("):
            return i, line
    return None, None


def find_fn_brace(lines, anchor_idx, max_lookahead=20):
    """Find the opening brace '{' of the function body after anchor_idx."""
    for i in range(anchor_idx, min(anchor_idx + max_lookahead, len(lines))):
        stripped = lines[i].strip()
        if '{' in stripped:
            return i
        if i > anchor_idx and stripped.startswith("SYSCALL_DEFINE"):
            return None
    return None


def note_setresuid16(path):
    """
    Diagnostic: the 16-bit sys_setresuid16 variant exists in 4.14 but is the
    ancient 16-bit-uid ABI and is NOT used on arm64 / AOSP android-4.14. We do
    not hook it. Log its presence for transparency.
    """
    with open(path) as f:
        content = f.read()
    if "sys_setresuid16" in content:
        print("  NOTE: sys_setresuid16 (16-bit uid ABI) present but intentionally "
              "NOT hooked — arm64 tillua467 v2.4 uses the 32-bit uid_t "
              "SYSCALL_DEFINE3(setresuid) path only.")


def patch_setresuid(path):
    """Inject the manager fd-delivery block into SYSCALL_DEFINE3(setresuid)."""

    with open(path) as f:
        content = f.read()

    lines = content.splitlines(keepends=True)
    if not lines:
        print(f"ERROR: empty file {path}")
        return False

    # ── 1. Locate the function ──
    anchor_idx, anchor_line = find_syscall_defn_line(lines, "setresuid")
    if anchor_idx is None:
        print(f"ERROR: could not find SYSCALL_DEFINE3(setresuid, ...) in {path}")
        return False

    # ── 2. Locate the opening brace ──
    brace_idx = find_fn_brace(lines, anchor_idx)
    if brace_idx is None:
        print(f"ERROR: could not find opening brace after SYSCALL_DEFINE3(setresuid) "
              f"at line {anchor_idx + 1}")
        print(f"  Anchor text: {anchor_line.strip()}")
        for k in range(anchor_idx, min(anchor_idx + 12, len(lines))):
            print(f"    {k + 1}: {lines[k].rstrip()}")
        return False

    print(f"Found SYSCALL_DEFINE3(setresuid) at line {anchor_idx + 1}, "
          f"body brace at line {brace_idx + 1}")

    # ── 3. Idempotency guard ──
    search_end = min(brace_idx + 30, len(lines))
    func_top = ''.join(lines[brace_idx:search_end])
    if MARKER in func_top:
        print("OK: setresuid manager fd hook already present — skipping injection")
        note_setresuid16(path)
        return True

    # ── 4. Insert the block right after the opening brace ──
    brace_pos = lines[brace_idx].find('{')
    if brace_pos < 0:
        print(f"ERROR: no '{{' found on line {brace_idx + 1}: "
              f"'{lines[brace_idx].strip()}'")
        return False

    old_line = lines[brace_idx]
    before_brace = old_line[:brace_pos + 1]
    after_brace = old_line[brace_pos + 1:]
    lines[brace_idx] = before_brace + '\n' + INSERT_BLOCK + after_brace

    new_content = ''.join(lines)
    if new_content == content:
        print(f"ERROR: insert produced no change in {path}")
        return False

    with open(path, 'w') as f:
        f.write(new_content)

    # ── 5. Verify ──
    if MARKER in new_content and "ksu_handle_setresuid" in new_content:
        print(f"OK: patched {path} with setresuid [ksu_driver] fd hook")
    else:
        print(f"ERROR: marker/ksu_handle_setresuid not found after insertion in {path}")
        return False

    note_setresuid16(path)
    return True


if __name__ == "__main__":
    positional_args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(positional_args) > 0:
        path = positional_args[0]
    else:
        path = find_sys_c()

    if not path or not os.path.exists(path):
        print(f"ERROR: kernel/sys.c not found at {path or '(none given)'}")
        print("Hint: run this script from the kernel source root directory")
        sys.exit(1)

    if not patch_setresuid(path):
        sys.exit(1)
