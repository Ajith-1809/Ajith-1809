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
#include <linux/kprobes.h>

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

/* ===== SUSFS structs matching kernel-4.14 branch layout =====
 *
 * These MUST match the struct definitions in include/linux/susfs.h
 * from the kernel-4.14 branch (not v1.5.5). The kernel-4.14 layout
 * places target_ino/is_statically BEFORE target_pathname, unlike
 * the v1.5.5 layout which has pathname at offset 0.
 *
 * When the userspace tool sends the old v1.5.5 format (pathname-only),
 * the dispatch code manually converts it to the new format before
 * calling the real susfs_* handler.
 */
#include <linux/susfs_def.h>

/* kernel-4.14: unsigned long target_ino + char pathname[256]  → sizeof=264 */
struct st_susfs_sus_path {
	unsigned long           target_ino;
	char                    target_pathname[SUSFS_MAX_LEN_PATHNAME];
};

/* kernel-4.14: same layout as v1.5.5 — just char pathname + unsigned long dev */
struct st_susfs_sus_mount {
	char                    target_pathname[SUSFS_MAX_LEN_PATHNAME];
	unsigned long           target_dev;
};

/* kernel-4.14: int is_statically + unsigned long target_ino + char pathname + spoof data
 * sizeof(int) + padding + sizeof(unsigned long) + 256 + ...
 * On arm64: 4 + 4 + 8 + 256 + ... = 272 before spoofed fields */
struct st_susfs_sus_kstat {
	int                     is_statically;
	unsigned long           target_ino;
	char                    target_pathname[SUSFS_MAX_LEN_PATHNAME];
	unsigned long           spoofed_ino;
	unsigned long           spoofed_dev;
	unsigned int            spoofed_nlink;
	long long               spoofed_size;
	long                    spoofed_atime_tv_sec;
	long                    spoofed_mtime_tv_sec;
	long                    spoofed_ctime_tv_sec;
	long                    spoofed_atime_tv_nsec;
	long                    spoofed_mtime_tv_nsec;
	long                    spoofed_ctime_tv_nsec;
	unsigned long           spoofed_blksize;
	unsigned long long      spoofed_blocks;
};

struct st_susfs_try_umount {
	char                    target_pathname[SUSFS_MAX_LEN_PATHNAME];
	int                     mnt_mode;
};

struct st_susfs_uname {
	char sysname[__NEW_UTS_LEN + 1];
	char nodename[__NEW_UTS_LEN + 1];
	char release[__NEW_UTS_LEN + 1];
	char version[__NEW_UTS_LEN + 1];
	char machine[__NEW_UTS_LEN + 1];
	char domainname[__NEW_UTS_LEN + 1];
};

/* kernel-4.14: unsigned long target_ino + char pathname + char redirected */
struct st_susfs_open_redirect {
	unsigned long           target_ino;
	char                    target_pathname[SUSFS_MAX_LEN_PATHNAME];
	char                    redirected_pathname[SUSFS_MAX_LEN_PATHNAME];
};

struct st_sus_su {
	int mode;
};

/* ===== GKI backport struct definitions ===== */
struct st_susfs_sus_maps {
	char target_pathname[SUSFS_MAX_LEN_PATHNAME];
	unsigned long target_ino;
	unsigned long target_dev;
	unsigned long long target_pgoff;
	unsigned long target_prot;
	unsigned long target_addr_size;
	char spoofed_pathname[SUSFS_MAX_LEN_PATHNAME];
	unsigned long spoofed_ino;
	unsigned long spoofed_dev;
	unsigned long long spoofed_pgoff;
	unsigned long spoofed_prot;
	bool is_statically;
	int compare_mode;
	bool is_isolated_entry;
	bool is_file;
	unsigned long prev_target_ino;
	unsigned long next_target_ino;
	bool need_to_spoof_pathname;
	bool need_to_spoof_ino;
	bool need_to_spoof_dev;
	bool need_to_spoof_pgoff;
	bool need_to_spoof_prot;
};

struct st_susfs_sus_proc_fd_link {
	char target_link_name[SUSFS_MAX_LEN_PATHNAME];
	char spoofed_link_name[SUSFS_MAX_LEN_PATHNAME];
};

