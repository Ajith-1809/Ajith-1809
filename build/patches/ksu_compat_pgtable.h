/* SPDX-License-Identifier: GPL-2.0 */
/*
 * ksu_compat_pgtable.h — Compatibility stub for <linux/pgtable.h>
 *
 * Kernel 5.9+ split asm/pgtable.h into this separate header.
 * On 4.14 CAF kernels, just include asm/pgtable.h instead.
 * This file is copied into include/linux/pgtable.h during the build.
 */
#include <asm/pgtable.h>
