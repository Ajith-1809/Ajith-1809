#!/usr/bin/env python3
"""
patch_init.py — Fix KSUN built-in init path for root access

The built-in init path (kernelsu_init → else branch) is missing TWO critical
calls that exist in the LKM (late-load) path:

  1. apply_kernelsu_rules() — registers the "ksu" SELinux domain/type in the
     policy database. Without this, setup_selinux("u:r:ksu:s0") fails during
     escape_with_root_profile(), the process keeps its original shell context,
     and root cannot write to /data/adb/ or /data/system/.

  2. ksu_load_allow_list() — calls ksu_grant_root_to_shell() which adds
     UID 2000 (ADB shell) to the KSU allowlist bitmap. Without this,
     allowed_for_su() returns false for all non-root UIDs, creating a
     chicken-and-egg bootstrap deadlock.

Together these produce a bootstrap deadlock:
  ┌─ Manager app can't call GRANT_ROOT (its UID not registered)
  ├─ ADB shell can't get root with usable SELinux (ksu domain doesn't exist)
  ├─ ksud can't be installed (root can't write /data/adb/ with shell context)
  └─ throne_tracker can't auto-crown Manager (ksud not running)
"""

import re
import sys

INIT_C_PATH = "KernelSU-Next/kernel/core/init.c"


