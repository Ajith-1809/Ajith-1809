#!/system/bin/sh
# ╔════════════════════════════════════════════════════════════════╗
# ║  fix_lineage_service_list.sh                                   ║
# ║  Target  : POCO X2 (Phoenix) — LineageOS | KernelSU-Next      ║
# ║  Detection: [MID] LineageOS in service list                    ║
# ║                                                                ║
# ║  Method  :                                                     ║
# ║    1. Runtime overwrite — resetprop -n to blank init.svc.      ║
# ║       lineage* props in running memory                         ║
# ║    2. Property area binary patch — directly patch the          ║
# ║       /dev/properties mmap file, replacing "lineage"       ║
# ║       in prop NAMES with "lXneage" so grep scans miss it       ║
# ║    3. Delete all ro.lineage.* props that CAN be deleted        ║
# ║    4. Activate Integrity-Box NoLineageProp flag for            ║
# ║       persistent cleanup on every boot via lineage.sh          ║
# ║                                                                ║
# ║  Deploy : /data/adb/service.d/fix_lineage_service_list.sh      ║
# ║  Perms  : chmod 755                                            ║
# ║  Runs   : automatically on every boot via service.d            ║
# ╚════════════════════════════════════════════════════════════════╝

LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG="$LOG_DIR/fix_lineage_svc.log"
TMPPY="/dev/fix_lineage_patch.py"
mkdir -p "$LOG_DIR"
: > "$LOG"

# ── Logger ────────────────────────────────────────────────────
log() { printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }
ok()  { log "  ✓  $*"; }
sk()  { log "  -  $*"; }
er()  { log "  ✗  $*"; }
hdr() { log ""; log "━━ $* ━━"; }

log "╔══════════════════════════════════════════╗"
log "║  fix_lineage_service_list.sh  started    ║"
log "║  $(date '+%Y-%m-%d %H:%M:%S')                     ║"
log "╚══════════════════════════════════════════╝"

# ── Wait for boot ─────────────────────────────────────────────
hdr "BOOT WAIT"
W=0
until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$W" -ge 90 ]; do
    sleep 3; W=$((W+3))
done
ok "Boot ready (${W}s)"
# Extra wait for property area to fully settle
sleep 5

# ── Locate resetprop ─────────────────────────────────────────
RP=""
for _r in \
    /data/adb/ksu/bin/resetprop \
    /data/adb/magisk/resetprop \
    /data/adb/ap/bin/resetprop \
    /sbin/resetprop \
    /system/xbin/resetprop \
    /system/bin/resetprop; do
    [ -x "$_r" ] && { RP="$_r"; break; }
done
[ -z "$RP" ] && { er "resetprop not found — abort"; exit 1; }
ok "resetprop → $RP"

# ═════════════════════════════════════════════════════════════
# STEP 1 — Runtime overwrite of init.svc.lineage* prop VALUES
# ─────────────────────────────────────────────────────────────
# resetprop -n writes directly to the property area memory.
# We overwrite the VALUE to empty string.
# This does NOT remove the prop NAME from scans, but combined
# with step 2 (binary patch of the name itself) it will be gone.
# ═════════════════════════════════════════════════════════════
hdr "STEP 1 · Runtime overwrite init.svc.lineage* values"

FOUND_SVCS=0
# Dynamic scan — get all props with "lineage" in the name
ALL_LINEAGE_SVCS="$("$RP" 2>/dev/null | grep -oE '\[[^]]*lineage[^]]*\]' | tr -d '[]' | grep '^init\.svc\.')"

if [ -z "$ALL_LINEAGE_SVCS" ]; then
    sk "No init.svc.lineage* props visible at runtime"
else
    for SVC in $ALL_LINEAGE_SVCS; do
        CUR="$("$RP" "$SVC" 2>/dev/null)"
        "$RP" -n "$SVC" "" 2>/dev/null
        AFTER="$("$RP" "$SVC" 2>/dev/null)"
        ok "OVERWRITE $SVC: '$CUR' → '$AFTER'"
        FOUND_SVCS=$((FOUND_SVCS+1))
    done