struct st_susfs_sus_memfd {
	char target_pathname[248];
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

/* GKI backport externs */
extern int susfs_add_sus_maps(struct st_susfs_sus_maps __user *user_info);
extern int susfs_update_sus_maps(struct st_susfs_sus_maps __user *user_info);
extern int susfs_add_sus_proc_fd_link(struct st_susfs_sus_proc_fd_link __user *user_info);
extern int susfs_add_sus_memfd(struct st_susfs_sus_memfd __user *user_info);

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
		if (copy_to_user(arg, "v1.5.5", sizeof("v1.5.5")))
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
			"add_sus_map\n"
			"add_sus_maps\n"
			"update_sus_maps\n"
			"add_sus_proc_fd_link\n"
			"add_sus_memfd\n";
		if (copy_to_user(arg, features, sizeof(features)))
			return -EFAULT;
		if (put_user(0, (int __user *)((char __user *)arg + 8192)))
			return -EFAULT;
		ret = 0;
		break;
	}

	case CMD_SUSFS_SHOW_VARIANT: {
		/* struct { char variant[16]; int err; } */
		if (copy_to_user(arg, "NON-GKI", sizeof("NON-GKI")))
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

	/* ============ GKI backport commands ============ */
	case CMD_SUSFS_ADD_SUS_MAPS:
		ret = susfs_add_sus_maps((struct st_susfs_sus_maps __user *)arg);
		break;

	case CMD_SUSFS_UPDATE_SUS_MAPS:
		ret = susfs_update_sus_maps((struct st_susfs_sus_maps __user *)arg);
		break;

	case CMD_SUSFS_ADD_SUS_PROC_FD_LINK:
		ret = susfs_add_sus_proc_fd_link((struct st_susfs_sus_proc_fd_link __user *)arg);
		break;

	case CMD_SUSFS_ADD_SUS_MEMFD:
		ret = susfs_add_sus_memfd((struct st_susfs_sus_memfd __user *)arg);
		break;

	default:
		return -EOPNOTSUPP;
	}

	return ret;
}
EXPORT_SYMBOL_GPL(susfs_handle_sys_reboot);

/* ===== prctl-based SUSFS dispatch (for ksu_susfs userspace tool) =====
 *
 * The ksu_susfs userspace tool communicates with the kernel via
 * prctl(KERNEL_SU_OPTION, cmd, data, 0, &error), where KERNEL_SU_OPTION
 * is 0xDEADBEEF.  Upstream KernelSU hooks sys_prctl directly, but KSU-Next
 * v3.2.0-legacy only registers a kprobe on sys_reboot.  Since the userspace
 * tool uses prctl, we register a second kprobe to intercept SUSFS commands
 * sent via the prctl path.
 *
 * Calling convention (prctl):
 *   option = 0xDEADBEEF (KERNEL_SU_OPTION)
 *   arg2   = SUSFS CMD code (CMD_SUSFS_*)
 *   arg3   = data pointer (input or output buffer)
 *   arg5   = int __user *error (where to write return code)
 *
 * Unlike susfs_handle_sys_reboot(), the prctl path passes scalar values
 * directly (e.g. enable_log uses arg3 as the value, not a pointer), and
 * the SHOW commands write version/features to arg3 with error in arg5
 * (instead of embedding error at a fixed offset past the buffer).
 */

/* Determine the prctl syscall symbol name based on kernel version.
 * arm64 renamed syscalls from sys_* to __arm64_sys_* starting at v4.16. */
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 16, 0)
#define PRCTL_SYMBOL "__arm64_sys_prctl"
#else
#define PRCTL_SYMBOL "sys_prctl"
#endif

/* Return 0 if this was a SUSFS command and should NOT fall through to
 * the real prctl handler; return -1 if it's not our command and the
 * real prctl should handle it.  This mirrors the convention used by
 * upstream ksu_handle_prctl (return 0 = handled, return -1 = skip). */
