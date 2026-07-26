#!/usr/bin/env python3
"""
patch_ksud_activation.py — Wire KSU-Next's init.rc RC-injection hooks into the
host fs/ syscalls for MANUAL_HOOK mode (no kprobes, no bootloop on CAF 4.14).

ROOT CAUSE (verified in KernelSU-Next/kernel/runtime/ksud_integration.c):
  KSU-Next activates installed modules by appending KERNEL_SU_RC[] to init's
  init.rc read. That RC (ksud_integration.c:43-64) contains:
      on post-fs-data
          exec u:r:ksu:s0 root -- /data/adb/ksud post-fs-data
  which runs `ksud post-fs-data` (moves /data/adb/modules_update/* ->
  /data/adb/modules/* and activates them). The interception works by:
    (1) read hook  -> ksu_apply_init_rc_proxy() swaps f_op so reads of
                       init.rc append KERNEL_SU_RC past EOF;
    (2) fstat hook  -> bumps the reported st_size by ksu_rc_len so init reads
                       past EOF and actually sees the appended RC.
  Both are REQUIRED: without (2), init sizes init.rc by the original length and
  never reads the appended RC -> ksud post-fs-data never runs -> modules stay in
  "requires reboot" forever.

  Under CONFIG_KSU_MANUAL_HOOK=y, ksu_ksud_init() (ksud_integration.c:885-899)
  registers these hooks ONLY under KSU_KPROBES_HOOK. The manual stubs
  (ksu_handle_sys_read @467, ksu_handle_vfs_read @746, ksu_handle_newfstat_ret
  @817, ksu_handle_fstat64_ret @826) exist but have ZERO callers, so the
  intercept is dead code. Root still works because app-root goes through the
  separately-wired execve hook (patch_fs_exec.py -> ksu_handle_execveat).

FIX (mirror patch_fs_exec.py: extern decl + IS_ENABLED guard, NO kprobes):
  Insert plain-C calls at the syscall entry points the kprobes pre-handlers
  already target:
    - fs/read_write.c  SYSCALL_DEFINE3(read, ...)     -> ksu_handle_sys_read(fd)
      (kprobe pre-handler sys_read_kp calls ksu_handle_sys_read at entry; applies
       f_op proxy BEFORE init reads init.rc)
    - fs/stat.c       SYSCALL_DEFINE2(newfstat, ...)  -> ksu_handle_newfstat_ret(&fd,&statbuf)
      (matches SYS_FSTAT_SYMBOL = "__arm64_sys_newfstat" on arm64)
    - fs/stat.c       SYSCALL_DEFINE4(newfstatat, ...) -> ksu_handle_newfstat_ret(...)
      (safety net: bionic fstat may resolve to newfstatat(AT_EMPTY_PATH) on arm64)

  ksu_vfs_read_hook defaults true (ksud_integration.c:76) so the fstat stub
  fires. ksu_apply_init_rc_proxy self-guards (static rc_hooked + stop_init_rc_hook)
  so the mechanism is a no-op after the first init.rc access.

BOOTLOOP SAFETY (LOW risk): after the f_op swap, subsequent vfs_read on the
  proxied file routes to read_proxy (not vfs_read), so the read hook never
  re-enters for init.rc; is_init_rc early-outs for non-init; d_path uses a
  seqlock. The manual fstat hook runs at syscall return in process context.

SELinux: no change needed. The ksu domain is already functional (root works =>
  apply_kernelsu_rules()+cache_sid() ran; rules.c grants init all perms on ksu;
  RC uses explicit u:r:ksu:s0 exec context).

Usage:
  python3 patch_ksud_activation.py [path/to/source/tree]
"""

import os
import sys

PATCH_MARKER = "ksu_handle_sys_read"      # read-half idempotency marker
STAT_MARKER = "ksu_handle_newfstat_ret"   # stat-half idempotency marker

READ_C = "fs/read_write.c"
STAT_C = "fs/stat.c"

# --- insertion blocks (tab-indented, matching kernel style) ---

# Inserted inside SYSCALL_DEFINE3(read, ...), after `loff_t pos = ...`, before
# the vfs_read call. `fd` (unsigned int) is in scope.
INSERT_READ = (
    "\t\t#if IS_ENABLED(CONFIG_KSU)\n"
    "\t\t{\n"
    "\t\t\textern void ksu_handle_sys_read(unsigned int fd);\n"
    "\t\t\tksu_handle_sys_read(fd);\n"
    "\t\t}\n"
    "\t\t#endif\n"
)

# Replaces the `if (!error) { error = cp_new_stat(...); }` two-liner in
# SYSCALL_DEFINE2(newfstat, ...) with a braced block that also calls
# ksu_handle_newfstat_ret on the success path. `fd` (unsigned int) and
# `statbuf` (struct stat __user *) are in scope.
NEWFSTAT_ANCHOR = (
    "\tif (!error)\n"
    "\t\terror = cp_new_stat(&stat, statbuf);\n"
)
INSERT_FSTAT = (
    "\tif (!error) {\n"
    "\t\terror = cp_new_stat(&stat, statbuf);\n"
    "\t#if IS_ENABLED(CONFIG_KSU)\n"
    "\t\t{\n"
    "\t\t\textern void ksu_handle_newfstat_ret(unsigned int *fd, "
    "struct stat __user **statbuf_ptr);\n"
    "\t\t\tksu_handle_newfstat_ret(&fd, &statbuf);\n"
    "\t\t}\n"
    "\t#endif\n"
    "\t}\n"
)

