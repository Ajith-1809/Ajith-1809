#!/usr/bin/env python3
"""
patch_get_app_profile_dispatch.py — Fix the Superuser list under CONFIG_KSU_DISABLE_POLICY.

ROOT CAUSE (verified in kernel/supercall/dispatch.c:do_get_app_profile):
    static int do_get_app_profile(void __user *arg)
    {
    #ifdef CONFIG_KSU_DISABLE_POLICY
        return -EOPNOTSUPP;          // <-- rejects EVERY Manager per-uid profile read
    #endif
        ...
    }

  Our build enables CONFIG_KSU_DISABLE_POLICY=y (phoenix_v2.4.fragment, line 17).
  That makes the kernel's GET_APP_PROFILE supercall handler UNCONDITIONALLY
  return -EOPNOTSUPP for EVERY manager attempt to fetch a single app's profile
  by uid.

  THE SYMPTOM THIS CAUSES:
  The KSU-Next Manager (com.rifsxd.ksunext) shows the home-screen count
  "N apps have root" using getSuperuserCount -> KSU_IOCTL_NEW_GET_ALLOW_LIST ->
  do_new_get_allow_list -> ksu_get_allow_list(). That handler is NOT guarded by
  DISABLE_POLICY, so it correctly reads the in-memory allow_list and counts the
  granted apps (count == 1, e.g. bin.mt.plus). But the Superuser *list* view must
  resolve each uid to its package/profile: it calls Natives.getAppProfile(uid)
  -> KSU_IOCTL_GET_APP_PROFILE -> do_get_app_profile, which the kernel rejects
  with -EOPNOTSUPP. The Manager cannot resolve any uid to a package -> the
  Superuser list renders EMPTY even though the home count says 1 app has root.

  This is the exact mirror of the do_set_app_profile bug that
  patch_set_app_profile_dispatch.py fixes for GRANTING root. Here we fix READING
  the per-uid profile so the Superuser list can populate.

WHY THIS FIX (not just dropping CONFIG_KSU_DISABLE_POLICY):
  DISABLE_POLICY is intentionally used on this CAF 4.14 build to skip loading the
  persisted .allowlist file and to force default_root_profile on elevation. The
  ONLY broken link is that the Manager cannot READ an app's app_profile by uid,
  because do_get_app_profile bails before calling ksu_get_app_profile(), which
  itself is NOT guarded by DISABLE_POLICY and just walks allow_list.

  ksu_get_app_profile() (allowlist.c) only does list_for_each_entry_rcu over
  allow_list and memcpy's the profile back; it has no DISABLE_POLICY dependency.
  So letting do_get_app_profile proceed lets the Manager resolve each granted
  uid to its package/profile and render the Superuser list. Minimal, surgical,
  preserves the rest of the DISABLE_POLICY design.

FIX: Remove the early `return -EOPNOTSUPP;` under CONFIG_KSU_DISABLE_POLICY so
  do_get_app_profile proceeds to copy_from_user + ksu_get_app_profile.

Usage:
  python3 patch_get_app_profile_dispatch.py [path/to/supercall/dispatch.c]
"""

import sys
import os

MARKER = "KSUN_GET_APP_PROFILE_DISPATCH_FIX"

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
        print("OK: get_app_profile dispatch fix already present — skipping")
        return True

    # Locate do_get_app_profile and the DISABLE_POLICY early-return block.
    idx = content.find("static int do_get_app_profile(")
    if idx < 0:
        print("ERROR: do_get_app_profile() not found in %s" % path)
        return False

    # The exact block to neutralize (the early return under DISABLE_POLICY).
    bad_block = (
        "#ifdef CONFIG_KSU_DISABLE_POLICY\n"
        "    return -EOPNOTSUPP;\n"
        "#endif\n"
    )
    # Search within the function body (next ~600 chars after the signature).
    body = content[idx:idx + 600]
    bidx = body.find(bad_block)
    if bidx < 0:
        print("ERROR: DISABLE_POLICY early-return block not found in "
              "do_get_app_profile()")
        print("Looking for:")
        print(repr(bad_block))
        print("Function body excerpt:")
        print(body[:400])
        return False

    # Replace the bad block with a comment explaining the override. We keep
    # DISABLE_POLICY semantics for *policy* (default profile) but allow the
    # per-uid profile READ so the Manager's Superuser list can resolve granted
    # apps. See build/patches/patch_get_app_profile_dispatch.py.
    good_block = (
        "#ifdef CONFIG_KSU_DISABLE_POLICY\n"
        "    /*\n"
        "     * KSUN build fix: under DISABLE_POLICY the upstream code returns\n"
        "     * -EOPNOTSUPP here, which makes the Manager unable to READ a single\n"
        "     * app's profile by uid, so its Superuser list renders empty even\n"
        "     * though getSuperuserCount (GET_ALLOW_LIST, not guarded) reports N\n"
        "     * apps. ksu_get_app_profile() is itself NOT guarded by DISABLE_POLICY\n"
        "     * and only walks allow_list, so we MUST let it run. See\n"
        "     * build/patches/patch_get_app_profile_dispatch.py.\n"
        "     */\n"
        "#endif\n"
        "    /* KSUN_GET_APP_PROFILE_DISPATCH_FIX: proceed past DISABLE_POLICY */\n"
    )

    new_body = body[:bidx] + good_block + body[bidx + len(bad_block):]
    new_content = content[:idx] + new_body + content[idx + len(body):]

    with open(path, "w") as f:
        f.write(new_content)

    if MARKER in new_content and "do_get_app_profile" in new_content:
        print("OK: neutralized DISABLE_POLICY early-return in do_get_app_profile()")
        return True
    print("ERROR: get_app_profile dispatch fix incomplete")
    return False


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    path = args[0] if args else find_file()
    if not path or not os.path.exists(path):
        print("ERROR: dispatch.c not found at %s" % (path or "(none)"))
        sys.exit(1)
    if not patch(path):
        sys.exit(1)
