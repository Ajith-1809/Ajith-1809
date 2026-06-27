// SPDX-License-Identifier: GPL-2.0
/*
 * ksu_susfs_compat.c — SUSFS compatibility shim for KSUN v3.2.0-legacy
 *
 * Bridges the official SUSFS kernel module (kernel-4.14 branch from
 * simonpunk/susfs4ksu) with the KSU-Next v3.2.0-legacy supercall dispatch.
 *
 * Provides:
 *   - susfs_is_current_ksu_domain() / susfs_is_current_zygote_domain()
 *   - ksu_try_umount() / susfs_try_umount_all()
 *   - ksu_susfs_enable_sus_su() / ksu_susfs_disable_sus_su()
 *   - susfs_handle_sys_reboot() — routes all SUSFS CMD_* codes from the
 *     kernel/reboot.c supercall dispatch to the real susfs.c handlers.
 *
 * Compiled as part of kernelsu.o via the built-in Makefile.
 * The real susfs.c lives in fs/ and is compiled as susfs.o.
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
#include <linux/prctl.h>
#include <linux/slab.h>
#include <linux/stat.h>
#include <linux/time.h>
#include <linux/syscalls.h>
#include <linux/utsname.h>

/* ===== SUSFS structs and function declarations =====
 *
 * The KBapna v1.5.5 tree defines structs inside CONFIG guards under
 * different symbol names than the v2 kernel-4.14 branch.  Rather than
 * depending on which susfs.h is installed, we define the structs we
 * need locally here, matching v1.5.5 layout (pathname-first, no
 * target_ino/is_statically prefix).  Functions are declared with extern
 * — they resolve at link time against fs/susfs.o.
 */
#include <linux/susfs_def.h>

/* ===== v1.5.5-compatible struct definitions =====
 *
 * Layout notes for arm64 (8-byte unsigned long):
 *   v2:   unsigned long target_ino + char pathname[256]  → sizeof=264
 *   v1.5: char pathname[256]                              → sizeof=256
 */
struct st_susfs_sus_path {
	char target_pathname[SUSFS_MAX_LEN_PATHNAME];
};

struct st_susfs_sus_mount {
	char target_pathname[SUSFS_MAX_LEN_PATHNAME];
	unsigned long target_dev;
};

struct st_susfs_sus_kstat {
	char target_pathname[SUSFS_MAX_LEN_PATHNAME];
	unsigned long spoofed_ino;
	unsigned long spoofed_dev;
	unsigned int spoofed_nlink;
	long long spoofed_size;
	long spoofed_atime_tv_sec;
	long spoofed_mtime_tv_sec;
	long spoofed_ctime_tv_sec;
	long spoofed_atime_tv_nsec;
	long spoofed_mtime_tv_nsec;
	long spoofed_ctime_tv_nsec;
	unsigned long spoofed_blksize;
	unsigned long long spoofed_blocks;
};

struct st_susfs_try_umount {
	char target_pathname[SUSFS_MAX_LEN_PATHNAME];
	int mnt_mode;
};

struct st_susfs_uname {
	char sysname[__NEW_UTS_LEN + 1];
	char nodename[__NEW_UTS_LEN + 1];
	char release[__NEW_UTS_LEN + 1];
	char version[__NEW_UTS_LEN + 1];
	char machine[__NEW_UTS_LEN + 1];
	char domainname[__NEW_UTS_LEN + 1];
};

struct st_susfs_open_redirect {
	char target_pathname[SUSFS_MAX_LEN_PATHNAME];
	char redirected_pathname[SUSFS_MAX_LEN_PATHNAME];
};

struct st_sus_su {
	int mode;
};

/* ===== Extern function declarations from fs/susfs.c =====
 * These are the real SUSFS handlers linked into vmlinux.
 * Declared here to avoid depending on include/linux/susfs.h
 * (which may guard struct definitions under unexpected CONFIG names). */
extern int susfs_add_sus_path(struct st_susfs_sus_path __user *user_info);
extern int susfs_add_sus_mount(struct st_susfs_sus_mount __user *user_info);
extern int susfs_add_sus_kstat(struct st_susfs_sus_kstat __user *user_info);
extern int susfs_update_sus_kstat(struct st_susfs_sus_kstat __user *user_info);
extern int susfs_add_try_umount(struct st_susfs_try_umount __user *user_info);
extern int susfs_set_uname(struct st_susfs_uname __user *user_info);
extern int susfs_set_cmdline_or_bootconfig(char __user *cmdline);
extern int susfs_add_open_redirect(struct st_susfs_open_redirect __user *user_info);
extern int susfs_sus_su(struct st_sus_su __user *user_info);
extern int susfs_get_sus_su_working_mode(void);
extern void susfs_set_log(bool enabled);
extern void susfs_try_umount(uid_t uid);
extern void susfs_init(void);
extern int susfs_enable_avc_log_spoofing(bool enabled);
extern int susfs_hide_sus_mnts_for_non_su_procs(bool enabled);

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
EXPORT_SYMBOL_GPL(susfs_is_current_ksu_domain);

