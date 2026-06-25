#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
#
# susfs_show_commands.sh — Add SUSFS userspace SHOW commands to kernel 4.14
#
# The KBapna v1.5.5 SUSFS tree has all hook functions compiled in, but lacks
# the three userspace SHOW commands that KSU modules like BREENE use to
# detect SUSFS at runtime:
#
#   0x555e1  CMD_SUSFS_SHOW_VERSION
#   0x555e2  CMD_SUSFS_SHOW_ENABLED_FEATURES
#   0x555e3  CMD_SUSFS_SHOW_VARIANT
#
# This script:
#   1. Adds SHOW structs to include/linux/susfs.h
#   2. Adds SHOW functions to fs/susfs.c  (using v1.5.5's existing logging style)
#   3. Adds SUSFS magic dispatch (SHOW commands only) to
#      KernelSU-Next/kernel/supercall/supercall.c
#
# Run from the KBapna kernel source root (after KSUN setup.sh has run).
# Usage: susfs_show_commands.sh <kernel-src-path>

set -euo pipefail

KERNEL_SRC="$1"

echo "=== Adding SUSFS SHOW commands ==="

# ──────────────────────────────────────────────
# Step 1: Get SUSFS_LOGI style from susfs.c
# ──────────────────────────────────────────────
SUSFS_C="$KERNEL_SRC/fs/susfs.c"
if [ ! -f "$SUSFS_C" ]; then
    echo "::error::susfs.c not found at $SUSFS_C"
    exit 1
fi

# Determine the LOG macro used by v1.5.5
# v1.5.5 uses: "if (susfs_is_log_enabled) printk(KERN_INFO ...)" pattern
# We'll define our own SUSFS_LOGI in a guarded block so it doesn't conflict.
HAS_SUSFS_LOGI=$(grep -c 'SUSFS_LOGI' "$SUSFS_C" || true)
if [ "$HAS_SUSFS_LOGI" -gt 0 ]; then
    LOG_MACRO="SUSFS_LOGI"
else
    LOG_MACRO="pr_info"
fi
echo "  Using log macro: $LOG_MACRO"

# ──────────────────────────────────────────────
# Step 2: Append SHOW structs to susfs.h
# ──────────────────────────────────────────────
SUSFS_H="$KERNEL_SRC/include/linux/susfs.h"
if [ ! -f "$SUSFS_H" ]; then
    echo "::error::susfs.h not found at $SUSFS_H"
    exit 1
fi

if grep -q 'st_susfs_enabled_features' "$SUSFS_H"; then
    echo "  susfs.h already patched — skipping"
else
    echo "  Adding SHOW structs to susfs.h ..."
    # Find the forward-declarations separator comment and insert before it
    # Pattern: the line "/***********************/" followed by forward decls
    cat >> "$SUSFS_H" << 'SUSFS_STRUCTS'

/* ================================================
 * SUSFS SHOW commands — added by susfs_show_commands.sh
 * ================================================ */

/* get enabled features */
struct st_susfs_enabled_features {
	char                                    enabled_features[8192];
	int                                     err;
};

/* show variant */
struct st_susfs_variant {
	char                                    susfs_variant[16];
	int                                     err;
};

/* show version */
struct st_susfs_version {
	char                                    susfs_version[16];
	int                                     err;
};
SUSFS_STRUCTS
    echo "  Structs added to susfs.h"
fi

# ──────────────────────────────────────────────
# Step 3: Append SHOW functions to susfs.c
# ──────────────────────────────────────────────
if grep -q 'CMD_SUSFS_SHOW_VERSION' "$SUSFS_C"; then
    echo "  susfs.c already patched — skipping"
else
    echo "  Adding SHOW functions to susfs.c ..."
    # We add a static helper copy_config_to_buf and the three SHOW functions.
    # Guard with a unique define for idempotency.
    cat >> "$SUSFS_C" << 'SUSFS_SHOW_FUNCS'

/* ================================================
 * SUSFS SHOW commands — added by susfs_show_commands.sh
 * These enable userspace (KSU modules like BREENE) to
 * query SUSFS version, variant, and enabled features.
 * Uses v1.5.5-compatible signatures (void __user ** dispatch).
 * ================================================ */
