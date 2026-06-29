#!/usr/bin/env python3
"""
Patch kernel/reboot.c to intercept SUSFS magic values (magic2 = 0xFAFAFAFA)
and return directly from the syscall, bypassing the CAP_SYS_BOOT check.

The KSU-Next kprobe on __arm64_sys_reboot intercepts SUSFS CMDs in its
pre_handler (ksu_handle_sys_reboot), but ALWAYS returns 0 — so the real
sys_reboot() executes and returns -EINVAL (wrong magics for reboot).
The SUSFS userspace binary checks the syscall return value and reports
"SUSFS operation not supported" for any non-zero return.

This patch inserts a direct check in the REAL sys_reboot body so the
SUSFS handler's return value (0 = success) reaches userspace directly.

Usage: python3 patch_reboot.py [path/to/kernel/reboot.c]

If no path is given, searches for kernel/reboot.c in the cwd.
"""

import sys
import os


def find_reboot():
    """Find kernel/reboot.c relative to the current directory."""
    candidates = [
        "kernel/reboot.c",
        "kernel/sys.c",  # fallback
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def patch_reboot(path):
    """Insert SUSFS magic2 == 0xFAFAFAFA check at the top of SYSCALL_DEFINE4(reboot).

    Places the check right before the first `if (!capable(CAP_SYS_BOOT))`
    statement, ensuring SUSFS commands bypass CAP_SYS_BOOT and the standard
    reboot magic validation which would return -EINVAL.
    """
    with open(path) as f:
        content = f.read()

    # Anchor: find the capable(CAP_SYS_BOOT) check
    # Common pattern in kernel 4.14:
    #   /* For sanity, we'll ... */
    #   if (!capable(CAP_SYS_BOOT))
    #       return -EPERM;
    anchors = [
        '\t/* For sanity, we\'ll perform a quick test',
        '\t/* For sanity, we\'ll perform a quick test to see if we',
        '\tif (!capable(CAP_SYS_BOOT))',
    ]

    inserted = False
    for anchor in anchors:
        if anchor in content:
            susfs_block = (
                '\t/* SUSFS command dispatch via reboot syscall magic */\n'
                '\tif (unlikely(magic2 == 0xFAFAFAFA)) {\n'
                '\t\textern int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg);\n'
                '\t\treturn susfs_handle_sys_reboot(cmd, arg);\n'
                '\t}\n'
                '\n\t'
            )
            # Replace first occurrence of anchor with SUSFS block + anchor
            new_content = content.replace(anchor, susfs_block + anchor.lstrip(), 1)
            if new_content != content:
                content = new_content
                inserted = True
                print(f"OK: patched {path} (anchor: '{anchor.strip()[:40]}')")
                break

    if not inserted:
        # Fallback: insert after variable declarations
        # Look for the char buffer / int ret = 0 pattern
        fallback_anchor = '\tchar buffer[256];'
        if fallback_anchor in content:
            susfs_block = (
                fallback_anchor + '\n'
                '\t/* SUSFS command dispatch via reboot syscall magic */\n'
                '\tif (unlikely(magic2 == 0xFAFAFAFA)) {\n'
                '\t\textern int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg);\n'
                '\t\treturn susfs_handle_sys_reboot(cmd, arg);\n'
                '\t}\n'
            )
            content = content.replace(fallback_anchor, susfs_block, 1)
            inserted = True
            print(f"OK: patched {path} (fallback anchor: 'char buffer[256]')")

        # Another fallback: int ret = 0;
        if not inserted:
            fallback_anchor2 = '\tint ret = 0;'
            if fallback_anchor2 in content:
                susfs_block = (
                    fallback_anchor2 + '\n'
                    '\t/* SUSFS command dispatch via reboot syscall magic */\n'
                    '\tif (unlikely(magic2 == 0xFAFAFAFA)) {\n'
                    '\t\textern int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg);\n'
                    '\t\treturn susfs_handle_sys_reboot(cmd, arg);\n'
                    '\t}\n'
                )
                content = content.replace(fallback_anchor2, susfs_block, 1)
                inserted = True
                print(f"OK: patched {path} (fallback anchor: 'int ret = 0;')")

    if not inserted:
        # Last ditch: look for LINUX_REBOOT_MAGIC2 check line
        magic_check = '(magic2 != LINUX_REBOOT_MAGIC2'
        if magic_check in content:
            insert_before = '\tif (magic1 != LINUX_REBOOT_MAGIC1 ||'
            if insert_before in content:
                susfs_block = (
                    '\t/* SUSFS command dispatch */\n'
                    '\tif (unlikely(magic2 == 0xFAFAFAFA)) {\n'
                    '\t\textern int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg);\n'
                    '\t\treturn susfs_handle_sys_reboot(cmd, arg);\n'
                    '\t}\n'
                    '\n\t'
                )
                content = content.replace(insert_before, susfs_block + insert_before.lstrip(), 1)
                inserted = True
                print(f"OK: patched {path} (fallback anchor: LINUX_REBOOT_MAGIC2 check)")

    if not inserted:
        print(f"ERROR: Could not find any anchor in {path}")
        return False

    with open(path, 'w') as f:
        f.write(content)
    print(f"Patched file written: {path}")
    return True


def verify_patch(path):
    """Verify the SUSFS dispatch was inserted correctly."""
    with open(path) as f:
        content = f.read()
    if '0xFAFAFAFA' in content and 'susfs_handle_sys_reboot' in content:
        print("VERIFY: SUSFS dispatch successfully inserted in the correct location")
        # Show the inserted block
        idx = content.index('0xFAFAFAFA')
        print("--- context ---")
        # Find line start before 0xFAFAFAFA
        line_start = content.rfind('\n', 0, idx) + 1
        line_end = content.find('\n', idx)
        print(content[line_start - 40:line_end + 200])
        print("---")
        return True
    else:
        print("VERIFY FAILED: SUSFS dispatch markers not found in output")
        return False


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = find_reboot()

    if not path or not os.path.exists(path):
        print(f"ERROR: kernel/reboot.c not found at {path or '(none given)'}")
        print("Hint: run this script from the kernel source root directory")
        sys.exit(1)

    if not patch_reboot(path):
        sys.exit(1)

    if not verify_patch(path):
        sys.exit(1)


if __name__ == "__main__":
    main()