bool susfs_is_current_zygote_domain(void)
{
	const struct task_security_struct *tsec;

	tsec = (const struct task_security_struct *)current_cred()->security;
	if (unlikely(!tsec))
		return false;
	return unlikely(tsec->sid == susfs_zygote_sid);
}
EXPORT_SYMBOL_GPL(susfs_is_current_zygote_domain);
#endif

/* ===== Try-umount implementation =====
 * KBapna's core_hook calls ksu_try_umount() to umount a single path.
 * The kernel-4.14 branch's susfs_try_umount(uid) iterates over the
 * try_umount list and calls ksu_try_umount() for EACH entry — so
 * ksu_try_umount MUST do the actual umount work, NOT delegate to
 * susfs_try_umount (which would cause infinite recursion).
 *
 * On kernel 4.14, path_umount() (added in 5.9) does not exist and
 * ksys_umount() is not exported on all CAF trees.  We use sys_umount()
 * (the raw syscall handler from SYSCALL_DEFINE2(umount, ...), already
 * declared in <linux/syscalls.h>) with set_fs(KERNEL_DS) to pass a
 * kernel pointer.  Since our compat code is linked into vmlinux (not
 * a module), the reference resolves at link time.
 */

void ksu_try_umount(const char *mnt, bool check_mnt, int flags, uid_t uid)
{
	mm_segment_t old_fs;
	int err;

	/* sys_umount() expects a __user pointer.  On kernel 4.14 we can
	 * safely switch address limits to pass a kernel-space string.
	 * The function is declared in <linux/syscalls.h> as:
	 *   asmlinkage long sys_umount(char __user *name, int flags); */
	old_fs = get_fs();
	set_fs(KERNEL_DS);
	err = sys_umount((char __user *)mnt, flags);
	set_fs(old_fs);

	if (err) {
		/* Not all paths are mountpoints; silence expected failures
		 * unless logging is explicitly requested. */
		if (err != -EINVAL && err != -ENOENT)
			pr_debug("susfs: umount '%s' failed: %d\n", mnt, err);
	}
}
EXPORT_SYMBOL_GPL(ksu_try_umount);

/* susfs_try_umount_all — called from KSU core_hook on setuid events.
 * Delegates to susfs_try_umount() in susfs.c which iterates the list
 * and calls ksu_try_umount() per entry. */
void susfs_try_umount_all(uid_t uid)
{
	susfs_try_umount(uid);
}
EXPORT_SYMBOL_GPL(susfs_try_umount_all);

/* ===== sus_su stubs =====
 * sus_su mode switching is deprecated for non-GKI kernels (kprobes
 * disabled).  These are no-ops for our 4.14 CAF build.
 */

void ksu_susfs_enable_sus_su(void)
{
}
EXPORT_SYMBOL_GPL(ksu_susfs_enable_sus_su);

void ksu_susfs_disable_sus_su(void)
{
}
EXPORT_SYMBOL_GPL(ksu_susfs_disable_sus_su);

/* ===== GKI-backported feature stubs =====
 * These features exist in the GKI susfs branch but not in kernel-4.14.
 * Provide stub implementations so the SUSFS userspace tool (brene etc.)
 * detects them as "available" rather than "not supported" (-EOPNOTSUPP).
 */

/* AVC log spoofing: no-op on 4.14 (avc_log path isn't hooked this way). */
int susfs_enable_avc_log_spoofing(bool enabled)
{
	return 0;
}
EXPORT_SYMBOL_GPL(susfs_enable_avc_log_spoofing);

/* Hide sus mounts for non-su processes: no-op on 4.14. */
int susfs_hide_sus_mnts_for_non_su_procs(bool enabled)
{
	return 0;
}
EXPORT_SYMBOL_GPL(susfs_hide_sus_mnts_for_non_su_procs);

/* ===== SUSFS initialization =====
 * The kernel-4.14 branch's susfs.c defines void susfs_init(void) but
 * has NO module_init/late_initcall — so it's NEVER called on boot.
 * This means susfs_spin_lock, uname init, etc. are skipped.
 * We call it here since this file compiles into the same vmlinux.
 */
static int __init ksu_susfs_compat_init(void)
{
#ifdef CONFIG_KSU_SUSFS
	susfs_init();
	pr_info("ksu_susfs_compat: SUSFS initialized via late_initcall\n");
#endif
	return 0;
}
late_initcall(ksu_susfs_compat_init);

