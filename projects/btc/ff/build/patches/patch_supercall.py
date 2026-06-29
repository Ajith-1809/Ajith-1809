#!/usr/bin/env python3
"""
Patch supercall.c to route SUSFS commands (magic2 = 0xFAFAFAFA)
at the START of ksu_handle_sys_reboot(), before the KSU magic check.

The userspace susfs binary calls:
    reboot(0xDEADBEEF, 0xFAFAFAFA, cmd, arg)
where magic1=0xDEADBEEF (KSU_INSTALL_MAGIC1) and magic2=0xFAFAFAFA (SUSFS_MAGIC).
So we check magic2 (NOT magic1) for the SUSFS dispatch.

Usage: python3 patch_supercall.py [path/to/supercall.c]

If no path is given, searches in the current directory for:
  - drivers/kernelsu/supercall/supercall.c
  - KernelSU-Next/kernel/supercall/supercall.c
  - kernel/supercall/supercall.c
"""

import sys
import os


def find_file():
    """Find supercall.c in expected locations relative to cwd."""
    candidates = [
        "drivers/kernelsu/supercall/supercall.c",
        "KernelSU-Next/kernel/supercall/supercall.c",
        "kernel/supercall/supercall.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def patch_file(path):
    """Forward-patch supercall.c: insert SUSFS dispatch (checking magic2)
    BEFORE the KSU magic1 != KSU_INSTALL_MAGIC1 early-return check.

    The userspace susfs binary sends reboot(0xDEADBEEF, 0xFAFAFAFA, cmd, arg)
    where magic1=0xDEADBEEF is KSU's magic and magic2=0xFAFAFAFA is SUSFS magic.
    We intercept magic2 BEFORE KSU processes magic1."""
    with open(path) as f:
        content = f.read()

    # The SUSFS dispatch block: checks magic2 (not magic1) before any KSU check
    # NOTE: SUSFS commands are now handled by the patch_reboot.py in kernel/reboot.c
    # directly. This kprobe handler just returns 0 (skip KSU processing for SUSFS),
    # letting the real sys_reboot() run and handle the command via the direct patch.
    forward_code = (
        '\t/* SUSFS dispatch — kernel/reboot.c handles return value directly */\n'
        '\tif (magic2 == 0xFAFAFAFA) {\n'
        '\t\treturn 0;\n'
        '\t}\n'
        '\tif (magic1 != KSU_INSTALL_MAGIC1)\n'
    )

    # Replace the first `if (magic1 != KSU_INSTALL_MAGIC1)` check with:
    #   1. SUSFS early-return (magic2 check)
    #   2. The original KSU check

    old_line = '\tif (magic1 != KSU_INSTALL_MAGIC1)\n'

    if old_line in content:
        content = content.replace(old_line, forward_code, 1)
        with open(path, 'w') as f:
            f.write(content)
        print(f"OK: forward-patched {path} (checks magic2=0xFAFAFAFA)")
        return True
    else:
        print(f"ERROR: could not find anchor pattern in {path}")
        return False


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = find_file()

    if not path or not os.path.exists(path):
        print(f"ERROR: supercall.c not found at {path or '(none given)'}")
        sys.exit(1)

    if not patch_file(path):
        sys.exit(1)


if __name__ == "__main__":
    main()
