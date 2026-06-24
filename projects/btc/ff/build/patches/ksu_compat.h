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

/* ===== put_task_struct() availability =====
 * In 4.14 it's in <linux/sched/task.h>. If that header doesn't exist,
 * it's in <linux/sched.h> which we already include above.
 * This is just a safety check.
 */
#ifndef put_task_struct
/* fallback — should never trigger on 4.14 */
#define put_task_struct(t)  do { if (atomic_dec_and_test(&(t)->usage)) __put_task_struct(t); } while (0)
#endif

#endif /* _KSU_COMPAT_H_ */