#ifdef CONFIG_KSU_SUSFS

/* Helper: copy a config name into the features buffer */
static inline int susfs_copy_config_to_buf(const char *config, char *buf,
					   size_t *copied, size_t buf_size)
{
	size_t len = strlen(config);
	if (*copied + len >= buf_size)
		return -ENOSPC;
	memcpy(buf + *copied, config, len);
	*copied += len;
	return 0;
}

/* Show enabled features — returns list of compiled-in CONFIG options */
void susfs_get_enabled_features(void __user **user_info)
{
	struct st_susfs_enabled_features *info;
	char *buf_ptr = NULL;
	size_t copied_size = 0;

	info = kzalloc(sizeof(*info), GFP_KERNEL);
	if (!info)
		goto out;

	if (copy_from_user(info, (struct st_susfs_enabled_features __user *)*user_info,
			   sizeof(*info))) {
		info->err = -EFAULT;
		goto out_copy;
	}

	buf_ptr = info->enabled_features;

#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	info->err = susfs_copy_config_to_buf("CONFIG_KSU_SUSFS_SUS_PATH\n",
					     buf_ptr, &copied_size,
					     sizeof(info->enabled_features));
	if (info->err) goto out_copy;
	buf_ptr = info->enabled_features + copied_size;
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	info->err = susfs_copy_config_to_buf("CONFIG_KSU_SUSFS_SUS_MOUNT\n",
					     buf_ptr, &copied_size,
					     sizeof(info->enabled_features));
	if (info->err) goto out_copy;
	buf_ptr = info->enabled_features + copied_size;
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT
	info->err = susfs_copy_config_to_buf("CONFIG_KSU_SUSFS_SUS_KSTAT\n",
					     buf_ptr, &copied_size,
					     sizeof(info->enabled_features));
	if (info->err) goto out_copy;
	buf_ptr = info->enabled_features + copied_size;
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
	info->err = susfs_copy_config_to_buf("CONFIG_KSU_SUSFS_SPOOF_UNAME\n",
					     buf_ptr, &copied_size,
					     sizeof(info->enabled_features));
	if (info->err) goto out_copy;
	buf_ptr = info->enabled_features + copied_size;
#endif
#ifdef CONFIG_KSU_SUSFS_ENABLE_LOG
	info->err = susfs_copy_config_to_buf("CONFIG_KSU_SUSFS_ENABLE_LOG\n",
					     buf_ptr, &copied_size,
					     sizeof(info->enabled_features));
	if (info->err) goto out_copy;
	buf_ptr = info->enabled_features + copied_size;
#endif
#ifdef CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
	info->err = susfs_copy_config_to_buf("CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS\n",
					     buf_ptr, &copied_size,
					     sizeof(info->enabled_features));
	if (info->err) goto out_copy;
	buf_ptr = info->enabled_features + copied_size;
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	info->err = susfs_copy_config_to_buf("CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG\n",
					     buf_ptr, &copied_size,
					     sizeof(info->enabled_features));
	if (info->err) goto out_copy;
	buf_ptr = info->enabled_features + copied_size;
#endif
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT
	info->err = susfs_copy_config_to_buf("CONFIG_KSU_SUSFS_OPEN_REDIRECT\n",
					     buf_ptr, &copied_size,
					     sizeof(info->enabled_features));
	if (info->err) goto out_copy;
	buf_ptr = info->enabled_features + copied_size;
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
	info->err = susfs_copy_config_to_buf("CONFIG_KSU_SUSFS_SUS_MAP\n",
					     buf_ptr, &copied_size,
					     sizeof(info->enabled_features));
	if (info->err) goto out_copy;
	buf_ptr = info->enabled_features + copied_size;
#endif

	info->err = 0;

out_copy:
	if (copy_to_user((struct st_susfs_enabled_features __user *)*user_info,
			 info, sizeof(*info))) {
		info->err = -EFAULT;
	}
	pr_info("susfs: CMD_SUSFS_SHOW_ENABLED_FEATURES -> ret: %d\n", info->err);
	kfree(info);
out:
	return;
}