def patch_init_c(path=INIT_C_PATH):
    with open(path, "r") as f:
        content = f.read()

    changed = False

    # ── Patch 1: add apply_kernelsu_rules() + cache_sid() after
    #    ksu_lsm_hook_init() ──────────────────────────────────────────
    lsm_hook_pattern = (
        "\t\tksu_lsm_hook_init();\n"
        "\n"
        "\t\tksu_adb_root_init();\n"
    )
    lsm_hook_replacement = (
        "\t\tksu_lsm_hook_init();\n"
        "\t\tapply_kernelsu_rules();\n"
        "\t\tcache_sid();\n"
        "\t\tsetup_ksu_cred();\n"
        "\n"
        "\t\tksu_adb_root_init();\n"
    )

    if lsm_hook_replacement in content:
        print("  (patch 1: apply_kernelsu_rules already there — skipping)")
    elif lsm_hook_pattern in content:
        content = content.replace(lsm_hook_pattern, lsm_hook_replacement, 1)
        changed = True
        print("  patched: apply_kernelsu_rules() + cache_sid() added after ksu_lsm_hook_init()")
    else:
        print("ERROR: could not find ksu_lsm_hook_init() target in init.c")
        print("Looking for:")
        print(repr(lsm_hook_pattern))
        sys.exit(1)

    # ── Patch 2: add ksu_load_allow_list() after ksu_allowlist_init() ─
    allowlist_pattern = (
        "\t\tksu_allowlist_init();\n"
        "\n"
        "\t\tksu_throne_tracker_init();\n"
    )
    allowlist_replacement = (
        "\t\tksu_allowlist_init();\n"
        "\t\tksu_load_allow_list();\n"
        "\n"
        "\t\tksu_throne_tracker_init();\n"
    )

    if allowlist_replacement in content:
        print("  (patch 2: ksu_load_allow_list already there — skipping)")
    elif allowlist_pattern in content:
        content = content.replace(allowlist_pattern, allowlist_replacement, 1)
        changed = True
        print("  patched: ksu_load_allow_list() added after ksu_allowlist_init()")
    else:
        print("ERROR: could not find ksu_allowlist_init() target in init.c")
        print("Looking for:")
        print(repr(allowlist_pattern))
        sys.exit(1)

    # ── Patch 3: add delayed ksud startup via workqueue (safety net) ──
    # NOTE: ksu_throne_tracker_init() is declared extern in init.c
    # (defined in kernel/throne_tracker.c), so we anchor on the
    # kernelsu_init() function declaration instead.

    # Add required includes (kmod.h for call_usermodehelper, delay.h for msecs_to_jiffies)
    if '#include <linux/kmod.h>' not in content:
        if '#include <linux/kernel.h>' in content:
            content = content.replace(
                '#include <linux/kernel.h>\n',
                '#include <linux/kernel.h>\n#include <linux/kmod.h>\n',
                1
            )
            changed = True
            print("  patched: added #include <linux/kmod.h>")
        elif '#include <linux/workqueue.h>' in content:
            content = content.replace(
                '#include <linux/workqueue.h>\n',
                '#include <linux/workqueue.h>\n#include <linux/kmod.h>\n',
                1
            )
            changed = True
            print("  patched: added #include <linux/kmod.h>")

    if '#include <linux/delay.h>' not in content:
        if '#include <linux/kmod.h>' in content:
            content = content.replace(
                '#include <linux/kmod.h>\n',
                '#include <linux/kmod.h>\n#include <linux/delay.h>\n',
                1
            )
            changed = True
            print("  patched: added #include <linux/delay.h>")

    # Insert workqueue function code before kernelsu_init()
    init_func_start = (
        "int __init kernelsu_init(void)\n"
        "{\n"
    )
    workqueue_code = (
        "static struct delayed_work ksu_ksud_start_work;\n"
        "\n"
        "static void ksu_ksud_start_worker(struct work_struct *work)\n"
        "{\n"
        "\tchar *argv[] = {\"/sbin/ksud\", NULL};\n"
        "\tchar *envp[] = {\"HOME=/\", \"PATH=/sbin:/system/bin\", NULL};\n"
        "\tint ret = call_usermodehelper(argv[0], argv, envp, UMH_WAIT_PROC);\n"
        "\tpr_info(\"ksu: attempted ksud startup via usermodehelper (ret=%d)\\n\", ret);\n"
        "\tif (ret) {\n"
        "\t\t/* Ramdisk /sbin/ksud may not exist; try /data/adb/ksu/bin/ksud */\n"
        "\t\targv[0] = \"/data/adb/ksu/bin/ksud\";\n"
        "\t\tret = call_usermodehelper(argv[0], argv, envp, UMH_WAIT_PROC);\n"
        "\t\tpr_info(\"ksu: fallback ksud from /data/adb/ (ret=%d)\\n\", ret);\n"
        "\t}\n"
        "}\n"
        "\n"
        "static void ksu_schedule_ksud_start(void)\n"
        "{\n"
        "\tINIT_DELAYED_WORK(&ksu_ksud_start_work, ksu_ksud_start_worker);\n"
        "\tschedule_delayed_work(&ksu_ksud_start_work, msecs_to_jiffies(5000));\n"
        "\tpr_info(\"ksu: scheduled ksud start in 5s (safety net)\\n\");\n"
        "}\n"
    )

    # Insert call after ksu_throne_tracker_init() in built-in path
    builtin_pattern = (
        "\t\tksu_throne_tracker_init();\n"
        "\n"
        "\t\tksu_ksud_init();\n"
    )
    builtin_replacement = (
        "\t\tksu_throne_tracker_init();\n"
        "\t\tksu_schedule_ksud_start();\n"
        "\n"
        "\t\tksu_ksud_init();\n"
    )

    if "ksu_schedule_ksud_start" in content:
        print("  (patch 3: ksud workqueue already there — skipping)")
    elif init_func_start in content:
        # Insert the workqueue functions before kernelsu_init
        content = content.replace(init_func_start, workqueue_code + "\n" + init_func_start, 1)
        changed = True
        print("  patched: added ksud delayed workqueue fallback")

        # Insert the call in the built-in path
        if builtin_pattern in content:
            content = content.replace(builtin_pattern, builtin_replacement, 1)
            print("  patched: added ksu_schedule_ksud_start() call in built-in path")
        else:
            # Fallback: try without the blank line
            builtin_alt = (
                "\t\tksu_throne_tracker_init();\n"
                "\t\tksu_ksud_init();\n"
            )
            builtin_alt_replace = (
                "\t\tksu_throne_tracker_init();\n"
                "\t\tksu_schedule_ksud_start();\n"
                "\t\tksu_ksud_init();\n"
            )
            if builtin_alt in content:
                content = content.replace(builtin_alt, builtin_alt_replace, 1)
                print("  patched: added ksu_schedule_ksud_start() (no blank line variant)")
            else:
                print("ERROR: could not find ksu_throne_tracker_init() call site")
                sys.exit(1)
    else:
        print("ERROR: could not find kernelsu_init() function start in init.c")
        print("Looking for:")
        print(repr(init_func_start))
        sys.exit(1)

    if changed:
        with open(path, "w") as f:
            f.write(content)
        print("  init.c patched successfully")
    else:
        print("  nothing to change — init.c already fully patched")

    # Final verification
    if "ksu_load_allow_list" not in content:
        print("ERROR: verification failed — ksu_load_allow_list not found in patched file")
        sys.exit(1)
    if "apply_kernelsu_rules" not in content:
        print("ERROR: verification failed — apply_kernelsu_rules not found in patched file")
        sys.exit(1)
    if "ksu_schedule_ksud_start" not in content:
        print("ERROR: verification failed — ksu_schedule_ksud_start not found in patched file")
        sys.exit(1)

    return True


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else INIT_C_PATH
    patch_init_c(path)
