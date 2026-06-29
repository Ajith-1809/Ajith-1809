#!/system/bin/sh
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  stealth_unified.sh  —  Consolidated SUSFS stealth script          ║
# ║  Device   : POCO X2 (Phoenix) | LineageOS | KernelSU-Next          ║
# ║  SUSFS    : v1.5.5 (ABI: sys_reboot) — NON-GKI kernel-4.14        ║
# ║  Author   : Generated for Ajithkumar                               ║
# ║                                                                    ║
# ║  Combines all 5 scripts into 1 with full SUSFS coverage:          ║
# ║    • new_ff_master_fixed.sh — game lib hiding + main loop         ║
# ║    • spoof_detections.sh — prop spoofing                          ║
# ║    • milltina_defeat.sh — hard prop nuke + flags                  ║
# ║    • fix_lineage_service_list.sh — binary prop patch              ║
# ║    • fix_inode_inconsistency.sh — sus_kstat + maps                ║
# ║                                                                    ║
# ║  Deploy : /data/adb/service.d/stealth_unified.sh                  ║
# ║  Perms  : chmod 755                                               ║
# ║  Logs   : /data/adb/Box-Brain/Integrity-Box-Logs/stealth_*.log    ║
# ╚══════════════════════════════════════════════════════════════════════╝

export PATH=$PATH:/data/adb/ksu/bin:/system/bin:/system/xbin

# ==============================================================
# CONFIGURATION
# ==============================================================
SUSFS_DIR="/data/adb/susfs4ksu"
BACKUP="$SUSFS_DIR/backup_ff"
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

mkdir -p "$BACKUP" "$BACKUP32" "$CLEAN_PROC" "$LOG_DIR"
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
# LOGGING HELPERS
# ==============================================================
log() { printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }
ok()  { log "  ✓  $*"; }
sk()  { log "  –  $*"; }
er()  { log "  ✗  $*"; }
hdr() { log ""; log "━━ $* ━━"; }

log "╔═══════════════════════════════════════════════════╗"
log "║  stealth_unified.sh  started                      ║"
log "║  $(date '+%Y-%m-%d %H:%M:%S')                                ║"
log "╚═══════════════════════════════════════════════════╝"

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

# Extra wait for property area to settle
sleep 5

# Verify SUSFS binary is functional
SUSFS=""
for _b in /data/adb/ksu/bin/ksu_susfs /data/adb/ksu/bin/susfs $(command -v ksu_susfs 2>/dev/null); do
    [ -x "$_b" ] && SUSFS="$_b" && break
done

if [ -z "$SUSFS" ]; then
    er "SUSFS binary not found — aborting"
    exit 1
fi
ok "SUSFS binary: $SUSFS"

# Check kernel SUSFS version
SUSFS_VER=$("$SUSFS" show version 2>/dev/null | grep -oP 'v[\d.]+' || echo "unknown")
ok "Kernel SUSFS: $SUSFS_VER"

# ==============================================================
# SECTION 1 — BASIC SUSFS CONFIG
# ==============================================================
hdr "SECTION 1 · Core SUSFS settings"

# Enable AVC log spoofing (hide avc denial messages that leak sus context)
"$SUSFS" enable_avc_log_spoofing 1 2>/dev/null \
    && ok "AVC log spoofing: ON" \
    || sk "AVC log spoofing: not available"

# Hide sus mounts for non-su processes (blocks zygote caching)
"$SUSFS" hide_sus_mnts_for_non_su_procs 1 2>/dev/null \
    && ok "Hide sus mounts: ON" \
    || sk "Hide sus mounts: not available"

# Enable SUSFS logging for debugging (set to 0 after testing)
"$SUSFS" enable_log 1 2>/dev/null \
    && ok "SUSFS log: ON" \
    || sk "SUSFS log: not available"

# ==============================================================
# SECTION 2 — SPOOF UNAME + CMDLINE
# ==============================================================
hdr "SECTION 2 · Kernel spoofing"

# Spoof uname to a stock-like kernel string
# Format: set_uname <release> <version>
# Using a clean Pixel-style kernel string to avoid suspicion
"$SUSFS" set_uname \
    "4.14.186-perf+-android-15-00224-g870f7ff8f5ed" \
    "#1 SMP PREEMPT Mon Jan 10 12:00:00 CST 2022" \
    2>/dev/null \
    && ok "Uname spoofed to stock kernel string" \
    || er "Uname spoof failed"

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

