#!/usr/bin/env python3
"""
patch_selinux_fallback.py — Retry KSU domain registration + fallback to INIT_CONTEXT

On CAF 4.14, apply_kernelsu_rules() is called during kernel init (module_init),
but the Android userspace init process later loads its own SELinux policy which
overwrites the KSU rules. When escape_with_root_profile() later calls
setup_selinux("u:r:ksu:s0") during GRANT_ROOT, the ksu domain doesn't exist in
the current policy and the transition fails.

This patch modifies setup_selinux() to:
  1. Try the requested domain transition
  2. On failure (and when domain == KERNEL_SU_CONTEXT):
     a. Call apply_kernelsu_rules() to register the ksu type/domain
     b. Call cache_sid() to cache the SID
     c. Retry the domain transition
  3. If the retry also fails, fall back to INIT_CONTEXT which always exists

This breaks the bootstrap deadlock: GRANT_ROOT succeeds → process gets u:r:ksu:s0
→ root shell can write to /data/adb/ → install ksud → register Manager.
"""

import sys

SELINUX_C_PATH = "KernelSU-Next/kernel/selinux/selinux.c"


PATCHED_FUNC = (
    'void setup_selinux(const char *domain, struct cred *cred)\n'
    '{\n'
    '    if (transive_to_domain(domain, cred, false)) {\n'
    '        pr_err("transive domain failed.\\n");\n'
    '        /* Try to register KSU domain dynamically */\n'
    '        if (strcmp(domain, KERNEL_SU_CONTEXT) == 0) {\n'
    '            pr_info("retrying with apply_kernelsu_rules + cache_sid\\n");\n'
    '            apply_kernelsu_rules();\n'
    '            cache_sid();\n'
    '            if (transive_to_domain(domain, cred, false) == 0) {\n'
    '                return;  /* Succeeded after re-registration */\n'
    '            }\n'
    '            pr_err("retry failed, falling back to INIT_CONTEXT\\n");\n'
    '        }\n'
    '        /* Fallback to INIT_CONTEXT when all else fails */\n'
    '        if (strcmp(domain, INIT_CONTEXT) != 0) {\n'
    '            pr_info("falling back to INIT_CONTEXT\\n");\n'
    '            if (transive_to_domain(INIT_CONTEXT, cred, false)) {\n'
    '                pr_err("fallback to INIT_CONTEXT also failed.\\n");\n'
    '            }\n'
    '        }\n'
    '    }\n'
    '}\n'
)

ORIG_FUNC = (
    'void setup_selinux(const char *domain, struct cred *cred)\n'
    '{\n'
    '    if (transive_to_domain(domain, cred, false)) {\n'
    '        pr_err("transive domain failed.\\n");\n'
    '        return;\n'
    '    }\n'
    '}\n'
)

# Intermediate pattern from old patch (in case already patched)
SIMPLE_FALLBACK_FUNC = (
    'void setup_selinux(const char *domain, struct cred *cred)\n'
    '{\n'
    '    if (transive_to_domain(domain, cred, false)) {\n'
    '        pr_err("transive domain failed, trying init context.\\n");\n'
    '        transive_to_domain(INIT_CONTEXT, cred, false);\n'
    '    }\n'
    '}\n'
)


def patch_selinux_c(path=SELINUX_C_PATH):
    with open(path, "r") as f:
        content = f.read()

    if PATCHED_FUNC in content:
        print("  already patched with retry+fallback — skipping")
        return True

    if SIMPLE_FALLBACK_FUNC in content:
        # Upgrade from simple fallback to retry+fallback
        content = content.replace(SIMPLE_FALLBACK_FUNC, PATCHED_FUNC, 1)
        changed = True
        print("  upgraded: simple fallback -> retry+fallback")
    elif ORIG_FUNC in content:
        content = content.replace(ORIG_FUNC, PATCHED_FUNC, 1)
        changed = True
        print("  patched: setup_selinux() now retries with apply_kernelsu_rules + cache_sid, then falls back to INIT_CONTEXT")
    else:
        print("ERROR: could not find setup_selinux() target")
        print("Looking for original:")
        print(repr(ORIG_FUNC))
        print("Looking for simple fallback:")
        print(repr(SIMPLE_FALLBACK_FUNC))
        sys.exit(1)

    if changed:
        with open(path, "w") as f:
            f.write(content)

    # Verification
    if "apply_kernelsu_rules" in content and "cache_sid" in content and "INIT_CONTEXT" in content:
        print("  verification OK: retry + fallback logic present")
        return True
    else:
        print("ERROR: verification failed")
        sys.exit(1)


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else SELINUX_C_PATH
    patch_selinux_c(path)
