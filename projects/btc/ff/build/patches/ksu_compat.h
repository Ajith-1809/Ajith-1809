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
 * Added in kernel 5.3 (commit c9b9cfe). In 4.14 we:
 * 1. Disable pagefaults (so __get_user won't fault on bad addr)
 * 2. Call the existing strncpy_from_user
 * 3. Re-enable pagefaults
 * This is identical to the upstream implementation.
 */
#ifndef HAVE_ARCH_STRNCPY_FROM_USER_NOFAULT
static inline long
strncpy_from_user_nofault(char *dst, const char __user *src, long count)
{
	long ret;

	if (unlikely(count <= 0))
		return 0;

	pagefault_disable();
	ret = strncpy_from_user(dst, src, count);
	pagefault_enable();
	return ret;
}
#endif

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

#endif /* _KSU_COMPAT_H_ */
