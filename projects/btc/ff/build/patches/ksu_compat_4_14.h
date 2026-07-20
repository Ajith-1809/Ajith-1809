/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ksu_compat_4_14.h — KSUN v3.3.0 compat layer for Linux 4.14 CAF kernels
 *
 * Force-included via ccflags-y in KernelSU-Next/kernel/Kbuild.
 * Provides minimal type/macro definitions that exist in kernel 5.3+ but
 * are absent on tillua467's 4.14 CAF (Qualcomm SM6150) kernel.
 *
 * This file is NOT needed on newer kernel targets (5.10+).
 *
 * NOTE: Include kernel headers AFTER the guard so each #include is only
 * resolved once per translation unit.  Only add includes here when the
 * missing symbol is purely header-related (no struct/API difference).
 */

#ifndef __KSU_COMPAT_4_14_H
#define __KSU_COMPAT_4_14_H

/* ======================================================================
 * Headers that 4.14 CAF does not pull in transitively for all v3.3.0
 * compilation units but that must be visible for standard functions.
 * ====================================================================== */
#include <linux/uaccess.h>     /* strncpy_from_user() — syscall_event_bridge.c  */

/* ======================================================================
 * __flush_icache_range — not declared on 4.14 CAF arm64
 *
 * ksu_flush_icache macro (patch_memory.c:105) expands to the bare
 * identifier __flush_icache_range without trailing parentheses, so a
 * function-like macro compat wouldn't expand.  We use an object-like
 * macro redirecting to flush_icache_range which IS declared on 4.14.
 * ====================================================================== */
#ifndef __flush_icache_range
#define __flush_icache_range flush_icache_range
#endif

/* ======================================================================
 * syscall_fn_t — kernel 5.3+ include/linux/syscalls.h
 *
 * On arm64 4.14 CAF, asm/syscall.h does not define sys_call_ptr_t
 * and syscall_hook.h only typedefs syscall_fn_t for x86_64.
 * We provide the standard kernel 5.3+ definition for arm64.
 * Forward-declare pt_regs; the full definition comes via asm/ptrace.h.
 * ====================================================================== */
#if defined(__aarch64__)
struct pt_regs;
typedef long (*syscall_fn_t)(const struct pt_regs *regs);
#endif

/* ======================================================================
 * copy_to_kernel_nofault — kernel 5.8+ (replaced probe_kernel_write)
 *
 * Hook/arm64/patch_memory.c uses copy_to_kernel_nofault() unconditionally.
 * On 4.14 (< 5.8) the equivalent is probe_kernel_write() with the same
 * signature: long (void *dst, const void *src, size_t len).
 * The calling code already includes <linux/uaccess.h> which declares it.
 * ====================================================================== */
#include <linux/version.h>
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0)
#define copy_to_kernel_nofault(dst, src, len) probe_kernel_write(dst, src, len)
#define copy_from_user_nofault(to, from, n) copy_from_user(to, from, n)
#define copy_to_user_nofault(to, from, n)   copy_to_user(to, from, n)
#endif

/* ======================================================================
 * __nocfi — Clang CFI attribute (not available on 4.14 GCC)
 *
 * Used in hook/syscall_event_bridge.c and hook/arm64/syscall_hook.c
 * on function definitions. Expands to nothing on GCC 4.14.
 * ====================================================================== */
#ifndef __nocfi
#define __nocfi
#endif

/* ======================================================================
 * ksys_close — kernel 4.17+ (not available on 4.14 CAF)
 *
 * Used in include/util.h: for kernels < 5.11 it aliases ksu_close_fd to
 * ksys_close. On 4.14 (< 4.17) where ksys_close does not exist, redirect
 * to sys_close which has the same signature: long (unsigned int fd).
 * ====================================================================== */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 17, 0)
#define ksys_close sys_close
#endif

/* ======================================================================
 * ksys_unshare — kernel 4.17+ (not available on 4.14 CAF)
 *
 * Used in infra/su_mount_ns.c.  On 4.14 the equivalent is sys_unshare
 * with the same signature: long (unsigned long flags).
 * ====================================================================== */
#if LINUX_VERSION_CODE < KERNEL_VERSION(4, 17, 0)
#define ksys_unshare sys_unshare
#endif

/* ======================================================================
 * untagged_addr — Linux 4.19+ arm64 address-tag stripping macro
 *
 * Used in hook/syscall_event_bridge.c to strip address tags from
 * user pointers. On 4.14 where this macro does not exist, use the
 * identity — arm64 4.14 does not use top-byte-ignore (TBI) in a
 * way that requires stripping for kernel syscalls.
 * ====================================================================== */
#ifndef untagged_addr
#define untagged_addr(addr) (addr)
#endif

/* ======================================================================
 * __pte_to_phys — arm64 kernel 5.3+ (arch/arm64/include/asm/pte.h)
 *
 * Used in hook/arm64/patch_memory.c, function phys_from_virt().
 * On 4.14 arm64 where this macro does not exist, compute the physical
 * address from the page table entry via pte_pfn().
 * ====================================================================== */
#ifndef __pte_to_phys
#define __pte_to_phys(pte) (pte_pfn(pte) << PAGE_SHIFT)
#endif

/* ======================================================================
 * SECCOMP_ARCH_NATIVE_NR / SECCOMP_ARCH_COMPAT_NR — kernel 5.7+
 * (include/linux/seccomp.h)
 *
 * Used in infra/seccomp_cache.c as DECLARE_BITMAP size.  On 4.14 these
 * are not defined.  Use a generous fixed value — arm64 has well under
 * 500 syscalls, the extra ~12 bytes per bitmap is harmless.
 * ====================================================================== */
#ifndef SECCOMP_ARCH_NATIVE_NR
#define SECCOMP_ARCH_NATIVE_NR 512
#endif
#ifndef SECCOMP_ARCH_COMPAT_NR
#define SECCOMP_ARCH_COMPAT_NR 512
#endif

/* ======================================================================
 * TWA_RESUME — kernel 5.7+ enum task_work_notify_mode
 *
 * Used in policy/allowlist.c as 3rd arg to task_work_add().
 * On 4.14, task_work_add(task, work, bool) where a true 3rd arg adds the
 * work to the head of the list — equivalent to TWA_RESUME behaviour.
 * ====================================================================== */
#ifndef TWA_RESUME
#define TWA_RESUME 1
#endif

/* ======================================================================
 * put_task_struct — moved to <linux/sched/task.h> in kernel 4.11
 *
 * On CAF 4.14 it is a static inline declared in <linux/sched/task.h>,
 * but allowlist.c does not include that header.  Force-include it.
 * ====================================================================== */
#include <linux/sched/task.h>

/* ======================================================================
 * task_pgrp / task_session -- <linux/sched/signal.h> on CAF 4.14
 *
 * Used in supercall/dispatch.c (do_set_init_pgrp).  These are static
 * inline functions in the CAF 4.14 kernel headers but are not pulled
 * in transitively by any header that dispatch.c includes.
 * ====================================================================== */
#include <linux/sched/signal.h>

#endif /* __KSU_COMPAT_4_14_H */
