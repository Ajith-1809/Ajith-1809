/* SPDX-License-Identifier: GPL-2.0 */
/*
 * susfs_v2_backport_compat.h — SUSFS v2.2.0 backport compat layer for kernel 4.14
 *
 * Force-included via ccflags-y in fs/Makefile for susfs.o.
 *
 * Provides:
 *  - Legacy v1.5.5 flags that KBapna tree's kernel hooks reference
 *  - v2.2.0-new defines that the replaced GKI source (susfs.c) expects
 *  - v2.2.0 inline helpers (susfs_is_current_proc_umounted etc.)
 *  - fsnotify callback API shim (handle_inode_event -> handle_event)
 *  - fsnotify_add_inode_mark compat (GKI 5.15 -> kernel 4.14)
 *
 * Without this header, the v1.5.5 hooks and v2.2.0 susfs.c cannot both
 * compile on kernel 4.14.
 */
#ifndef _SUSFS_V2_BACKPORT_COMPAT_H_
#define _SUSFS_V2_BACKPORT_COMPAT_H_

#include <linux/version.h>
#include <linux/fsnotify_backend.h>
#include <linux/bits.h>
#include <linux/threads.h>
#include <linux/thread_info.h>
#include <linux/cred.h>

/* =====================================================================
 * SECTION 1 — Legacy v1.5.5 defines (for KBapna tree's kernel hooks)
 *
 * These are defined in KBapna's original v1.5.5 susfs_def.h but NOT
 * in v2.2.0's susfs_def.h. Kernel hook callers (fs/stat.c, fs/open.c,
 * fs/exec.c, fs/namei.c, fs/namespace.c) reference them at compile time.
 * ===================================================================== */

#ifndef INODE_STATE_SUS_PATH
#define INODE_STATE_SUS_PATH BIT(24)
#endif
#ifndef INODE_STATE_SUS_MOUNT
#define INODE_STATE_SUS_MOUNT BIT(25)
#endif
#ifndef INODE_STATE_SUS_KSTAT
#define INODE_STATE_SUS_KSTAT BIT(26)
#endif
#ifndef INODE_STATE_OPEN_REDIRECT
#define INODE_STATE_OPEN_REDIRECT BIT(27)
#endif
#ifndef TASK_STRUCT_NON_ROOT_USER_APP_PROC
#define TASK_STRUCT_NON_ROOT_USER_APP_PROC BIT(24)
#endif

#ifndef DEFAULT_SUS_MNT_ID
#define DEFAULT_SUS_MNT_ID 100000
#endif
#ifndef DEFAULT_SUS_MNT_GROUP_ID
#define DEFAULT_SUS_MNT_GROUP_ID 1000
#endif
#ifndef DEFAULT_SUS_MNT_ID_FOR_KSU_PROC_UNSHARE
#define DEFAULT_SUS_MNT_ID_FOR_KSU_PROC_UNSHARE 1000000
#endif

/* =====================================================================
 * SECTION 2 — v2.2.0 defines (from GKI gki-android14-5.15 susfs_def.h)
 *
 * These are needed by the replaced v2.2.0 susfs.c/susfs.h source files.
 * The original v1.5.5 susfs_def.h is preserved intact, so v2.2.0-only
 * defines must live here.
 * ===================================================================== */

#ifndef SUSFS_MAGIC
#define SUSFS_MAGIC 0xFAFAFAFA
#endif