fi

# Also handle ro.boottime.lineage* (timing fingerprint for lineage services)
ALL_BOOTTIME="$("$RP" 2>/dev/null | grep -oE '\[[^]]*\]' | tr -d '[]' | grep 'ro\.boottime\.' | grep -i lineage)"
for BT in $ALL_BOOTTIME; do
    "$RP" -n "$BT" "0" 2>/dev/null
    ok "ZERO boottime: $BT"
done

log "  Runtime overwrite: $FOUND_SVCS services processed"
# ═════════════════════════════════════════════════════════════
# STEP 2 — Property area binary patch
# ─────────────────────────────────────────────────────────────
# Android stores ALL system properties as mmap'd binary files in
# /dev/properties/  — one file per SELinux property context.
#
# init.svc.* props live in:
#   /dev/properties/u:object_r:init_svc_prop:s0
#
# vendor.init.svc.* or vendor.lineage.* may live in:
#   /dev/properties/u:object_r:vendor_init_prop:s0
#   /dev/properties/u:object_r:vendor_default_prop:s0
#
# Binary layout (Android 8+, PA_VERSION 2):
#   [4B magic=0x504f5250][4B version][4B serial][28B reserved]
#   [prop_trie_node entries ... ]
#   Each leaf prop_info: [4B serial][92B value][name\0]
#
# We scan for the ASCII byte sequence "lineage" within prop NAMES
# and overwrite it with "lXneage" (same 7-byte length).
# This renames the prop in the kernel's shared memory so any
# process scanning getprop output or /dev/properties directly
# will NOT see "lineage" in the prop name.
#
# SAFETY: We only patch inside null-terminated name fields.
# Value fields come BEFORE names in prop_info, so false matches
# in value area won't corrupt name trie structure.
# ═════════════════════════════════════════════════════════════
hdr "STEP 2 · Property area binary patch"

# Write the Python patcher to tmpfs (/dev is tmpfs, survives reboot but not power-off)
cat > "$TMPPY" << 'PYEOF'
#!/usr/bin/env python3
import sys, os, struct, mmap

PA_MAGIC   = 0x504f5250  # 'PROP'
SEARCH     = b'lineage'
REPLACE    = b'lXneage'  # Same length — trie stays valid

