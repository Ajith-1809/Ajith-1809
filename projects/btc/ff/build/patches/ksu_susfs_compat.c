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
 *   - susfs_handle_sys_reboot() — handles SUSFS supercall IOCTL commands
 *     from userspace (v2.x detection API: show_version / show_features /
 *     show_variant).
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
#include <linux/uaccess.h>

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

/* ===== SUSFS supercall handler (sys_reboot hook) =====
 *
 * SUSFS v2.x userspace tools (ksu_susfs, brene-susfs module) communicate
 * via the reboot syscall:
 *   syscall(SYS_reboot, 0xDEADBEEF, 0xFAFAFAFA, CMD, &info)
 *
 * The kernel/reboot.c hook routes 0xDEADBEEF magic1 to us when
 * magic2 == 0xFAFAFAFA (SUSFS_MAGIC).  We respond to the three
 * detection IOCTL commands that userspace sends:
 *
 *   CMD_SUSFS_SHOW_VERSION          (0x555e1)
 *   CMD_SUSFS_SHOW_ENABLED_FEATURES (0x555e2)
 *   CMD_SUSFS_SHOW_VARIANT          (0x555e3)
 *
 * The userspace struct layouts (must match ksu_susfs show.c exactly):
 *
 *   struct st_susfs_version { char version[16]; int err; };
 *   struct st_susfs_enabled_features { char features[8192]; int err; };
 *   struct st_susfs_variant { char variant[16]; int err; };
 */

#define SUSFS_CMD_SHOW_VERSION         0x555e1
#define SUSFS_CMD_SHOW_ENABLED_FEATURES 0x555e2
#define SUSFS_CMD_SHOW_VARIANT          0x555e3

int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg)
{
	switch (cmd) {
	case SUSFS_CMD_SHOW_VERSION: {
		/* struct st_susfs_version { char version[16]; int err; } */
		char __user *version  = arg;
		int  __user *err_field = (int __user *)((char __user *)arg + 16);

		if (copy_to_user(version, "v1.5.5", sizeof("v1.5.5")))
			return -EFAULT;
		if (put_user(0, err_field))
			return -EFAULT;
		return 0;
	}
	case SUSFS_CMD_SHOW_ENABLED_FEATURES: {
		/* struct st_susfs_enabled_features { char features[8192]; int err; } */
		static const char features[] =
			"add_sus_path\n"
			"add_sus_path_loop\n"
			"hide_sus_mnts_for_non_su_procs\n"
			"add_sus_kstat\n"
			"update_sus_kstat\n"
			"add_sus_kstat_statically\n"
			"set_uname\n"
			"enable_log\n"
			"set_cmdline_or_bootconfig\n"
			"add_open_redirect\n"
			"add_sus_mount\n";
		char __user *feat  = arg;
		int  __user *err_field = (int __user *)((char __user *)arg + 8192);

		if (copy_to_user(feat, features, sizeof(features)))
			return -EFAULT;
		if (put_user(0, err_field))
			return -EFAULT;
		return 0;
	}
	case SUSFS_CMD_SHOW_VARIANT: {
		/* struct st_susfs_variant { char variant[16]; int err; } */
		char __user *variant  = arg;
		int  __user *err_field = (int __user *)((char __user *)arg + 16);

		if (copy_to_user(variant, "NON-GKI", sizeof("NON-GKI")))
			return -EFAULT;
		if (put_user(0, err_field))
			return -EFAULT;
		return 0;
	}
	default:
		return -EINVAL;
	}
}
EXPORT_SYMBOL_GPL(susfs_handle_sys_reboot);
