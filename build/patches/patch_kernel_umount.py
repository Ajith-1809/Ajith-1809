#!/usr/bin/env python3
"""
patch_kernel_umount.py - Fix kernel_umount.c for CAF 4.14 compat

Problem: KSUN Kbuild injects path_umount/can_umount into fs/namespace.c
via $(shell sed ...) during Kbuild parsing. But the Kbuild is in drivers/
hierarchy, which the kernel build system processes AFTER fs/. So the
injection modifies the source AFTER fs/namespace.c has already been
compiled. The injected path_umount never makes it into fs/namespace.o.

However, KSU_HAS_PATH_UMOUNT IS still defined (the grep runs during the
SAME Kbuild parsing as the sed, and finds path_umount in the now-modified
source). This makes kernel_umount.c compile the path_umount() branch,
but the symbol doesn't exist in any object file, causing linker error:
    undefined reference to `path_umount'

Fix: Remove the `|| defined(KSU_HAS_PATH_UMOUNT)` from the preprocessor
guard so that on kernels < 5.9, the sys_umount() fallback path is always
used. Also remove the conditional include guard around <linux/syscalls.h>
since the fallback path needs it.

This aligns with the project directive: "no backports" — use the native
sys_umount() path which works correctly on CAF 4.14.
"""

import os
import sys


def patch_kernel_umount(filepath):
    with open(filepath, 'r') as f:
        lines = f.readlines()

    original = lines.copy()
    modified = False

    # 1. Remove conditional guard around #include <linux/syscalls.h>
    #    Looking for:  #ifndef KSU_HAS_PATH_UMOUNT\n#include <linux/syscalls.h>\n#endif
    for i in range(len(lines) - 2):
        if ('#ifndef KSU_HAS_PATH_UMOUNT' in lines[i] and
                '#include <linux/syscalls.h>' in lines[i+1] and
                '#endif' in lines[i+2]):
            # Remove lines[i] (#ifndef) and lines[i+2] (#endif)
            # Keep only lines[i+1] (#include)
            lines[i] = lines[i+1]  # Promote #include to this position
            lines[i+1] = None      # Mark for removal
            lines[i+2] = None      # Mark for removal
            modified = True
            print("  Removed #ifndef KSU_HAS_PATH_UMOUNT guard around <linux/syscalls.h>")
            break

    # Clean up None lines
    if modified:
        lines = [l for l in lines if l is not None]

    # 2. Remove || defined(KSU_HAS_PATH_UMOUNT) from the main guard
    #    Two-line pattern:
    #      #if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 9, 0) ||                           \
    #      \tdefined(KSU_HAS_PATH_UMOUNT)
    #    Single-line pattern:
    #      #if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 9, 0) || defined(KSU_HAS_PATH_UMOUNT)
    for i in range(len(lines)):
        line = lines[i]
        stripped = line.strip()

        # Check for continuation line pattern: "|| \" + next line with defined(KSU_HAS_PATH_UMOUNT)
        if ('KERNEL_VERSION(5, 9, 0) ||' in stripped and stripped.rstrip().endswith('\\')):
            if i + 1 < len(lines) and 'defined(KSU_HAS_PATH_UMOUNT)' in lines[i+1]:
                # Remove || and continuation from current line
                before_or = line.rstrip().rstrip('\\').rstrip()
                if before_or.endswith('||'):
                    before_or = before_or.rstrip('|').rstrip()
                lines[i] = before_or + '\n'
                lines[i+1] = None  # Mark for removal
                modified = True
                print("  Removed '|| defined(KSU_HAS_PATH_UMOUNT)' from main guard (two-line)")
                break

        # Check for single-line pattern
        if ('KERNEL_VERSION(5, 9, 0) ||' in stripped and
                'defined(KSU_HAS_PATH_UMOUNT)' in stripped):
            # Remove || defined(KSU_HAS_PATH_UMOUNT)
            idx = stripped.find('||')
            after_pipe = stripped[idx+2:]
            # Remove the || and everything after it
            before_pipe = stripped[:idx].rstrip()
            lines[i] = line.replace(stripped, before_pipe)
            modified = True
            print("  Removed '|| defined(KSU_HAS_PATH_UMOUNT)' from main guard (single-line)")
            break

        if 'KERNEL_VERSION(5, 9, 0) ||' in stripped:
            # Check if defined(KSU_HAS_PATH_UMOUNT) is on the same line
            after_or = stripped[stripped.index('||')+2:]
            if 'defined(KSU_HAS_PATH_UMOUNT)' in after_or:
                before_or = stripped[:stripped.index('||')].rstrip()
                lines[i] = line.replace(stripped, before_or)
                modified = True
                print("  Removed '|| defined(KSU_HAS_PATH_UMOUNT)' from main guard (same line)")
                break

        if 'KERNEL_VERSION(5, 9, 0) ||' in stripped:
            # Maybe the next line has defined(KSU_HAS_PATH_UMOUNT) without continuation
            if i + 1 < len(lines) and 'defined(KSU_HAS_PATH_UMOUNT)' in lines[i+1]:
                lines[i] = line.rstrip() + '\n'
                lines[i+1] = None
                modified = True
                print("  Removed '|| defined(KSU_HAS_PATH_UMOUNT)' from main guard (next line)")
                break

    # Clean up None lines
    lines = [l for l in lines if l is not None]

    if modified:
        with open(filepath, 'w') as f:
            f.writelines(lines)
        print(f"  Patched {filepath}")
    else:
        print(f"  No changes needed for {filepath}")

    return modified


def main():
    # Default path is relative to kernel source root
    filepath = "KernelSU-Next/kernel/feature/kernel_umount.c"
    if len(sys.argv) > 1:
        filepath = sys.argv[1]

    print(f"=== Patching kernel_umount.c for CAF 4.14 ===")
    if not os.path.exists(filepath):
        print(f"  ERROR: {filepath} not found")
        sys.exit(1)

    patch_kernel_umount(filepath)
    print("=== Done ===")


if __name__ == '__main__':
    main()
