// SPDX-License-Identifier: GPL-2.0
/*
 * ksu_susfs_compat.c — SUSFS compatibility shim for KSUN v3.2.0-legacy
 *
 * KBapna's original KernelSU-Next tree had SUSFS integration functions
 * patched into selinux.c and core_hook.c. The upstream KSUN v3.2.0-legacy
 * (applied fresh by setup.sh) does NOT have these custom additions.
 *
 * This file provides the missing symbols so vmlink succeeds:
 *   - susfs_ksu_sid / susfs_zygote_sid / susfs_init_sid (global u32)
 *   - susfs_is_current_ksu_domain() / susfs_is_current_zygote_domain()
 *   - ksu_try_umount() / susfs_try_umount_all()
 *
 * Compiled as part of kernelsu.o via the built-in Makefile.
 */

#include <linux/types.h>
#include <linux/uidgid.h>
#include <linux/path.h>
#include <linux/namei.h>
#include <linux/mount.h>
#include <linux/fs.h>
#include <linux/cred.h>
#include <linux/sched.h>
#include <linux/version.h>
#include <linux/printk.h>

/* ===== SID-based domain checks =====
 * KBapna's original selinux.c declared these globals and functions
 * inside #ifdef CONFIG_KSU_SUSFS.
 * They allow SUSFS hooks in fs/namespace.c to check whether the
 * current process is running in the KSU or Zygote SELinux domain.
 *
 * sid values: initialized to 0; they get set when userspace triggers
 * the prctl CMD_SUSFS_SET_KSU_SID / CMD_SUSFS_SET_ZYGOTE_SID.
 * Until set, domain checks return false (safe default).
 */

#ifdef CONFIG_SECURITY_SELINUX
#include "objsec.h"

u32 susfs_ksu_sid __read_mostly = 0;
u32 susfs_zygote_sid __read_mostly = 0;
u32 susfs_init_sid __read_mostly = 0;

bool susfs_is_current_ksu_domain(void)
{
	const struct task_security_struct *tsec;

	tsec = (const struct task_security_struct *)current_cred()->security;
	if (unlikely(!tsec))
		return false;
	return unlikely(tsec->sid == susfs_ksu_sid);
}

bool susfs_is_current_zygote_domain(void)
{
	const struct task_security_struct *tsec;

	tsec = (const struct task_security_struct *)current_cred()->security;
	if (unlikely(!tsec))
		return false;
	return unlikely(tsec->sid == susfs_zygote_sid);
}
#endif

/* ===== Try-umount stubs =====
 * KBapna's original core_hook.c provided ksu_try_umount() and
 * susfs_try_umount_all() for unmounting KSU-sensitive mount points
 * from non-root user namespaces.
 *
 * On kernel 4.14, the underlying path_umount() syscall does NOT exist
 * (added in kernel 5.9). KBapna's own ksu_umount_mnt() returns
 * -ENOSYS on pre-5.9 kernels. These stubs are functionally equivalent.
 *
 * The extern declarations in fs/susfs.c and fs/namespace.c still
 * reference the symbols; we provide them as no-ops.
 */

void ksu_try_umount(const char *mnt, bool check_mnt, int flags, uid_t uid)
{
}

void susfs_try_umount_all(uid_t uid)
{
}
