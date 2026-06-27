/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ksu_compat.h — KernelSU-Next v3.0.0 compatibility layer for kernel 4.14
 *
 * Backports APIs and defines that KSUN v3.0.0 expects from newer kernels
 * (5.3+, 5.9+, etc) but which don't exist in the CAF 4.14 tree.
 *
 * Force-included via ccflags-y in drivers/kernelsu/Makefile.
 */
#ifndef _KSU_COMPAT_H_
#define _KSU_COMPAT_H_

#include <linux/version.h>
#include <linux/sched.h>
#include <linux/uaccess.h>

/* ===== TWA_* flags for task_work_add() =====
 * TWA_NONE  (always existed)
 * TWA_RESUME (added in kernel 5.3, commit 4b7b3ef7e8b)
 * In CAF 4.14 the enum may not have all values. Define them.
 */
#ifndef TWA_NONE
#define TWA_NONE  0
#endif
#ifndef TWA_RESUME
#define TWA_RESUME 1
#endif

/* ===== strncpy_from_user_nofault() =====
 * The tillua467 v2.4 kernel (4.14-openela) already provides this.
 * For older 4.14 kernels without this backport, uncomment the
 * definition below.
 *
 * Original kernel 5.3 commit c9b9cfe. Equivalent to:
 *   pagefault_disable();
 *   ret = strncpy_from_user(dst, src, count);
 *   pagefault_enable();
 */

/* Uncomment for kernels that don't provide strncpy_from_user_nofault:
#ifndef HAVE_ARCH_STRNCPY_FROM_USER_NOFAULT
static inline long
strncpy_from_user_nofault(char *dst, const void __user *unsafe_addr, long count)
{
    long ret;
    if (unlikely(count <= 0))
        return 0;
    pagefault_disable();
    ret = strncpy_from_user(dst, unsafe_addr, count);
    pagefault_enable();
    return ret;
}
#endif
*/

/* ===== selinux_inode() compat =====
 * Kernel 4.14 CAF does NOT have the selinux_inode(inode) function
 * (added in kernel 5.x GKI). On 4.14, the inode security struct
 * is accessible via inode->i_security. Provide a compat definition.
 * Include objsec.h for struct inode_security_struct (it is available
 * after 'make prepare' generates flask.h). Guarded with #ifndef so
 * kernels that already define selinux_inode are not affected.
 */
#ifdef CONFIG_SECURITY_SELINUX
#include "objsec.h"
#ifndef selinux_inode
#define selinux_inode(inode) ((struct inode_security_struct *)((inode)->i_security))
#endif
#endif

/* ===== selinux_cred() compat =====
 * The tillua467 v2.4 kernel (4.14-openela) already provides selinux_cred()
 * in security/selinux/include/objsec.h via the blob-based model.
 */

/* =====================================================================
 * SUSFS defines for KSUN supercall dispatch
 * Required by KernelSU-Next/kernel/supercall/supercall.c for SUSFS
 * SHOW command dispatch (CMD_SUSFS_SHOW_VERSION, etc.).
 * Only the SHOW commands are defined here — other SUSFS CMD codes
 * are in fs/susfs_def.h and reachable via linux/susfs_def.h.
 * ===================================================================== */
#ifndef SUSFS_MAGIC
#define SUSFS_MAGIC 0xFAFAFAFA
#endif

/* SUSFS SHOW command codes (from include/linux/susfs_def.h) */
#ifndef CMD_SUSFS_SHOW_VERSION
#define CMD_SUSFS_SHOW_VERSION 0x555e1
#endif
#ifndef CMD_SUSFS_SHOW_ENABLED_FEATURES
#define CMD_SUSFS_SHOW_ENABLED_FEATURES 0x555e2
#endif
#ifndef CMD_SUSFS_SHOW_VARIANT
#define CMD_SUSFS_SHOW_VARIANT 0x555e3
#endif

/* Forward declarations for SUSFS SHOW functions — defined in fs/susfs.c */
#ifdef CONFIG_KSU_SUSFS
void susfs_get_enabled_features(void __user **user_info);
void susfs_show_variant(void __user **user_info);
void susfs_show_version(void __user **user_info);
#else
static inline void susfs_get_enabled_features(void __user **user_info) { }
static inline void susfs_show_variant(void __user **user_info) { }
static inline void susfs_show_version(void __user **user_info) { }
#endif /* CONFIG_KSU_SUSFS */

#endif /* _KSU_COMPAT_H_ */