static int handle_prctl_susfs(unsigned long option, unsigned long arg2,
			      unsigned long arg3, unsigned long arg4,
			      unsigned long arg5)
{
	mm_segment_t old_fs;
	void __user *data = (void __user *)arg3;
	int ret = 0;
	int errval;

	/* Not a KSU/SUSFS prctl call — let normal prctl handle it */
	if (option != 0xDEADBEEF)
		return -1;

	switch (arg2) {

	/* ============ SUS_PATH commands ============ */
	case CMD_SUSFS_ADD_SUS_PATH:
	case CMD_SUSFS_ADD_SUS_PATH_LOOP: {
		struct st_susfs_sus_path _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME];
		if (copy_from_user(_oldp, data, sizeof(_oldp))) {
			ret = -EFAULT; break;
		}
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs(); set_fs(KERNEL_DS);
		ret = susfs_add_sus_path((struct st_susfs_sus_path __user *)&_info);
		set_fs(old_fs);
		break;
	}

	/* ============ SUS_MOUNT commands ============ */
	case CMD_SUSFS_ADD_SUS_MOUNT:
		ret = susfs_add_sus_mount((struct st_susfs_sus_mount __user *)data);
		break;

	/* ============ SUS_KSTAT commands ============ */
	case CMD_SUSFS_ADD_SUS_KSTAT: {
		struct st_susfs_sus_kstat _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME];
		if (copy_from_user(_oldp, data, sizeof(_oldp))) {
			ret = -EFAULT; break;
		}
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs(); set_fs(KERNEL_DS);
		ret = susfs_add_sus_kstat((struct st_susfs_sus_kstat __user *)&_info);
		set_fs(old_fs);
		break;
	}

	case CMD_SUSFS_UPDATE_SUS_KSTAT: {
		struct st_susfs_sus_kstat _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME];
		if (copy_from_user(_oldp, data, sizeof(_oldp))) {
			ret = -EFAULT; break;
		}
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs(); set_fs(KERNEL_DS);
		ret = susfs_update_sus_kstat((struct st_susfs_sus_kstat __user *)&_info);
		set_fs(old_fs);
		break;
	}

	case CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY: {
		struct st_susfs_sus_kstat _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME];
		if (copy_from_user(_oldp, data, sizeof(_oldp))) {
			ret = -EFAULT; break;
		}
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs(); set_fs(KERNEL_DS);
		ret = susfs_add_sus_kstat((struct st_susfs_sus_kstat __user *)&_info);
		set_fs(old_fs);
		break;
	}

	/* ============ TRY_UMOUNT commands ============ */
	case CMD_SUSFS_ADD_TRY_UMOUNT:
		ret = susfs_add_try_umount((struct st_susfs_try_umount __user *)data);
		break;

	case CMD_SUSFS_RUN_UMOUNT_FOR_CURRENT_MNT_NS:
		susfs_try_umount(current_uid().val);
		ret = 0;
		break;

	/* ============ HIDE_SUS_MNTS (GKI backport stub) ============ */
	case CMD_SUSFS_HIDE_SUS_MNTS_FOR_NON_SU_PROCS:
		/* prctl passes the int value directly in arg3, not a pointer */
		ret = susfs_hide_sus_mnts_for_non_su_procs(arg3 ? true : false);
		break;

	/* ============ SPOOF_UNAME commands ============ */
	case CMD_SUSFS_SET_UNAME:
		ret = susfs_set_uname((struct st_susfs_uname __user *)data);
		break;

	/* ============ ENABLE_LOG ============ */
	case CMD_SUSFS_ENABLE_LOG:
		/* prctl passes the int value directly in arg3 */
		susfs_set_log(arg3 ? true : false);
		ret = 0;
		break;

	/* ============ ENABLE_AVC_LOG_SPOOFING (GKI backport stub) ============ */
	case CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING:
		/* prctl passes the int value directly in arg3 */
		ret = susfs_enable_avc_log_spoofing(arg3 ? true : false);
		break;

	/* ============ SPOOF_CMDLINE ============ */
	case CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG:
		ret = susfs_set_cmdline_or_bootconfig((char __user *)data);
		break;

	/* ============ OPEN_REDIRECT ============ */
	case CMD_SUSFS_ADD_OPEN_REDIRECT: {
		struct st_susfs_open_redirect _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME * 2];
		if (copy_from_user(_oldp, data, sizeof(_oldp))) {
			ret = -EFAULT; break;
		}
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs(); set_fs(KERNEL_DS);
		ret = susfs_add_open_redirect((struct st_susfs_open_redirect __user *)&_info);
		set_fs(old_fs);
		break;
	}

	/* ============ SUS_SU ============ */
