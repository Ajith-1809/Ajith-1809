#!/usr/bin/env python3
"""
Replace sepolicy.c (KSUN v3.3.0) with v3.2.0-legacy version for 4.14 CAF compat.

KSUN v3.3.0 refactored sepolicy.c to use kernel 5.5+ APIs:
- avtab_node flex_array (kernel 5.0+)
- filename_trans_key/_datum structure changes (kernel 5.7+)
- struct selinux_policy for dup/destroy (kernel 5.5+)
- type_val_to_struct (kernel 5.1+)
- hashtab_insert 5-arg variant (kernel 5.9+)

The v3.2.0-legacy sepolicy.c already has LINUX_VERSION_CODE guards
covering all these cases and works on 4.14 out of the box.
"""

import sys
import os
import urllib.request

SEPOLICY_3_2_0_LEGACY_URL = (
    "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/"
    "v3.2.0-legacy/kernel/selinux/sepolicy.c"
)


def find_file():
    candidates = [
        "KernelSU-Next/kernel/selinux/sepolicy.c",
        "drivers/kernelsu/selinux/sepolicy.c",
        "kernel/selinux/sepolicy.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def fetch_legacy():
    print(f"  Fetching v3.2.0-legacy sepolicy.c from GitHub...")
    with urllib.request.urlopen(SEPOLICY_3_2_0_LEGACY_URL) as resp:
        content = resp.read().decode("utf-8")
    return content


def patch_file(path, content):
    # Remove the compat/kernel_compat.h include — it doesn't exist in v3.3.0 tree
    # and is only relevant for Huawei devices
    old_line = '#include "compat/kernel_compat.h" // Add check Huawei Device'
    if old_line in content:
        content = content.replace(old_line, '// #include "compat/kernel_compat.h" (Huawei only, removed for 4.14 CAF)')
        print("  Removed compat/kernel_compat.h include (Huawei-only, not in v3.3.0 tree)")
    else:
        # Try alternate forms
        import re
        content = re.sub(
            r'#include\s+"compat/kernel_compat\.h".*$',
            '// #include "compat/kernel_compat.h" (Huawei only, removed for 4.14 CAF)',
            content,
            flags=re.MULTILINE,
        )

    print(f"  Writing {path} ({len(content)} bytes)")
    with open(path, "w") as f:
        f.write(content)
    print("OK: sepolicy.c replaced with 4.14-compatible version")
    return True


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = find_file()

    if not path or not os.path.exists(path):
        print(f"ERROR: sepolicy.c not found at {path or '(none given)'}")
        sys.exit(1)

    content = fetch_legacy()
    if not patch_file(path, content):
        sys.exit(1)


if __name__ == "__main__":
    main()