/* CMD codes matching v2.2.0 exactly */
#ifndef CMD_SUSFS_ADD_SUS_PATH
#define CMD_SUSFS_ADD_SUS_PATH 0x55550
#endif
#ifndef CMD_SUSFS_ADD_SUS_PATH_LOOP
#define CMD_SUSFS_ADD_SUS_PATH_LOOP 0x55553
#endif
#ifndef CMD_SUSFS_ADD_SUS_MOUNT
#define CMD_SUSFS_ADD_SUS_MOUNT 0x55560
#endif
#ifndef CMD_SUSFS_ADD_SUS_KSTAT
#define CMD_SUSFS_ADD_SUS_KSTAT 0x55570
#endif
#ifndef CMD_SUSFS_UPDATE_SUS_KSTAT
#define CMD_SUSFS_UPDATE_SUS_KSTAT 0x55571
#endif
#ifndef CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY
#define CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY 0x55572
#endif
#ifndef CMD_SUSFS_RUN_UMOUNT_FOR_CURRENT_MNT_NS
#define CMD_SUSFS_RUN_UMOUNT_FOR_CURRENT_MNT_NS 0x555d0
#endif
#ifndef CMD_SUSFS_ADD_TRY_UMOUNT
#define CMD_SUSFS_ADD_TRY_UMOUNT 0x55580
#endif
#ifndef CMD_SUSFS_SET_UNAME
#define CMD_SUSFS_SET_UNAME 0x55590
#endif
#ifndef CMD_SUSFS_ENABLE_LOG
#define CMD_SUSFS_ENABLE_LOG 0x555a0
#endif
#ifndef CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG
#define CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG 0x555b0
#endif
#ifndef CMD_SUSFS_ADD_OPEN_REDIRECT
#define CMD_SUSFS_ADD_OPEN_REDIRECT 0x555c0
#endif
#ifndef CMD_SUSFS_SHOW_VERSION
#define CMD_SUSFS_SHOW_VERSION 0x555e1
#endif
#ifndef CMD_SUSFS_SHOW_ENABLED_FEATURES
#define CMD_SUSFS_SHOW_ENABLED_FEATURES 0x555e2
#endif
#ifndef CMD_SUSFS_SHOW_VARIANT
#define CMD_SUSFS_SHOW_VARIANT 0x555e3
#endif
#ifndef CMD_SUSFS_SHOW_SUS_SU_WORKING_MODE
#define CMD_SUSFS_SHOW_SUS_SU_WORKING_MODE 0x555e4
#endif
#ifndef CMD_SUSFS_IS_SUS_SU_READY
#define CMD_SUSFS_IS_SUS_SU_READY 0x555f0
#endif

/* Buffer/constant sizes */
#ifndef SUSFS_MAX_LEN_PATHNAME
#define SUSFS_MAX_LEN_PATHNAME 256
#endif
#ifndef SUSFS_FAKE_CMDLINE_OR_BOOTCONFIG_SIZE
#define SUSFS_FAKE_CMDLINE_OR_BOOTCONFIG_SIZE 8192
#endif
#ifndef SUSFS_ENABLED_FEATURES_SIZE
#define SUSFS_ENABLED_FEATURES_SIZE 8192
#endif
#ifndef SUSFS_MAX_VERSION_BUFSIZE
#define SUSFS_MAX_VERSION_BUFSIZE 16
#endif
#ifndef SUSFS_MAX_VARIANT_BUFSIZE
#define SUSFS_MAX_VARIANT_BUFSIZE 16
#endif

/* Try-umount flags */
#ifndef TRY_UMOUNT_DEFAULT
#define TRY_UMOUNT_DEFAULT 0
#endif
#ifndef TRY_UMOUNT_DETACH
#define TRY_UMOUNT_DETACH 1
#endif

#ifndef VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT
#define VFSMOUNT_MNT_FLAGS_KSU_UNSHARED_MNT 0x80000000
#endif

/* Mount-ID constants (v2.2.0 renames) */
#ifndef DEFAULT_KSU_MNT_ID
#define DEFAULT_KSU_MNT_ID 2000000000
#endif
#ifndef DEFAULT_KSU_MNT_GROUP_ID
#define DEFAULT_KSU_MNT_GROUP_ID 200000
#endif

/* FUSE detection — v2.2.0 uses this for sdcardfs; not in 4.14's magic.h */
#ifndef FUSE_SUPER_MAGIC
#define FUSE_SUPER_MAGIC 0x65735546
#endif