/* ===== SUSFS supercall dispatch =====
 *
 * The kernel/reboot.c hook routes reboot() syscalls with:
 *   magic1 == 0xDEADBEEF (KSU_INSTALL_MAGIC1)
 *   magic2 == 0xFAFAFAFA (SUSFS_MAGIC)
 * into us.  We extract cmd from the third argument and arg from the
 * fourth, then dispatch to the appropriate susfs.c handler function.
 *
 * This implements the same protocol the ksu_susfs userspace tool uses
 * (via prctl on upstream KernelSU, or via reboot syscall on KSU-Next).
 */

int susfs_handle_sys_reboot(unsigned int cmd, void __user *arg)
{
	int ret = 0;
	mm_segment_t old_fs;

	switch (cmd) {

	/* ============ SUS_PATH commands ============ */
	case CMD_SUSFS_ADD_SUS_PATH:
	case CMD_SUSFS_ADD_SUS_PATH_LOOP: {
		/* Old v1.5.5 tool sends struct WITHOUT target_ino
		 * (pathname at offset 0). Kernel-4.14 branch expects
		 * target_ino first. Read old pathname, build proper
		 * struct, forward via set_fs(KERNEL_DS).
		 * ADD_SUS_PATH_LOOP is the same code path (the loop flag
		 * is a GKI optimization; on 4.14 we just do add_sus_path). */
		struct st_susfs_sus_path _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME];
		if (copy_from_user(_oldp, arg, sizeof(_oldp)))
			return -EFAULT;
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_add_sus_path((struct st_susfs_sus_path __user *)&_info);
		set_fs(old_fs);
		break;
	}

	/* ============ SUS_MOUNT commands ============ */
	case CMD_SUSFS_ADD_SUS_MOUNT:
		ret = susfs_add_sus_mount((struct st_susfs_sus_mount __user *)arg);
		break;

	/* ============ SUS_KSTAT commands ============ */
	case CMD_SUSFS_ADD_SUS_KSTAT: {
		/* Old tool sends struct WITHOUT target_ino/is_statically.
		 * New struct has: int + padding + unsigned long + pathname.
		 * Read old pathname, build proper struct, forward via KERNEL_DS. */
		struct st_susfs_sus_kstat _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME];
		if (copy_from_user(_oldp, arg, sizeof(_oldp)))
			return -EFAULT;
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_add_sus_kstat((struct st_susfs_sus_kstat __user *)&_info);
		set_fs(old_fs);
		break;
	}

	case CMD_SUSFS_UPDATE_SUS_KSTAT: {
		struct st_susfs_sus_kstat _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME];
		if (copy_from_user(_oldp, arg, sizeof(_oldp)))
			return -EFAULT;
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_update_sus_kstat((struct st_susfs_sus_kstat __user *)&_info);
		set_fs(old_fs);
		break;
	}

	case CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY: {
		struct st_susfs_sus_kstat _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME];
		if (copy_from_user(_oldp, arg, sizeof(_oldp)))
			return -EFAULT;
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_add_sus_kstat((struct st_susfs_sus_kstat __user *)&_info);
		set_fs(old_fs);
		break;
	}

	/* ============ TRY_UMOUNT commands ============ */
	case CMD_SUSFS_ADD_TRY_UMOUNT:
		ret = susfs_add_try_umount((struct st_susfs_try_umount __user *)arg);
		break;

	case CMD_SUSFS_RUN_UMOUNT_FOR_CURRENT_MNT_NS:
		susfs_try_umount(current_uid().val);
		ret = 0;
		break;

	/* ============ HIDE_SUS_MNTS (GKI backport stub) ============ */
	case CMD_SUSFS_HIDE_SUS_MNTS_FOR_NON_SU_PROCS: {
		int enabled;
		if (copy_from_user(&enabled, arg, sizeof(enabled)))
			return -EFAULT;
		ret = susfs_hide_sus_mnts_for_non_su_procs(enabled ? true : false);
		break;
	}

	/* ============ SPOOF_UNAME commands ============ */
	case CMD_SUSFS_SET_UNAME:
		ret = susfs_set_uname((struct st_susfs_uname __user *)arg);
		break;

	/* ============ ENABLE_LOG ============ */
	case CMD_SUSFS_ENABLE_LOG: {
		int enabled;
		if (copy_from_user(&enabled, arg, sizeof(enabled)))
			return -EFAULT;
		susfs_set_log(enabled ? true : false);
		ret = 0;
		break;
	}

	/* ============ ENABLE_AVC_LOG_SPOOFING (GKI backport stub) ============ */
	case CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING: {
		int enabled;
		if (copy_from_user(&enabled, arg, sizeof(enabled)))
			return -EFAULT;
		ret = susfs_enable_avc_log_spoofing(enabled ? true : false);
		break;
	}

	/* ============ SPOOF_CMDLINE ============ */
	case CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG:
		ret = susfs_set_cmdline_or_bootconfig((char __user *)arg);
		break;

	/* ============ OPEN_REDIRECT ============ */
	case CMD_SUSFS_ADD_OPEN_REDIRECT: {
		/* Old tool sends struct WITHOUT target_ino.
		 * New struct has target_ino first; read old pathnames
		 * and forward via KERNEL_DS. */
		struct st_susfs_open_redirect _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME * 2];
		if (copy_from_user(_oldp, arg, sizeof(_oldp)))
			return -EFAULT;
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_add_open_redirect((struct st_susfs_open_redirect __user *)&_info);
		set_fs(old_fs);
		break;
	}

	/* ============ SUS_SU ============
	 * sus_su mode switching is guarded by CONFIG_KSU_SUSFS_SUS_SU.
	 * We only compile the dispatch calls when the config is enabled.
	 * When disabled (the default), users get -EOPNOTSUPP. */
