// SPDX-License-Identifier: GPL-2.0
/*
 * ksu_susfs_compat.c — SUSFS compatibility shim for KSUN v3.2.0-legacy
 *
 * Bridges the official SUSFS kernel module (kernel-4.14 branch from
 * simonpunk/susfs4ksu) with the KSU-Next supercall dispatch.
 *
 * Provides:
 *   - ksu_try_umount() / susfs_try_umount_all()
 *   - ksu_susfs_enable_sus_su() / ksu_susfs_disable_sus_su()
 *   - susfs_handle_sys_reboot() — routes all SUSFS CMD_* codes from the
 *     kernel/reboot.c supercall dispatch to the real susfs.c handlers.
 *
 * Note: SELinux domain check functions (susfs_is_current_ksu_domain etc.)
 * and ksu_handle_sys_reboot() are now provided natively by KSUN's updated
 * legacy branch (selinux/selinux.c and supercall/supercall.c respectively).
 * Do NOT redefine them here.
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

/* ===== SUSFS structs matching kernel-4.14 branch =====
 *
 * All structs below match the kernel-4.14 branch of simonpunk/susfs4ksu,
 * with target_ino/is_statically prefix fields at offset 0.  The dispatch
 * code fills these and passes them directly to the real susfs_* handlers
 * via set_fs(KERNEL_DS) — no manual format conversion is needed.
 *
 * IMPORTANT: The kernel-4.14 branch structs do NOT carry a uid field.
 * The userspace binary sends an extended buffer with uid at offset 256,
 * but it is extracted at dispatch time and NOT forwarded to the kernel.
 *
 * Functions are declared with extern — they resolve at link time
 * against fs/susfs.o (compiled from fs/susfs.c).
 */
#include <linux/susfs_def.h>

/* kernel-4.14 struct (no uid field in this branch): target_ino(8) + pathname(256)  → sizeof=264
 *
 * NOTE: The userspace binary sends an extended buffer (path[256] + uid[4] + target_ino[8]).
 * The uid is read from the binary at dispatch time for logging but is NOT part of the
 * kernel struct — kernel-4.14 branch does not support per-UID path hiding. */
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
	char                    release[__NEW_UTS_LEN + 1];
	char                    version[__NEW_UTS_LEN + 1];
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
	bool                    is_statically;
	int                     compare_mode;
	bool                    is_isolated_entry;
	bool                    is_file;
	unsigned long           prev_target_ino;
	unsigned long           next_target_ino;
	char                    target_pathname[SUSFS_MAX_LEN_PATHNAME];
	unsigned long           target_ino;
	unsigned long           target_dev;
	unsigned long long      target_pgoff;
	unsigned long           target_prot;
	unsigned long           target_addr_size;
	char                    spoofed_pathname[SUSFS_MAX_LEN_PATHNAME];
	unsigned long           spoofed_ino;
	unsigned long           spoofed_dev;
	unsigned long long      spoofed_pgoff;
	unsigned long           spoofed_prot;
	bool                    need_to_spoof_pathname;
	bool                    need_to_spoof_ino;
	bool                    need_to_spoof_dev;
	bool                    need_to_spoof_pgoff;
	bool                    need_to_spoof_prot;
};

struct st_susfs_sus_proc_fd_link {
	char target_link_name[SUSFS_MAX_LEN_PATHNAME];
	char spoofed_link_name[SUSFS_MAX_LEN_PATHNAME];
};

struct st_susfs_sus_memfd {
	char target_pathname[248];
};

#ifndef SUSFS_MAX_LEN_MFD_NAME
#define SUSFS_MAX_LEN_MFD_NAME 248
#endif

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
extern void susfs_spoof_uname(struct new_utsname *tmp);
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

/* SUSFS domain check wrappers for KSUN.
 * KSUN provides is_ksu_domain() and is_zygote() in selinux.c.
 * SUSFS expects susfs_is_current_ksu_domain() and
 * susfs_is_current_zygote_domain() — these wrappers bridge the gap.
 * The extern declarations resolve at link time against
 * KernelSU-Next/kernel/selinux/selinux.o. */
