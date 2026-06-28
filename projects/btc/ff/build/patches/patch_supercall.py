#!/usr/bin/env python3
"""
Patch supercall.c to route SUSFS_MAGIC (0xFAFAFAFA) commands
through ksu_handle_sys_reboot() to susfs_handle_sys_reboot().

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
    """Insert SUSFS dispatch before the final return 0; in ksu_handle_sys_reboot."""
    with open(path) as f:
        content = f.read()

    # The SUSFS dispatch code to insert (tab-indented to match existing code)
    susfs_code = (
        '\t#ifdef CONFIG_KSU_SUSFS\n'
        '\t/* SUSFS command dispatch (magic2 = 0xFAFAFAFA) */\n'
        '\tif (magic2 == SUSFS_MAGIC) {\n'
        '\t\textern int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg);\n'
        '\t\treturn susfs_handle_sys_reboot(cmd, *arg);\n'
        '\t}\n'
        '#endif\n'
        '\n'
        '\treturn 0;\n'
    )

    # Anchor: the function-ending return 0; followed by } and #ifdef KSU_KPROBES_HOOK
    anchor = '\treturn 0;\n}\n\n#ifdef KSU_KPROBES_HOOK'
    if anchor not in content:
        # Try without the blank line
        anchor = '\treturn 0;\n}\n#ifdef KSU_KPROBES_HOOK'

    if anchor in content:
        content = content.replace(anchor, susfs_code + '}\n\n#ifdef KSU_KPROBES_HOOK')
        with open(path, 'w') as f:
            f.write(content)
        print(f"OK: patched {path}")
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
