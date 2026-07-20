#!/usr/bin/env python3
"""
Patch file_wrapper.c (v3.3.0 KernelSU-Next) for 4.14 CAF kernel compatibility.

Adds #if version guards around struct file_operations members that were
introduced after 4.14:
  - iopoll                     (v4.16) — function + member assignment
  - remap_file_range + REMAP_FILE_DEDUP  (v4.20) — function + member
  - fadvise                    (v5.4)  — function + member
  - mmap_supported_flags       (v5.5)  — in the #else of >=6.12 block
  - alloc_file_pseudo          (v4.20) — call in pre-5.16 compat function

Usage: python3 patch_file_wrapper.py [path/to/file_wrapper.c]
"""

import sys
import os


def find_file():
    candidates = [
        "KernelSU-Next/kernel/infra/file_wrapper.c",
        "drivers/kernelsu/infra/file_wrapper.c",
        "kernel/infra/file_wrapper.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def patch_file(path):
    with open(path) as f:
        content = f.read()

    changed = False

    # ════════════════════════════════════════════════════════════════
    # 1. iopoll function — #else branch (pre-6.1)
    #    Lines 102-110: orig->f_op->iopoll() doesn't exist on 4.14
    #    Change #else to #elif >= 4.16, add plain #else returning 0
    # ════════════════════════════════════════════════════════════════
    old_iopoll_fn = (
        '#else\n'
        'static int ksu_wrapper_iopoll(struct kiocb *kiocb, bool spin)\n'
        '{\n'
        '    struct ksu_file_wrapper *data = kiocb->ki_filp->private_data;\n'
        '    struct file *orig = data->orig;\n'
        '    kiocb->ki_filp = orig;\n'
        '    return orig->f_op->iopoll(kiocb, spin);\n'
        '}\n'
        '#endif'
    )
    new_iopoll_fn = (
        '#elif LINUX_VERSION_CODE >= KERNEL_VERSION(4, 16, 0)\n'
        'static int ksu_wrapper_iopoll(struct kiocb *kiocb, bool spin)\n'
        '{\n'
        '    struct ksu_file_wrapper *data = kiocb->ki_filp->private_data;\n'
        '    struct file *orig = data->orig;\n'
        '    kiocb->ki_filp = orig;\n'
        '    return orig->f_op->iopoll(kiocb, spin);\n'
        '}\n'
        '#else\n'
        'static int ksu_wrapper_iopoll(struct kiocb *kiocb, bool spin)\n'
        '{\n'
        '    return 0;\n'
        '}\n'
        '#endif'
    )
    if old_iopoll_fn in content:
        content = content.replace(old_iopoll_fn, new_iopoll_fn, 1)
        changed = True
        print("  Patched: iopoll function -> #elif >= 4.16 / #else stub")

    # ════════════════════════════════════════════════════════════════
    # 2. iopoll member assignment (ksu_create_file_wrapper)
    #    Line 392: p->ops.iopoll = fp->f_op->iopoll ? ...
    # ════════════════════════════════════════════════════════════════
    old_iopoll_assign = (
        '    p->ops.iopoll = fp->f_op->iopoll ? ksu_wrapper_iopoll : NULL;\n'
    )
    new_iopoll_assign = (
        '#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 16, 0)\n'
        '    p->ops.iopoll = fp->f_op->iopoll ? ksu_wrapper_iopoll : NULL;\n'
        '#endif\n'
    )
    if old_iopoll_assign in content:
        content = content.replace(old_iopoll_assign, new_iopoll_assign, 1)
        changed = True
        print("  Patched: iopoll assignment -> #if >= 4.16")

    # ════════════════════════════════════════════════════════════════
    # 3. ksu_wrapper_remap_file_range function (lines 333-349)
    #    Uses REMAP_FILE_DEDUP + f_op->remap_file_range
    # ════════════════════════════════════════════════════════════════
    old_remap_fn = (
        '// https://cs.android.com/android/kernel/superproject/+'
        '/common-android-mainline:common/fs/read_write.c;l=1598-1599;'
        'drc=398da7defe218d3e51b0f3bdff75147e28125b60\n'
        '// https://cs.android.com/android/kernel/superproject/+'
        '/common-android-mainline:common/fs/remap_range.c;l=403-404;'
        'drc=398da7defe218d3e51b0f3bdff75147e28125b60\n'
        '// REMAP_FILE_DEDUP: use file_out\n'
        '// https://cs.android.com/android/kernel/superproject/+'
        '/common-android-mainline:common/fs/remap_range.c;l=483-484;'
        'drc=398da7defe218d3e51b0f3bdff75147e28125b60\n'
        'static loff_t ksu_wrapper_remap_file_range(struct file *file_in, loff_t pos_in,\n'
        '                                           struct file *file_out,\n'
        '                                           loff_t pos_out, loff_t len,\n'
        '                                           unsigned int remap_flags)\n'
        '{\n'
        '    if (remap_flags & REMAP_FILE_DEDUP) {\n'
        '        struct ksu_file_wrapper *data = file_out->private_data;\n'
        '        struct file *orig = data->orig;\n'
        '        return orig->f_op->remap_file_range(file_in, pos_in, orig, pos_out, len,\n'
        '                                            remap_flags);\n'
        '    } else {\n'
        '        struct ksu_file_wrapper *data = file_in->private_data;\n'
        '        struct file *orig = data->orig;\n'
        '        return orig->f_op->remap_file_range(orig, pos_in, file_out, pos_out,\n'
        '                                            len, remap_flags);\n'
        '    }\n'
        '}\n'
    )
    new_remap_fn = (
        '#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 20, 0)\n'
        'static loff_t ksu_wrapper_remap_file_range(struct file *file_in, loff_t pos_in,\n'
        '                                           struct file *file_out,\n'
        '                                           loff_t pos_out, loff_t len,\n'
        '                                           unsigned int remap_flags)\n'
        '{\n'
        '    if (remap_flags & REMAP_FILE_DEDUP) {\n'
        '        struct ksu_file_wrapper *data = file_out->private_data;\n'
        '        struct file *orig = data->orig;\n'
        '        return orig->f_op->remap_file_range(file_in, pos_in, orig, pos_out, len,\n'
        '                                            remap_flags);\n'
        '    } else {\n'
        '        struct ksu_file_wrapper *data = file_in->private_data;\n'
        '        struct file *orig = data->orig;\n'
        '        return orig->f_op->remap_file_range(orig, pos_in, file_out, pos_out,\n'
        '                                            len, remap_flags);\n'
        '    }\n'
        '}\n'
        '#endif\n'
    )
    if old_remap_fn in content:
        content = content.replace(old_remap_fn, new_remap_fn, 1)
        changed = True
        print("  Patched: remap_file_range function -> #if >= 4.20")

    # ════════════════════════════════════════════════════════════════
    # 4. remap_file_range member assignment (ksu_create_file_wrapper)
    #    Lines 429-430
    # ════════════════════════════════════════════════════════════════
    old_remap_assign = (
        '    p->ops.remap_file_range =\n'
        '        fp->f_op->remap_file_range ? ksu_wrapper_remap_file_range : NULL;\n'
    )
    new_remap_assign = (
        '#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 20, 0)\n'
        '    p->ops.remap_file_range =\n'
        '        fp->f_op->remap_file_range ? ksu_wrapper_remap_file_range : NULL;\n'
        '#endif\n'
    )
    if old_remap_assign in content:
        content = content.replace(old_remap_assign, new_remap_assign, 1)
        changed = True
        print("  Patched: remap_file_range assignment -> #if >= 4.20")

    # ════════════════════════════════════════════════════════════════
    # 5. ksu_wrapper_fadvise function (lines 351-360)
    # ════════════════════════════════════════════════════════════════
    old_fadvise_fn = (
        'static int ksu_wrapper_fadvise(struct file *fp, loff_t off1, loff_t off2,\n'
        '                               int flags)\n'
        '{\n'
        '    struct ksu_file_wrapper *data = fp->private_data;\n'
        '    struct file *orig = data->orig;\n'
        '    if (orig->f_op->fadvise) {\n'
        '        return orig->f_op->fadvise(orig, off1, off2, flags);\n'
        '    }\n'
        '    return -EINVAL;\n'
        '}\n'
    )
    new_fadvise_fn = (
        '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)\n'
        'static int ksu_wrapper_fadvise(struct file *fp, loff_t off1, loff_t off2,\n'
        '                               int flags)\n'
        '{\n'
        '    struct ksu_file_wrapper *data = fp->private_data;\n'
        '    struct file *orig = data->orig;\n'
        '    if (orig->f_op->fadvise) {\n'
        '        return orig->f_op->fadvise(orig, off1, off2, flags);\n'
        '    }\n'
        '    return -EINVAL;\n'
        '}\n'
        '#endif\n'
    )
    if old_fadvise_fn in content:
        content = content.replace(old_fadvise_fn, new_fadvise_fn, 1)
        changed = True
        print("  Patched: fadvise function -> #if >= 5.4")

    # ════════════════════════════════════════════════════════════════
    # 6. fadvise member assignment (ksu_create_file_wrapper)
    #    Line 431
    # ════════════════════════════════════════════════════════════════
    old_fadvise_assign = (
        '    p->ops.fadvise = fp->f_op->fadvise ? ksu_wrapper_fadvise : NULL;\n'
    )
    new_fadvise_assign = (
        '#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 4, 0)\n'
        '    p->ops.fadvise = fp->f_op->fadvise ? ksu_wrapper_fadvise : NULL;\n'
        '#endif\n'
    )
    if old_fadvise_assign in content:
        content = content.replace(old_fadvise_assign, new_fadvise_assign, 1)
        changed = True
        print("  Patched: fadvise assignment -> #if >= 5.4")

    # ════════════════════════════════════════════════════════════════
    # 7. mmap_supported_flags (lines 404-408)
    #    Current: #if >= 6.12 -> fop_flags; #else -> mmap_supported_flags
    #    Change: #if >= 6.12 -> fop_flags; #elif >= 5.5 -> mmap_supported_flags
    # ════════════════════════════════════════════════════════════════
    old_mmap_block = (
        '#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 12, 0)\n'
        '    p->ops.fop_flags = fp->f_op->fop_flags;\n'
        '#else\n'
        '    p->ops.mmap_supported_flags = fp->f_op->mmap_supported_flags;\n'
        '#endif\n'
    )
    new_mmap_block = (
        '#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 12, 0)\n'
        '    p->ops.fop_flags = fp->f_op->fop_flags;\n'
        '#elif LINUX_VERSION_CODE >= KERNEL_VERSION(5, 5, 0)\n'
        '    p->ops.mmap_supported_flags = fp->f_op->mmap_supported_flags;\n'
        '#endif\n'
    )
    if old_mmap_block in content:
        content = content.replace(old_mmap_block, new_mmap_block, 1)
        changed = True
        print("  Patched: mmap_supported_flags -> #elif >= 5.5")

    # ════════════════════════════════════════════════════════════════
    # 8. alloc_file_pseudo in pre-5.16 compat function (line 516)
    #    Called inside ksu_anon_inode_create_getfile_compat(...)
    #    alloc_file_pseudo was added in 4.20.  For < 4.20 use alloc_file().
    # ════════════════════════════════════════════════════════════════
    old_alloc_block = (
        '    file = alloc_file_pseudo(inode, anon_inode_mnt, name,\n'
        '                             flags & (O_ACCMODE | O_NONBLOCK), fops);\n'
        '    if (IS_ERR(file))\n'
        '        goto err_iput;\n'
    )
    new_alloc_block = (
        '#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 20, 0)\n'
        '    file = alloc_file_pseudo(inode, anon_inode_mnt, name,\n'
        '                             flags & (O_ACCMODE | O_NONBLOCK), fops);\n'
        '#else\n'
        '    {\n'
        '        struct path __path = {\n'
        '            .dentry = d_make_root(inode),\n'
        '            .mnt = anon_inode_mnt,\n'
        '        };\n'
        '        if (IS_ERR_OR_NULL(__path.dentry)) {\n'
        '            file = ERR_PTR(__path.dentry'
        ' ? PTR_ERR(__path.dentry) : -ENOMEM);\n'
        '            goto err;\n'
        '        }\n'
        '        file = alloc_file(&__path,'
        ' flags & (O_ACCMODE | O_NONBLOCK), fops);\n'
        '        if (IS_ERR(file)) {\n'
        '            dput(__path.dentry);\n'
        '            goto err;\n'
        '        }\n'
        '    }\n'
        '#endif\n'
        '    if (IS_ERR(file))\n'
        '        goto err_iput;\n'
    )
    if old_alloc_block in content:
        content = content.replace(old_alloc_block, new_alloc_block, 1)
        changed = True
        print("  Patched: alloc_file_pseudo -> #if >= 4.20 / #else alloc_file via d_make_root")

    if not changed:
        print("  No patterns matched — file may already be patched or structure differs.")
        return False

    with open(path, 'w') as f:
        f.write(content)
    print(f"OK: patched {path}")
    return True


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = find_file()

    if not path or not os.path.exists(path):
        print(f"ERROR: file_wrapper.c not found at {path or '(none given)'}")
        sys.exit(1)

    if not patch_file(path):
        sys.exit(1)


if __name__ == "__main__":
    main()
