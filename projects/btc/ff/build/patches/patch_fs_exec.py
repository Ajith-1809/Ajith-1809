#!/usr/bin/env python3
"""
patch_fs_exec.py — Wire KSUN's execve hook into do_execveat_common() for
MANUAL_HOOK mode (no kprobes, no bootloop on CAF 4.14).

WHY THIS MATTERS (root cause of "Manager Working but no app root"):
  In KSU-Next's legacy branch, the app-root ELEVATION path (execve of
  /system/bin/su -> sucompat -> escape_with_root_profile() -> commit_creds(uid
  0)) lives ENTIRELY in kernel/hook/hook_manager.c, which is wrapped in
  `#ifdef KSU_KPROBES_HOOK`. Under CONFIG_KSU_MANUAL_HOOK that whole block is
  compiled out, so NO syscall hook is ever registered and NO app can be
  elevated to root — only the [ksu_driver] fd (delivered via the setresuid
  task_work, independent of hook mode) reaches the Manager, so the Manager
  still shows "Working" while root grants to apps silently fail.

  The elevation entry point ksu_handle_execveat_sucompat() is reachable ONLY
  via (a) the sys_enter tracepoint (absent under MANUAL_HOOK) or (b) the
  in-tree wrapper ksu_handle_execveat() in kernel/core/init.c:31 — which is
  plain C, NOT gated by KPROBES_HOOK, and already calls BOTH
  ksu_handle_execveat_ksud (fd injection / zygote detection) AND
  ksu_handle_execveat_sucompat (the root elevation). It is compiled into
  vmlinux regardless of hook mode.

FIX:
  Insert a single call to ksu_handle_execveat() into
  fs/exec.c:do_execveat_common() (after the IS_ERR(filename) guard). This
  restores BOTH the fd-injection and the root-elevation paths with ZERO
  kprobes — no register_kprobe, no bootloop — satisfying the
  "kernel-level stealth, no kprobe bootloop" constraint in CLAUDE.md.

  ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv,
  void *envp, int *flags):
    - fd: read as a pointer only; ksud/sucompat never write *fd, so a stack
      int is fine.
    - filename_ptr: &filename (struct filename * -> struct filename **).
    - argv: &argv (struct user_arg_ptr -> void *); sucompat ignores it, ksud
      uses it for argv inspection (valid struct user_arg_ptr *).
    - envp/flags: NULL (optional, unused for our purpose).

We use an extern declaration inline so no header changes are needed — the
linker resolves the symbol since both live in the same vmlinux.
"""

import os
import sys

# Marker so we can detect an already-applied patch regardless of which symbol
# name is present.
PATCH_MARKER = "ksu_handle_execveat"

# The target code block to insert (CONFIG_KSU guard around the extern decl to
# avoid unused-symbol warnings when KSU=n).
INSERT_BLOCK = '''\t/* KernelSU Next (MANUAL_HOOK): execve hook for fd injection + root elevation */
#if IS_ENABLED(CONFIG_KSU)
\t{
\t\textern int ksu_handle_execveat(int *fd, struct filename **filename_ptr,
\t\t\t\t\t\tvoid *argv, void *envp, int *flags);
\t\tint ksu_fd = 0;
\t\tksu_handle_execveat(&ksu_fd, &filename, (void *)&argv, NULL, NULL);
\t}
#endif
'''

# Two possible anchor strings to locate the insertion point.
# Anchor A: the IS_ERR filename guard
ANCHOR_A = '\tif (IS_ERR(filename))\n\t\treturn PTR_ERR(filename);\n\n'

# Anchor B: the bprm allocation (fallback)
ANCHOR_B = '\tstruct linux_binprm *bprm;\n'


def patch_fs_exec(path="fs/exec.c"):
    with open(path, "r") as f:
        content = f.read()

    # Check if already patched (either the new wrapper call or the legacy
    # ksu_handle_execve_ksud call — both achieve the same goal, so skip to
    # avoid double-injecting on a re-run over an already-patched tree).
    if PATCH_MARKER in content or "ksu_handle_execve_ksud" in content:
        print("  already patched: execve hook found in fs/exec.c")
        return True

    # Find insertion point — after the IS_ERR guard
    idx = content.find(ANCHOR_A)
    if idx >= 0:
        insert_pos = idx + len(ANCHOR_A)
        print("  anchor A found at byte", idx)
    else:
        # Fallback: find bprm allocation line
        idx = content.find(ANCHOR_B)
        if idx < 0:
            print("ERROR: could not find insertion point in fs/exec.c")
            sys.exit(1)
        insert_pos = idx
        print("  anchor B (bprm) found at byte", idx)

    new_content = content[:insert_pos] + INSERT_BLOCK + content[insert_pos:]

    with open(path, "w") as f:
        f.write(new_content)

    print("  fs/exec.c written with execve hook")

    # Verify
    if PATCH_MARKER in new_content:
        print("  VERIFIED: hook call present")
    else:
        print("  WARNING: hook call not found after insertion")
        sys.exit(1)

    return True


if __name__ == "__main__":
    target = sys.argv[1] if len(sys.argv) > 1 else "fs/exec.c"
    if not os.path.exists(target):
        print(f"ERROR: {target} not found")
        sys.exit(1)
    patch_fs_exec(target)
