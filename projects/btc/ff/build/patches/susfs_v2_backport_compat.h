/* SPDX-License-Identifier: GPL-2.0 */
/*
 * susfs_v2_backport_compat.h — SUSFS v2.2.0 backport compat layer for kernel 4.14
 *
 * Backports APIs that SUSFS v2.2.0 (gki-android14-5.15 branch) expects
 * from newer kernels but which don't exist in the CAF 4.14 tree.
 *
 * Force-included via ccflags-y in fs/Makefile for susfs.o.
 *
 * Key differences:
 *  - fsnotify_ops: 4.14 uses handle_event (old API) instead of
 *    handle_inode_event (5.x+ API). We wrap the new-style handler
 *    in a shim for 4.14.
 */
#ifndef _SUSFS_V2_BACKPORT_COMPAT_H_
#define _SUSFS_V2_BACKPORT_COMPAT_H_

#include <linux/version.h>
#include <linux/fsnotify_backend.h>
#include <linux/bits.h>

/* ===== Legacy v1.5.5 flags used by KBapna tree's kernel-side hooks =====
 * The KBapna tree already has SUSFS v1.5.5 hooks applied to kernel source
 * files (fs/stat.c, fs/open.c, fs/exec.c, etc.) that reference these
 * legacy INODE_STATE_* and TASK_STRUCT_* flags. The v2.2.0 susfs_def.h
 * does not define them. Provide them here for compilation of the hooks.
 * These flags use bits 24+ — well above the kernel's standard inode
 * I_* flags (bits 0-13) and task state bits.
 */
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

/* ===== fsnotify_ops.handle_inode_event compat =====
 * Kernel 5.0+ (approx) changed the fsnotify callback from:
 *   int (*handle_event)(group, inode, inode_mark, vfsmount_mark,
 *                       mask, dir, file_name, cookie)
 * to:
 *   int (*handle_inode_event)(mark, mask, inode, dir, file_name, cookie)
 *
 * On 4.14, we must provide handle_event. We create a shim that
 * discards the extra args (group, vfsmount_mark) and passes the
 * rest through to the new-style handler.
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 0, 0)

/* Forward declare the new-style handler from susfs.c */
extern int susfs_handle_sdcard_inode_event(struct fsnotify_mark *mark, u32 mask,
                                         struct inode *inode, struct inode *dir,
                                         const struct qstr *file_name, u32 cookie);

static inline int __susfs_handle_event_compat(struct fsnotify_group *group,
                                              struct inode *inode,
                                              struct fsnotify_mark *inode_mark,
                                              struct fsnotify_mark *vfsmount_mark,
                                              u32 mask, struct inode *dir,
                                              const struct qstr *file_name, u32 cookie)
{
	return susfs_handle_sdcard_inode_event(inode_mark, mask, inode, dir, file_name, cookie);
}

/* Override the fsnotify_ops initializer macro to use our compat shim */
#define FS_NOTIFY_INODE_EVENT_HANDLER __susfs_handle_event_compat

#else
#define FS_NOTIFY_INODE_EVENT_HANDLER susfs_handle_sdcard_inode_event
#endif /* LINUX_VERSION_CODE < KERNEL_VERSION(5,0,0) */

#endif /* _SUSFS_V2_BACKPORT_COMPAT_H_ */