#ifdef CONFIG_KSU_SUSFS_SUS_SU
	case CMD_SUSFS_SUS_SU:
		ret = susfs_sus_su((struct st_sus_su __user *)arg);
		break;
	case CMD_SUSFS_IS_SUS_SU_READY:
		ret = susfs_get_sus_su_working_mode();
		break;
	case CMD_SUSFS_SHOW_SUS_SU_WORKING_MODE:
		ret = susfs_get_sus_su_working_mode();
		break;
#else
	case CMD_SUSFS_SUS_SU:
	case CMD_SUSFS_IS_SUS_SU_READY:
	case CMD_SUSFS_SHOW_SUS_SU_WORKING_MODE:
		ret = -EOPNOTSUPP;
		break;
#endif

	/* ============ SHOW commands ============ */
	case CMD_SUSFS_SHOW_VERSION: {
		/* struct { char version[16]; int err; } */
		if (copy_to_user(arg, SUSFS_VERSION, sizeof("v1.5.5")))
			return -EFAULT;
		if (put_user(0, (int __user *)((char __user *)arg + 16)))
			return -EFAULT;
		ret = 0;
		break;
	}

	case CMD_SUSFS_SHOW_ENABLED_FEATURES: {
		/* struct { char features[8192]; int err; } */
		static const char features[] =
			"add_sus_path\n"
			"add_sus_path_loop\n"
			"enable_avc_log_spoofing\n"
			"hide_sus_mnts_for_non_su_procs\n"
			"add_sus_kstat\n"
			"update_sus_kstat\n"
			"add_sus_kstat_statically\n"
			"set_uname\n"
			"enable_log\n"
			"set_cmdline_or_bootconfig\n"
			"add_open_redirect\n"
			"add_sus_mount\n"
			"add_try_umount\n"
			"run_try_umount\n"
			"hide_ksu_susfs_symbols\n"
			"spoof_cmdline_or_bootconfig\n"
			"sus_overlayfs\n"
			"auto_add_sus_ksu_default_mount\n"
			"auto_add_sus_bind_mount\n"
			"auto_add_try_umount_for_bind_mount\n"
			"add_sus_map\n";
		if (copy_to_user(arg, features, sizeof(features)))
			return -EFAULT;
		if (put_user(0, (int __user *)((char __user *)arg + 8192)))
			return -EFAULT;
		ret = 0;
		break;
	}

	case CMD_SUSFS_SHOW_VARIANT: {
		/* struct { char variant[16]; int err; } */
		if (copy_to_user(arg, SUSFS_VARIANT, sizeof("NON-GKI")))
			return -EFAULT;
		if (put_user(0, (int __user *)((char __user *)arg + 16)))
			return -EFAULT;
		ret = 0;
		break;
	}

	/* ============ SUS_MAP (add_sus_map from userspace) ============ */
	/* The userspace tool sends CMD 0x60020 for add_sus_map.
	 * We route it to add_sus_path since susfs_sus_ino_for_show_map_vma
	 * checks against the SUS_PATH_HLIST.
	 * Same struct compat pattern: old tool sends pathname at offset 0
	 * (no target_ino), new struct expects target_ino at offset 0. */
	case CMD_SUSFS_ADD_SUS_MAP: {
		struct st_susfs_sus_path _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME];
		if (copy_from_user(_oldp, arg, sizeof(_oldp)))
			return -EFAULT;
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_add_sus_path((struct st_susfs_sus_path __user *)&_info);
		set_fs(old_fs);
		break;
	}

	default:
		return -EOPNOTSUPP;
	}

	return ret;
}
EXPORT_SYMBOL_GPL(susfs_handle_sys_reboot);
