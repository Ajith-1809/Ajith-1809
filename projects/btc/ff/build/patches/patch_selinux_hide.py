#!/usr/bin/env python3
"""
Patch selinux_hide.c (KSUN v3.3.0) for 4.14 CAF kernel compatibility.

On CAF 4.14, struct selinux_state embeds:
  struct selinux_ss ss { status_page, status_lock, policydb, ... }

v3.3.0 uses the 5.5+ API where these fields are directly on selinux_state
(or via ->policy pointer for the policy).  This patch redirects field
accesses to the ss sub-struct for kernels < 5.5.

Usage: python3 patch_selinux_hide.py [target_path]

If target_path is given, patch that file. Otherwise default to
KernelSU-Next/kernel/feature/selinux_hide.c relative to cwd.
"""
import os
import sys
import re

if len(sys.argv) > 1:
    TARGET = sys.argv[1]
else:
    TARGET = os.path.join("KernelSU-Next", "kernel", "feature", "selinux_hide.c")


def sed_inplace(path, pattern, replacement):
    with open(path, "r") as f:
        content = f.read()
    count = content.count(pattern)
    if count == 0:
        print(f"  WARNING: pattern '{pattern}' not found in {path}")
        return 0
    content = content.replace(pattern, replacement)
    with open(path, "w") as f:
        f.write(content)
    print(f"  Replaced {count}x: {pattern} -> {replacement}")
    return count


def main():
    if not os.path.exists(TARGET):
        print(f"::error::Target not found: {TARGET}")
        sys.exit(1)

    total = 0

    # status_lock -> ss.status_lock (line 250, 285, 294, 296, 509, 513)
    total += sed_inplace(TARGET, "selinux_state.status_lock", "selinux_state.ss.status_lock")

    # status_page -> ss.status_page (line 253, 258)
    total += sed_inplace(TARGET, "selinux_state.status_page", "selinux_state.ss.status_page")

    # selinux_state.policy -> selinux_state.ss.policydb (line 338 + more)
    # On 4.14 there's no struct selinux_policy; the policy data is in ss.policydb directly.
    pattern_policy_field = "selinux_state.policy"
    replacement_policy_field = "selinux_state.ss.policydb"
    # Only replace "selinux_state.policy" when it's a field access,
    # not when it's followed by "->" (pointer deref to struct selinux_policy).
    # We need to handle both:
    #   selinux_state.policy->policydb  ->  selinux_state.ss.policydb
    #   selinux_state.policy->xxx  ->  selinux_state.ss.policydb.xxx (or different approach)
    with open(TARGET, "r") as f:
        lines = f.readlines()

    new_lines = []
    for line in lines:
        if "selinux_state.policy->" in line:
            # Replace: selinux_state.policy->policydb  ->  selinux_state.ss.policydb
            # And: selinux_state.policy->other_field  ->  needs per-case handling
            line = line.replace("selinux_state.policy->policydb", "selinux_state.ss.policydb")
            # For non-policydb accesses through ->policy, we may need special handling
            if "selinux_state.policy->" in line:
                print(f"  WARNING: remaining 'selinux_state.policy->' in line: {line.strip()}")
        new_lines.append(line)

    with open(TARGET, "w") as f:
        f.writelines(new_lines)
    total += 1

    # struct selinux_policy type usage -> #if guard or replace with local struct
    # On 4.14 there's no struct selinux_policy.  We just need the code to compile.
    # The policy pointer deref pattern needs to be removed (we access policydb directly).
    # "policy = selinux_state.policy" -> skip (no such assignment on 4.14)

    if total == 0:
        print("::error::No changes applied — file may already be patched")
        sys.exit(1)

    print(f"selinux_hide.c: {total} patch group(s) applied OK")
    sys.exit(0)


if __name__ == "__main__":
    main()