# Inserted inside SYSCALL_DEFINE4(newfstatat, ...), before the
# `return cp_new_stat(&stat, statbuf);` line. `dfd` (int) is the dir/fd; with
# AT_EMPTY_PATH it IS the fd of init.rc. `statbuf` is in scope.
INSERT_FSTATAT = (
    "\t#if IS_ENABLED(CONFIG_KSU)\n"
    "\t{\n"
    "\t\textern void ksu_handle_newfstat_ret(unsigned int *fd, "
    "struct stat __user **statbuf_ptr);\n"
    "\t\tunsigned int ksu_fd = (unsigned int)dfd;\n"
    "\t\tksu_handle_newfstat_ret(&ksu_fd, &statbuf);\n"
    "\t}\n"
    "\t#endif\n"
)


def find_file(rel, root="."):
    """Resolve a source path that may live under several tree layouts.

    `rel` is like 'fs/read_write.c'. When `root` is provided we try
    root/rel plus common sub-tree prefixes; otherwise bare rel/prefixes.
    """
    prefix = "" if root in (".", "") else root.rstrip("/") + "/"
    candidates = [
        prefix + rel,
        prefix + os.path.join("KernelSU-Next", rel),
        prefix + os.path.join("kernel", rel),
        prefix + os.path.join("drivers", "kernelsu", rel),
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def insert_in_func(content, sig_anchor, inner_anchor, block,
                  after=True, scope=900):
    """Find sig_anchor; within `scope` bytes after it find inner_anchor; insert
    `block` after (after=True) or before (after=False) inner_anchor's line."""
    sidx = content.find(sig_anchor)
    if sidx < 0:
        return None, "signature not found: %r" % sig_anchor
    window = content[sidx:sidx + scope]
    iidx = window.find(inner_anchor)
    if iidx < 0:
        return None, ("inner anchor %r not found within %d bytes of "
                      "signature" % (inner_anchor, scope))
    pos = sidx + iidx
    if after:
        eol = content.find("\n", pos)
        insert_pos = eol + 1
    else:
        sol = content.rfind("\n", sidx, pos) + 1
        insert_pos = sol
    return content[:insert_pos] + block + content[insert_pos:], None


def patch_read(path):
    with open(path) as f:
        content = f.read()
    if PATCH_MARKER in content:
        print("  already patched: read hook present in %s" % path)
        return True
    new, err = insert_in_func(
        content,
        "SYSCALL_DEFINE3(read, unsigned int, fd,",
        "loff_t pos = file_pos_read(f.file);",
        INSERT_READ,
        after=True,
    )
    if err:
        print("ERROR: %s (in %s)" % (err, path))
        return False
    with open(path, "w") as f:
        f.write(new)
    print("  fs/read_write.c: read RC-inject hook inserted")
    return PATCH_MARKER in new


def patch_stat(path):
    with open(path) as f:
        content = f.read()
    if STAT_MARKER in content:
        print("  already patched: fstat hooks present in %s" % path)
        return True

    # (1) newfstat: replace `if (!error) error = cp_new_stat(...);` with a
    #     braced block that also calls ksu_handle_newfstat_ret on success.
    sidx = content.find("SYSCALL_DEFINE2(newfstat, unsigned int, fd,")
    if sidx < 0:
        print("ERROR: newfstat signature not found in %s" % path)
        return False
    window = content[sidx:sidx + 600]
    aidx = window.find(NEWFSTAT_ANCHOR)
    if aidx < 0:
        print("ERROR: newfstat anchor not found in %s" % path)
        return False
    pos = sidx + aidx
    new = content[:pos] + INSERT_FSTAT + content[pos + len(NEWFSTAT_ANCHOR):]
    if STAT_MARKER not in new:
        print("ERROR: newfstat hook not present after insertion in %s" % path)
        return False

    # (2) newfstatat: before `return cp_new_stat(&stat, statbuf);`
    new2, err = insert_in_func(
        new,
        "SYSCALL_DEFINE4(newfstatat,",
        "return cp_new_stat(&stat, statbuf);",
        INSERT_FSTATAT,
        after=False,
    )
    if err:
        print("ERROR: %s (in %s)" % (err, path))
        return False

    with open(path, "w") as f:
        f.write(new2)
    print("  fs/stat.c: newfstat + newfstatat RC-inject hooks inserted")
    return STAT_MARKER in new2


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    read_path = find_file(READ_C, root)
    stat_path = find_file(STAT_C, root)

    if not read_path:
        print("ERROR: %s not found (tried prefixes under %r)" % (READ_C, root))
        sys.exit(1)
    if not stat_path:
        print("ERROR: %s not found (tried prefixes under %r)" % (STAT_C, root))
        sys.exit(1)

    ok = True
    ok = patch_read(read_path) and ok
    ok = patch_stat(stat_path) and ok

    if not ok:
        sys.exit(1)
    print("OK: KSUN init.rc RC-injection hooks wired (MANUAL_HOOK)")


if __name__ == "__main__":
    main()
