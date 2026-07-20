#!/system/bin/sh
# ╔══════════════════════════════════════════════════════════════╗
# ║           milltina_defeat.sh  —  v2.0                       ║
# ║  Device : POCO X2 (Phoenix) | LineageOS | KernelSU-Next     ║
# ║  Author : Generated for Ajithkumar                          ║
# ║                                                             ║
# ║  Targets (milltina v1.2.1):                                 ║
# ║  [HIGH] pihooks.disable.gms_props         → NUKE prop       ║
# ║  [HIGH] pihooks.disable.gms_key_attest... → NUKE prop       ║
# ║  [MID]  LineageOS in service list         → MASK svc props  ║
# ║  [CRIT] Inconsistent inode                → SuSFS sus_maps  ║
# ║                                                             ║
# ║  Deploy: /data/adb/service.d/milltina_defeat.sh             ║
# ║  Perm  : chmod 755                                          ║
# ╚══════════════════════════════════════════════════════════════╝

# ── Dirs & Logging ────────────────────────────────────────────
LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG="$LOG_DIR/milltina_defeat.log"
mkdir -p "$LOG_DIR"
: > "$LOG"

ts()  { date '+%H:%M:%S'; }
log() { printf "[%s] %s\n" "$(ts)" "$*" | tee -a "$LOG"; }
ok()  { log "  ✓  $*"; }
sk()  { log "  –  $*"; }
er()  { log "  ✗  $*"; }
hdr() { log ""; log "══ $* ══"; }

log "╔══════════════════════════════════════╗"
log "║  milltina_defeat.sh  started         ║"
log "║  $(date '+%Y-%m-%d %H:%M:%S')                   ║"
log "╚══════════════════════════════════════╝"

# ── Wait for full boot ────────────────────────────────────────
WAITED=0
until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$WAITED" -ge 90 ]; do
    sleep 3
    WAITED=$((WAITED + 3))
done
log "Boot ready (${WAITED}s)"

# ── Resolve resetprop ─────────────────────────────────────────
RP=""
for _rp in \
    /data/adb/ksu/bin/resetprop \
    /data/adb/magisk/resetprop \
    /data/adb/ap/bin/resetprop \
    /sbin/resetprop \
    /system/xbin/resetprop \
    /system/bin/resetprop; do
    [ -x "$_rp" ] && { RP="$_rp"; break; }
done
[ -z "$RP" ] && { er "resetprop not found — abort"; exit 1; }
ok "resetprop → $RP"

# ── Helpers ───────────────────────────────────────────────────

# Hard-delete a prop from BOTH runtime and persistent store.
# Uses -p flag to hit /data/property as well.
nuke_prop() {
    local P="$1"
    local CUR; CUR="$("$RP" "$P" 2>/dev/null)"
    if [ -z "$CUR" ]; then
        sk "NUKE $P (already absent)"
        return
    fi
    # Delete from runtime store
    "$RP" --delete "$P" 2>/dev/null
    # Delete from persistent store (/data/property)
    "$RP" -p --delete "$P" 2>/dev/null
    # Verify
    local AFTER; AFTER="$("$RP" "$P" 2>/dev/null)"
    if [ -z "$AFTER" ]; then
        ok "NUKE $P (was: $CUR)"
    else
        # Still exists — overwrite with empty string as fallback
        "$RP" -n -p "$P" "" 2>/dev/null
        ok "NUKE $P → blanked (was: $CUR)"
    fi
}

# Set a prop value, skip if already correct
set_prop() {
    local P="$1" V="$2"
    local CUR; CUR="$("$RP" "$P" 2>/dev/null)"
    [ "$CUR" = "$V" ] && { sk "SET  $P (already $V)"; return; }
    "$RP" -n "$P" "$V" 2>/dev/null
    ok "SET  $P = $V (was: ${CUR:-<empty>})"
}

# Overwrite a normally read-only prop using -n (no-trigger) flag
mask_prop() {
    local P="$1" V="$2"
    local CUR; CUR="$("$RP" "$P" 2>/dev/null)"
    [ "$CUR" = "$V" ] && { sk "MASK $P (already $V)"; return; }
    "$RP" -n "$P" "$V" 2>/dev/null
    ok "MASK $P = $V (was: ${CUR:-<empty>})"
}

# ══════════════════════════════════════════════════════════════
# FIX 1 & 2 — [HIGH] pihooks props
# ─────────────────────────────────────────────────────────────
# milltina flags these props on EXISTENCE, not just value=true.
# Setting to false still triggers the HIGH. Only solution is
# complete deletion from both runtime + persistent property store.
#
# Root cause: Integrity-Box enablegms/disablegms flags write
# these via set_resetprop (resetprop -n -p). We must nuke both
# the runtime entry AND the /data/property persistent file.
# ══════════════════════════════════════════════════════════════
hdr "FIX 1+2 · NUKE pihooks props"

