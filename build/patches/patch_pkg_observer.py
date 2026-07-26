#!/usr/bin/env python3
"""
Replace pkg_observer.c (v3.3.0 KernelSU-Next) with a version that compiles
on 4.14 CAF kernels using the pre-5.5 fsnotify API.

On 4.14 CAF:
  - handle_event has 2x fsnotify_mark params (inode_mark + vfsmount_mark)
  - fsnotify_init_mark takes group as 2nd arg (not free_fn)
  - fsnotify_add_mark takes (mark, inode, allow_dups) [not **markp, no vfsmount]
"""

import sys
import os


# ── 4.14-compatible replacement content ──────────────────────────────
PKG_OBSERVER_4_14 = '''\
#include <linux/fsnotify_backend.h>
#include <linux/fs.h>
#include <linux/namei.h>
#include <linux/slab.h>
#include <linux/rculist.h>
#include <linux/version.h>

#include "klog.h"
#include "manager/throne_tracker.h"

#define MASK_SYSTEM (FS_CREATE | FS_MOVE | FS_EVENT_ON_CHILD)

struct watch_dir {
    const char *path;
    u32 mask;
    struct path kpath;
    struct inode *inode;
    struct fsnotify_mark *mark;
};

static struct fsnotify_group *g;

/* 4.14 CAF handle_event callback signature:
 *   int (*)(struct fsnotify_group *, struct inode *,
 *           struct fsnotify_mark *, struct fsnotify_mark *,
 *           u32, const void *, int, const unsigned char *,
 *           u32, struct fsnotify_iter_info *)
 * file_name is param 8, the SECOND mark is ignored (it's the vfsmount mark).
 */
static int ksu_handle_event(struct fsnotify_group *group, struct inode *inode,
                            struct fsnotify_mark *inode_mark,
                            struct fsnotify_mark *vfsmount_mark,
                            u32 mask, const void *data, int data_type,
                            const unsigned char *file_name,
                            u32 cookie,
                            struct fsnotify_iter_info *iter_info)
{
    if (!file_name)
        return 0;
    if (mask & FS_ISDIR)
        return 0;
    if (memcmp(file_name, "packages.list", 13) == 0) {
        pr_info("packages.list detected: %d\\n", mask);
        track_throne(false);
    }
    return 0;
}

static const struct fsnotify_ops ksu_ops = {
    .handle_event = ksu_handle_event,
};

static int add_mark_on_inode(struct inode *inode, u32 mask,
                             struct fsnotify_mark **out)
{
    struct fsnotify_mark *m;

    m = kzalloc(sizeof(*m), GFP_KERNEL);
    if (!m)
        return -ENOMEM;

    fsnotify_init_mark(m, g);
    m->mask = mask;

    /* CAF 4.14: fsnotify_add_mark(mark, inode, allow_dups) — no group, no mnt */
    if (fsnotify_add_mark(m, inode, NULL, 0)) {
        fsnotify_put_mark(m);
        return -EINVAL;
    }
    *out = m;
    return 0;
}

static int watch_one_dir(struct watch_dir *wd)
{
    struct inode *inode;
    int ret;

    ret = kern_path(wd->path, 0, &wd->kpath);
    if (ret) {
        pr_err("watch: kern_path(%s) failed: %d\\n", wd->path, ret);
        return ret;
    }

    inode = wd->kpath.dentry->d_inode;
    if (!inode) {
        path_put(&wd->kpath);
        return -ENOENT;
    }

    ihold(inode);
    wd->inode = inode;

    ret = add_mark_on_inode(inode, wd->mask, &wd->mark);
    if (ret) {
        iput(inode);
        path_put(&wd->kpath);
        return ret;
    }

    pr_info("watch: now watching %s\\n", wd->path);
    return 0;
}

static void unwatch_one_dir(struct watch_dir *wd)
{
    if (wd->mark) {
        fsnotify_destroy_mark(wd->mark, g);
        fsnotify_put_mark(wd->mark);
        wd->mark = NULL;
    }
    if (wd->inode) {
        iput(wd->inode);
        wd->inode = NULL;
    }
    if (wd->kpath.dentry) {
        path_put(&wd->kpath);
        wd->kpath.dentry = NULL;
    }
}

static struct watch_dir g_watch = {
    .path = "/data/system",
    .mask = MASK_SYSTEM,
};

int ksu_observer_init(void)
{
    int ret = 0;

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 0, 0)
    g = fsnotify_alloc_group(&ksu_ops, 0);
#else
    g = fsnotify_alloc_group(&ksu_ops);
#endif
    if (IS_ERR(g))
        return PTR_ERR(g);

    ret = watch_one_dir(&g_watch);
    pr_info("observer init done\\n");
    return 0;
}

void ksu_observer_exit(void)
{
    unwatch_one_dir(&g_watch);
    if (g) {
        fsnotify_put_group(g);
        g = NULL;
    }
    pr_info("observer exit done\\n");
}
'''


def find_file():
    candidates = [
        "KernelSU-Next/kernel/manager/pkg_observer.c",
        "drivers/kernelsu/manager/pkg_observer.c",
        "kernel/manager/pkg_observer.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def patch_file(path):
    print(f"  Replacing {path} with 4.14-compatible fsnotify implementation")
    with open(path, 'w') as f:
        f.write(PKG_OBSERVER_4_14)
    print("OK: pkg_observer.c replaced with 4.14-compatible version")
    return True


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = find_file()

    if not path or not os.path.exists(path):
        print(f"ERROR: pkg_observer.c not found at {path or '(none given)'}")
        sys.exit(1)

    if not patch_file(path):
        sys.exit(1)


if __name__ == "__main__":
    main()
