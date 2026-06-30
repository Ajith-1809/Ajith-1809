#!/usr/bin/env python3
"""
Patch kernel/sys.c to intercept prctl(option=0xDEADBEEF, ...) syscalls
and route them to susfs_handle_sys_reboot(arg2, (void __user*)arg3).

The ksu_susfs userspace binary calls:
    prctl(0xDEADBEEF, CMD, &info, NULL, &error)
where option=0xDEADBEEF is KERNEL_SU_OPTION (KSU_NEXT's magic value),
arg2 = CMD_SUSFS_*, arg3 = pointer to info struct, arg5 = error pointer.

Insert at the top of SYSCALL_DEFINE3(prctl, ...) in kernel/sys.c a fast
path that recognizes option == 0xDEADBEEF, calls
susfs_handle_sys_reboot(arg2, (void __user*)arg3), and propagates the
return value back to userspace as if prctl() returned it directly.

This complements the kernel/reboot.c backend so both sys_reboot-ABI
and prctl-ABI callers can dispatch into the SUSFS command router.

Usage: python3 patch_prctl.py [path/to/kernel/sys.c]
"""

import sys
import os


def find_sys_c():
    candidates = [
        "kernel/sys.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def patch_prctl(path):
    with open(path) as f:
        content = f.read()

    # Anchor: SYSCALL_DEFINE3(prctl, int, option, unsigned long, arg2, unsigned long, arg3)
    # kernel 4.14 has this at line ~1900
    anchor = "SYSCALL_DEFINE3(prctl, int, option, unsigned long, arg2, unsigned long, arg3)"
    if anchor not in content:
        # Try alternate spellings
        for variant in [
            "asmlinkage long sys_prctl(int option, unsigned long arg2,",
            "SYSCALL_DEFINE3(prctl,",
        ]:
            if variant in content:
                anchor = variant
                break
        else:
            print(f"ERROR: could not find prctl syscall anchor in {path}")
            return False

    susfs_block = (
        '\t/* SUSFS command dispatch via prctl syscall */\n'
        '\tif (unlikely(option == 0xDEADBEEF)) {\n'
        '\t\textern int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg);\n'
        '\t\treturn susfs_handle_sys_reboot((unsigned int)arg2, (void __user *)arg3);\n'
        '\t}\n'
        '\n'
    )

    # Insert susfs_block after the anchor line (and its trailing brace if any)
    idx = content.find(anchor)
    end_anchor = content.find('\n', idx) + 1
    new_content = content[:end_anchor] + susfs_block + content[end_anchor:]
    if new_content == content:
        print(f"ERROR: insert produced no change in {path}")
        return False

    with open(path, 'w') as f:
        f.write(new_content)
    print(f"OK: patched {path} (added prctl->susfs dispatch after '{anchor[:60]}...')")
    return True


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = find_sys_c()

    if not path or not os.path.exists(path):
        print(f"ERROR: kernel/sys.c not found at {path or '(none given)'}")
        sys.exit(1)

    if not patch_prctl(path):
        sys.exit(1)


if __name__ == "__main__":
    main()
