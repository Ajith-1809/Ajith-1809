#!/system/bin/sh
# ================================================================
#  spoof_detections.sh
#  Device  : POCO X2 (Phoenix) — LineageOS | KernelSU-Next
#  Tool    : milltina v1.2.1
#  Purpose : Spoof / suppress all 6 reported detections
#
#  Detection map:
#  [HIGH] persist.sys.pihooks.disable.gms_props=true         → FIX 1
#  [HIGH] persist.sys.pihooks.disable.gms_key_attest...=true → FIX 2
#  [MID]  ro.build.flavor=lineage_phoenix-userdebug          → FIX 3
#  [MID]  LineageOS in service list                          → FIX 4
#  [MID]  Custom ROM / deprecated kernel                     → FIX 5
#  [CRIT] Inconsistent inode (sus_maps)                      → FIX 6 (note)
#
#  Place in /data/adb/service.d/spoof_detections.sh
#  It will auto-run on every boot after the framework starts.
# ================================================================

LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG="$LOG_DIR/spoof_detections.log"
mkdir -p "$LOG_DIR"
> "$LOG"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOG"
}

log "=== spoof_detections.sh started ==="
log "Device: $(getprop ro.product.device) | Android: $(getprop ro.build.version.release)"

# ── Wait for boot to complete ────────────────────────────────
WAITED=0
until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$WAITED" -ge 60 ]; do
    sleep 2
    WAITED=$((WAITED + 2))
done
log "Boot completed (waited ${WAITED}s)"

# ── Locate resetprop ─────────────────────────────────────────
RESETPROP=""
for rp in \
    /data/adb/ksu/bin/resetprop \
    /data/adb/magisk/resetprop \
    /data/adb/ap/bin/resetprop \
    /sbin/resetprop \
    /system/bin/resetprop \
    /system/xbin/resetprop \
    $(command -v resetprop 2>/dev/null); do
    [ -x "$rp" ] && { RESETPROP="$rp"; break; }
done

if [ -z "$RESETPROP" ]; then
    log "ERROR: resetprop not found — cannot continue."
    exit 1
fi
log "resetprop: $RESETPROP"

# ── Helpers ──────────────────────────────────────────────────
rp_set() {
    # rp_set <prop> <value>
    local PROP="$1" VAL="$2"
    local CUR; CUR="$("$RESETPROP" "$PROP" 2>/dev/null)"
    if [ "$CUR" = "$VAL" ]; then
        log "  [SKIP] $PROP = $VAL"
    else
        "$RESETPROP" "$PROP" "$VAL" 2>/dev/null
        log "  [SET]  $PROP = $VAL  (was: ${CUR:-<empty>})"
    fi
}

rp_del() {
    # rp_del <prop>
    local PROP="$1"
    local CUR; CUR="$("$RESETPROP" "$PROP" 2>/dev/null)"
    if [ -z "$CUR" ]; then
        log "  [SKIP] $PROP already absent"
    else
        "$RESETPROP" --delete "$PROP" 2>/dev/null \
            || "$RESETPROP" -p -d "$PROP" 2>/dev/null
        log "  [DEL]  $PROP  (was: $CUR)"
    fi
}

# ================================================================
# FIX 1 — [HIGH] persist.sys.pihooks.disable.gms_props=true
# Integrity-Box sets this when the disablegms flag is active.
# Milltina flags it as suspicious → reset to false.
# ================================================================
log ""
log "--- FIX 1: pihooks gms_props ---"
rp_set "persist.sys.pihooks.disable.gms_props" "false"

# ================================================================
# FIX 2 — [HIGH] persist.sys.pihooks.disable.gms_key_attestation_block=true
# Same cause as FIX 1 — another disablegms side-effect.
# ================================================================
log ""
log "--- FIX 2: pihooks gms_key_attestation_block ---"
rp_set "persist.sys.pihooks.disable.gms_key_attestation_block" "false"

# ================================================================
# FIX 3 — [MID] ro.build.flavor=lineage_phoenix-userdebug
# This prop is never spoofed by Integrity-Box.
# Spoof to stock MIUI value for Phoenix (Snapdragon 730G).
# Also clean ro.build.type and ro.build.tags for consistency.
# ================================================================
log ""
log "--- FIX 3: ro.build.flavor / build type / tags ---"
rp_set "ro.build.flavor"   "phoenix-user"
rp_set "ro.build.type"     "user"
rp_set "ro.build.tags"     "release-keys"
rp_set "ro.debuggable"     "0"
rp_set "ro.secure"         "1"
# Also spoof the fingerprint if it still contains userdebug
FP="$("$RESETPROP" ro.build.fingerprint 2>/dev/null)"
if echo "$FP" | grep -q "userdebug"; then
    FP_CLEAN="$(echo "$FP" | sed 's/userdebug/user/g; s/test-keys/release-keys/g')"
    rp_set "ro.build.fingerprint" "$FP_CLEAN"
    log "  [FP]   Fingerprint sanitized"
fi