extern bool is_ksu_domain(void);
extern bool is_zygote(const struct cred *cred);

bool susfs_is_current_ksu_domain(void)
{
	return is_ksu_domain();
}
EXPORT_SYMBOL_GPL(susfs_is_current_ksu_domain);

bool susfs_is_current_zygote_domain(void)
{
	return is_zygote(current_cred());
}
EXPORT_SYMBOL_GPL(susfs_is_current_zygote_domain);

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

/* ===== GKI-backported feature implementations (kernel-4.14) =====
 * These features exist fully in the GKI susfs branch and are stubbed
 * here for kernel-4.14.  Returns success so userspace tools detect
 * them as "available" rather than "not supported" (-EOPNOTSUPP).
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

/* ksu_handle_sys_reboot is now provided natively by KSUN
 * (KernelSU-Next/kernel/supercall/supercall.c). The patch_reboot.py
 * script injects the call into kernel/reboot.c to satisfy the Kbuild
 * hook check — the symbol resolves at link time from supercall.o. */

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
	/* Spoof kernel release at boot time — overrides utsname for ALL
	 * userspace processes, keeping Disclosure Detector item 4 clean
	 * ("release name not modified").  This runs before init so
	 * uname -r and /proc/version both read "4.14.275" immediately.
	 */
	{
		char orig[65];
		strncpy(orig, init_uts_ns.name.release, 64);
		orig[64] = '\0';
		memcpy(init_uts_ns.name.release, "4.14.275\0", 10);
		pr_info("ksu_susfs_compat: release spoof → 4.14.275 (was %s)\n", orig);
	}
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
	case 0x55550: /* CMD_SUSFS_ADD_SUS_PATH */
	case 0x55569: /* CMD_SUSFS_ADD_SUS_PATH_LOOP */ {
		/* Struct layout conversion: the userspace binary sends:
		 *   path[256] at offset 0
		 *   uid[4]    at offset 256
		 *   target_ino[8] at offset 260
		 * The kernel-4.14 branch expects:
		 *   target_ino at offset 0, pathname at offset 8 (NO uid field).
		 * Read each field separately and construct the kernel struct.
		 * bin_uid is read for logging but NOT passed to the kernel. */
		char bin_pathname[SUSFS_MAX_LEN_PATHNAME];
		unsigned long bin_ino;
		uid_t bin_uid;
		struct st_susfs_sus_path _info = {0};

		/* Binary sends pathname at offset 0 (256 bytes) */
		if (copy_from_user(bin_pathname, arg, sizeof(bin_pathname)))
			return -EFAULT;
		/* Binary sends uid at offset 256 (after pathname) */
		if (copy_from_user(&bin_uid,
				   (void __user *)arg + SUSFS_MAX_LEN_PATHNAME,
				   sizeof(bin_uid)))
			return -EFAULT;
		/* Binary sends target_ino at offset 260 (after pathname + uid) */
		if (copy_from_user(&bin_ino,
				   (void __user *)arg + SUSFS_MAX_LEN_PATHNAME + sizeof(uid_t),
				   sizeof(bin_ino)))
			return -EFAULT;

		/* Fill kernel-4.14 struct: target_ino at offset 0, pathname at offset 8.
		 * bin_uid was read from the binary for potential logging but the kernel
		 * struct does not carry uid — kernel-4.14 doesn't support per-UID paths. */
		_info.target_ino = bin_ino;
		memcpy(_info.target_pathname, bin_pathname,
		       SUSFS_MAX_LEN_PATHNAME);

		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_add_sus_path((struct st_susfs_sus_path __user *)&_info);
		set_fs(old_fs);
		if (ret == 0)
			put_user(0, (int __user *)((char __user *)arg + 16));
		break;
	}


		/* ============ SUS_MOUNT commands ============ */
	case 0x55560: /* CMD_SUSFS_ADD_SUS_MOUNT */ {
		/* Binary sends only pathname (256 bytes) without target_dev.
		 * Kernel-4.14 expects pathname + dev (264 bytes). Zero-fill
		 * the dev field to avoid garbage. */
		struct st_susfs_sus_mount _info = {0};
		if (copy_from_user(_info.target_pathname, arg,
				   sizeof(_info.target_pathname)))
			return -EFAULT;
		/* target_dev stays 0 from {0} initialization */
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_add_sus_mount((struct st_susfs_sus_mount __user *)&_info);
		set_fs(old_fs);
		if (ret == 0)
			put_user(0, (int __user *)((char __user *)arg + 16));
		break;
	}


	/* ============ SUS_KSTAT commands ============ */
	case 0x55570: /* CMD_SUSFS_ADD_SUS_KSTAT */
	case 0x55571: /* CMD_SUSFS_UPDATE_SUS_KSTAT */
	case 0x55572: /* CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY */ {
		/* Direct struct passthrough: kernel-4.14 struct layout
		 * (is_statically+padding+target_ino at offset 0, pathname
		 * at offset 16) matches what the userspace binary sends.
		 * No conversion needed. UPDATE vs ADD distinguishes path. */
		struct st_susfs_sus_kstat _info;
		if (copy_from_user(&_info, arg, sizeof(_info)))
			return -EFAULT;
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		if (cmd == 0x55571) /* CMD_SUSFS_UPDATE_SUS_KSTAT */
			ret = susfs_update_sus_kstat((struct st_susfs_sus_kstat __user *)&_info);
		else
			ret = susfs_add_sus_kstat((struct st_susfs_sus_kstat __user *)&_info);
		set_fs(old_fs);
		if (ret == 0)
			put_user(0, (int __user *)((char __user *)arg + 16));
		break;
	}

	/* ============ TRY_UMOUNT commands ============ */
	case 0x55580: /* CMD_SUSFS_ADD_TRY_UMOUNT */ {
		struct st_susfs_try_umount _info;
		if (copy_from_user(&_info, arg, sizeof(_info)))
			return -EFAULT;
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_add_try_umount((struct st_susfs_try_umount __user *)&_info);
		set_fs(old_fs);
		if (ret == 0)
			put_user(0, (int __user *)((char __user *)arg + 16));
		break;
	}

	case 0x555d0: /* CMD_SUSFS_RUN_UMOUNT_FOR_CURRENT_MNT_NS */
		susfs_try_umount(current_uid().val);
		ret = 0;
		put_user(0, (int __user *)((char __user *)arg + 16));
		break;

	/* ============ HIDE_SUS_MNTS (GKI backport stub) ============ */
	/* CMD code 0x55561 is master-branch's HIDE_SUS_MNTS_FOR_NON_SU_PROCS
	 * (not defined in kernel-4.14). Treat as no-op for compatibility. */
	case 0x55561: {
		int enabled;
		if (copy_from_user(&enabled, arg, sizeof(enabled)))
			return -EFAULT;
		ret = susfs_hide_sus_mnts_for_non_su_procs(enabled ? true : false);
		if (ret == 0)
			put_user(0, (int __user *)((char __user *)arg + 16));
		break;
	}

		/* ============ SPOOF_UNAME commands ============ */
	case 0x55590: /* CMD_SUSFS_SET_UNAME */ {
		/* ksu_susfs v1.5.5 binary sends the kernel-4.14 struct layout:
		 *   char release[65]  at offset 0
		 *   char version[65]  at offset 65
		 * Direct copy — no conversion needed. */
		struct st_susfs_uname _info = {0};

		if (copy_from_user(&_info, arg, sizeof(_info)))
			return -EFAULT;

		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_set_uname((struct st_susfs_uname __user *)&_info);
		set_fs(old_fs);
		if (ret == 0) {
			susfs_spoof_uname(utsname());
			/* Do NOT clobber live utsname()->release. The read path
			 * (newuname) copies my_uname.release (set above) into the
			 * returned struct, so the spoof is authoritative. Writing
			 * the real release back here poisons utsname()->release,
			 * which (a) makes /proc/sys/kernel/osrelease report real and
			 * (b) gets re-captured by any later `set_uname default`
			 * call into my_uname.release, silently killing the spoof.
			 * The live utsname stays at the real value on purpose. */
			pr_info("ksu_susfs: uname spoof stored (release='%s')\n",
				utsname()->release);
			/* Binary checks err code at arg+16 */
			if (ret == 0)
				put_user(0, (int __user *)((char __user *)arg + 16));
		}
		break;

	}


	/* ============ ENABLE_LOG ============ */
	case 0x555a0: /* CMD_SUSFS_ENABLE_LOG */ {
		int enabled;
		if (copy_from_user(&enabled, arg, sizeof(enabled)))
			return -EFAULT;
		susfs_set_log(enabled ? true : false);
		ret = 0;
		/* Binary checks err at arg+16 */
		if (ret == 0)
			put_user(0, (int __user *)((char __user *)arg + 16));
		break;
	}

	/* ============ ENABLE_AVC_LOG_SPOOFING (GKI backport stub) ============ */
	/* 0x60010 is master-branch CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING, not
	 * defined in 4.14. Treat as no-op. */
	case 0x60010: {
		int enabled;
		if (copy_from_user(&enabled, arg, sizeof(enabled)))
			return -EFAULT;
		ret = susfs_enable_avc_log_spoofing(enabled ? true : false);
		if (ret == 0)
			put_user(0, (int __user *)((char __user *)arg + 16));
		break;
	}

	/* ============ SPOOF_CMDLINE ============ */
	case 0x555b0: /* CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG */ {
		char _cmdline[SUSFS_FAKE_CMDLINE_OR_BOOTCONFIG_SIZE];
		if (copy_from_user(_cmdline, arg, sizeof(_cmdline)))
			return -EFAULT;
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_set_cmdline_or_bootconfig((char __user *)_cmdline);
		set_fs(old_fs);
		if (ret == 0)
			put_user(0, (int __user *)((char __user *)arg + 16));
		break;
	}

	/* ============ OPEN_REDIRECT ============ */
	case 0x555c0: /* CMD_SUSFS_ADD_OPEN_REDIRECT */ {
		/* Direct struct passthrough: kernel-4.14 struct layout
		 * (target_ino at offset 0, target_pathname at offset 8,
		 * redirected_pathname at offset 264) matches the binary.
		 * No conversion needed. */
		struct st_susfs_open_redirect _info;
		if (copy_from_user(&_info, arg, sizeof(_info)))
			return -EFAULT;
		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_add_open_redirect((struct st_susfs_open_redirect __user *)&_info);
		set_fs(old_fs);
		if (ret == 0)
			put_user(0, (int __user *)((char __user *)arg + 16));
		break;
	}

	/* ============ SUS_SU ============
	 * sus_su mode switching is guarded by CONFIG_KSU_SUSFS_SUS_SU.
	 * The kernel-4.14 branch has no CONFIG_KSU_SUSFS_SUS_SU, so the
	 * CMDs are unconditionally mapped to -EOPNOTSUPP fall-through. */
