/*
 * ksu_root_helper.c — Minimal ARM64 static binary to bootstrap KSU root
 *
 * Usage: ksu_root_helper [commands...]
 *
 * This program:
 *  1. Calls reboot(0xDEADBEEF, 0xCAFEBABE, 0, &fd) to get a KSU driver fd
 *  2. Calls ioctl(fd, KSU_IOCTL_GRANT_ROOT, NULL) to escalate to UID 0
 *  3. Creates /data/adb/ksu/bin/ directory structure
 *  4. Copies ksud from /data/local/tmp/ to /data/adb/ksu/bin/
 *  5. Runs ksud debug set-manager to register the Manager app
 *  6. Executes any remaining arguments as a command under root
 *
 * Compile for ARM64 (static, no libc dependency):
 *   aarch64-linux-gnu-gcc -static -Os -nostdlib -ffreestanding \
 *       -o ksu_root_helper ksu_root_helper.c
 */

#define __NR_ioctl   29
#define __NR_reboot  142
#define __NR_mkdirat 34
#define __NR_execve  221
#define __NR_openat  56
#define __NR_read    63
#define __NR_write   64
#define __NR_close   57
#define __NR_fstat   80
#define __NR_mmap    222
#define __NR_exit    93
#define __NR_getuid  172
#define __NR_setuid  146
#define __NR_getgid  104

#define KSU_INSTALL_MAGIC1  0xDEADBEEF
#define KSU_INSTALL_MAGIC2  0xCAFEBABE

/* KSU_IOCTL_GRANT_ROOT = _IOC(_IOC_NONE, 'K', 1, 0) */
#define KSU_IOCTL_GRANT_ROOT  (('K' << 8) | 1)

#define AT_FDCWD (-100)

#define O_RDONLY   0
#define O_WRONLY   1
#define O_CREAT   0100
#define O_TRUNC   01000

#define S_IRWXU   0700
#define S_IRWXG   0070
#define S_IRWXO   0007

#ifndef NULL
#define NULL ((void *)0)
#endif

static long sys_call(long nr, long a0, long a1, long a2, long a3, long a4, long a5)
{
    register long x8 __asm__("x8") = nr;
    register long x0 __asm__("x0") = a0;
    register long x1 __asm__("x1") = a1;
    register long x2 __asm__("x2") = a2;
    register long x3 __asm__("x3") = a3;
    register long x4 __asm__("x4") = a4;
    register long x5 __asm__("x5") = a5;

    __asm__ volatile(
        "svc #0\n"
        : "=r"(x0)
        : "r"(x0), "r"(x1), "r"(x2), "r"(x3), "r"(x4), "r"(x5), "r"(x8)
        : "memory"
    );
    return x0;
}

/* Convert a hex digit to char */
static char hex_char(unsigned long v, int nibble)
{
    int d = (v >> (nibble * 4)) & 0xf;
    if (d < 10) return '0' + d;
    return 'a' + d - 10;
}

static void write_str(const char *s)
{
    unsigned long n = 0;
    while (s[n]) n++;
    sys_call(__NR_write, 1, (long)s, n, 0, 0, 0);
}

static void write_hex(unsigned long v)
{
    char buf[18];
    int i;
    buf[0] = '0';
    buf[1] = 'x';
    for (i = 15; i >= 0; i--) {
        buf[16 - i + 1] = hex_char(v, i);
    }
    buf[18] = '\0';
    /* Skip leading zeros */
    int start = 2;
    while (start < 17 && buf[start] == '0') start++;
    if (start == 17) start = 16; /* keep last zero */
    write_str(buf + start - 2); /* keep 0x prefix */
}

static void write_dec(long v)
{
    char buf[20];
    int i = 19;
    int neg = 0;

    if (v < 0) {
        neg = 1;
        v = -v;
    }

    buf[19] = '\0';
    if (v == 0) {
        buf[--i] = '0';
    } else {
        while (v > 0 && i > 0) {
            buf[--i] = '0' + (v % 10);
            v /= 10;
        }
    }
    if (neg && i > 0) buf[--i] = '-';
    write_str(buf + i);
}

static long sys_reboot(long a0, long a1, long a2, long a3)
{
    return sys_call(__NR_reboot, a0, a1, a2, a3, 0, 0);
}

static long sys_ioctl(long fd, long cmd, long arg)
{
    return sys_call(__NR_ioctl, fd, cmd, arg, 0, 0, 0);
}

static long sys_mkdirat(long dfd, const char *path, long mode)
{
    return sys_call(__NR_mkdirat, dfd, (long)path, mode, 0, 0, 0);
}

static long sys_openat(long dfd, const char *path, long flags, long mode)
{
    return sys_call(__NR_openat, dfd, (long)path, flags, mode, 0, 0);
}

static long sys_close(long fd)
{
    return sys_call(__NR_close, fd, 0, 0, 0, 0, 0);
}

static long sys_read(long fd, void *buf, unsigned long count)
{
    return sys_call(__NR_read, fd, (long)buf, count, 0, 0, 0);
}

static long sys_write(long fd, const void *buf, unsigned long count)
{
    return sys_call(__NR_write, fd, (long)buf, count, 0, 0, 0);
}

