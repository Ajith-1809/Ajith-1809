#!/usr/bin/env python3
"""
Patch supercall.c to route SUSFS commands (magic2 = 0xFAFAFAFA)
at the START of the reboot_handler_pre kprobe, before any KSU logic.

Supports both:
  - KSUN v3.3.0+ (4-space indent, 'install KSU fd' comment)
  - KSUN legacy branch (tab indent, 'if (magic1 != KSU_INSTALL_MAGIC1)')

Usage: python3 patch_supercall.py [path/to/supercall.c]
"""

import sys
import os


def find_file():
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
    with open(path) as f:
        content = f.read()

    inserted = False

    # ── Anchor 1: v3.3.0+ (4-space indent) ──
    # NOTE: The kprobe must NOT call susfs_handle_sys_reboot here because it
    # would cause double-execution when the real sys_reboot handler also
    # dispatches SUSFS commands via patch_reboot.py.  Instead, just return 0
    # to skip the KSU install-FD logic; the real syscall handles the dispatch.
    anchor_v33 = '    /* Check if this is a request to install KSU fd */\n'
    susfs_block_v33 = (
        '    /* SUSFS command dispatch via supercall */\n'
        '    if (unlikely(magic2 == 0xFAFAFAFA)) {\n'
        '        return 0;\n'
        '    }\n'
    )
    if anchor_v33 in content:
        # Insert SUSFS block BEFORE the KSU fd comment
        content = content.replace(
            anchor_v33,
            susfs_block_v33 + '\n' + anchor_v33,
            1
        )
        with open(path, 'w') as f:
            f.write(content)
        print(f"OK: patched {path} (v3.3.0 anchor)")
        return True

    # ── Anchor 2: legacy branch (tab indent) ──
    anchor_legacy = '\tif (magic1 != KSU_INSTALL_MAGIC1)\n'
    susfs_block_legacy = (
        '\t/* SUSFS command dispatch via supercall */\n'
        '\tif (unlikely(magic2 == 0xFAFAFAFA)) {\n'
        '\t\treturn 0;\n'
        '\t}\n'
    )
    if anchor_legacy in content:
        content = content.replace(
            anchor_legacy,
            susfs_block_legacy + '\n' + anchor_legacy,
            1
        )
        with open(path, 'w') as f:
            f.write(content)
        print(f"OK: patched {path} (legacy anchor)")
        return True

    print(f"ERROR: could not find any anchor pattern in {path}")
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