/* Address-space flags for i_mapping (v2.2.0 uses these instead of INODE_STATE_*) */
#ifndef AS_FLAGS_SUS_PATH
#define AS_FLAGS_SUS_PATH 33
#endif
#ifndef AS_FLAGS_SUS_MOUNT
#define AS_FLAGS_SUS_MOUNT 34
#endif
#ifndef AS_FLAGS_SUS_KSTAT
#define AS_FLAGS_SUS_KSTAT 35
#endif
#ifndef AS_FLAGS_OPEN_REDIRECT
#define AS_FLAGS_OPEN_REDIRECT 36
#endif
#ifndef AS_FLAGS_SUS_MAP
#define AS_FLAGS_SUS_MAP 39
#endif

#ifndef TIF_PROC_UMOUNTED
#define TIF_PROC_UMOUNTED 33
#endif

/* Nameidata flags for LOOKUP_LAST detection */
#ifndef ND_STATE_LOOKUP_LAST
#define ND_STATE_LOOKUP_LAST 32
#endif
#ifndef ND_STATE_OPEN_LAST
#define ND_STATE_OPEN_LAST 64
#endif
#ifndef ND_FLAGS_LOOKUP_LAST
#define ND_FLAGS_LOOKUP_LAST 0x2000000
#endif

#ifndef MAGIC_MOUNT_WORKDIR
#define MAGIC_MOUNT_WORKDIR "/debug_ramdisk/workdir"
#endif

/* =====================================================================
 * SECTION 3 — v2.2.0 inline helpers (from GKI susfs_def.h)
 *
 * These are static inline functions defined in the GKI susfs_def.h
 * that the replaced v2.2.0 susfs.c calls directly.
 * ===================================================================== */

#ifndef __SUSFS_V2_COMPAT_HELPERS
#define __SUSFS_V2_COMPAT_HELPERS

static inline bool susfs_starts_with(const char *str, const char *prefix)
{
	while (*prefix) {
		if (*str++ != *prefix++)
			return false;
	}
	return true;
}

static inline bool susfs_ends_with(const char *str, const char *suffix)
{
	size_t str_len, suffix_len;

	if (!str || !suffix)
		return false;

	str_len = strlen(str);
	suffix_len = strlen(suffix);

	if (suffix_len > str_len)
		return false;

	return !strcmp(str + str_len - suffix_len, suffix);
}

static inline bool susfs_is_current_proc_umounted(void)
{
	return (likely(test_thread_flag(TIF_PROC_UMOUNTED)));
}

static inline void susfs_set_current_proc_umounted(void)
{
	set_thread_flag(TIF_PROC_UMOUNTED);
}

static inline bool susfs_is_current_proc_umounted_app(void)
{
	return (likely(test_thread_flag(TIF_PROC_UMOUNTED)) &&
		current_uid().val >= 10000);
}

#define SUSFS_IS_INODE_SUS_MAP(inode) \
		inode && inode->i_mapping && \
		unlikely(test_bit(AS_FLAGS_SUS_MAP, &inode->i_mapping->flags)) && \
		susfs_is_current_proc_umounted_app()

#define SUSFS_IS_INODE_OPEN_REDIRECT_WITHOUT_UID_CHECK(inode) \
		inode && inode->i_mapping && \
		unlikely(test_bit(AS_FLAGS_OPEN_REDIRECT, &inode->i_mapping->flags))

#define SUSFS_IS_INODE_OPEN_REDIRECT(inode) \
		inode && inode->i_mapping && \
		unlikely(test_bit(AS_FLAGS_OPEN_REDIRECT, &inode->i_mapping->flags)) && \
		susfs_is_current_proc_umounted_app()

#endif /* __SUSFS_V2_COMPAT_HELPERS */