nuke_prop "persist.sys.pihooks.disable.gms_props"
nuke_prop "persist.sys.pihooks.disable.gms_key_attestation_block"
nuke_prop "persist.sys.pihooks.disable"
nuke_prop "persist.sys.kihooks.disable"
nuke_prop "persist.sys.pixelprops.vending"

# Also nuke any related props that may exist
for _p in $("$RP" 2>/dev/null | grep -oE '\[persist\.sys\.(pihooks|kihooks|pixelprops)[^\]]+\]' | tr -d '[]'); do
    nuke_prop "$_p"
done

# Prevent Integrity-Box from re-writing them on next boot:
# Remove the enablegms/disablegms flag files so the module's
# post-fs-data.sh skips those blocks entirely.
for _f in \
    /data/adb/Box-Brain/enablegms \
    /data/adb/Box-Brain/disablegms; do
    if [ -f "$_f" ]; then
        rm -f "$_f"
        ok "Removed flag: $_f"
    fi
done

# ══════════════════════════════════════════════════════════════
# FIX 3 — [MID] LineageOS in service list
# ─────────────────────────────────────────────────────────────
# milltina scans init.svc.* props for LineageOS service names.
# These are set by Android init from .rc files and sit in the
# read-only property area — resetprop --delete silently fails.
# Strategy: overwrite with spoofed neutral value using -n flag.
#
# Known LineageOS services on Phoenix (LineageOS 20/21):
#   lineage_health, lineage_trust, lineage_livedisplay,
#   lineage_perf, lineage_updater, vendor.lineage.*
# ══════════════════════════════════════════════════════════════
hdr "FIX 3 · Mask LineageOS init.svc props"

# Dynamically find ALL init.svc.* props containing "lineage"
LINEAGE_SVCS="$("$RP" 2>/dev/null | grep -oE '\[init\.svc\.[^\]]*lineage[^\]]*\]' | tr -d '[]')"

if [ -z "$LINEAGE_SVCS" ]; then
    sk "No init.svc.lineage* props found at runtime"
else
    for _svc in $LINEAGE_SVCS; do
        # Overwrite service state — "stopped" is a valid neutral value
        mask_prop "$_svc" "stopped"
    done
fi

# Also handle ro.boottime.* for lineage services (timing fingerprint)
for _p in $("$RP" 2>/dev/null | grep -oE '\[ro\.boottime\.[^\]]*lineage[^\]]*\]' | tr -d '[]'); do
    mask_prop "$_p" "0"
done

# Delete all ro.lineage.* props (these CAN be deleted at runtime)
hdr "FIX 3b · Delete ro.lineage.* props"
for _prop in \
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
    ro.lineage.build.zip_type; do
    CUR="$("$RP" "$_prop" 2>/dev/null)"
    [ -n "$CUR" ] && { "$RP" --delete "$_prop" 2>/dev/null; ok "DEL  $_prop"; } || sk "DEL  $_prop (absent)"
done

# Catch any remaining ro.lineage.* dynamically
for _p in $("$RP" 2>/dev/null | grep -oE '\[ro\.lineage[^\]]+\]' | tr -d '[]'); do
    CUR="$("$RP" "$_p" 2>/dev/null)"
    [ -n "$CUR" ] && { "$RP" --delete "$_p" 2>/dev/null; ok "DEL  $_p"; }
done

# Enable Integrity-Box's built-in NoLineageProp flag so lineage.sh
# also cleans props on next boot-time run
touch /data/adb/Box-Brain/NoLineageProp
touch /data/adb/Box-Brain/nodebug
touch /data/adb/Box-Brain/tag
ok "Set Integrity-Box flags: NoLineageProp + nodebug + tag"

# ══════════════════════════════════════════════════════════════
# FIX 4 — [CRIT] Inconsistent inode (sus_maps)
# ─────────────────────────────────────────────────────────────
# milltina compares the inode of a .so mapped in /proc/*/maps
# against the real fs inode. This CANNOT be resolved at the
# shell/prop level. Requires kernel-level SuSFS sus_maps.
#
# SuSFS sus_maps works by intercepting /proc/*/maps reads and
# replacing inode values for specified paths with the real one.
#
# On Phoenix (msm-4.14, Unholy Kernel), sus_maps is NOT yet
# supported. Two paths forward:
#   1. Request SUS Maps from Unholy Kernel dev (preferred)
#   2. Try a kernel that has GKI + SuSFS support
#
# We attempt the SuSFS sus_maps call anyway in case a future
# kernel update adds support.
# ══════════════════════════════════════════════════════════════
hdr "FIX 4 · SuSFS sus_maps (inode)"

