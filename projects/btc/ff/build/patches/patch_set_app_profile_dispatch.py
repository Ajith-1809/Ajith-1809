#!/usr/bin/env python3
"""
patch_set_app_profile_dispatch.py — Fix app-root grants under CONFIG_KSU_DISABLE_POLICY.

ROOT CAUSE (verified in kernel/supercall/dispatch.c:do_set_app_profile):
    static int do_set_app_profile(void __user *arg)
    {
    #ifdef CONFIG_KSU_DISABLE_POLICY
        return -EOPNOTSUPP;          // <-- rejects EVERY Manager grant
    #endif
        ...
    }

  Our build enables CONFIG_KSU_DISABLE_POLICY=y (phoenix_v2.4.fragment, line 17).
  That makes the kernel's SET_APP_PROFILE supercall handler UNCONDITIONALLY
  return -EOPNOTSUPP for EVERY manager attempt to grant an app. The Manager
  issues SET_APP_PROFILE when the user toggles "allow" on an app
  (e.g. MT Manager / bin.mt.plus); the kernel refuses it; the Manager shows
  "failed to update app profile". This is why no `profile_valid` line for the
  app ever appears in ksun_diag.log, and why the Manager shows "Working"
  (its [ksu_driver] fd still arrives) but no app gets root.

  NOTE: the KSU_APP_PROFILE_VER exact-match check in profile_valid() was a
  RED HERRING — the Manager v3.3.0 transmits version 4, which equals the
  kernel's KSU_APP_PROFILE_VER (4). The diag proves recv_version==expected_ver.

WHY THIS FIX (not just dropping CONFIG_KSU_DISABLE_POLICY):
  DISABLE_POLICY is intentionally used on this CAF 4.14 build to (a) skip
  loading the persisted .allowlist file and (b) force default_root_profile on
  elevation (uid 0, full caps) instead of per-app policy. Those behaviors are
  fine and wanted. The ONLY broken link is that the Manager cannot register
  an app's allow-uid in allow_list_bitmap, because do_set_app_profile bails
  before calling ksu_set_app_profile().

  ksu_set_app_profile() (allowlist.c:280-285) sets allow_list_bitmap[uid] |= 1
  for a granted app REGARDLESS of DISABLE_POLICY (that block is not guarded by
  #ifdef CONFIG_KSU_DISABLE_POLICY). So allowing do_set_app_profile to proceed
  lets the Manager set the bitmap bit, which is exactly what allowed_for_su()
  -> escape_with_root_profile() needs to elevate the app. This is the minimal,
  surgical fix that preserves the rest of the DISABLE_POLICY design.

FIX: Remove the early `return -EOPNOTSUPP;` under CONFIG_KSU_DISABLE_POLICY so
  do_set_app_profile proceeds to copy_from_user + ksu_set_app_profile (which
  sets the allow bitmap). ksu_persistent_allow_list() (schedules a file write)
  is harmless under DISABLE_POLICY because ksu_load_allow_list() is the side
  that is skipped.

Usage:
  python3 patch_set_app_profile_dispatch.py [path/to/supercall/dispatch.c]
"""

import sys
import os

MARKER = "KSUN_SET_APP_PROFILE_DISPATCH_FIX"

DISPATCH_C_PATH = "KernelSU-Next/kernel/supercall/dispatch.c"


def find_file():
    candidates = [
        "KernelSU-Next/kernel/supercall/dispatch.c",
        "kernel/supercall/dispatch.c",
        "drivers/kernelsu/supercall/dispatch.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def patch(path):
    with open(path) as f:
        content = f.read()

    if MARKER in content:
        print("OK: set_app_profile dispatch fix already present — skipping")
        return True

    # Locate do_set_app_profile and the DISABLE_POLICY early-return block.
    idx = content.find("static int do_set_app_profile(")
    if idx < 0:
        print("ERROR: do_set_app_profile() not found in %s" % path)
        return False

    # The exact block to neutralize (the early return under DISABLE_POLICY).
    bad_block = (
        "#ifdef CONFIG_KSU_DISABLE_POLICY\n"
        "    return -EOPNOTSUPP;\n"
        "#endif\n"
    )
    # Search within the function body (next ~20 lines after the signature).
    body = content[idx:idx + 600]
    bidx = body.find(bad_block)
    if bidx < 0:
        print("ERROR: DISABLE_POLICY early-return block not found in "
              "do_set_app_profile()")
        print("Looking for:")
        print(repr(bad_block))
        print("Function body excerpt:")
        print(body[:400])
        return False

    # Replace the bad block with a comment explaining the override. We keep
    # DISABLE_POLICY semantics for *policy* (default profile) but allow the
    # allow-uid bitmap to be registered so granted apps can elevate.
    good_block = (
        "#ifdef CONFIG_KSU_DISABLE_POLICY\n"
        "    /*\n"
        "     * KSUN build fix: under DISABLE_POLICY the upstream code returns\n"
        "     * -EOPNOTSUPP here, which makes the Manager unable to register an\n"
        "     * app's allow-uid in allow_list_bitmap, so no app can ever get\n"
        "     * root (Manager shows \"failed to update app profile\"). We still\n"
        "     * use the default_root_profile for the actual elevation, but we\n"
        "     * MUST let ksu_set_app_profile() run so the bitmap bit is set.\n"
        "     * See build/patches/patch_set_app_profile_dispatch.py.\n"
        "     */\n"
        "#endif\n"
        "    /* KSUN_SET_APP_PROFILE_DISPATCH_FIX: proceed past DISABLE_POLICY */\n"
    )

    new_body = body[:bidx] + good_block + body[bidx + len(bad_block):]
    new_content = content[:idx] + new_body + content[idx + len(body):]

    with open(path, "w") as f:
        f.write(new_content)

    if MARKER in new_content and "do_set_app_profile" in new_content:
        print("OK: neutralized DISABLE_POLICY early-return in do_set_app_profile()")
        return True
    print("ERROR: set_app_profile dispatch fix incomplete")
    return False


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0] if args else find_file()
    if not path or not os.path.exists(path):
        print("ERROR: dispatch.c not found at %s" % (path or "(none)"))
        sys.exit(1)
    if not patch(path):
        sys.exit(1)