static long sys_getuid(void)
{
    return sys_call(__NR_getuid, 0, 0, 0, 0, 0, 0);
}

static long sys_getgid(void)
{
    return sys_call(__NR_getgid, 0, 0, 0, 0, 0, 0);
}

static long sys_execve(const char *path, char *const argv[], char *const envp[])
{
    return sys_call(__NR_execve, (long)path, (long)argv, (long)envp, 0, 0, 0);
}

static long sys_exit(long code)
{
    return sys_call(__NR_exit, code, 0, 0, 0, 0, 0);
}

/* Copy a file from src to dst using only syscalls */
static int copy_file(const char *dst_path, const char *src_path)
{
    char buf[4096];
    long n;

    write_str("  [copy_file] src=");
    write_str(src_path);
    write_str(" dst=");
    write_str(dst_path);
    write_str("\n");

    long src_fd = sys_openat(AT_FDCWD, src_path, O_RDONLY, 0);
    if (src_fd < 0) {
        write_str("  [copy_file] ERROR: open src failed, ret=");
        write_dec(src_fd);
        write_str("\n");
        return -1;
    }

    long dst_fd = sys_openat(AT_FDCWD, dst_path, O_WRONLY | O_CREAT | O_TRUNC, 0755);
    if (dst_fd < 0) {
        write_str("  [copy_file] ERROR: open dst failed, ret=");
        write_dec(dst_fd);
        write_str("\n");
        sys_close(src_fd);
        return -1;
    }

    while ((n = sys_read(src_fd, buf, sizeof(buf))) > 0) {
        char *p = buf;
        while (n > 0) {
            long w = sys_write(dst_fd, p, n);
            if (w <= 0) {
                write_str("  [copy_file] ERROR: write failed, ret=");
                write_dec(w);
                write_str("\n");
                sys_close(dst_fd);
                sys_close(src_fd);
                return -1;
            }
            p += w;
            n -= w;
        }
    }

    sys_close(dst_fd);
    sys_close(src_fd);
    write_str("  [copy_file] OK\n");
    return 0;
}

void _start(void)
{
    long ret;
    int fd = -1;

    /* Write banner */
    write_str("ksu_root_helper v2 starting\n");

    /* Show current uid/gid */
    write_str("  Before: uid=");
    write_dec(sys_getuid());
    write_str(" gid=");
    write_dec(sys_getgid());
    write_str("\n");

    /* Step 1: Get KSU driver fd via reboot magic */
    write_str("  [step 1] Calling reboot(0xDEADBEEF, 0xCAFEBABE, 0, &fd)...\n");
    ret = sys_reboot(KSU_INSTALL_MAGIC1, KSU_INSTALL_MAGIC2, 0, (long)&fd);
    write_str("  [step 1] reboot returned ");
    write_dec(ret);
    write_str(", fd=");
    write_dec(fd);
    write_str("\n");

    if (fd < 0) {
        write_str("  [step 1] WARNING: fd invalid, trying fd=3 as fallback\n");
        fd = 3;
    }

    /* Step 2: Grant root via KSU ioctl */
    write_str("  [step 2] Calling ioctl(");
    write_dec(fd);
    write_str(", 0x4B01, NULL)...\n");
    ret = sys_ioctl(fd, KSU_IOCTL_GRANT_ROOT, 0);
    write_str("  [step 2] ioctl returned ");
    write_dec(ret);
    write_str("\n");

    /* Check uid after grant */
    write_str("  After ioctl: uid=");
    write_dec(sys_getuid());
    write_str(" gid=");
    write_dec(sys_getgid());
    write_str("\n");

    /* Step 3: Try to create directories */
    write_str("  [step 3] Creating /data/adb/ksu/bin/...\n");
    ret = sys_mkdirat(AT_FDCWD, "/data/adb", 0755);
    write_str("    mkdir /data/adb: ");
    write_dec(ret);
    write_str("\n");

    ret = sys_mkdirat(AT_FDCWD, "/data/adb/ksu", 0755);
    write_str("    mkdir /data/adb/ksu: ");
    write_dec(ret);
    write_str("\n");

    ret = sys_mkdirat(AT_FDCWD, "/data/adb/ksu/bin", 0755);
    write_str("    mkdir /data/adb/ksu/bin: ");
    write_dec(ret);
    write_str("\n");

    /* Step 4: Copy ksud binary */
    write_str("  [step 4] Copying ksud...\n");
    ret = copy_file("/data/adb/ksu/bin/ksud", "/data/local/tmp/ksud");
    write_str("    copy_file: ");
    write_dec(ret);
    write_str("\n");

    /* Step 5: Try to set-manager */
    write_str("  [step 5] Executing ksud debug set-manager...\n");
    {
        char *argv[] = {"/data/adb/ksu/bin/ksud", "debug", "set-manager", NULL};
        char *envp[] = {"PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin:/data/adb/ksu/bin", NULL};
        sys_execve("/data/adb/ksu/bin/ksud", argv, envp);
    }
    write_str("  [step 5] exec failed (ksud not found or not root)\n");

    write_str("  Done. Exiting.\n");
    sys_exit(0);
}
