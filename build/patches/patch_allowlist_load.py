#!/usr/bin/env python3
"""
patch_allowlist_load.py — Two fixes for the persisted allow-list under
CONFIG_KSU_DISABLE_POLICY (phoenix_v2.4.fragment line 17).

Our build sets CONFIG_KSU_DISABLE_POLICY=y. That flag was causing TWO user
visible bugs on this CAF 4.14 KSUN build:

FIX 1 — "grants lost after every reboot"
  ksu_load_allow_list() (kernel/policy/allowlist.c) starts with:
      void ksu_load_allow_list()
      {
      #ifdef CONFIG_KSU_DISABLE_POLICY
          pr_info("allowlist load skipped because policy is disabled\n");
          return;                       // <-- bails BEFORE reading the file
      #endif
          loff_t off = 0;
          ... opens /data/adb/ksu/.allowlist, restores allow_list_bitmap ...
  Because of the early return, the persisted .allowlist is NEVER read back
  into the in-memory allow_list_bitmap at boot. A granted app works for the
  current boot (ksu_set_app_profile() sets the bitmap and the Manager writes
  the file to disk), but after a reboot the bitmap starts empty -> the app
  needs to be re-granted in the Manager.
  FIX: remove the early return so ksu_load_allow_list() proceeds to restore
  the persisted bitmap. (profile_valid()'s exact-version check is already
  gated behind #ifndef CONFIG_KSU_DISABLE_POLICY — patch_profile_valid.py —
  so the mixed v3/v4 records the Manager writes pass and are restored.)

FIX 2 — "a phantom app is granted root by default, but it isn't installed"
  ksu_grant_root_to_shell() is invoked in ksu_load_allow_list() under
  #ifdef CONFIG_KSU_DEBUG, which auto-grants UID 2000 (com.android.shell).
  (patch_allowlist.py earlier moved that call ABOVE the DISABLE_POLICY guard
  so shell survives boot under DISABLE_POLICY.) That entry shows up in the
  Manager as a pre-granted app the user never approved and often does not
  recognise as a real app -> the "phantom default grant".
  The throne tracker's prune keeps it because uid 2000 IS in
  /data/system/packages.list, so pruning cannot remove it. The only clean
  fix is to stop auto-granting it.
  FIX: remove the CONFIG_KSU_DEBUG shell auto-grant block. The user grants
  apps (including shell, if they want it) manually in the Manager; with FIX 1
  that grant now persists across reboots. Nothing else depends on this
  auto-grant (the KSU diag logger uses ksu_cred, not the shell uid).

Both edits are order-independent and idempotent (guarded by MARKER).

Usage:
  python3 patch_allowlist_load.py [path/to/policy/allowlist.c]
"""

import sys
import os

MARKER = "KSUN_ALLOWLIST_LOAD_FIX"

ALLOWLIST_C_PATH = "KernelSU-Next/kernel/policy/allowlist.c"


def find_file():
    candidates = [
        "KernelSU-Next/kernel/policy/allowlist.c",
        "kernel/policy/allowlist.c",
        "drivers/kernelsu/policy/allowlist.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def patch(path):
    with open(path) as f:
        content = f.read()

    if MARKER in content:
        print("OK: allowlist load+phantom fix already present — skipping")
        return True

    changed = False

    # --- FIX 1: neutralize the DISABLE_POLICY early-return in load ----------
    load_guard = (
        "#ifdef CONFIG_KSU_DISABLE_POLICY\n"
        "\tpr_info(\"allowlist load skipped because policy is disabled\\n\");\n"
        "\treturn;\n"
        "#endif\n"
    )
    if load_guard in content:
        # Drop the whole guard block so the file load runs unconditionally.
        # Log to ksun_diag.log (via ksu_profile_diag_log, provided by
        # patch_profile_valid.py) so the boot-time restore is observable
        # from TWRP even though dmesg is unreadable on the booted ROM.
        content = content.replace(
            load_guard,
            "\t/* KSUN_ALLOWLIST_LOAD_FIX: never skip restoring the persisted "
            "bitmap at boot */\n"
            "\t{\n"
            "\t\tchar _pdbuf[128];\n"
            "\t\tsnprintf(_pdbuf, sizeof(_pdbuf),\n"
            "\t\t\t\"KSU_DIAG allowlist_load: restoring persisted bitmap "
            "(DISABLE_POLICY)\\n\");\n"
            "\t\tksu_profile_diag_log(_pdbuf);\n"
            "\t}\n",
            1,
        )
        changed = True
        print("OK: FIX1 removed DISABLE_POLICY early-return in "
              "ksu_load_allow_list() — bitmap restored at boot")
    else:
        print("WARN: load DISABLE_POLICY guard not found; assuming already "
              "handled or not present")

    # --- FIX 2: remove the DEBUG shell auto-grant (phantom) -----------------
    shell_grant = (
        "#ifdef CONFIG_KSU_DEBUG\n"
        "\t// always allow adb shell by default\n"
        "\tksu_grant_root_to_shell();\n"
        "#endif\n"
    )
    if shell_grant in content:
        content = content.replace(
            shell_grant,
            "\t/* KSUN_ALLOWLIST_LOAD_FIX: do NOT auto-grant shell; "
            "avoid phantom default grant */\n",
            1,
        )
        changed = True
        print("OK: FIX2 removed CONFIG_KSU_DEBUG shell auto-grant "
              "(phantom default grant gone)")
    else:
        print("WARN: DEBUG shell-grant block not found; assuming already "
              "handled or CONFIG_KSU_DEBUG path differs")

    # --- FIX 3: self-clean stale shell phantom from the persisted file -----
    # FIX 2 stopped NEW auto-grants, but the on-disk .allowlist from prior
    # builds still carries the com.android.shell (uid 2000) entry. With FIX 1
    # we now reload that file at boot, which would re-introduce the phantom.
    # Drop it at load time; the next persist write (triggered below for
    # version-migrated files, and on any grant) drops it from disk for good.
    load_skip = (
        "        migrate_profile(version, &profile);\n"
    )
    if load_skip in content:
        content = content.replace(
            load_skip,
            load_skip
            + "        /* KSUN_ALLOWLIST_LOAD_FIX: drop the legacy shell auto-grant "
              "phantom (uid 2000) on load */\n"
            "        if (profile.current_uid == 2000 &&\n"
            "            !strcmp(profile.key, \"com.android.shell\")) {\n"
            "            {\n"
            "                char _pdbuf[128];\n"
            "                snprintf(_pdbuf, sizeof(_pdbuf),\n"
            "                    \"KSU_DIAG allowlist_load: skipped legacy shell "
            "phantom uid 2000\\n\");\n"
            "                ksu_profile_diag_log(_pdbuf);\n"
            "            }\n"
            "            continue;\n"
            "        }\n",
            1,
        )
        changed = True
        print("OK: FIX3 added self-clean of stale shell phantom at load")
    else:
        print("WARN: load migrate_profile marker not found; phantom may "
              "reload from disk — check kernel version")

    if not changed:
        print("NOTE: nothing changed")
        return True

    with open(path, "w") as f:
        f.write(content)

    # Idempotency / sanity: MARKER text is present, early-return gone.
    if MARKER in content and "allowlist load skipped because policy is disabled" not in content:
        print("OK: allowlist load fix written and verified")
        return True
    print("ERROR: allowlist load fix incomplete")
    return False


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0] if args else find_file()
    if not path or not os.path.exists(path):
        print("ERROR: allowlist.c not found at %s" % (path or "(none)"))
        sys.exit(1)
    if not patch(path):
        sys.exit(1)