/* =====================================================================
 * SECTION 4 — fsnotify callback API compat
 *
 * Kernel 5.0+ changed the fsnotify_ops callback:
 *   Old (4.14): handle_event(group, inode, inode_mark, vfsmount_mark,
 *                            mask, data, data_type, file_name, cookie,
 *                            iter_info)
 *   New (5.x):  handle_inode_event(mark, mask, inode, dir, file_name, cookie)
 *
 * On 4.14 we register a handle_event shim that extracts the dir and
 * file_name from the old-style params and forwards to the new-style handler.
 * ===================================================================== */

#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 0, 0)

/* Forward declare the v2.2.0-style handler from susfs.c */
extern int susfs_handle_sdcard_inode_event(struct fsnotify_mark *mark, u32 mask,
					   struct inode *inode, struct inode *dir,
					   const struct qstr *file_name, u32 cookie);

/*
 * Shim matching kernel 4.14's handle_event signature.
 *
 * Kernel 4.14 signature (from include/linux/fsnotify_backend.h):
 *   int (*handle_event)(struct fsnotify_group *group, struct inode *inode,
 *                       struct fsnotify_mark *inode_mark,
 *                       struct fsnotify_mark *vfsmount_mark,
 *                       u32 mask, const void *data, int data_type,
 *                       const unsigned char *file_name, u32 cookie,
 *                       struct fsnotify_iter_info *iter_info);
 *
 * When data_type == FSNOTIFY_EVENT_INODE, data is the (inode *) dir.
 * file_name is a raw c-string, not a struct qstr.
 */
static inline int __susfs_handle_event_compat(struct fsnotify_group *group,
					      struct inode *inode,
					      struct fsnotify_mark *inode_mark,
					      struct fsnotify_mark *vfsmount_mark,
					      u32 mask, const void *data,
					      int data_type,
					      const unsigned char *file_name,
					      u32 cookie,
					      struct fsnotify_iter_info *iter_info)
{
	struct inode *dir = NULL;
	struct qstr qstr_file;

	/* Extract dir from data if applicable */
	if (data_type == FSNOTIFY_EVENT_INODE)
		dir = (struct inode *)data;

	/* Convert raw c-string file_name to struct qstr */
	if (file_name) {
		qstr_file.name = file_name;
		qstr_file.len  = strlen(file_name);
		qstr_file.hash = 0;
	} else {
		qstr_file.name = NULL;
		qstr_file.len  = 0;
		qstr_file.hash = 0;
	}

	return susfs_handle_sdcard_inode_event(inode_mark, mask, inode, dir,
					       &qstr_file, cookie);
}

/* Override the fsnotify_ops initializer to use our compat shim */
#define FS_NOTIFY_INODE_EVENT_HANDLER __susfs_handle_event_compat

#else
#define FS_NOTIFY_INODE_EVENT_HANDLER susfs_handle_sdcard_inode_event
#endif /* LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0) */

/* =====================================================================
 * SECTION 5 — fsnotify_add_inode_mark compat
 *
 * v2.2.0 susfs.c uses fsnotify_add_inode_mark(m, inode, allow_dups).
 * Kernel 4.14 does not have this function; it has fsnotify_add_mark()
 * which takes two additional args (group and a place-holder fsnotify_mark).
 * Provide a compat inline that wraps the 4.14 API.
 * ===================================================================== */

#ifndef HAVE_FSNOTIFY_ADD_INODE_MARK
#define HAVE_FSNOTIFY_ADD_INODE_MARK
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 0, 0)
static inline int fsnotify_add_inode_mark(struct fsnotify_mark *mark,
					   struct inode *inode,
					   int allow_dups)
{
	/*
	 * On 4.14: fsnotify_add_mark(mark, inode, NULL, allow_dups)
	 * Pass NULL for vfsmount (inode mark, not mount mark).
	 */
	return fsnotify_add_mark(mark, inode, NULL, allow_dups);
}
#endif /* LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0) */
#endif /* HAVE_FSNOTIFY_ADD_INODE_MARK */

#endif /* _SUSFS_V2_BACKPORT_COMPAT_H_ */
