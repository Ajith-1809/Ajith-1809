#!/usr/bin/env python3
"""
Replace selinux/rules.c (KSUN v3.3.0) for 4.14 CAF kernel compat.

v3.3.0 uses kernel 5.5+ SELinux APIs (selinux_state.policy, policy_mutex).
On CAF 4.14, the SELinux policy lives in selinux_state.ss->policydb.

We provide both <5.10 and >=5.10 paths in the same file, preserving
all sepol batch dispatch logic from v3.3.0.
"""

import sys
import os


RULES_4_14 = '''\
#include "linux/rcupdate.h"
#include "security.h"
#include <linux/uaccess.h>
#include <linux/types.h>
#include <linux/version.h>
#include <linux/lockdep.h>
#include <linux/slab.h>
#include <linux/string.h>
#include <linux/stop_machine.h>
#include <linux/sched.h>

#include "uapi/selinux.h"
#include "klog.h"
#include "selinux.h"
#include "sepolicy.h"
#include "ss/services.h"
#include "linux/lsm_audit.h"
#include "xfrm.h"

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)
#define SELINUX_POLICY_INSTEAD_SELINUX_SS
#endif

/*
 * On kernels >= 5.10, access via selinux_state.policy.
 * On < 5.10 (incl. CAF 4.14), access via selinux_state.ss.
 */
#ifdef SELINUX_POLICY_INSTEAD_SELINUX_SS
struct selinux_policy *backup_sepolicy;
#endif

#define ALL NULL

/* Module-level mutex for < 5.10 path; on 5.10+ selinux_state.policy_mutex is used */
static DEFINE_MUTEX(ksu_policy_lock);

/* sepol command codes — must match userspace */
#define KSU_SEPOLICY_CMD_NORMAL_PERM    0
#define KSU_SEPOLICY_CMD_XPERM          1
#define KSU_SEPOLICY_CMD_TYPE_STATE     2
#define KSU_SEPOLICY_CMD_TYPE           3
#define KSU_SEPOLICY_CMD_ATTR           4
#define KSU_SEPOLICY_CMD_TYPE_ATTR      5
#define KSU_SEPOLICY_CMD_TYPE_TRANSITION 6
#define KSU_SEPOLICY_CMD_TYPE_CHANGE    7
#define KSU_SEPOLICY_CMD_GENFSCON       8

#define KSU_SEPOLICY_SUBCMD_NORMAL_PERM_ALLOW       0
#define KSU_SEPOLICY_SUBCMD_NORMAL_PERM_DENY        1
#define KSU_SEPOLICY_SUBCMD_NORMAL_PERM_AUDITALLOW  2
#define KSU_SEPOLICY_SUBCMD_NORMAL_PERM_DONTAUDIT   3
#define KSU_SEPOLICY_SUBCMD_XPERM_ALLOW             0
#define KSU_SEPOLICY_SUBCMD_XPERM_AUDITALLOW        1
#define KSU_SEPOLICY_SUBCMD_XPERM_DONTAUDIT         2
#define KSU_SEPOLICY_SUBCMD_TYPE_STATE_PERMISSIVE    0
#define KSU_SEPOLICY_SUBCMD_TYPE_STATE_ENFORCE       1
#define KSU_SEPOLICY_SUBCMD_TYPE_CHANGE_CHANGE       0
#define KSU_SEPOLICY_SUBCMD_TYPE_CHANGE_MEMBER       1

/*
 * Resolve the active policydb pointer.
 */
static struct policydb *get_policydb(void)
{
#ifdef SELINUX_POLICY_INSTEAD_SELINUX_SS
    return &selinux_state.policy->policydb;
#else
    return &selinux_state.ss->policydb;
#endif
}

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
extern int avc_ss_reset(u32 seqno);
#else
extern int avc_ss_reset(struct selinux_avc *avc, u32 seqno);
#endif

static void reset_avc_cache(void)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
    avc_ss_reset(0);
    selnl_notify_policyload(0);
    selinux_status_update_policyload(0);
#else
    struct selinux_avc *avc = selinux_state.avc;
    avc_ss_reset(avc, 0);
    selnl_notify_policyload(0);
    selinux_status_update_policyload(&selinux_state, 0);
#endif
    selinux_xfrm_notify_policyload();
}

static int apply_kernelsu_rules_fn(void *ptr)
{
    struct policydb *db = (struct policydb *)ptr;

    ksu_type(db, KERNEL_SU_DOMAIN, "domain");
    ksu_permissive(db, KERNEL_SU_DOMAIN);
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "mlstrustedsubject");
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "netdomain");
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "bluetoothdomain");

    ksu_type(db, KERNEL_SU_FILE, "file_type");
    ksu_typeattribute(db, KERNEL_SU_FILE, "mlstrustedobject");
    ksu_allow(db, "domain", KERNEL_SU_FILE, ALL, ALL);

    ksu_allow(db, KERNEL_SU_DOMAIN, ALL, ALL, ALL);

    if (db->policyvers >= POLICYDB_VERSION_XPERMS_IOCTL) {
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "blk_file", ALL);
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "fifo_file", ALL);
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "chr_file", ALL);
        ksu_allowxperm(db, KERNEL_SU_DOMAIN, ALL, "file", ALL);
    }

    ksu_allow(db, "init", KERNEL_SU_DOMAIN, ALL, ALL);

    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "dir", "search");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "dir", "read");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "file", "open");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "file", "read");
    ksu_allow(db, "servicemanager", KERNEL_SU_DOMAIN, "process", "getattr");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "process", "sigchld");

    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "dir", "search");
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "file", "read");
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "file", "open");
    ksu_allow(db, "logd", KERNEL_SU_DOMAIN, "file", "getattr");

    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fd", "use");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "write");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "read");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "open");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "fifo_file", "getattr");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "unix_stream_socket", "read");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "unix_stream_socket", "write");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "unix_stream_socket", "connectto");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "unix_stream_socket", "getopt");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "unix_stream_socket", "getattr");

    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "memfd_file", "execute");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "memfd_file", "getattr");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "memfd_file", "map");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "memfd_file", "read");
    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "memfd_file", "write");

    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "dir", "search");
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "file", "read");
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "file", "open");
    ksu_allow(db, "hwservicemanager", KERNEL_SU_DOMAIN, "process", "getattr");

    ksu_allow(db, "domain", KERNEL_SU_DOMAIN, "binder", ALL);

    ksu_allow(db, "system_server", KERNEL_SU_DOMAIN, "process", "getpgid");
    ksu_allow(db, "system_server", KERNEL_SU_DOMAIN, "process", "sigkill");

    return 0;
}

void apply_kernelsu_rules(void)
{
    struct policydb *db;

    if (!getenforce()) {
        pr_info("SELinux permissive or disabled, apply rules!\\n");
    }

#ifdef SELINUX_POLICY_INSTEAD_SELINUX_SS
    /*
     * >= 5.10: duplicate, modify, RCU-swap
     */
    struct selinux_policy *pol, *old_pol = selinux_state.policy;
    mutex_lock(&selinux_state.policy_mutex);

    backup_sepolicy =
        ksu_dup_sepolicy(rcu_dereference_protected(
            old_pol, lockdep_is_held(&selinux_state.policy_mutex)));
    if (IS_ERR(backup_sepolicy)) {
        pr_err("failed to create backup sepolicy: %ld\\n", PTR_ERR(backup_sepolicy));
        backup_sepolicy = NULL;
    } else {
        backup_sepolicy->sidtab = kzalloc(sizeof(*backup_sepolicy->sidtab), GFP_KERNEL);
        if (!backup_sepolicy->sidtab) {
            pr_err("failed to alloc backup sidtab\\n");
            ksu_destroy_sepolicy(backup_sepolicy);
            backup_sepolicy = NULL;
        } else {
            int ret = policydb_load_isids(&backup_sepolicy->policydb,
                                          backup_sepolicy->sidtab);
            if (ret) {
                pr_err("failed to load isids: %d!\\n", ret);
                kfree(backup_sepolicy->sidtab);
                ksu_destroy_sepolicy(backup_sepolicy);
                backup_sepolicy = NULL;
            } else {
                pr_info("backup sepolicy success! latest_granting=%d\\n",
                        backup_sepolicy->latest_granting);
            }
        }
    }

    pol = ksu_dup_sepolicy(rcu_dereference_protected(
        old_pol, lockdep_is_held(&selinux_state.policy_mutex)));
    if (IS_ERR(pol)) {
        pr_err("failed to dup selinux_policy: %ld\\n", PTR_ERR(pol));
        goto out_unlock;
    }
    db = &pol->policydb;

    apply_kernelsu_rules_fn((void *)db);

    rcu_assign_pointer(selinux_state.policy, pol);
    synchronize_rcu();
    ksu_destroy_sepolicy(old_pol);
    reset_avc_cache();
out_unlock:
    mutex_unlock(&selinux_state.policy_mutex);
#else
    /*
     * < 5.10 (incl. CAF 4.14): modify policydb in-place
     */
    mutex_lock(&ksu_policy_lock);
    db = get_policydb();
    if (!db) {
        pr_err("failed to get policydb\\n");
        mutex_unlock(&ksu_policy_lock);
        return;
    }
    apply_kernelsu_rules_fn((void *)db);
    reset_avc_cache();
    mutex_unlock(&ksu_policy_lock);
#endif
}

/* ===========================================================
 * sepol batch dispatch (unchanged from v3.3.0)
 * =========================================================== */
#define KSU_SEPOLICY_MAX_BATCH_SIZE (8U * 1024U * 1024U)
#define KSU_SEPOLICY_MAX_ARGS 5

struct sepol_data {
    u32 cmd;
    u32 subcmd;
};

struct sepol_batch_cursor {
    const u8 *cur;
    const u8 *end;
};

static size_t sepol_remaining(const struct sepol_batch_cursor *cursor)
{
    return (size_t)(cursor->end - cursor->cur);
}

static int sepol_read_cmd_header(struct sepol_batch_cursor *cursor,
                                 struct sepol_data *header)
{
    if (sepol_remaining(cursor) < sizeof(*header))
        return -EINVAL;
    memcpy(header, cursor->cur, sizeof(*header));
    cursor->cur += sizeof(*header);
    return 0;
}

static int sepol_read_string(struct sepol_batch_cursor *cursor,
                             const char **out)
{
    u32 len;
    const char *str;
    if (sepol_remaining(cursor) < sizeof(len))
        return -EINVAL;
    memcpy(&len, cursor->cur, sizeof(len));
    cursor->cur += sizeof(len);
    if (len >= sepol_remaining(cursor))
        return -EINVAL;
    str = (const char *)cursor->cur;
    if (memchr(str, 0, len) != NULL || str[len] != 0)
        return -EINVAL;
    cursor->cur += len + 1;
    *out = (len == 0) ? ALL : str;
    return 0;
}

static int sepol_require_not_all(const char *value, const char *name)
{
    if (value != ALL) return 0;
    pr_err("sepol: %s cannot be ALL.\\n", name);
    return -EINVAL;
}

static int sepol_expected_argc(u32 cmd)
{
    switch (cmd) {
    case KSU_SEPOLICY_CMD_NORMAL_PERM:   return 4;
    case KSU_SEPOLICY_CMD_XPERM:         return 5;
    case KSU_SEPOLICY_CMD_TYPE_STATE:    return 1;
    case KSU_SEPOLICY_CMD_TYPE:
    case KSU_SEPOLICY_CMD_TYPE_ATTR:     return 2;
    case KSU_SEPOLICY_CMD_ATTR:          return 1;
    case KSU_SEPOLICY_CMD_TYPE_TRANSITION: return 5;
    case KSU_SEPOLICY_CMD_TYPE_CHANGE:   return 4;
    case KSU_SEPOLICY_CMD_GENFSCON:      return 3;
    default: return -EINVAL;
    }
}

static int apply_one_sepolicy_cmd(struct policydb *db,
                                  const struct sepol_data *header,
                                  const char **args)
{
    bool success = false;
    int ret;

    switch (header->cmd) {
    case KSU_SEPOLICY_CMD_NORMAL_PERM:
        if (header->subcmd == KSU_SEPOLICY_SUBCMD_NORMAL_PERM_ALLOW)
            success = ksu_allow(db, args[0], args[1], args[2], args[3]);
        else if (header->subcmd == KSU_SEPOLICY_SUBCMD_NORMAL_PERM_DENY)
            success = ksu_deny(db, args[0], args[1], args[2], args[3]);
        else if (header->subcmd == KSU_SEPOLICY_SUBCMD_NORMAL_PERM_AUDITALLOW)
            success = ksu_auditallow(db, args[0], args[1], args[2], args[3]);
        else if (header->subcmd == KSU_SEPOLICY_SUBCMD_NORMAL_PERM_DONTAUDIT)
            success = ksu_dontaudit(db, args[0], args[1], args[2], args[3]);
        else
            pr_err("sepol: unknown subcmd: %d\\n", header->subcmd);
        return success ? 0 : -EINVAL;

    case KSU_SEPOLICY_CMD_XPERM:
        ret = sepol_require_not_all(args[3], "operation");
        if (ret < 0) return ret;
        ret = sepol_require_not_all(args[4], "perm_set");
        if (ret < 0) return ret;
        if (header->subcmd == KSU_SEPOLICY_SUBCMD_XPERM_ALLOW)
            success = ksu_allowxperm(db, args[0], args[1], args[2], args[4]);
        else if (header->subcmd == KSU_SEPOLICY_SUBCMD_XPERM_AUDITALLOW)
            success = ksu_auditallowxperm(db, args[0], args[1], args[2], args[4]);
        else if (header->subcmd == KSU_SEPOLICY_SUBCMD_XPERM_DONTAUDIT)
            success = ksu_dontauditxperm(db, args[0], args[1], args[2], args[4]);
        else
            pr_err("sepol: unknown subcmd: %d\\n", header->subcmd);
        return success ? 0 : -EINVAL;

    case KSU_SEPOLICY_CMD_TYPE_STATE:
        ret = sepol_require_not_all(args[0], "type");
        if (ret < 0) return ret;
        if (header->subcmd == KSU_SEPOLICY_SUBCMD_TYPE_STATE_PERMISSIVE)
            success = ksu_permissive(db, args[0]);
        else if (header->subcmd == KSU_SEPOLICY_SUBCMD_TYPE_STATE_ENFORCE)
            success = ksu_enforce(db, args[0]);
        else
            pr_err("sepol: unknown subcmd: %d\\n", header->subcmd);
        return success ? 0 : -EINVAL;

    case KSU_SEPOLICY_CMD_TYPE:
    case KSU_SEPOLICY_CMD_TYPE_ATTR:
        ret = sepol_require_not_all(args[0], "type");
        if (ret < 0) return ret;
        ret = sepol_require_not_all(args[1], "attribute");
        if (ret < 0) return ret;
        if (header->cmd == KSU_SEPOLICY_CMD_TYPE)
            success = ksu_type(db, args[0], args[1]);
        else
            success = ksu_typeattribute(db, args[0], args[1]);
        return success ? 0 : -EINVAL;

    case KSU_SEPOLICY_CMD_ATTR:
        ret = sepol_require_not_all(args[0], "attribute");
        if (ret < 0) return ret;
        if (header->subcmd == 0)
            success = ksu_typeattribute(db, args[0], args[0]);
        else
            pr_err("sepol: unknown subcmd: %d\\n", header->subcmd);
        return success ? 0 : -EINVAL;

    case KSU_SEPOLICY_CMD_TYPE_TRANSITION: {
        const char *object = ALL;
        ret = sepol_require_not_all(args[0], "src");
        if (ret < 0) return ret;
        ret = sepol_require_not_all(args[1], "tgt");
        if (ret < 0) return ret;
        ret = sepol_require_not_all(args[2], "cls");
        if (ret < 0) return ret;
        ret = sepol_require_not_all(args[3], "default_type");
        if (ret < 0) return ret;
        object = args[4];
        success = ksu_type_transition(db, args[0], args[1], args[2], args[3], object);
        return success ? 0 : -EINVAL;
    }

    case KSU_SEPOLICY_CMD_TYPE_CHANGE:
        ret = sepol_require_not_all(args[0], "src");
        if (ret < 0) return ret;
        ret = sepol_require_not_all(args[1], "tgt");
        if (ret < 0) return ret;
        ret = sepol_require_not_all(args[2], "cls");
        if (ret < 0) return ret;
        ret = sepol_require_not_all(args[3], "default_type");
        if (ret < 0) return ret;
        if (header->subcmd == KSU_SEPOLICY_SUBCMD_TYPE_CHANGE_CHANGE)
            success = ksu_type_change(db, args[0], args[1], args[2], args[3]);
        else if (header->subcmd == KSU_SEPOLICY_SUBCMD_TYPE_CHANGE_MEMBER)
            success = ksu_type_member(db, args[0], args[1], args[2], args[3]);
        else
            pr_err("sepol: unknown subcmd: %d\\n", header->subcmd);
        return success ? 0 : -EINVAL;

    case KSU_SEPOLICY_CMD_GENFSCON:
        ret = sepol_require_not_all(args[0], "name");
        if (ret < 0) return ret;
        ret = sepol_require_not_all(args[1], "path");
        if (ret < 0) return ret;
        ret = sepol_require_not_all(args[2], "context");
        if (ret < 0) return ret;
        if (!ksu_genfscon(db, args[0], args[1], args[2])) {
            pr_err("sepol: genfscon failed.\\n");
            return -EINVAL;
        }
        return 0;

    default:
        pr_err("sepol: unknown cmd: %d\\n", header->cmd);
        return -EINVAL;
    }
}

int handle_sepolicy(void __user *user_data, u64 data_len)
{
    struct policydb *db;
    struct sepol_batch_cursor cursor;
    u8 *payload;
    int ret;
    int success_cmd_count;
    u32 cmd_index;

    if (!user_data || !data_len)
        return -EINVAL;
    if (data_len > KSU_SEPOLICY_MAX_BATCH_SIZE)
        return -E2BIG;

    payload = kvmalloc((size_t)data_len, GFP_KERNEL);
    if (!payload)
        return -ENOMEM;

    if (copy_from_user(payload, user_data, (size_t)data_len)) {
        ret = -EFAULT;
        goto out_free;
    }

    if (!getenforce())
        pr_info("SELinux permissive or disabled when handle policy!\\n");

#ifdef SELINUX_POLICY_INSTEAD_SELINUX_SS
    {
        struct selinux_policy *pol, *old_pol;
        mutex_lock(&selinux_state.policy_mutex);
        old_pol = selinux_state.policy;
        pol = ksu_dup_sepolicy(rcu_dereference_protected(
            old_pol, lockdep_is_held(&selinux_state.policy_mutex)));
        if (IS_ERR(pol)) {
            ret = PTR_ERR(pol);
            pr_err("ksu_dup_sepolicy err: %d\\n", ret);
            goto out_unlock;
        }
        db = &pol->policydb;

        /* process batch */
        cursor.cur = payload;
        cursor.end = payload + (size_t)data_len;
        ret = 0; success_cmd_count = 0; cmd_index = 0;
        while (cursor.cur < cursor.end) {
            struct sepol_data header;
            const char *args[KSU_SEPOLICY_MAX_ARGS] = { 0 };
            int expected_argc;
            u32 arg_index;

            ret = sepol_read_cmd_header(&cursor, &header);
            if (ret < 0) { pr_err("sepol: failed cmd #%u.\\n", cmd_index); goto out_drop_new; }

            expected_argc = sepol_expected_argc(header.cmd);
            if (expected_argc < 0) { ret = -EINVAL; goto out_drop_new; }

            for (arg_index = 0; arg_index < (u32)expected_argc; arg_index++) {
                ret = sepol_read_string(&cursor, &args[arg_index]);
                if (ret < 0) { pr_err("sepol: failed cmd #%u arg #%u.\\n", cmd_index, arg_index); goto out_drop_new; }
            }

            ret = apply_one_sepolicy_cmd(db, &header, args);
            if (ret < 0) { pr_err("sepol: cmd #%u failed.\\n", cmd_index); goto out_drop_new; }
            success_cmd_count++;
            cmd_index++;
        }

        /* swap */
        rcu_assign_pointer(selinux_state.policy, pol);
        synchronize_rcu();
        ksu_destroy_sepolicy(old_pol);
        reset_avc_cache();
        pr_info("sepol: applied %d cmds\\n", success_cmd_count);
        ret = 0;

    out_drop_new:
        if (ret && pol) ksu_destroy_sepolicy(pol);
    out_unlock:
        mutex_unlock(&selinux_state.policy_mutex);
    }
#else
    /* < 5.10 path: modify in-place */
    mutex_lock(&ksu_policy_lock);
    db = get_policydb();
    if (!db) {
        pr_err("failed to get policydb\\n");
        mutex_unlock(&ksu_policy_lock);
        kvfree(payload);
        return -EINVAL;
    }

    cursor.cur = payload;
    cursor.end = payload + (size_t)data_len;
    ret = 0; success_cmd_count = 0; cmd_index = 0;
    while (cursor.cur < cursor.end) {
        struct sepol_data header;
        const char *args[KSU_SEPOLICY_MAX_ARGS] = { 0 };
        int expected_argc;
        u32 arg_index;

        ret = sepol_read_cmd_header(&cursor, &header);
        if (ret < 0) { pr_err("sepol: failed cmd #%u.\\n", cmd_index); break; }

        expected_argc = sepol_expected_argc(header.cmd);
        if (expected_argc < 0) { ret = -EINVAL; break; }

        for (arg_index = 0; arg_index < (u32)expected_argc; arg_index++) {
            ret = sepol_read_string(&cursor, &args[arg_index]);
            if (ret < 0) { pr_err("sepol: failed cmd #%u arg #%u.\\n", cmd_index, arg_index); break; }
        }
        if (ret < 0) break;

        ret = apply_one_sepolicy_cmd(db, &header, args);
        if (ret < 0) { pr_err("sepol: cmd #%u failed.\\n", cmd_index); break; }
        success_cmd_count++;
        cmd_index++;
    }

    if (ret == 0 || ret == -EOPNOTSUPP) {
        reset_avc_cache();
        pr_info("sepol: applied %d cmds\\n", success_cmd_count);
        ret = success_cmd_count;
    }
    mutex_unlock(&ksu_policy_lock);
#endif

out_free:
    kvfree(payload);
    return ret;
}

int ksu_apply_sepolicy_batch(const char *batch, size_t len)
{
    struct policydb *db = get_policydb();
    struct sepol_batch_cursor cursor;
    int ret = 0;

    if (!db)
        return -EINVAL;

    cursor.cur = (const u8 *)batch;
    cursor.end = cursor.cur + len;

    while (sepol_remaining(&cursor) > 0) {
        struct sepol_data hdr;
        ret = sepol_read_cmd_header(&cursor, &hdr);
        if (ret) break;
        const char *args[KSU_SEPOLICY_MAX_ARGS] = { 0 };
        int expected_argc = sepol_expected_argc(hdr.cmd);
        if (expected_argc < 0) { ret = -EINVAL; break; }
        u32 arg_index;
        for (arg_index = 0; arg_index < (u32)expected_argc; arg_index++) {
            ret = sepol_read_string(&cursor, &args[arg_index]);
            if (ret) break;
        }
        if (ret) break;
        ret = apply_one_sepolicy_cmd(db, &hdr, args);
        if (ret) break;
    }
    return ret;
}
'''


def find_file():
    candidates = [
        "KernelSU-Next/kernel/selinux/rules.c",
        "drivers/kernelsu/selinux/rules.c",
        "kernel/selinux/rules.c",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return None


def patch_file(path):
    print(f"  Replacing {path} with 4.14-compatible SELinux rules")
    with open(path, 'w') as f:
        f.write(RULES_4_14)
    print("OK: rules.c replaced with 4.14-compatible version")
    return True


def main():
    if len(sys.argv) > 1:
        path = sys.argv[1]
    else:
        path = find_file()

    if not path or not os.path.exists(path):
        print(f"ERROR: rules.c not found at {path or '(none given)'}")
        sys.exit(1)

    if not patch_file(path):
        sys.exit(1)


if __name__ == "__main__":
    main()