# ================================================================
# FIX 4 — [MID] LineageOS in service list
# Milltina scans init.svc.* props for LineageOS-named services.
# These props are set by init and cannot be deleted with resetprop.
# Best runtime mitigation: delete all ro.lineage.* props so the
# string "lineage" appears as few places as possible, and rely on
# SuSFS sus_path to hide /data/adb/service.d/lineage.sh from scans.
#
# Also delete the lineage.* system properties that DO allow deletion.
# ================================================================
log ""
log "--- FIX 4: LineageOS prop cleanup ---"
for PROP in \
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
    rp_del "$PROP"
done

# Catch any remaining lineage props dynamically
"$RESETPROP" | grep -i "\[ro\.lineage" | while IFS= read -r line; do
    PROP="$(echo "$line" | sed -E 's/^\[([^]]+)\].*/\1/')"
    [ -n "$PROP" ] && rp_del "$PROP"
done

# SuSFS sus_path hint (if SuSFS is active, add the lineage service script path)
SUSFS_BIN="$(command -v susfs 2>/dev/null)"
if [ -n "$SUSFS_BIN" ]; then
    log "  [SUSFS] Adding sus_path for lineage service script..."
    "$SUSFS_BIN" add_sus_path /data/adb/service.d/lineage.sh 2>/dev/null \
        && log "  [SUSFS] sus_path added: /data/adb/service.d/lineage.sh" \
        || log "  [SUSFS] sus_path failed (may already be set)"
else
    log "  [WARN]  susfs binary not found — init.svc.lineage cannot be hidden at runtime."
    log "          Add to susfs.sh: add_sus_path /data/adb/service.d/lineage.sh"
fi

# ================================================================
# FIX 5 — [MID] Custom ROM / deprecated kernel
# Milltina checks /proc/version for the kernel build string.
# KernelSU-Next has built-in kernel name spoofing via SuSFS.
# If SuSFS kernel name spoofing is NOT configured, set it here.
#
# Stock MIUI kernel string for POCO X2 (msm-4.14):
#   Linux version 4.14.x-perf+ (builder@host) ...
#
# We also spoof ro.build.version.release and ro.product.* props
# to not expose LineageOS/custom ROM strings.
# ================================================================
log ""
log "--- FIX 5: Kernel / ROM props ---"

# Spoof ro.build.version.release to stock Android for Phoenix
# (MIUI ships Android 11 for POCO X2)
rp_set "ro.build.version.release"      "11"
rp_set "ro.build.version.sdk"          "30"

# Hide custom ROM identifiers in product props
PRODUCT_NAME="$("$RESETPROP" ro.product.name 2>/dev/null)"
if echo "$PRODUCT_NAME" | grep -qi "lineage\|crDroid\|PixelExperience\|Evolution"; then
    rp_set "ro.product.name"   "phoenix"
    rp_set "ro.product.device" "phoenix"
    rp_set "ro.product.model"  "POCO X2"
    rp_set "ro.product.brand"  "POCO"
    rp_set "ro.product.manufacturer" "Xiaomi"
    log "  [SET]  Product props spoofed to stock POCO X2"
else
    log "  [SKIP] Product props already clean"
fi

# Spoof kernel version prop (used by some detections)
rp_set "ro.kernel.version" "4.14"

# KernelSU-Next: if SuSFS kernel name spoofing is available,
# set the spoofed uname string to match stock MIUI kernel
KSUD="/data/adb/ksu/bin/ksud"
if [ -x "$KSUD" ]; then
    log "  [KSU]  KernelSU-Next detected"
    # SuSFS kernel spoofing is configured in susfs.sh / module config,
    # not at runtime. Verify your susfs.sh has:
    #   susfs set_uname "Linux version 4.14.116-perf+ ..."
    log "  [KSU]  Ensure susfs set_uname is configured in your SuSFS module"
else
    log "  [WARN]  ksud not found at $KSUD"
fi

# ================================================================
# FIX 6 — [CRIT] Inconsistent inode (sus_maps)
# This detection compares the inode of a mapped library in
# /proc/<pid>/maps against the actual filesystem inode.
# It CANNOT be fixed at the prop/shell level.
# It requires SuSFS sus_maps support in the kernel.
#
# Status for Phoenix (msm-4.14 / Unholy Kernel):
#   - Unholy Kernel does NOT yet support SUS Maps.
#   - Contact the Unholy Kernel developer to request SUS Maps.
#   - Alternatively try a kernel that supports it (e.g. KernelSU
#     GKI builds if your device ever gets GKI support).
#
# Nothing to do here programmatically.
# ================================================================
log ""
log "--- FIX 6: Inconsistent inode ---"
log "  [INFO]  This requires SuSFS sus_maps kernel support."
log "  [INFO]  Unholy Kernel (Phoenix) does not yet support sus_maps."
log "  [INFO]  Contact Unholy Kernel dev to request SUS Maps support."

# ================================================================
# SUMMARY
# ================================================================
log ""
log "=== Final prop state ==="
for PROP in \
    persist.sys.pihooks.disable.gms_props \
    persist.sys.pihooks.disable.gms_key_attestation_block \
    ro.build.flavor \
    ro.build.type \
    ro.build.tags \
    ro.debuggable \
    ro.product.name \
    ro.product.model \
    ro.build.version.release; do
    log "  $PROP = $("$RESETPROP" "$PROP" 2>/dev/null)"
done
log ""
log "=== spoof_detections.sh complete ==="
exit 0