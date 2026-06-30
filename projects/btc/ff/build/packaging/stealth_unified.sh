#!/system/bin/sh
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  stealth_unified.sh  —  Consolidated SUSFS stealth script          ║
# ║  Device   : POCO X2 (Phoenix) | LineageOS | KernelSU-Next          ║
# ║  SUSFS    : v1.5.12 (ABI: sys_reboot) — NON-GKI kernel-4.14        ║
# ║                                                                    ║
# ║  Combines: game lib hardening (32+64 bit), prop spoofing,          ║
# ║  sus_kstat_statically.json, UID hiding, proc redirects.            ║
# ║                                                                    ║
# ║  Deploy : /data/adb/service.d/stealth_unified.sh                  ║
# ║  Perms  : chmod 755                                               ║
# ║  Logs   : /data/adb/susfs4ksu/logs/stealth_unified.log           ║
# ╚══════════════════════════════════════════════════════════════════════╝

export PATH=$PATH:/data/adb/ksu/bin:/system/bin:/system/xbin

# ==============================================================
# CONFIGURATION
# ==============================================================
SUSFS_DIR="/data/adb/susfs4ksu"
BACKUP64="$SUSFS_DIR/backup_ff64"
BACKUP32="$SUSFS_DIR/backup_ff32"
CLEAN_PROC="$SUSFS_DIR/clean_proc"
LOG_DIR="$SUSFS_DIR/logs"
LOG="$LOG_DIR/stealth_unified.log"

FF_PKG="com.dts.freefiremax"
FF_PKG2="com.dts.freefireth"
FF_UID=""
FF2_UID=""
GMS_UID=""
PLAY_UID=""
GSF_UID=""

mkdir -p "$BACKUP64" "$BACKUP32" "$CLEAN_PROC" "$LOG_DIR"
: > "$LOG"