/* Show variant — returns "GKI" or "NON-GKI" */
void susfs_show_variant(void __user **user_info)
{
	struct st_susfs_variant info = {0};

	if (copy_from_user(&info, (struct st_susfs_variant __user *)*user_info,
			   sizeof(info))) {
		info.err = -EFAULT;
		goto out;
	}

	strlcpy(info.susfs_variant, SUSFS_VARIANT, sizeof(info.susfs_variant));
	info.err = 0;

out:
	if (copy_to_user((struct st_susfs_variant __user *)*user_info,
			 &info, sizeof(info))) {
		info.err = -EFAULT;
	}
	pr_info("susfs: CMD_SUSFS_SHOW_VARIANT -> ret: %d\n", info.err);
}

/* Show version — returns SUSFS_VERSION string */
void susfs_show_version(void __user **user_info)
{
	struct st_susfs_version info = {0};

	if (copy_from_user(&info, (struct st_susfs_version __user *)*user_info,
			   sizeof(info))) {
		info.err = -EFAULT;
		goto out;
	}

	strlcpy(info.susfs_version, SUSFS_VERSION, sizeof(info.susfs_version));
	info.err = 0;

out:
	if (copy_to_user((struct st_susfs_version __user *)*user_info,
			 &info, sizeof(info))) {
		info.err = -EFAULT;
	}
	pr_info("susfs: CMD_SUSFS_SHOW_VERSION -> ret: %d\n", info.err);
}

#endif /* CONFIG_KSU_SUSFS */
SUSFS_SHOW_FUNCS
    echo "  SHOW functions added to susfs.c"
fi

# ──────────────────────────────────────────────
# Step 4: Patch KSUN supercall.c for SUSFS dispatch
# ──────────────────────────────────────────────
# Find supercall.c
SUPERCALL_C=""
for candidate in \
    "$KERNEL_SRC/KernelSU-Next/kernel/supercall/supercall.c" \
    "$KERNEL_SRC/KernelSU/kernel/supercall/supercall.c" \
    "$KERNEL_SRC/drivers/kernelsu/supercall/supercall.c"; do
    if [ -f "$candidate" ]; then
        SUPERCALL_C="$candidate"
        break
    fi
done

if [ -z "$SUPERCALL_C" ]; then
    echo "::error::supercall.c not found in any expected location"
    exit 1
fi
echo "  Found supercall.c at: $SUPERCALL_C"

if grep -q 'SUSFS_MAGIC' "$SUPERCALL_C"; then
    echo "  supercall.c already patched — skipping"
else
    echo "  Adding SUSFS SHOW dispatch to supercall.c ..."

    # Find the ksu_handle_sys_reboot function and insert SUSFS SHOW dispatch
    # after the magic1 check returns 0, before the KSU_INSTALL_MAGIC2 check.
    # Use awk to add the SUSFS block after:
    #    if (magic1 != KSU_INSTALL_MAGIC1)
    #        return 0;
    # and before the next line.

    awk '
    # Track state
    /ksu_handle_sys_reboot/ { found_func = 1 }
    found_func && /if \(magic1 != KSU_INSTALL_MAGIC1\)/ { found_magic1 = 1 }
    found_magic1 && /return 0;/ && !done {
        print "    /* SUSFS SHOW commands dispatch — added by susfs_show_commands.sh */"
        print "    if (magic2 == SUSFS_MAGIC && current_uid().val == 0) {"
        print "        switch(cmd) {"
        print "        case CMD_SUSFS_SHOW_ENABLED_FEATURES:"
        print "            susfs_get_enabled_features(arg);"
        print "            return 0;"
        print "        case CMD_SUSFS_SHOW_VARIANT:"
        print "            susfs_show_variant(arg);"
        print "            return 0;"
        print "        case CMD_SUSFS_SHOW_VERSION:"
        print "            susfs_show_version(arg);"
        print "            return 0;"
        print "        default:"
        print "            return -EINVAL;"
        print "        }"
        print "    }"
        done = 1
    }
    { print }
    ' "$SUPERCALL_C" > "${SUPERCALL_C}.tmp" && mv "${SUPERCALL_C}.tmp" "$SUPERCALL_C"

    echo "  SUSFS SHOW dispatch added to supercall.c"
fi

echo "=== SUSFS SHOW commands applied successfully ==="