# Set cmdline via SUSFS spoof_cmdline
"$SUSFS" set_cmdline_or_bootconfig "$CLEAN_PROC/cmdline" 2>/dev/null \
    && ok "Cmdline spoofed via SUSFS" \
    || sk "Cmdline spoof: not available"

# ==============================================================
# SECTION 3 — PROPERTY SPOOFING
# ==============================================================
hdr "SECTION 3 · Property spoofing"

# Locate resetprop
RP=""
for _r in \
    /data/adb/ksu/bin/resetprop \
    /data/adb/magisk/resetprop \
    /sbin/resetprop \
    /system/xbin/resetprop \
    /system/bin/resetprop; do
    [ -x "$_r" ] && { RP="$_r"; break; }
done
[ -n "$RP" ] && ok "resetprop: $RP" || er "resetprop NOT found"

# ── resetprop helpers ──
rp_set() {
    local P="$1" V="$2"
    local CUR; CUR="$("$RP" "$P" 2>/dev/null)"
    [ "$CUR" = "$V" ] && { sk "SET $P (already $V)"; return; }
    "$RP" -n "$P" "$V" 2>/dev/null
    local AFTER; AFTER="$("$RP" "$P" 2>/dev/null)"
    ok "SET $P = $V (was: ${CUR:-<empty>}, now: ${AFTER:-<empty>})"
}