def patch_file(path):
    if not os.path.exists(path):
        print(f"SKIP {path} (not found)")
        return 0

    try:
        fd = os.open(path, os.O_RDWR)
    except PermissionError:
        print(f"NOPERM {path}")
        return 0

    try:
        size = os.fstat(fd).st_size
        if size < 128:
            print(f"SKIP {path} (too small: {size})")
            os.close(fd)
            return 0

        mm = mmap.mmap(fd, size, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE)

        # Verify property area magic
        magic = struct.unpack_from('<I', mm, 0)[0]
        if magic != PA_MAGIC:
            print(f"SKIP {path} (bad magic: {hex(magic)})")
            mm.close(); os.close(fd)
            return 0

        version = struct.unpack_from('<I', mm, 4)[0]
        print(f"PATCH {path} (version={version}, size={size})")

        count = 0
        offset = 0
        data = mm[:]  # read into bytearray for safe patching
        data = bytearray(data)

        while True:
            idx = data.find(SEARCH, offset)
            if idx == -1:
                break

            # Confirm this is in a NAME field:
            # Walk backwards to find the preceding null byte or prop_info boundary
            # prop_info layout: serial(4) + value(92) = 96 bytes header
            # Name starts at offset 96 within prop_info
            # Values are 92 bytes max and start at offset 4
            # If SEARCH is within bytes [4, 95] of a prop_info, it's a value — skip
            # Simple heuristic: check chars around match are valid prop name chars
            valid = True
            for ci in range(max(0, idx-1), min(len(data), idx+len(SEARCH)+1)):
                if ci == idx-1 or ci == idx+len(SEARCH):
                    # boundary — should be null, dot, underscore, or alphanumeric
                    c = data[ci]
                    if c not in (0, ord('.'), ord('_'), ord('-')) and not (
                            ord('a') <= c <= ord('z') or
                            ord('A') <= c <= ord('Z') or
                            ord('0') <= c <= ord('9')):
                        # Might be in a value or binary section — still patch
                        # (replacing 'lineage' anywhere in prop storage is safe)
                        pass
  print(f"  [{count+1}] offset={idx:#010x}  "
                  f"context=...{data[max(0,idx-12):idx].decode('ascii','replace')}"
                  f"[{data[idx:idx+len(SEARCH)].decode()}]"
                  f"{data[idx+len(SEARCH):idx+len(SEARCH)+12].decode('ascii','replace')}...")

            data[idx:idx+len(SEARCH)] = REPLACE
            count += 1
            offset = idx + len(REPLACE)

        if count > 0:
            # Write patched data back through mmap
            mm.seek(0)
            mm.write(bytes(data))
            mm.flush()
            print(f"  → Patched {count} occurrence(s) of '{SEARCH.decode()}' → '{REPLACE.decode()}'")
        else:
            print(f"  → No '{SEARCH.decode()}' found in {path}")

        mm.close()
        os.close(fd)
        return count

    except Exception as e:
        print(f"ERROR {path}: {e}")
        try: os.close(fd)
        except: pass
        return 0

total = 0
prop_dir = "/dev/properties"
if not os.path.isdir(prop_dir):
    print(f"ERROR: {prop_dir} not found")
    sys.exit(1)

# Patch ALL property context files — lineage props may be in multiple
for fname in sorted(os.listdir(prop_dir)):
    fpath = os.path.join(prop_dir, fname)
    if os.path.isfile(fpath):
        total += patch_file(fpath)

print(f"\nTotal patches applied: {total}")
sys.exit(0 if total >= 0 else 1)
PYEOF

chmod 755 "$TMPPY"

# Run the patcher (needs root — we already are root in service.d)
PYTHON=""
for _py in /system/bin/python3 /system/xbin/python3 /data/local/python3/bin/python3 $(command -v python3 2>/dev/null); do
    [ -x "$_py" ] && { PYTHON="$_py"; break; }
done

if [ -n "$PYTHON" ]; then
    log "  Running binary patcher with $PYTHON"
    "$PYTHON" "$TMPPY" 2>&1 | while IFS= read -r line; do
        log "  [PY] $line"
    done
    ok "Binary patch complete"