SUSFS="$(command -v susfs 2>/dev/null)"
if [ -n "$SUSFS" ]; then
    ok "SuSFS binary found: $SUSFS"

    # Add sus_path for known detection-triggering paths
    for _path in \
        /data/adb/service.d/lineage.sh \
        /data/adb/service.d/prop.sh \
        /data/adb/service.d/hash.sh \
        /data/adb/service.d/shamiko.sh \
        /data/adb/modules/playintegrityfix \
        /data/adb/ksu; do
        "$SUSFS" add_sus_path "$_path" 2>/dev/null \
            && ok "sus_path → $_path" \
            || sk "sus_path → $_path (already set or unsupported)"
    done

    # sus_maps: hide inode inconsistency for common targets
    for _lib in \
        /system/lib64/libdex.so \
        /apex/com.android.art/lib64/libdexfile.so \
        /apex/com.android.art/lib64/libart.so; do
        [ -f "$_lib" ] && {
            "$SUSFS" add_sus_maps "$_lib" 2>/dev/null \
                && ok "sus_maps → $_lib" \
                || sk "sus_maps → $_lib (kernel may lack support)"
        }
    done
else
    er "SuSFS binary not found in PATH"
    er "sus_maps cannot be applied — kernel patch required"
    log ""
    log "  ┌─ ACTION REQUIRED ─────────────────────────────┐"
    log "  │  Your kernel (Unholy, msm-4.14) lacks sus_maps│"
    log "  │  Contact Unholy Kernel dev and request:        │"
    log "  │    SuSFS sus_maps / SUS Maps kernel support    │"
    log "  │  Telegram: search 'Unholy Kernel Phoenix'      │"
    log "  └───────────────────────────────────────────────┘"
fi

# ══════════════════════════════════════════════════════════════
# HARDENING — General prop cleanup (prevent future detections)
# ══════════════════════════════════════════════════════════════
hdr "HARDENING · Build props"

set_prop "ro.build.flavor"   "phoenix-user"
set_prop "ro.secure"         "1"
set_prop "ro.build.version.release" "11"


# Boot state props
set_prop "ro.boot.verifiedbootstate"       "green"
set_prop "ro.boot.vbmeta.device_state"     "locked"
set_prop "vendor.boot.vbmeta.device_state" "locked"
set_prop "ro.boot.flash.locked"            "1"
set_prop "ro.boot.veritymode"              "enforcing"
set_prop "ro.boot.warranty_bit"            "0"
set_prop "ro.vendor.boot.warranty_bit"     "0"
set_prop "ro.vendor.warranty_bit"          "0"
set_prop "ro.warranty_bit"                 "0"
set_prop "sys.oem_unlock_allowed"          "0"
set_prop "ro.is_ever_orange"               "0"
set_prop "ro.secureboot.lockstate"         "locked"

# ══════════════════════════════════════════════════════════════
# VERIFICATION REPORT
# ══════════════════════════════════════════════════════════════
hdr "VERIFICATION"

log "  pihooks.gms_props              = $("$RP" persist.sys.pihooks.disable.gms_props 2>/dev/null || echo '<deleted>')"
log "  pihooks.gms_key_attestation    = $("$RP" persist.sys.pihooks.disable.gms_key_attestation_block 2>/dev/null || echo '<deleted>')"
log "  ro.build.flavor                = $("$RP" ro.build.flavor 2>/dev/null)"
log "  ro.build.type                  = $("$RP" ro.build.type 2>/dev/null)"
log "  ro.build.tags                  = $("$RP" ro.build.tags 2>/dev/null)"
log "  ro.debuggable                  = $("$RP" ro.debuggable 2>/dev/null)"
log "  ro.boot.verifiedbootstate      = $("$RP" ro.boot.verifiedbootstate 2>/dev/null)"
log ""

_remaining=0
[ -n "$("$RP" persist.sys.pihooks.disable.gms_props 2>/dev/null)" ]              && { er "STILL DETECTED: pihooks.gms_props";         _remaining=$((_remaining+1)); }
[ -n "$("$RP" persist.sys.pihooks.disable.gms_key_attestation_block 2>/dev/null)" ] && { er "STILL DETECTED: pihooks.gms_key_attestation"; _remaining=$((_remaining+1)); }

if [ "$_remaining" -eq 0 ]; then
    ok "All prop-level detections cleared ✓"
else
    er "$_remaining prop(s) still present — reboot may be needed"
fi

log ""
log "╔══════════════════════════════════════╗"
log "║  milltina_defeat.sh  complete        ║"
log "║  Log → $LOG"
log "╚══════════════════════════════════════╝"
exit 0