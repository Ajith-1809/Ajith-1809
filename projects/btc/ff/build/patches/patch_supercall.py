#!/usr/bin/env python3
"""
Patch supercall.c to route SUSFS_MAGIC (0xFAFAFAFA) commands
at the START of ksu_handle_sys_reboot(), BEFORE the KSU magic check.

This ensures SUSFS dispatch runs even when magic1 != KSU_INSTALL_MAGIC1
(0xDEADBEEF). The old approach placed the SUSFS check at the end of the
function, after KSU's early-return path — KSU returned 0 for any magic1
that wasn't 0xDEADBEEF, so SUSFS commands were silently dropped.

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
    """Forward-patch supercall.c: insert SUSFS dispatch BEFORE the
    KSU magic1 != KSU_INSTALL_MAGIC1 early-return check."""
    with open(path) as f:
        content = f.read()

    forward_code = (
        '\t/* Forward SUSFS dispatch — check magic BEFORE KSU magic check */\n'
        '\tif (magic1 == 0xFAFAFAFA) {\n'
        '\t\textern int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg);\n'
        '\t\treturn susfs_handle_sys_reboot(cmd, *arg);\n'
        '\t}\n'
        '\tif (magic1 != KSU_INSTALL_MAGIC1)\n'
    )

    old_line = '\tif (magic1 != KSU_INSTALL_MAGIC1)\n'

    if old_line in content:
        content = content.replace(old_line, forward_code, 1)
        with open(path, 'w') as f:
            f.write(content)
        print(f"OK: forward-patched {path}")
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