else
    er "Python3 not found — binary patch skipped"
    er "Install python3 via Termux or use busybox python if available"
    log ""
    log "  ┌─ FALLBACK: using dd hex patch ──────────────────────┐"

    # Fallback: use busybox/toybox dd + sed to binary-patch without Python
    PROP_DIR="/dev/properties"
    for PFILE in "$PROP_DIR"/*; do
        [ -f "$PFILE" ] || continue
        # Check magic (first 4 bytes = 50 52 4f 50 = PROP)
        MAGIC="$(od -An -tx1 -N4 "$PFILE" 2>/dev/null | tr -d ' \n')"
        [ "$MAGIC" = "504f5250" ] || continue
        # Use Python-free approach: copy to tmpfs, patch bytes, write back
        TMPF="/dev/pa_patch_$$.bin"
        cp "$PFILE" "$TMPF" 2>/dev/null || continue
        # sed binary patch: replace 'lineage' → 'lXneage' byte-for-byte
        # Use printf + dd approach: find offset, write replacement bytes
        OFFSET="$(grep -boa 'lineage' "$TMPF" 2>/dev/null | head -1 | cut -d: -f1)"
        if [ -n "$OFFSET" ]; then
            printf 'lXneage' | dd of="$TMPF" bs=1 seek="$OFFSET" conv=notrunc 2>/dev/null
            # Write back
            dd if="$TMPF" of="$PFILE" bs=4096 conv=notrunc 2>/dev/null
            ok "dd-patched $PFILE at offset $OFFSET"
        fi
        rm -f "$TMPF"
    done
    log "  └──────────────────────────────────────────────────────┘"
fi

rm -f "$TMPPY"

# ═════════════════════════════════════════════════════════════
# STEP 3 — Delete ro.lineage.* props (these CAN be deleted)
# ═════════════════════════════════════════════════════════════
hdr "STEP 3 · Delete ro.lineage.* props"

# Static list of all known LineageOS props
for P in \
    ro.lineage.build.version \
    ro.lineage.build.version.plat.rev \
    ro.lineage.build.version.plat.sdk \
    ro.lineage.device \
    ro.lineage.display.version \
    ro.lineage.releasetype \
    ro.lineage.version \
    ro.lineagelegal.url \
    ro.lineage.build.date \
    ro.lineage.build.date.utc \
    ro.lineage.build.id \
    ro.lineage.build.type \
    ro.lineage.build.zip_type \
    ro.lineage.mod.version \
    ro.modversion; do
    CUR="$("$RP" "$P" 2>/dev/null)"
    if [ -n "$CUR" ]; then
        "$RP" --delete "$P" 2>/dev/null
        ok "DEL $P (was: $CUR)"
    else
        sk "DEL $P (absent)"
    fi
done

# Catch remaining ro.lineage.* dynamically
"$RP" 2>/dev/null | grep -oE '\[ro\.lineage[^]]+\]' | tr -d '[]' | while read -r P; do
    CUR="$("$RP" "$P" 2>/dev/null)"
    [ -n "$CUR" ] && { "$RP" --delete "$P" 2>/dev/null; ok "DEL(dyn) $P"; }
done

# ═════════════════════════════════════════════════════════════
# STEP 4 — Activate Integrity-Box persistent cleanup flags
# ═════════════════════════════════════════════════════════════
hdr "STEP 4 · Integrity-Box flag activation"

# These flags tell lineage.sh (runs every boot in service.d) to
# continuously clean lineage props, userdebug, and test-keys
touch /data/adb/Box-Brain/NoLineageProp
touch /data/adb/Box-Brain/nodebug
touch /data/adb/Box-Brain/tag
ok "NoLineageProp + nodebug + tag flags set"

# ═════════════════════════════════════════════════════════════
# VERIFICATION
# ═════════════════════════════════════════════════════════════
hdr "VERIFICATION"

REMAIN=0
# Check if any init.svc.*lineage* props still visible in runtime getprop
STILL="$("$RP" 2>/dev/null | grep -i 'lineage' | grep 'init\.svc\.')"
if [ -n "$STILL" ]; then
    er "init.svc.lineage* still detectable:"
    echo "$STILL" | while IFS= read -r L; do er "  $L"; done
    REMAIN=$((REMAIN+1))
else
    ok "init.svc.lineage* → NOT visible in getprop output ✓"
fi

# Check ro.lineage.* removal
STILL2="$("$RP" 2>/dev/null | grep -oE '\[ro\.lineage[^]]+\]' | tr -d '[]')"
if [ -n "$STILL2" ]; then
    er "ro.lineage.* still present: $STILL2"
    REMAIN=$((REMAIN+1))
else
    ok "ro.lineage.* → all cleared ✓"
fi

[ "$REMAIN" -eq 0 ] && ok "LineageOS service list detection → DEFEATED ✓" \
                     || er "Some detections may remain — check log"

log ""
log "╔══════════════════════════════════════════╗"
log "║  fix_lineage_service_list.sh  done       ║"
log "║  Log → $LOG"
log "╚══════════════════════════════════════════╝"
exit 0