rp_del() {
    local P="$1" CUR="$("$RP" "$P" 2>/dev/null)"
    [ -z "$CUR" ] && { sk "DEL $P (already absent)"; return; }
    "$RP" --delete "$P" 2>/dev/null
    "$RP" -p --delete "$P" 2>/dev/null
    local AFTER; AFTER="$("$RP" "$P" 2>/dev/null)"
    [ -z "$AFTER" ] && ok "DEL $P (was: $CUR)" \
                     || ok "DEL $P → blanked (was: $CUR)"
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

# Dynamic cleanup for remaining ro.lineage.*
"$RP" 2>/dev/null | grep -oP '(?<=\[)ro\.lineage[^\]]+(?=\])' | while read -r P; do
    rp_del "$P"
done

# ── 3f — Mask init.svc.lineage* service props ──
log ""
log "--- 3f · Mask init.svc.lineage* ---"
"$RP" 2>/dev/null | grep -oP '(?<=\[)[^\]]*lineage[^\]]*(?=\])' | grep '^init\.svc\.' | while read -r SVC; do
    rp_set "$SVC" "stopped"
done
"$RP" 2>/dev/null | grep -oP '(?<=\[)[^\]]*lineage[^\]]*(?=\])' | grep '^ro\.boottime\.' | while read -r BT; do
    rp_set "$BT" "0"
done

# ==============================================================
# SECTION 4 — BINARY PROPERTY PATCH (remove "lineage" from /dev/properties/)
# ==============================================================
hdr "SECTION 4 · Binary property patch"

# Strategy: replace "lineage" -> "lXneage" in property area mmap files
# Android 15 stores properties in /dev/__properties__/ (not /dev/properties/).

# Try both known property storage paths
for PROP_DIR in "/dev/__properties__" "/dev/properties"; do
    if [ -d "" ]; then
        PATCHED=0
        for PFILE in ""/*; do
            [ -f "" ] || continue

            # Find and patch all "lineage" occurrences
            COUNT=0
            [ "" -eq 0 ] && continue

            # Use sed for in-place binary patch (replace 'lineage' with 'lXneage')
            TMPF=$(mktemp) || continue
            cp "" "" 2>/dev/null || { rm -f ""; continue; }

            # Replace byte-for-byte (same length, no offset change)
            sed -i 's/lineage/lXneage/g' "" 2>/dev/null

            # Write back to original (overwrite via dd to preserve mmap)
            dd if="" of="" bs=4096 conv=notrunc 2>/dev/null
            rm -f ""
            PATCHED=$((PATCHED + COUNT))
            ok "Patched  'lineage' -> 'lXneage' in $(basename "")"
        done
        [ "" -gt 0 ] && ok "Binary patch ():  occurrences rewritten"                              || log "  No 'lineage' strings found in "
    else
        sk " not found"
    fi
donemkdir -p /data/adb/Box-Brain
touch /data/adb/Box-Brain/NoLineageProp 2>/dev/null
touch /data/adb/Box-Brain/nodebug 2>/dev/null
touch /data/adb/Box-Brain/tag 2>/dev/null
ok "Integrity-Box flags set"

# ==============================================================
# SECTION 5 — FETCH UIDs
# ==============================================================
hdr "SECTION 5 · UID discovery"

get_uid() {
    local PKG="$1"
    grep "^$PKG " /data/system/packages.list 2>/dev/null | awk '{print $2}'
}

# Alternative UID lookup (for newer Android where packages.list has different format)
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

# Google services
GMS_UID=$(get_uid com.google.android.gms)
[ -z "$GMS_UID" ] && GMS_UID=$(get_uid_alt com.google.android.gms)
PLAY_UID=$(get_uid com.android.vending)
[ -z "$PLAY_UID" ] && PLAY_UID=$(get_uid_alt com.android.vending)
GSF_UID=$(get_uid com.google.android.gsf)
[ -z "$GSF_UID" ] && GSF_UID=$(get_uid_alt com.google.android.gsf)
ok "GMS: ${GMS_UID:-?} | Play: ${PLAY_UID:-?} | GSF: ${GSF_UID:-?}"

# ==============================================================
# SECTION 6 — GLOBAL add_sus_path (works for ALL uid>=10000 process)
# ==============================================================
hdr "SECTION 6 · SUSFS path hiding"

# NOTE: add_sus_path applies to ALL umounted processes with uid >= 10000
# This covers both FF Max and FF Normal automatically.
# The old script's add_sus_path_for_uid does NOT exist — we use add_sus_path globally.

add_sus_path() {
    local P="$1"
    [ -e "$P" ] || return
    "$SUSFS" add_sus_path "$P" 2>/dev/null \
        && ok "sus_path  → $P" \
        || sk "sus_path  → $P (already set or invalid)"
}

# ── Critical paths for game and GMS apps ──
log ""
log "--- Paths for all apps (uid>=10000) ---"

# Root detection paths
for P in \
    /data/adb/ksu \
    /data/adb/ksu/bin \
    /data/adb/susfs4ksu \
    /data/adb/tricky_store \
    /data/adb/anti_safetycore \
    /data/adb/zygisk-detach \
    /data/adb/VerifiedBootHash \
    /data/adb/boot_hash \
    /data/adb/pif.prop \
    /data/adb/modules \
    /data/adb/modules_update \
    /data/adb/zygisk \
    /data/adb/zygisksu \
    /data/adb/service.d \
    /data/adb/Box-Brain \
    /debug_ramdisk; do
    add_sus_path "$P"
done

# Proc paths
for P in \
    /proc/version \
    /proc/cmdline \
    /proc/kallsyms \
    /proc/config.gz \
    /proc/net; do
    [ -e "$P" ] && add_sus_path "$P"
done

# System prop paths
for P in \
    /system/build.prop \
    /system/etc/prop.default; do
    [ -e "$P" ] && add_sus_path "$P"
done

# ==============================================================
# SECTION 7 — TRY_UMOUNT for module directories
# ==============================================================
hdr "SECTION 7 · Try umount module dirs"

"$SUSFS" add_try_umount /data/adb/modules_update 0 2>/dev/null \
    && ok "try_umount → /data/adb/modules_update" || sk "try_umount → already set"
"$SUSFS" add_try_umount /data/adb/zygisk 0 2>/dev/null \
    && ok "try_umount → /data/adb/zygisk" || sk "try_umount → already set"
"$SUSFS" add_try_umount /data/adb/zygisksu 0 2>/dev/null \
    && ok "try_umount → /data/adb/zygisksu" || sk "try_umount → already set"

# ==============================================================
# SECTION 8 — OPEN_REDIRECT for /proc/
# ==============================================================
hdr "SECTION 8 · Open redirect /proc/ files"

"$SUSFS" add_open_redirect /proc/version "$CLEAN_PROC/version" 2>/dev/null \
    && ok "redirect  → /proc/version" || sk "redirect  → /proc/version (already set)"
"$SUSFS" add_open_redirect /proc/cmdline "$CLEAN_PROC/cmdline" 2>/dev/null \
    && ok "redirect  → /proc/cmdline" || sk "redirect  → /proc/cmdline (already set)"
"$SUSFS" add_open_redirect /proc/kallsyms "$CLEAN_PROC/kallsyms" 2>/dev/null \
    && ok "redirect  → /proc/kallsyms" || sk "redirect  → /proc/kallsyms (already set)"
"$SUSFS" add_open_redirect /proc/cpuinfo "$CLEAN_PROC/cpuinfo" 2>/dev/null \
    && ok "redirect  → /proc/cpuinfo" || sk "redirect  → /proc/cpuinfo (already set)"

# Also add redirects to sus_open_redirect.txt for boot-completed.sh persistence
mkdir -p "$SUSFS_DIR"
cat > "$SUSFS_DIR/sus_open_redirect.txt" << REOF
/proc/version $CLEAN_PROC/version 0
/proc/cmdline $CLEAN_PROC/cmdline 0
/proc/kallsyms $CLEAN_PROC/kallsyms 0
/proc/cpuinfo $CLEAN_PROC/cpuinfo 0
REOF
ok "sus_open_redirect.txt written"

# ==============================================================
# SECTION 9 — WRITE SUSFS CONFIG FILES
# ==============================================================
hdr "SECTION 9 · SUSFS config files"

# sus_maps.txt — hide injected libs from /proc/*/maps
# (kernel v1.5.5 uses sus_path as backend for sus_maps)
cat > "$SUSFS_DIR/sus_maps.txt" << 'MSEOF'
/data/adb/ksu
/data/adb/ksu/bin
/data/adb/susfs4ksu
/debug_ramdisk
/data/adb/tricky_store
/data/adb/pif.prop
MSEOF
ok "sus_maps.txt written"

# sus_path.txt — global paths (processed by boot-completed.sh)
cat > "$SUSFS_DIR/sus_path.txt" << 'PSEOF'
/data/adb/ksu 0
/data/adb/ksu/bin 0
/data/adb/susfs4ksu 0
/data/adb/tricky_store 0
/data/adb/anti_safetycore 0
/data/adb/zygisk-detach 0
/data/adb/VerifiedBootHash 0
/data/adb/boot_hash 0
/data/adb/pif.prop 0
/data/adb/modules 0
/data/adb/modules_update 0
/data/adb/zygisk 0
/data/adb/zygisksu 0
/data/adb/service.d 0
/debug_ramdisk 0
/proc/version 0
/proc/cmdline 0
/proc/kallsyms 0
/proc/config.gz 0
PSEOF
ok "sus_path.txt written"

# try_umount.txt
cat > "$SUSFS_DIR/try_umount.txt" << 'TREOF'
/data/adb/modules_update 0
/data/adb/zygisk 0
/data/adb/zygisksu 0
TREOF
ok "try_umount.txt written"

# ==============================================================
# SECTION 10 — GAME LIB BACKUP + REDIRECT + KSTAT
# ==============================================================
hdr "SECTION 10 · Game lib hardening"

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

# Find game native lib paths
find_game_path() {
    local PKG="$1"
    local ARCH="$2"  # "arm64" or "arm"
    local RESULT=""

    # Try /data/app/.../lib/ARCH (modern Android)
    RESULT=$(find /data/app -type d -name "$ARCH" 2>/dev/null | grep "$PKG" | head -1)

    # Try /data/user/0/.../lib (legacy)
    if [ -z "$RESULT" ]; then
        local LEGACY="/data/user/0/$PKG/lib"
        [ -d "$LEGACY" ] && RESULT="$LEGACY"
    fi

    echo "$RESULT"
}

# Determine if 64-bit or 32-bit
FFPATH=""
FF2PATH=""
IS_32BIT=0

# Try 64-bit first
FFPATH=$(find_game_path "$FF_PKG" "arm64")
if [ -n "$FFPATH" ]; then
    IS_32BIT=0
    ok "FF Max: 64-bit → $FFPATH"
else
    FFPATH=$(find_game_path "$FF_PKG" "arm")
    [ -n "$FFPATH" ] && { IS_32BIT=1; ok "FF Max: 32-bit → $FFPATH"; }
fi

FF2PATH=$(find_game_path "$FF_PKG2" "arm64")
[ -z "$FF2PATH" ] && FF2PATH=$(find_game_path "$FF_PKG2" "arm")
[ -n "$FF2PATH" ] && ok "FF Normal: → $FF2PATH" || sk "FF Normal: not installed"

# ── Backup libs ──
backup_libs() {
    local SRCDIR="$1" DESTDIR="$2"
    [ -z "$SRCDIR" ] && return
    [ -d "$SRCDIR" ] || return
    for LIB in $LIBS; do
        [ -f "$DESTDIR/$LIB" ] && continue  # already backed up
        [ -f "$SRCDIR/$LIB" ] || continue
        cp "$SRCDIR/$LIB" "$DESTDIR/$LIB" && ok "Backup: $LIB"
    done
}

if [ "$IS_32BIT" = "1" ]; then
    backup_libs "$FFPATH" "$BACKUP32"
    [ -n "$FF2PATH" ] && backup_libs "$FF2PATH" "$BACKUP32"
    backup_libs "/data/user/0/$FF_PKG/lib" "$BACKUP32"
    backup_libs "/data/user/0/$FF_PKG2/lib" "$BACKUP32"
    total=$(ls "$BACKUP32"/*.so 2>/dev/null | wc -l)
    ok "32-bit backup: $total libs"
else
    backup_libs "$FFPATH" "$BACKUP"
    [ -n "$FF2PATH" ] && backup_libs "$FF2PATH" "$BACKUP"
    total=$(ls "$BACKUP"/*.so 2>/dev/null | wc -l)
    ok "64-bit backup: $total libs"
fi

# ── Apply redirect + kstat for each lib ──
apply_lib_redirect() {
    local SRCPATH="$1" BACKPATH="$2"
    [ -f "$SRCPATH" ] || return
    [ -f "$BACKPATH" ] || return

    # Open redirect: when game reads lib, redirect to clean backup
    "$SUSFS" add_open_redirect "$SRCPATH" "$BACKPATH" 2>/dev/null

    # sus_kstat: store original stat BEFORE bind-mount/overlay
    "$SUSFS" add_sus_kstat "$SRCPATH" 2>/dev/null

    # Wait briefly then update kstat with full clone
    "$SUSFS" update_sus_kstat_full_clone "$SRCPATH" 2>/dev/null

    # Add to config file
    echo "$SRCPATH $BACKPATH 0" >> "$SUSFS_DIR/sus_open_redirect.txt"
}

log ""
log "--- Applying lib redirects ---"

if [ "$IS_32BIT" = "1" ]; then
    if [ -n "$FFPATH" ]; then
        for LIB in $LIBS; do
            apply_lib_redirect "$FFPATH/$LIB" "$BACKUP32/$LIB"
        done
    fi
    if [ -n "$FF2PATH" ]; then
        for LIB in $LIBS; do
            apply_lib_redirect "$FF2PATH/$LIB" "$BACKUP32/$LIB"
        done
    fi
    for LIB in $LIBS; do
        apply_lib_redirect "/data/user/0/$FF_PKG/lib/$LIB" "$BACKUP32/$LIB"
        apply_lib_redirect "/data/user/0/$FF_PKG2/lib/$LIB" "$BACKUP32/$LIB"
    done
else
    if [ -n "$FFPATH" ]; then
        for LIB in $LIBS; do
            apply_lib_redirect "$FFPATH/$LIB" "$BACKUP/$LIB"
        done
    fi
    if [ -n "$FF2PATH" ]; then
        for LIB in $LIBS; do
            apply_lib_redirect "$FF2PATH/$LIB" "$BACKUP/$LIB"
        done
    fi
fi

RCOUNT=$(grep -c "\.so" "$SUSFS_DIR/sus_open_redirect.txt" 2>/dev/null || echo 0)
log "Total lib redirects: $RCOUNT"

# ==============================================================
# SECTION 11 — ANDROID ID + CACHE CLEAR
# ==============================================================
hdr "SECTION 11 · ID rotation + cache clear"

# Rotate Android ID
NEW_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16 2>/dev/null || echo "a1b2c3d4e5f67890")
settings put secure android_id "$NEW_ID" 2>/dev/null
ok "Android ID rotated"

# Clear all detection traces
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
/data/user/0/com.google.android.settings.intelligence/shared_prefs
"

for DIR in $CLEAR_DIRS; do
    rm -rf "$DIR"/* 2>/dev/null
done
ok "Detection traces cleared"

# ==============================================================
# SECTION 12 — MAIN LOOP (runtime protection)
# ==============================================================
hdr "SECTION 12 · Main protection loop"

# Disable SUSFS log in main loop (reduce kernel noise)
"$SUSFS" enable_log 0 2>/dev/null
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

        # Rotate Android ID while playing
        NEW_ID=$(cat /dev/urandom | tr -dc 'a-f0-9' | head -c 16 2>/dev/null || echo "a1b2c3d4e5f67890")
        settings put secure android_id "$NEW_ID" 2>/dev/null

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
            settings put secure android_id "$NEW_ID" 2>/dev/null
            ok "Post-game cleanup done (ID=$NEW_ID)"

            # Re-apply critical props
            "$RP" -n ro.build.type "user" 2>/dev/null
            "$RP" -n ro.debuggable "0" 2>/dev/null
            "$RP" -n ro.boot.verifiedbootstate "green" 2>/dev/null

            FF_WAS_RUNNING=0
        fi

        sleep 10
    fi
done