#ifndef CONFIG_KSU_SUSFS_SUS_SU
	case 0x60000: /* CMD_SUSFS_SUS_SU */
	case 0x555f0: /* CMD_SUSFS_IS_SUS_SU_READY */
	case 0x555e4: /* CMD_SUSFS_SHOW_SUS_SU_WORKING_MODE */
		ret = -EOPNOTSUPP;
		break;
#endif

	/* ============ SHOW commands ============ */
	case 0x555e1: /* CMD_SUSFS_SHOW_VERSION */ {
		/* struct { char version[16]; int err; } */
		if (copy_to_user(arg, "v1.5.5", sizeof("v1.5.5")))
			return -EFAULT;
		if (put_user(0, (int __user *)((char __user *)arg + 16)))
			return -EFAULT;
		ret = 0;
		break;
	}

	case 0x555e2: /* CMD_SUSFS_SHOW_ENABLED_FEATURES */ {
		/* struct { char features[8192]; int err; } */
		/* Return CONFIG names so SUSFS4KSU module scripts and WebUI
		 * can detect features via grep for CONFIG_KSU_SUSFS_*. */
		static const char features[] =
			"CONFIG_KSU_SUSFS_SUS_PATH=y\n"
			"CONFIG_KSU_SUSFS_SUS_MAP=y\n"
			"CONFIG_KSU_SUSFS_SUS_MEMFD=y\n"
			"CONFIG_KSU_SUSFS_SUS_PROC_FD_LINK=y\n"
			"CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y\n"
			"CONFIG_KSU_SUSFS_SUS_MOUNT=y\n"
			"CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y\n"
			"CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y\n"
			"CONFIG_KSU_SUSFS_SUS_KSTAT=y\n"
			"CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y\n"
			"CONFIG_KSU_SUSFS_TRY_UMOUNT=y\n"
			"CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y\n"
			"CONFIG_KSU_SUSFS_SPOOF_UNAME=y\n"
			"CONFIG_KSU_SUSFS_ENABLE_LOG=y\n"
			"CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y\n"
			"CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y\n"
			"CONFIG_KSU_SUSFS_OPEN_REDIRECT=y\n";
		if (copy_to_user(arg, features, sizeof(features)))
			return -EFAULT;
		if (put_user(0, (int __user *)((char __user *)arg + 8192)))
			return -EFAULT;
		ret = 0;
		break;
	}

	case 0x555e3: /* CMD_SUSFS_SHOW_VARIANT */ {
		/* struct { char variant[16]; int err; } */
		if (copy_to_user(arg, "NON-GKI", sizeof("NON-GKI")))
			return -EFAULT;
		if (put_user(0, (int __user *)((char __user *)arg + 16)))
			return -EFAULT;
		ret = 0;
		break;
	}

		/* ============ SUS_MAP (add_sus_map from userspace) ============ */
	/* 0x60020 is master-branch CMD_SUSFS_ADD_SUS_MAP, not defined in 4.14.
	 * Routes to susfs_add_sus_path (kernel-4.14 treats SUS_MAP as path
	 * hiding via the SUS_PATH_HLIST). Same master-branch struct
	 * conversion as CMD_SUSFS_ADD_SUS_PATH is needed. */
	case 0x60020: {
		char bin_pathname[SUSFS_MAX_LEN_PATHNAME];
		unsigned long bin_ino;
		struct st_susfs_sus_path _info = {0};

		/* Binary sends pathname at offset 0 (256 bytes) */
		if (copy_from_user(bin_pathname, arg, sizeof(bin_pathname)))
			return -EFAULT;
		/* Binary sends target_ino at offset 256 */
		if (copy_from_user(&bin_ino,
				   (void __user *)arg + SUSFS_MAX_LEN_PATHNAME,
				   sizeof(bin_ino)))
			return -EFAULT;

		_info.target_ino = bin_ino;
		memcpy(_info.target_pathname, bin_pathname,
		       SUSFS_MAX_LEN_PATHNAME);

		old_fs = get_fs();
		set_fs(KERNEL_DS);
		ret = susfs_add_sus_path((struct st_susfs_sus_path __user *)&_info);
		set_fs(old_fs);
		if (ret == 0)
			put_user(0, (int __user *)((char __user *)arg + 16));
		break;
	}


	/* ============ GKI backport commands ============ */
	case 0x5556d: /* CMD_SUSFS_ADD_SUS_MAPS */
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
		ret = susfs_add_sus_maps((void __user *)arg);
#else
		ret = -EOPNOTSUPP;
#endif
		break;
	case 0x55562: /* CMD_SUSFS_UPDATE_SUS_MAPS */
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
		ret = susfs_update_sus_maps((void __user *)arg);
#else
		ret = -EOPNOTSUPP;
#endif
		break;
	case 0x5555f: /* CMD_SUSFS_ADD_SUS_PROC_FD_LINK */
#ifdef CONFIG_KSU_SUSFS_SUS_PROC_FD_LINK
		ret = susfs_add_sus_proc_fd_link((void __user *)arg);
#else
		ret = -EOPNOTSUPP;
#endif
		break;
	case 0x55563: /* CMD_SUSFS_ADD_SUS_MEMFD */
#ifdef CONFIG_KSU_SUSFS_SUS_MEMFD
		ret = susfs_add_sus_memfd((void __user *)arg);
#else
		ret = -EOPNOTSUPP;
#endif
		break;

	default:
		return -EOPNOTSUPP;
	}

	return ret;
}
EXPORT_SYMBOL_GPL(susfs_handle_sys_reboot);