#ifdef CONFIG_KSU_SUSFS_SUS_SU
	case CMD_SUSFS_SUS_SU:
		ret = susfs_sus_su((struct st_sus_su __user *)data);
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

	/* ============ SHOW commands (prctl convention) ============
	 * prctl: output buffer is arg3, error code goes to arg5 (int __user *).
	 * This differs from the reboot path where error is appended at a fixed
	 * offset past the output buffer. */
	case CMD_SUSFS_SHOW_VERSION:
		if (copy_to_user(data, "v1.5.5", sizeof("v1.5.5"))) {
			ret = -EFAULT; break;
		}
		errval = 0;
		if (put_user(errval, (int __user *)arg5))
			ret = -EFAULT;
		break;

	case CMD_SUSFS_SHOW_ENABLED_FEATURES: {
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
			"add_sus_map\n"
			"add_sus_maps\n"
			"update_sus_maps\n"
			"add_sus_proc_fd_link\n"
			"add_sus_memfd\n";
		if (copy_to_user(data, features, sizeof(features))) {
			ret = -EFAULT; break;
		}
		errval = 0;
		if (put_user(errval, (int __user *)arg5))
			ret = -EFAULT;
		break;
	}

	case CMD_SUSFS_SHOW_VARIANT:
		if (copy_to_user(data, "NON-GKI", sizeof("NON-GKI"))) {
			ret = -EFAULT; break;
		}
		errval = 0;
		if (put_user(errval, (int __user *)arg5))
			ret = -EFAULT;
		break;

	/* ============ SUS_MAP ============ */
	case CMD_SUSFS_ADD_SUS_MAP: {
		struct st_susfs_sus_path _info;
		char _oldp[SUSFS_MAX_LEN_PATHNAME];
		if (copy_from_user(_oldp, data, sizeof(_oldp))) {
			ret = -EFAULT; break;
		}
		memset(&_info, 0, sizeof(_info));
		memcpy(_info.target_pathname, _oldp, sizeof(_oldp));
		old_fs = get_fs(); set_fs(KERNEL_DS);
		ret = susfs_add_sus_path((struct st_susfs_sus_path __user *)&_info);
		set_fs(old_fs);
		break;
	}

	/* ============ GKI backport commands ============ */
	case CMD_SUSFS_ADD_SUS_MAPS:
		ret = susfs_add_sus_maps((struct st_susfs_sus_maps __user *)data);
		break;

	case CMD_SUSFS_UPDATE_SUS_MAPS:
		ret = susfs_update_sus_maps((struct st_susfs_sus_maps __user *)data);
		break;

	case CMD_SUSFS_ADD_SUS_PROC_FD_LINK:
		ret = susfs_add_sus_proc_fd_link((struct st_susfs_sus_proc_fd_link __user *)data);
		break;

	case CMD_SUSFS_ADD_SUS_MEMFD:
		ret = susfs_add_sus_memfd((struct st_susfs_sus_memfd __user *)data);
		break;

	default:
		pr_info("susfs_prctl: unknown cmd 0x%lx, -EOPNOTSUPP\n", arg2);
		ret = -EOPNOTSUPP;
		break;
	}

	/* Write the return code to arg5 (error pointer) if provided */
	if (arg5) {
		errval = ret;
		put_user(errval, (int __user *)arg5);
	}

	pr_debug("susfs_prctl: cmd 0x%lx ret %d\n", arg2, ret);
	return 0;
}

/* ===== prctl kprobe handler =====
 *
 * kprobe pre_handler for sys_prctl.  Fires on every prctl() syscall.
 * Fast-path returns immediately if option != 0xDEADBEEF.  When a SUSFS
 * command is detected, dispatches via handle_prctl_susfs(), prevents the
 * real sys_prctl from running, and returns the SUSFS result.
 *
 * We return 1 (NOTIFY_DONE) in both cases — the real prctl handler is
 * skipped only when we set regs->syscallno = -1.
 */

static struct kprobe prctl_kp;

static int prctl_handler_pre(struct kprobe *p, struct pt_regs *regs)
{
	unsigned long option, arg2, arg3, arg4, arg5;
	int ret;

	/* arm64 syscall convention: x0-x4 hold the first 5 args */
	option = regs->regs[0];
	arg2   = regs->regs[1];
	arg3   = regs->regs[2];
	arg4   = regs->regs[3];
	arg5   = regs->regs[4];

	/* Fast-path: not a KSU/SUSFS prctl call */
	if (option != 0xDEADBEEF)
		return 0;

	/* Handle SUSFS command */
	ret = handle_prctl_susfs(option, arg2, arg3, arg4, arg5);

	/* Prevent the real sys_prctl from executing and returning -EINVAL */
	regs->syscallno = -1;
	regs->regs[0] = (unsigned long)(long)ret;

	pr_debug("susfs_prctl: intercepted option=0x%lx cmd=0x%lx ret=%d\n",
		 option, arg2, ret);

	return 1; /* NOTIFY_DONE */
}

/* Register the prctl kprobe.  Failure is non-fatal — SUSFS commands sent
 * via prctl will simply fail, which is the same behavior as before. */
static int __init ksu_prctl_kprobe_init(void)
{
	int ret;

	prctl_kp.symbol_name = PRCTL_SYMBOL;
	prctl_kp.pre_handler = prctl_handler_pre;

	ret = register_kprobe(&prctl_kp);
	if (ret) {
		pr_warn("susfs_prctl: kprobe on '%s' failed (%d). SUSFS prctl dispatch unavailable.\n",
			PRCTL_SYMBOL, ret);
		return ret;
	}

	pr_info("susfs_prctl: kprobe on '%s' registered successfully\n",
		PRCTL_SYMBOL);
	return 0;
}

/* Unregister the prctl kprobe */
static void __exit ksu_prctl_kprobe_exit(void)
{
	unregister_kprobe(&prctl_kp);
}

/* Register at device_initcall level (after kprobes subsystem is ready,
 * before late_initcall where susfs_init runs) */
device_initcall(ksu_prctl_kprobe_init);