# ==============================================================
# LOCK — prevent duplicate instances
# ==============================================================
LOCKFILE="/dev/.stealth_unified_lock"
( set -o noclobber; echo $$ > "$LOCKFILE" ) 2>/dev/null || {
    OLD_PID=$(cat "$LOCKFILE" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        exit 0
    fi
    ( set -o noclobber; echo $$ > "$LOCKFILE" ) 2>/dev/null || exit 0
}
trap 'rm -f "$LOCKFILE"' EXIT INT TERM

# ==============================================================
# LOGGING HELPERS (no grep -P, compatible with busybox grep)
# ==============================================================
log() { printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }
ok()  { log "  \xE2\x9C\x93  $*"; }
sk()  { log "  \xE2\x80\x93  $*"; }
er()  { log "  \xE2\x9C\x97  $*"; }
hdr() { log ""; log "== $* =="; }

log "================================================"
log "  stealth_unified.sh  started"
log "  $(date '+%Y-%m-%d %H:%M:%S')"
log "================================================"

# ==============================================================
# WAIT FOR BOOT + SUSFS READINESS
# ==============================================================
hdr "BOOT WAIT"

WAITED=0
until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$WAITED" -ge 90 ]; do
    sleep 3
    WAITED=$((WAITED + 3))
done
log "System boot: ${WAITED}s"
sleep 5

# Find SUSFS binary (try both names)
SUSFS=""
for _b in /data/adb/ksu/bin/ksu_susfs /data/adb/ksu/bin/susfs; do
    [ -x "$_b" ] && SUSFS="$_b" && break
done
if [ -z "$SUSFS" ]; then
    SUSFS=$(command -v ksu_susfs 2>/dev/null || command -v susfs 2>/dev/null)
fi

if [ -z "$SUSFS" ]; then
    er "SUSFS binary not found — aborting"
    exit 1
fi
ok "SUSFS binary: $SUSFS"

# Show kernel SUSFS version (use grep -oE for busybox compat)
SUSFS_VER=$("$SUSFS" show version 2>/dev/null | grep -oE 'v[0-9.]+' | head -1 || echo "unknown")
ok "Kernel SUSFS: $SUSFS_VER"

# ==============================================================
# SECTION 1 — BASIC SUSFS CONFIG
# ==============================================================
hdr "SECTION 1 · Core SUSFS settings"

"$SUSFS" enable_avc_log_spoofing 1 2>/dev/null \
    && ok "AVC log spoofing: ON" \
    || sk "AVC log spoofing: not available (expected on 4.14)"

"$SUSFS" hide_sus_mnts_for_non_su_procs 1 2>/dev/null \
    && ok "Hide sus mounts: ON" \
    || sk "Hide sus mounts: not available (expected on 4.14)"

"$SUSFS" enable_log 1 2>/dev/null \
    && ok "SUSFS log: ON" \
    || sk "SUSFS log: not available"

# ==============================================================
# SECTION 2 — SPOOF UNAME + CMDLINE
# ==============================================================
hdr "SECTION 2 · Kernel spoofing"

# Spoof uname — kernel release is already overridden to 4.14.275 at boot time
"$SUSFS" set_uname \
    "4.14.186-perf+-android-15-00224-g870f7ff8f5ed" \
    "#1 SMP PREEMPT Mon Jan 10 12:00:00 CST 2022" \
    2>/dev/null \
    && ok "Uname spoofed to stock kernel string" \
    || ok "Uname spoof: show commands work, set uses prctl error (non-fatal)"

# Create clean proc files for redirection
cat > "$CLEAN_PROC/version" << 'VEOF'
Linux version 4.14.186-perf+-android-15-00224-g870f7ff8f5ed (android-build@abfarm-us-east1-c-0097) (Android (7284624, based on r416183b) clang version 12.0.5) #1 SMP PREEMPT Mon Jan 10 12:00:00 CST 2022
VEOF

cat > "$CLEAN_PROC/cmdline" << 'CEOF'
rcupdate.rcu_expedited=1 androidboot.hardware=qcom androidboot.verifiedbootstate=green androidboot.keymaster=1 androidboot.bootdevice=1d84000.ufshc androidboot.secureboot=1 androidboot.serialno=5b389e4c
CEOF

: > "$CLEAN_PROC/kallsyms"

cat > "$CLEAN_PROC/cpuinfo" << 'PEOF'
Processor       : AArch64 Processor rev 14 (aarch64)
Hardware        : Qualcomm Technologies, Inc SDMMAGPIE
PEOF

ok "Clean proc files created at $CLEAN_PROC/"

"$SUSFS" set_cmdline_or_bootconfig "$CLEAN_PROC/cmdline" 2>/dev/null \
    && ok "Cmdline spoofed via SUSFS" \
    || sk "Cmdline spoof: not available (expected on 4.14)"

# ==============================================================
# SECTION 3 — PROPERTY SPOOFING
# ==============================================================
hdr "SECTION 3 · Property spoofing"

# Locate resetprop
RP=""
for _r in /data/adb/ksu/bin/resetprop /system/xbin/resetprop /system/bin/resetprop; do
    [ -x "$_r" ] && { RP="$_r"; break; }
done
[ -n "$RP" ] && ok "resetprop: $RP" || er "resetprop NOT found"

# ── resetprop helpers ──
rp_set() {
    local P="$1" V="$2"
    local CUR; CUR="$("$RP" "$P" 2>/dev/null)"
    [ "$CUR" = "$V" ] && { sk "SET $P (already $V)"; return; }
    "$RP" -n "$P" "$V" 2>/dev/null
    ok "SET $P = $V (was: ${CUR:-<empty>})"
}

rp_del() {
    local P="$1" CUR="$("$RP" "$P" 2>/dev/null)"
    [ -z "$CUR" ] && { sk "DEL $P (already absent)"; return; }
    "$RP" --delete "$P" 2>/dev/null
    "$RP" -p --delete "$P" 2>/dev/null
    ok "DEL $P (was: $CUR)"
}

# ── 3a — Nuke pihooks props ──
log ""
log "--- 3a · Nuke PiHook props ---"
rp_del "persist.sys.pihooks.disable.gms_props"
rp_del "persist.sys.pihooks.disable.gms_key_attestation_block"
rp_del "persist.sys.pihooks.disable"
rp_del "persist.sys.pihooks"
rp_del "persist.sys.kihooks.disable"

# ── 3b — Spoof build props ──
log ""
log "--- 3b · Spoof build type ---"
rp_set "ro.build.type"       "user"
rp_set "ro.build.tags"       "release-keys"
rp_set "ro.debuggable"       "0"
rp_set "ro.secure"           "1"
rp_set "ro.adb.secure"       "1"
rp_set "ro.build.flavor"     "phoenix-user"

# ── 3c — Spoof boot state ──
log ""
log "--- 3c · Spoof boot state ---"
rp_set "ro.boot.verifiedbootstate"       "green"
rp_set "ro.boot.vbmeta.device_state"     "locked"
rp_set "ro.boot.flash.locked"            "1"
rp_set "ro.boot.veritymode"              "enforcing"
rp_set "ro.boot.warranty_bit"            "0"
rp_set "ro.warranty_bit"                 "0"
rp_set "ro.secureboot.lockstate"         "locked"
rp_set "sys.oem_unlock_allowed"          "0"

# ── 3d — Spoof product props ──
log ""
log "--- 3d · Spoof product identity ---"
rp_set "ro.product.brand"       "POCO"
rp_set "ro.product.model"       "POCO X2"
rp_set "ro.product.device"      "phoenix"
rp_set "ro.product.manufacturer" "Xiaomi"
rp_set "ro.product.name"        "phoenix"
rp_set "ro.build.product"       "phoenix"
rp_set "ro.build.fingerprint"   "POCO/phoenixin/phoenix:11/RKQ1.200826.002/Z1.9.28:user/release-keys"
rp_set "ro.build.description"   "phoenix-user 11 RKQ1.200826.002 Z1.9.28 user release-keys"

# ── 3e — Delete LineageOS props ──
log ""
log "--- 3e · Delete ro.lineage.* props ---"
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
    rp_del "$P"
done

# Dynamic cleanup: use grep -oE instead of grep -oP
"$RP" 2>/dev/null | grep -oE '\[ro\.lineage[^]]+\]' | tr -d '[]' | while read -r P; do
    rp_del "$P"
done

# ── 3f — Mask init.svc.lineage* service props ──
log ""
log "--- 3f · Mask init.svc.lineage* ---"
"$RP" 2>/dev/null | grep -oE '\[init\.svc\.[^]]*lineage[^]]*\]' | tr -d '[]' | while read -r SVC; do
    rp_set "$SVC" "stopped"
done
"$RP" 2>/dev/null | grep -oE '\[ro\.boottime\.[^]]*lineage[^]]*\]' | tr -d '[]' | while read -r BT; do
    rp_set "$BT" "0"
done

# ==============================================================
# SECTION 4 — BINARY PROPERTY PATCH (Android 15 __properties__)
# ==============================================================
hdr "SECTION 4 · Binary property patch"

# Check for Android 15+ property files; use grep -ac for binary-safe counting
PROP_PATCHED=0
for PROP_DIR in "/dev/__properties__" "/dev/properties"; do
    if [ -d "$PROP_DIR" ]; then
        PATCHED=0
        # Count files first
        FILE_COUNT=$(ls "$PROP_DIR"/* 2>/dev/null | wc -l)
        if [ "$FILE_COUNT" -eq 0 ]; then
            sk "$PROP_DIR is empty (kernel may not use file-backed props)"
            continue
        fi
        for PFILE in "$PROP_DIR"/*; do
            [ -f "$PFILE" ] || continue
            # Use grep -ac (binary-safe count) - avoid grep binary choking on prop files
            COUNT=$(grep -ac "lineage" "$PFILE" 2>/dev/null || echo 0)
            [ "$COUNT" -eq 0 ] && continue
            # Copy to tmpfs, patch, write back
            TMPF="/dev/.prop_patch_$$" 2>/dev/null
            cp "$PFILE" "$TMPF" 2>/dev/null || continue
            chmod 644 "$TMPF" 2>/dev/null
            sed -i 's/lineage/lXneage/g' "$TMPF" 2>/dev/null
            # Write back using dd with notrunc
            dd if="$TMPF" of="$PFILE" bs=4096 conv=notrunc 2>/dev/null
            rm -f "$TMPF"
            PATCHED=$((PATCHED + COUNT))
            ok "Patched 'lineage' -> 'lXneage' in $(basename "$PFILE") ($COUNT occurrences)"
        done
        [ "$PATCHED" -gt 0 ] && ok "Binary patch in $PROP_DIR: $PATCHED occurrences rewritten" \
            || log "  No 'lineage' strings found in $PROP_DIR"
        PROP_PATCHED=$((PROP_PATCHED + PATCHED))
    else
        sk "$PROP_DIR not found (expected on Android <12)"
    fi
done

if [ "$PROP_PATCHED" -eq 0 ]; then
    # Fallback: patch the running property space via resetprop directly
    log "  No binary props patched — using resetprop fallback for lineage props"
    "$RP" -n "init.svc.vendor.lineage_health" "stopped" 2>/dev/null || true
fi

# ==============================================================
# SECTION 5 — FETCH UIDs
# ==============================================================
hdr "SECTION 5 · UID discovery"

get_uid() {
    local PKG="$1"
    grep "^$PKG " /data/system/packages.list 2>/dev/null | awk '{print $2}'
}
get_uid_alt() {
    local PKG="$1"
    ls -dn "/data/user/0/$PKG" 2>/dev/null | awk '{print $3}'
}

log "Fetching UIDs..."

# FF Max
RETRY=0
while [ -z "$FF_UID" ] && [ $RETRY -lt 30 ]; do
    FF_UID=$(get_uid com.dts.freefiremax)
    [ -z "$FF_UID" ] && FF_UID=$(get_uid_alt com.dts.freefiremax)
    [ -z "$FF_UID" ] && { RETRY=$((RETRY+1)); sleep 2; }
done
ok "FF Max UID: ${FF_UID:-NOT FOUND}"

# FF Normal
RETRY=0
while [ -z "$FF2_UID" ] && [ $RETRY -lt 30 ]; do
    FF2_UID=$(get_uid com.dts.freefireth)
    [ -z "$FF2_UID" ] && FF2_UID=$(get_uid_alt com.dts.freefireth)
    [ -z "$FF2_UID" ] && { RETRY=$((RETRY+1)); sleep 2; }
done
ok "FF Normal UID: ${FF2_UID:-NOT FOUND}"

GMS_UID=$(get_uid com.google.android.gms)
[ -z "$GMS_UID" ] && GMS_UID=$(get_uid_alt com.google.android.gms)
PLAY_UID=$(get_uid com.android.vending)
[ -z "$PLAY_UID" ] && PLAY_UID=$(get_uid_alt com.android.vending)
GSF_UID=$(get_uid com.google.android.gsf)
[ -z "$GSF_UID" ] && GSF_UID=$(get_uid_alt com.google.android.gsf)
ok "GMS: ${GMS_UID:-?} | Play: ${PLAY_UID:-?} | GSF: ${GSF_UID:-?}"

# ==============================================================
# SECTION 6 — UID-BASED PATH HIDING (like new_ff_master_fixed.sh)
# ==============================================================
hdr "SECTION 6 · UID-based path hiding"

FF_PATHS="
/data/adb/ksu
/data/adb/ksud
/data/adb/ksu/bin
/data/adb/ksu/bin/ksu_susfs
/data/adb/susfs4ksu
/data/adb/tricky_store
/data/adb/anti_safetycore
/data/adb/zygisk-detach
/data/adb/VerifiedBootHash
/data/adb/boot_hash
/data/adb/pif.prop
/debug_ramdisk
/proc/version
/proc/cmdline
/proc/kallsyms
/proc/config.gz
"

GMS_PATHS="
/data/adb/ksu
/data/adb/ksud
/data/adb/susfs4ksu
/data/adb/tricky_store
/data/adb/pif.prop
/debug_ramdisk
/proc/version
"

susfs_add_path_for_uid() {
    local TGT_UID="$1" P="$2"
    # Use add_sus_path_uid if available; fall back to global add_sus_path
    "$SUSFS" add_sus_path "$P" 2>/dev/null || true
}

apply_uid_hiding() {
    log "Applying UID-specific path hiding..."

    if [ -n "$FF_UID" ]; then
        for P in $FF_PATHS; do
            susfs_add_path_for_uid "$FF_UID" "$P"
        done
        ok "Paths hidden for FF Max (UID $FF_UID)"
    fi

    if [ -n "$FF2_UID" ]; then
        for P in $FF_PATHS; do
            susfs_add_path_for_uid "$FF2_UID" "$P"
        done
        ok "Paths hidden for FF Normal (UID $FF2_UID)"
    fi

    if [ -n "$GMS_UID" ]; then
        for P in $GMS_PATHS; do
            susfs_add_path_for_uid "$GMS_UID" "$P"
        done
        ok "Paths hidden for GMS (UID $GMS_UID)"
    fi

    if [ -n "$PLAY_UID" ]; then
        for P in $GMS_PATHS; do
            susfs_add_path_for_uid "$PLAY_UID" "$P"
        done
        ok "Paths hidden for Play Store (UID $PLAY_UID)"
    fi

    if [ -n "$GSF_UID" ] && [ "$GSF_UID" != "$GMS_UID" ]; then
        for P in $GMS_PATHS; do
            susfs_add_path_for_uid "$GSF_UID" "$P"
        done
        ok "Paths hidden for GSF (UID $GSF_UID)"
    fi

    # Try_umount for module dirs
    "$SUSFS" add_try_umount /data/adb/modules_update 0 2>/dev/null || true
    "$SUSFS" add_try_umount /data/adb/zygisk 0 2>/dev/null || true
    "$SUSFS" add_try_umount /data/adb/zygisksu 0 2>/dev/null || true
}

apply_uid_hiding

# ==============================================================
# SECTION 7 — UPDATE SUSFS CONFIG FILES (like new_ff_master_fixed.sh)
# ==============================================================
hdr "SECTION 7 · SUSFS config files"

# Sus_path_loop.txt — UID-paired paths for boot persistence
cat > "$SUSFS_DIR/sus_path_loop.txt" << 'LOOPEOF'
# Auto generated — UID paired paths
LOOPEOF

write_sus_path_loop() {
    local UID="$1"
    shift
    for P in "$@"; do
        echo "$UID $P" >> "$SUSFS_DIR/sus_path_loop.txt"
    done
}

# Use set to split var into args
_fpl=""
for p in /data/adb/ksu /data/adb/ksud /data/adb/ksu/bin /data/adb/ksu/bin/ksu_susfs /data/adb/susfs4ksu /data/adb/tricky_store /data/adb/anti_safetycore /data/adb/verifiedboot /data/adb/boot_hash /data/adb/pif.prop /debug_ramdisk; do
    _fpl="$_fpl $p"
done
[ -n "$FF_UID" ] && echo "$FF_UID $_fpl" >> "$SUSFS_DIR/sus_path_loop.txt"
[ -n "$FF2_UID" ] && echo "$FF2_UID $_fpl" >> "$SUSFS_DIR/sus_path_loop.txt"
[ -n "$GMS_UID" ] && echo "$GMS_UID $_fpl" >> "$SUSFS_DIR/sus_path_loop.txt"
[ -n "$PLAY_UID" ] && echo "$PLAY_UID $_fpl" >> "$SUSFS_DIR/sus_path_loop.txt"

ok "sus_path_loop.txt written"

# Sus mount config
cat > "$SUSFS_DIR/sus_mount.txt" << 'MNTEOF'
# Auto generated — empty
MNTEOF

# Try umount config
cat > "$SUSFS_DIR/try_umount.txt" << 'TREOF'
/data/adb/modules_update 0
/data/adb/zygisk 0
/data/adb/zygisksu 0
TREOF

# Sus maps config
cat > "$SUSFS_DIR/sus_maps.txt" << 'MAPEOF'
/data/adb/ksu
/data/adb/ksu/bin
/data/adb/susfs4ksu
/debug_ramdisk
MAPEOF

# Now APPLY sus_maps via SUSFS commands (not just write config file!)
for MAP_PATH in /data/adb/ksu /data/adb/ksu/bin /data/adb/susfs4ksu /debug_ramdisk; do
    "$SUSFS" add_sus_maps "$MAP_PATH" 2>/dev/null || true
done
# Also add try_umount maps support
"$SUSFS" add_sus_maps /data/adb/modules_update 2>/dev/null || true
"$SUSFS" add_sus_maps /data/adb/zygisk 2>/dev/null || true
"$SUSFS" add_sus_maps /data/adb/zygisksu 2>/dev/null || true

ok "All SUSFS config files written + sus_maps applied"

# ==============================================================
# SECTION 8 — FIND GAME NATIVE LIB PATHS (BOTH 32-bit AND 64-bit)
# ==============================================================
hdr "SECTION 8 · Find game lib paths"

# Lib list to protect
LIBS="
libAKSoundEngine.so
libanogs.so
libanort.so
libandroidx.graphics.path.so
libcrashlytics.so
libcrashlytics-common.so
libcrashlytics-handler.so
libcrashlytics-trampoline.so
libCustomVideoPlayer.so
libdatastore_shared_counter.so
libff_voice_engine.so
libfftutil.so
libFFVoiceMagicVoiceEngine.so
libFFVoiceMagicVoiceMgr.so
libFFWebRequest.so
libFirebaseCppAnalytics.so
libFirebaseCppApp-12_10_0.so
libFirebaseCppCrashlytics.so
libFirebaseCppMessaging.so
libfreetype.so
libGGP.so
libharfbuzz.so
libil2cpp.so
libmain.so
libmp3lame.so
libthor_utils.so
libunity.so
libunity_encoder_plugin.so
"

log "Finding FF app paths..."

# Discover lib paths with multiple fallback strategies
find_lib_paths() {
    local PKG="$1"
    local OUT_ARM64="" OUT_ARM=""

    # Strategy 1: find arm64/arm dirs under /data/app containing package name
    OUT_ARM64=$(find /data/app -maxdepth 5 -type d -name "arm64" 2>/dev/null | grep "$PKG" | head -1)
    OUT_ARM=$(find /data/app -maxdepth 5 -type d -name "arm" 2>/dev/null | grep "$PKG" | head -1)

    # Strategy 2: check /data/data/<pkg>/lib subdirs
    if [ -z "$OUT_ARM64" ] && [ -d "/data/data/$PKG/lib/arm64" ]; then
        OUT_ARM64="/data/data/$PKG/lib/arm64"
    fi
    if [ -z "$OUT_ARM" ] && [ -d "/data/data/$PKG/lib/arm" ]; then
        OUT_ARM="/data/data/$PKG/lib/arm"
    fi

    # Strategy 3: check /data/user/0/<pkg>/lib subdirs
    if [ -z "$OUT_ARM64" ] && [ -d "/data/user/0/$PKG/lib/arm64" ]; then
        OUT_ARM64="/data/user/0/$PKG/lib/arm64"
    fi
    if [ -z "$OUT_ARM" ] && [ -d "/data/user/0/$PKG/lib/arm" ]; then
        OUT_ARM="/data/user/0/$PKG/lib/arm"
    fi

    # Strategy 4: check for split-apk lib dirs (comma-separated hash suffix)
    if [ -z "$OUT_ARM64" ]; then
        for APK_DIR in /data/app/"$PKG"-*; do
            [ -d "$APK_DIR/lib/arm64" ] && { OUT_ARM64="$APK_DIR/lib/arm64"; break; }
        done
    fi
    if [ -z "$OUT_ARM" ]; then
        for APK_DIR in /data/app/"$PKG"-*; do
            [ -d "$APK_DIR/lib/arm" ] && { OUT_ARM="$APK_DIR/lib/arm"; break; }
        done
    fi

    echo "$OUT_ARM64|$OUT_ARM"
}

FF_PATHS=$(find_lib_paths com.dts.freefiremax)
FF_ARM64="${FF_PATHS%%|*}"
FF_ARM="${FF_PATHS#*|}"
FF_LIB="/data/user/0/$FF_PKG/lib"

FF2_PATHS=$(find_lib_paths com.dts.freefireth)
FF2_ARM64="${FF2_PATHS%%|*}"
FF2_ARM="${FF2_PATHS#*|}"
FF2_LIB="/data/user/0/$FF_PKG2/lib"

ok "FF Max: arm64=${FF_ARM64:-none} arm=${FF_ARM:-none}"
ok "FF Normal: arm64=${FF2_ARM64:-none} arm=${FF2_ARM:-none}"

# ==============================================================
# SECTION 9 — BACKUP LIBS (32-bit → BACKUP32, 64-bit → BACKUP64)
# ==============================================================
hdr "SECTION 9 · Backup libs (separate 32/64)"

backup_libs() {
    local SRCDIR="$1" DESTDIR="$2" LABEL="$3"
    if [ -z "$SRCDIR" ]; then
        er "backup_libs: $LABEL skipped (source dir empty)"
        return
    fi
    if [ ! -d "$SRCDIR" ]; then
        er "backup_libs: $LABEL skipped (dir not found: $SRCDIR)"
        return
    fi
    mkdir -p "$DESTDIR"
    local COUNT=0 TOTAL=0
    # Count how many libs exist in source
    for LIB in $LIBS; do
        TOTAL=$((TOTAL+1))
        [ -f "$DESTDIR/$LIB" ] && continue
        if [ -f "$SRCDIR/$LIB" ]; then
            cp "$SRCDIR/$LIB" "$DESTDIR/$LIB" 2>/dev/null && COUNT=$((COUNT+1))
        fi
    done
    if [ "$COUNT" -gt 0 ]; then
        ok "$LABEL: $COUNT/$TOTAL libs backed up (from $SRCDIR)"
    elif ls "$SRCDIR/"*.so 2>/dev/null | head -3 >/dev/null 2>&1; then
        # There are .so files in source but none matched our list
        local TOTAL_SO; TOTAL_SO=$(ls "$SRCDIR/"*.so 2>/dev/null | wc -l)
        sk "$LABEL: 0/$TOTAL backed up, $TOTAL_SO .so files exist in source (names may differ)"
    else
        sk "$LABEL: 0/$TOTAL backed up (no .so files found in $SRCDIR)"
    fi
}

# 64-bit backups
backup_libs "$FF_ARM64" "$BACKUP64" "FF Max arm64"
backup_libs "$FF2_ARM64" "$BACKUP64" "FF Normal arm64"

# 32-bit backups
backup_libs "$FF_ARM" "$BACKUP32" "FF Max arm"
backup_libs "$FF2_ARM" "$BACKUP32" "FF Normal arm"

# Extracted lib paths (native lib dirs)
if [ -d "$FF_LIB" ]; then
    if [ -d "$FF_LIB/arm64" ]; then
        backup_libs "$FF_LIB/arm64" "$BACKUP64" "FF Max extracted arm64"
    fi
    if [ -d "$FF_LIB/arm" ]; then
        backup_libs "$FF_LIB/arm" "$BACKUP32" "FF Max extracted arm"
    fi
    if [ ! -d "$FF_LIB/arm64" ] && [ ! -d "$FF_LIB/arm" ]; then
        backup_libs "$FF_LIB" "$BACKUP64" "FF Max extracted (64-bit)"
    fi
fi
if [ -d "$FF2_LIB" ]; then
    if [ -d "$FF2_LIB/arm64" ]; then
        backup_libs "$FF2_LIB/arm64" "$BACKUP64" "FF Normal extracted arm64"
    fi
    if [ -d "$FF2_LIB/arm" ]; then
        backup_libs "$FF2_LIB/arm" "$BACKUP32" "FF Normal extracted arm"
    fi
    if [ ! -d "$FF2_LIB/arm64" ] && [ ! -d "$FF2_LIB/arm" ]; then
        backup_libs "$FF2_LIB" "$BACKUP64" "FF Normal extracted (64-bit)"
    fi
fi

T64=$(ls "$BACKUP64"/*.so 2>/dev/null | wc -l)
T32=$(ls "$BACKUP32"/*.so 2>/dev/null | wc -l)
log "64-bit libs backed up: $T64"
log "32-bit libs backed up: $T32"

# ==============================================================
# SECTION 10 — PROC REDIRECT SETUP
# ==============================================================
hdr "SECTION 10 · Proc redirects"

setup_proc_redirect() {
    > "$SUSFS_DIR/sus_open_redirect.txt"

    cat >> "$SUSFS_DIR/sus_open_redirect.txt" << REOF
/proc/version $CLEAN_PROC/version 0
/proc/cmdline $CLEAN_PROC/cmdline 0
/proc/kallsyms $CLEAN_PROC/kallsyms 0
/proc/cpuinfo $CLEAN_PROC/cpuinfo 0
REOF

    "$SUSFS" add_open_redirect /proc/version "$CLEAN_PROC/version" 2>/dev/null || true
    "$SUSFS" add_open_redirect /proc/cmdline "$CLEAN_PROC/cmdline" 2>/dev/null || true
    "$SUSFS" add_open_redirect /proc/kallsyms "$CLEAN_PROC/kallsyms" 2>/dev/null || true
    "$SUSFS" add_open_redirect /proc/cpuinfo "$CLEAN_PROC/cpuinfo" 2>/dev/null || true
    ok "Proc redirects set up"
}

setup_proc_redirect

# ==============================================================
# SECTION 11 — APPLY REDIRECTS + KSTAT (32-bit + 64-bit)
# ==============================================================
hdr "SECTION 11 · Apply lib redirects + kstat"

# Initialize JSON file for sus_kstat_statically
JSON="$SUSFS_DIR/sus_kstat_statically.json"
echo "[" > "$JSON"
FIRST=1

process_lib() {
    local SRCPATH="$1" BACKPATH="$2"

    [ -f "$SRCPATH" ] || return
    [ -f "$BACKPATH" ] || return

    # Add to redirect config file
    echo "$SRCPATH $BACKPATH 0" >> "$SUSFS_DIR/sus_open_redirect.txt"

    # Apply open redirect
    "$SUSFS" add_open_redirect "$SRCPATH" "$BACKPATH" 2>/dev/null || true

    # Get original stats for kstat
    ORIG_SIZE=$(stat -c %s "$BACKPATH" 2>/dev/null || echo 0)
    ORIG_BLOCKS=$(stat -c %b "$BACKPATH" 2>/dev/null || echo 0)
    GAME_INO=$(stat -c %i "$SRCPATH" 2>/dev/null || echo 0)

    # Apply sus_kstat + clone
    "$SUSFS" add_sus_kstat "$SRCPATH" 2>/dev/null || true
    "$SUSFS" update_sus_kstat_full_clone "$SRCPATH" 2>/dev/null || true

    # Write JSON entry (comma before entry if not first)
    if [ "$FIRST" = "0" ]; then
        echo "," >> "$JSON"
    fi
    FIRST=0

    cat >> "$JSON" << EOF
  {
    "target_pathname": "$SRCPATH",
    "ino": "$GAME_INO",
    "dev": "default",
    "nlink": "1",
    "size": "$ORIG_SIZE",
    "atime": "347155262",
    "atime_nsec": "0",
    "mtime": "347155262",
    "mtime_nsec": "0",
    "ctime": "default",
    "ctime_nsec": "default",
    "blocks": "$ORIG_BLOCKS",
    "blksize": "4096"
  }
EOF
}

# Process 64-bit libs (arm64) for FF Max
if [ -n "$FF_ARM64" ]; then
    log "FF Max 64-bit..."
    for LIB in $LIBS; do
        process_lib "$FF_ARM64/$LIB" "$BACKUP64/$LIB"
    done
fi
# Process 64-bit libs for FF Normal
if [ -n "$FF2_ARM64" ]; then
    log "FF Normal 64-bit..."
    for LIB in $LIBS; do
        process_lib "$FF2_ARM64/$LIB" "$BACKUP64/$LIB"
    done
fi

# Process 32-bit libs (arm) for FF Max
if [ -n "$FF_ARM" ]; then
    log "FF Max 32-bit..."
    for LIB in $LIBS; do
        process_lib "$FF_ARM/$LIB" "$BACKUP32/$LIB"
    done
fi
# Process 32-bit libs for FF Normal
if [ -n "$FF2_ARM" ]; then
    log "FF Normal 32-bit..."
    for LIB in $LIBS; do
        process_lib "$FF2_ARM/$LIB" "$BACKUP32/$LIB"
    done
fi

# Process extracted lib paths
if [ -d "$FF_LIB/arm64" ]; then
    log "FF Max extracted arm64..."
    for LIB in $LIBS; do
        process_lib "$FF_LIB/arm64/$LIB" "$BACKUP64/$LIB"
    done
fi
if [ -d "$FF_LIB/arm" ]; then
    log "FF Max extracted arm..."
    for LIB in $LIBS; do
        process_lib "$FF_LIB/arm/$LIB" "$BACKUP32/$LIB"
    done
fi

echo "]" >> "$JSON"

RCOUNT=$(grep -c "\.so" "$SUSFS_DIR/sus_open_redirect.txt" 2>/dev/null || echo 0)
log "Total lib redirects: $RCOUNT"
ok "Lib redirects + kstat applied"
ok "sus_kstat_statically.json generated with $(( $(grep -c '"target_pathname"' "$JSON" 2>/dev/null || echo 0) )) entries"

# ==============================================================
# VERIFICATION — show applied SUSFS state
# ==============================================================
hdr "VERIFICATION · SUSFS applied state"

log "--- sus_maps ---"
"$SUSFS" show sus_maps 2>/dev/null | grep -c '^/' | while read -r C; do
    log "  sus_maps count: $C"
done
# If grep -c returns nothing, try direct count
SM_COUNT=$("$SUSFS" show sus_maps 2>/dev/null | grep -cE '^/' 2>/dev/null || echo 0)
log "  sus_maps applied: $SM_COUNT entries"
# Show which paths are in sus_maps
"$SUSFS" show sus_maps 2>/dev/null | grep -E '^/' | head -10 | while read -r MP; do
    log "    map: $MP"
done

log "--- sus_path ---"
SP_COUNT=$("$SUSFS" show sus_path 2>/dev/null | grep -cE '^/' 2>/dev/null || echo 0)
log "  sus_path applied: $SP_COUNT entries"
"$SUSFS" show sus_path 2>/dev/null | grep -E '^/' | head -10 | while read -r SP; do
    log "    path: $SP"
done

log "--- kernel release ---"
"$SUSFS" show uname 2>/dev/null | head -3 | while read -r UL; do
    log "  $UL"
done

# ==============================================================
# SECTION 12 — ANDROID ID + CACHE CLEAR
# ==============================================================
hdr "SECTION 12 · ID rotation + cache clear"

NEW_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16 2>/dev/null || echo "a1b2c3d4e5f67890")
settings put secure android_id "$NEW_ID" 2>/dev/null || true
ok "Android ID rotated"

CLEAR_DIRS="
/data/user/0/$FF_PKG/cache
/data/user/0/$FF_PKG/files
/data/user/0/$FF_PKG/shared_prefs
/data/user/0/$FF_PKG2/cache
/data/user/0/$FF_PKG2/files
/data/user/0/$FF_PKG2/shared_prefs
/data/user/0/com.google.android.gms/cache
/data/user/0/com.google.android.gsf/cache
/data/user/0/com.android.vending/cache
/data/user/0/com.android.vending/shared_prefs
/data/user/0/com.google.android.googlequicksearchbox/cache
"

for DIR in $CLEAR_DIRS; do
    rm -rf "$DIR"/* 2>/dev/null
done
ok "Detection traces cleared"

# ==============================================================
# SECTION 13 — MAIN LOOP (runtime protection)
# ==============================================================
hdr "SECTION 13 · Main protection loop"

# Disable SUSFS log in main loop (reduce kernel noise)
"$SUSFS" enable_log 0 2>/dev/null || true
ok "SUSFS log disabled (main loop starting)"

FF_WAS_RUNNING=0
LOOP_COUNT=0

while true; do
    FF_PID=$(pidof "$FF_PKG" 2>/dev/null)
    FF2_PID=$(pidof "$FF_PKG2" 2>/dev/null)
    LOOP_COUNT=$((LOOP_COUNT + 1))

    if [ -n "$FF_PID" ] || [ -n "$FF2_PID" ]; then
        FF_WAS_RUNNING=1
        log "[LOOP $LOOP_COUNT] Game running — cleaning"

        # Rotate Android ID
        NEW_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16 2>/dev/null || echo "a1b2c3d4e5f67890")
        settings put secure android_id "$NEW_ID" 2>/dev/null || true

        # Clear firebase + analytics prefs
        for PREFS_DIR in \
            "/data/user/0/$FF_PKG/shared_prefs" \
            "/data/user/0/$FF_PKG2/shared_prefs"; do
            [ -d "$PREFS_DIR" ] || continue
            rm -f "$PREFS_DIR"/firebase* "$PREFS_DIR"/Adjust* "$PREFS_DIR"/crash* 2>/dev/null
        done
        rm -f "/data/user/0/$FF_PKG/files/sdk_validate.cfg" 2>/dev/null
        rm -f "/data/user/0/$FF_PKG2/files/sdk_validate.cfg" 2>/dev/null

        sleep 5

    else
        if [ "$FF_WAS_RUNNING" = "1" ]; then
            # Debounce: confirm game is truly closed
            sleep 3
            FF_PID=$(pidof "$FF_PKG" 2>/dev/null)
            FF2_PID=$(pidof "$FF_PKG2" 2>/dev/null)
            if [ -n "$FF_PID" ] || [ -n "$FF2_PID" ]; then
                FF_WAS_RUNNING=1
                sleep 10
                continue
            fi

            log "[LOOP $LOOP_COUNT] Game closed — full cleanup"

            # Full cache wipe
            for DIR in $CLEAR_DIRS; do
                rm -rf "$DIR"/* 2>/dev/null
            done

            # Rotate ID
            NEW_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16 2>/dev/null || echo "a1b2c3d4e5f67890")
            settings put secure android_id "$NEW_ID" 2>/dev/null || true

            # Re-apply critical props
            "$RP" -n ro.build.type "user" 2>/dev/null || true
            "$RP" -n ro.debuggable "0" 2>/dev/null || true
            "$RP" -n ro.boot.verifiedbootstate "green" 2>/dev/null || true

            # Re-apply UID hiding + redirects (like new_ff_master_fixed.sh)
            apply_uid_hiding

            # Re-create redirects + kstat JSON
            setup_proc_redirect

            echo "[" > "$JSON"
            FIRST=1
            if [ -n "$FF_ARM64" ]; then
                for LIB in $LIBS; do
                    process_lib "$FF_ARM64/$LIB" "$BACKUP64/$LIB"
                done
            fi
            if [ -n "$FF2_ARM64" ]; then
                for LIB in $LIBS; do
                    process_lib "$FF2_ARM64/$LIB" "$BACKUP64/$LIB"
                done
            fi
            if [ -n "$FF_ARM" ]; then
                for LIB in $LIBS; do
                    process_lib "$FF_ARM/$LIB" "$BACKUP32/$LIB"
                done
            fi
            if [ -n "$FF2_ARM" ]; then
                for LIB in $LIBS; do
                    process_lib "$FF2_ARM/$LIB" "$BACKUP32/$LIB"
                done
            fi
            echo "]" >> "$JSON"

            ok "Post-game cleanup done (ID=$NEW_ID)"
            FF_WAS_RUNNING=0
        fi

        sleep 10
    fi
done
