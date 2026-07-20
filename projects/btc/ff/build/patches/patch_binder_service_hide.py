#!/usr/bin/env python3
"""
Inject a SUSFS service-list scrub into drivers/android/binder.c.

Root cause (PE #2 "found lineageos in service list"):
  The disclosure detector / FF / GMS call android.os.IServiceManager.listServices()
  on the AIDL servicemanager (android::os::BnServiceManager). That is binder
  transaction code 4 (4th method in IServiceManager.aidl) to handle 0. The reply
  parcel is a pure string vector (no binder objects):
     [int32 status][int32 N][ N * (int32 utf16_len, utf16 bytes) ]
  We scrub every entry whose ASCII name contains "lineage" from the reply buffer
  for the detector/FF/GMS UIDs only, then compact and shrink data_size.

Injection points (verified against tillua467 v2.4 CAF 4.14 binder.c):
  A. Function + master switch + uid list, inserted before binder_fixup_parent().
  B. Call site: after the data copy into t->buffer, guarded by `reply && tr->code==4`.

Master switch `susfs_hide_lineage_services` is 0 by default (registered via
core_param under /sys/kernel/), so a mis-scrub cannot surprise-bootloop the
device — it is opt-in from userspace (ff_master) once verified.
"""
import sys

# ── A. injected near the other binder_* helpers ──────────────────────────────
C_PAYLOAD = r'''
/* ── SUSFS: hide LineageOS services from selected UIDs' listServices replies ──
 * See build/patches/patch_binder_service_hide.py. Default OFF; opt-in via
 *   echo 1 > /sys/kernel/susfs_hide_lineage_services
 */
#include <linux/uidgid.h>
#include <linux/slab.h>
#include <linux/string.h>
static int susfs_hide_lineage_services = 0;
core_param(susfs_hide_lineage_services, susfs_hide_lineage_services, int, 0644);

/* UIDs to hide lineage services from: GMS(10443), Disclosure(10566), FF(10574).
 * Edit here to add more. */
static const uid_t susfs_service_hide_uids[] = { 10443, 10566, 10574 };

static bool susfs_uid_in_hide_list(kuid_t uid)
{
	uid_t v = from_kuid(&init_user_ns, uid);
	int i;
	for (i = 0; i < (int)ARRAY_SIZE(susfs_service_hide_uids); i++)
		if (susfs_service_hide_uids[i] == v)
			return true;
	return false;
}

/* case-insensitive scan of an ASCII name buffer for the substring "lineage" */
static bool susfs_name_has_lineage(const char *name, int len)
{
	const char *needle = "lineage";
	int nlen = 7, i, j;
	for (i = 0; i + nlen <= len; i++) {
		for (j = 0; j < nlen; j++) {
			char c = name[i + j];
			if (c >= 'A' && c <= 'Z')
				c = (char)(c - 'A' + 'a');
			if (c != needle[j])
				break;
		}
		if (j == nlen)
			return true;
	}
	return false;
}

/* Scrub lineage entries from a IServiceManager.listServices(4) reply parcel.
 * target_proc owns the buffer; t holds the transaction. Pure-string parcel only. */
static void susfs_scrub_servicemanager_reply(struct binder_proc *target_proc,
					      struct binder_transaction *t)
{
	struct binder_alloc *alloc = &target_proc->alloc;
	struct binder_buffer *buf = t->buffer;
	int status, n, kept = 0;
	u32 ulen;
	binder_size_t src, wpos;
	u8 *tmp;
	char namebuf[256];
	int i;

	if (!susfs_hide_lineage_services)
		return;
	if (!t->to_proc || !t->to_proc->cred)
		return;
	if (!susfs_uid_in_hide_list(t->to_proc->cred->uid))
		return;
	/* Only a pure string parcel (no binder objects) is safe to compact. */
	if (buf->offsets_size != 0)
		return;

	binder_alloc_copy_from_buffer(alloc, &status, buf, 0, sizeof(status));
	binder_alloc_copy_from_buffer(alloc, &n, buf, 4, sizeof(n));
	if (n <= 0 || n > 4096)
		return;

	tmp = kmalloc(buf->data_size, GFP_KERNEL);
	if (!tmp)
		return;

	wpos = 8; /* after status + count */
	src = 8;
	for (i = 0; i < n; i++) {
		binder_size_t entry_off = src;
		int nb = 0, j;
		binder_alloc_copy_from_buffer(alloc, &ulen, buf, src, sizeof(ulen));
		if (ulen == 0 || ulen > 1024)
			goto out_free; /* malformed -> do not scrub */
		for (j = 0; j < (int)(ulen - 1) && nb < (int)sizeof(namebuf) - 1; j++) {
			u8 c;
			binder_alloc_copy_from_buffer(alloc, &c, buf,
				entry_off + 4 + (binder_size_t)j * 2, 1);
			namebuf[nb++] = (char)c;
		}
		namebuf[nb] = '\0';
		src += 4 + (binder_size_t)ulen * 2;
		if (!susfs_name_has_lineage(namebuf, nb)) {
			binder_alloc_copy_from_buffer(alloc, tmp + wpos, buf,
				entry_off, 4 + (size_t)ulen * 2);
			wpos += 4 + (binder_size_t)ulen * 2;
			kept++;
		}
	}

	/* write status + kept count, then compacted entries, shrink data_size */
	binder_alloc_copy_to_buffer(alloc, buf, 0, &status, sizeof(status));
	binder_alloc_copy_to_buffer(alloc, buf, 4, &kept, sizeof(kept));
	binder_alloc_copy_to_buffer(alloc, buf, 8, tmp + 8, wpos - 8);
	buf->data_size = (size_t)wpos;

out_free:
	kfree(tmp);
}
'''

CALL_SITE = (
    "\tif (binder_alloc_copy_user_to_buffer(\n"
    "\t\t\t\t&target_proc->alloc,\n"
    "\t\t\t\tt->buffer,\n"
    "\t\t\t\tALIGN(tr->data_size, sizeof(void *)),"
)

CALL_INJECT = (
    "\t/* SUSFS: scrub lineage services from listServices(4) replies for hidden UIDs */\n"
    "\tif (reply && tr->code == 4)\n"
    "\t\tsusfs_scrub_servicemanager_reply(target_proc, t);\n"
    "\n" + CALL_SITE
)

ANCHOR_FUNC = "static int binder_fixup_parent("


def patch(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        src = f.read()

    if "susfs_scrub_servicemanager_reply" in src:
        print("SKIP: binder service-hide already injected")
        return 0

    if CALL_SITE not in src:
        print("ERROR: call-site anchor not found in binder.c")
        return 1
    if ANCHOR_FUNC not in src:
        print("ERROR: function anchor not found in binder.c")
        return 1

    src = src.replace(CALL_SITE, CALL_INJECT, 1)
    src = src.replace(ANCHOR_FUNC, C_PAYLOAD + "\n" + ANCHOR_FUNC, 1)

    with open(path, "w", encoding="utf-8") as f:
        f.write(src)
    print("OK: injected SUSFS service-hide into binder.c")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: patch_binder_service_hide.py <binder.c>")
        sys.exit(2)
    sys.exit(patch(sys.argv[1]))
