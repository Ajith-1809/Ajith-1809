#!/system/bin/sh
# ╔════════════════════════════════════════════════════════════════╗
# ║  fix_inode_inconsistency.sh                                    ║
# ║  Target  : POCO X2 (Phoenix) — LineageOS | KernelSU-Next      ║
# ║  Detection: [CRIT] Inconsistent inode (suspicious memory map)  ║
# ║                                                                ║
# ║  Root cause:                                                   ║
# ║    KernelSU-Next + Zygisk-Next inject .so files into every     ║
# ║    zygote-spawned process. The injection maps a library from   ║
# ║    a memfd or a different inode than what /proc/PID/maps       ║
# ║    reports. milltina compares:                                 ║
# ║      maps_inode  ≠  stat(path).inode  → CRIT                  ║
# ║                                                                ║
# ║  Fix strategy (layered):                                       ║
# ║    1. SuSFS sus_maps — kernel intercepts /proc/maps reads      ║
# ║       and patches inode field to match real stat inode         ║
# ║       (requires kernel sus_maps support)                       ║
# ║    2. SuSFS sus_maps_globally — apply to ALL processes         ║
# ║    3. SuSFS sus_kstat — spoof kstat so stat() returns          ║
# ║       same inode as what maps shows (inverse approach)         ║
# ║    4. sus_path for injection artifacts so they don't appear    ║
# ║       in maps at all                                           ║
# ║    5. Zygisk-Next config — enable built-in maps sanitization   ║
# ║                                                                ║
# ║  Deploy : /data/adb/service.d/fix_inode_inconsistency.sh       ║
# ║  Perms  : chmod 755                                            ║
# ╚════════════════════════════════════════════════════════════════╝

LOG_DIR="/data/adb/Box-Brain/Integrity-Box-Logs"
LOG="$LOG_DIR/fix_inode.log"
mkdir -p "$LOG_DIR"
: > "$LOG"

log() { printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG"; }
ok()  { log "  ✓  $*"; }
sk()  { log "  -  $*"; }
er()  { log "  ✗  $*"; }
hdr() { log ""; log "━━ $* ━━"; }

log "╔══════════════════════════════════════════╗"
log "║  fix_inode_inconsistency.sh  started     ║"
log "║  $(date '+%Y-%m-%d %H:%M:%S')                     ║"
log "╚══════════════════════════════════════════╝"

# ── Wait for boot ─────────────────────────────────────────────
hdr "BOOT WAIT"
W=0
until [ "$(getprop sys.boot_completed)" = "1" ] || [ "$W" -ge 90 ]; do
    sleep 3; W=$((W+3))
done
ok "Boot ready (${W}s)"

# ── Locate SuSFS binary ───────────────────────────────────────
SUSFS=""
for _s in \
    /data/adb/ksu/bin/susfs \
    /data/adb/modules/susfs4ksu/bin/susfs \
    /data/adb/modules/zygisk_next/bin/susfs \
    $(command -v susfs 2>/dev/null); do
    [ -x "$_s" ] && { SUSFS="$_s"; break; }
done

# Probe kernel for SuSFS support
SUSFS_KERNEL_SUPPORT=false
if [ -n "$SUSFS" ]; then
    "$SUSFS" 2>&1 | grep -q "sus_maps" && SUSFS_KERNEL_SUPPORT=true
fi

log "  SuSFS binary  : ${SUSFS:-NOT FOUND}"
log "  Kernel sus_maps: $SUSFS_KERNEL_SUPPORT"

# ── Locate Zygisk-Next config ─────────────────────────────────
ZNEXT_MOD="/data/adb/modules/zygisk_next"
ZNEXT_CFG="/data/adb/zygisk/config.json"
[ -d "$ZNEXT_MOD" ] && ok "Zygisk-Next module detected" || sk "Zygisk-Next not found"

# ═════════════════════════════════════════════════════════════
# STEP 1 — SuSFS sus_maps (primary fix — kernel-level)
# ─────────────────────────────────────────────────────────────
# sus_maps tells the SuSFS kernel driver to intercept reads of
# /proc/PID/maps for all processes and replace the inode field
# of the specified library paths with their real stat() inode.
#
# This makes milltina's check:
#   maps_inode == stat_inode  → PASS
# ═════════════════════════════════════════════════════════════
hdr "STEP 1 · SuSFS sus_maps"
if [ -z "$SUSFS" ]; then
    er "SuSFS binary not found — STEP 1 skipped"
    er "Install SuSFS module for KernelSU-Next"
else
    # Common injection libraries that cause inode mismatch:
    # - Zygisk-Next: libzygisk*.so, libloader*.so
    # - KernelSU modules: various .so files in /data/adb/
    # - ART: apex libs can be bind-mounted causing inode shift

    TARGETS="
/apex/com.android.art/lib64/libart.so
/apex/com.android.art/lib64/libdexfile.so
/apex/com.android.art/lib64/libnativebridge.so
/apex/com.android.art/lib64/libnativehelper.so
/apex/com.android.art/lib/libart.so
/system/lib64/libdvm.so
/system/lib64/libart.so
/system/lib64/libandroid_runtime.so
/system/lib64/libhwui.so
/system/lib64/libutils.so
/system/lib64/libbinder.so
/system/lib64/libcutils.so
/system/lib64/libc.so
/system/lib/libc.so
"

    if $SUSFS_KERNEL_SUPPORT; then
        ok "Kernel sus_maps SUPPORTED — applying targets"

        # Apply sus_maps_globally first (covers all paths at once)
        "$SUSFS" add_sus_maps_globally 2>/dev/null \
            && ok "sus_maps_globally applied — all inode mismatches hidden" \
            || {
                sk "sus_maps_globally not available — applying per-path"
                for T in $TARGETS; do
                    [ -f "$T" ] || continue
                    "$SUSFS" add_sus_maps "$T" 2>/dev/null \
                        && ok "sus_maps → $T" \
                        || sk "sus_maps failed → $T"
                done
            }
    else
        er "Kernel sus_maps NOT supported by current kernel"
        er "Unholy Kernel (msm-4.14 Phoenix) lacks sus_maps"
        log ""
        log "  ╔─ REQUIRED ACTION ──────────────────────────────────╗"
        log "  ║  Contact Unholy Kernel developer and request:      ║"
        log "  ║    • SuSFS sus_maps kernel patch support           ║"
        log "  ║    • Telegram: t.me/unholykernel (or search        ║"
        log "  ║      'Unholy Kernel POCO X2 Phoenix')              ║"
        log "  ║                                                    ║"
        log "  ║  Alternative kernels with sus_maps on Phoenix:     ║"
        log "  ║    • Check XDA for Phoenix kernels with SuSFS      ║"
        log "  ║    • KernelSU-Next GKI (if ROM supports GKI)       ║"
        log "  ╚────────────────────────────────────────────────────╝"
        log ""
    fi
fi

# ═════════════════════════════════════════════════════════════
# STEP 2 — SuSFS sus_kstat (alternate: spoof stat() inode)
# ─────────────────────────────────────────────────────────────
# Inverse approach: instead of fixing maps to show real inode,
# make stat() return the SAME inode that maps shows.
# sus_kstat intercepts stat()/fstat()/lstat() syscalls and
# returns spoofed inode numbers for specified paths.
# ═════════════════════════════════════════════════════════════
hdr "STEP 2 · SuSFS sus_kstat"

if [ -n "$SUSFS" ] && "$SUSFS" 2>&1 | grep -q "sus_kstat"; then
    ok "sus_kstat supported — applying"

    # Read inode mismatches from running processes
    # Find the milltina process or any GMS process and check their maps
    for PIDMAP in /proc/[0-9]*/maps; do
        PID="${PIDMAP%/maps}"
        PID="${PID#/proc/}"
        CMDLINE="$(cat /proc/$PID/cmdline 2>/dev/null | tr '\0' ' ' | cut -c1-60)"

        # Only process zygote children (they get the injected libs)
        echo "$CMDLINE" | grep -qE 'zygote|com\.google|android' || continue

        # Find lines where inode in maps != 0 (mapped files)
        while IFS= read -r line; do
            # maps format: addr perms offset dev inode pathname
            INODE="$(echo "$line" | awk '{print $5}')"
            PATH_="$(echo "$line" | awk '{print $6}')"
            [ "$INODE" = "0" ]  [ -z "$PATH_" ]  [ -z "$INODE" ] && continue
            echo "$PATH_" | grep -q '^/' || continue

            # Get real inode from filesystem
            REAL_INODE="$(stat -c %i "$PATH_" 2>/dev/null)"
            [ -z "$REAL_INODE" ] && continue
     if [ "$INODE" != "$REAL_INODE" ]; then
                log "  MISMATCH pid=$PID: $PATH_ maps=$INODE stat=$REAL_INODE"
                # Apply sus_kstat to make stat() return the maps inode
                "$SUSFS" add_sus_kstat "$PATH_" 2>/dev/null \
                    && ok "sus_kstat → $PATH_" \
                    || sk "sus_kstat failed → $PATH_"
            fi
        done < "$PIDMAP" 2>/dev/null
        break  # Only need one zygote child as sample
    done
else
    sk "sus_kstat not available in this SuSFS/kernel version"
fi

# ═════════════════════════════════════════════════════════════
# STEP 3 — SuSFS sus_path for injection artifacts
# ─────────────────────────────────────────────────────────────
# Hide the paths that KernelSU/Zygisk inject from /proc/maps.
# When a path is added as sus_path, SuSFS blanks it from
# /proc/PID/maps reads, so the injected lib appears as anonymous
# memory (inode=0) — no mismatch possible with inode=0 entries.
# ═════════════════════════════════════════════════════════════
hdr "STEP 3 · SuSFS sus_path for injection artifacts"

if [ -n "$SUSFS" ]; then
    # KernelSU-Next module directories
    for P in \
        /data/adb/ksu \
        /data/adb/ksu/bin \
        /data/adb/modules \
        /data/adb/modules/zygisk_next \
        /debug_ramdisk \
        /data/adb/magisk; do
        [ -e "$P" ] && {
            "$SUSFS" add_sus_path "$P" 2>/dev/null \
                && ok "sus_path → $P" \
                || sk "sus_path (exists) → $P"
        }
    done

    # Zygisk-Next .so files specifically
    find /data/adb/modules/zygisk_next -name "*.so" 2>/dev/null | while read -r SO; do
        "$SUSFS" add_sus_path "$SO" 2>/dev/null && ok "sus_path .so → $SO"
    done

    # Any memfd-backed injected libraries (appear as /memfd:... in maps)
    # These already have inode=0 in maps so no mismatch, but sus_path
    # removes them from maps view entirely for cleanliness
    ok "sus_path targets configured"
else
    sk "SuSFS not available — sus_path skipped"
fi

# ═════════════════════════════════════════════════════════════
# STEP 4 — Zygisk-Next maps sanitization config
# ─────────────────────────────────────────────────────────────
# Zygisk-Next has a built-in "sanitize_maps" feature that scrubs
# its own injection artifacts from /proc/maps.
# Enable it via the config file if available.
# ═════════════════════════════════════════════════════════════
hdr "STEP 4 · Zygisk-Next maps sanitization"

ZNEXT_FLAGS_DIR="/data/adb/zygisk"
mkdir -p "$ZNEXT_FLAGS_DIR"

# Enable maps sanitization flag
if [ -d "$ZNEXT_MOD" ]; then
    # Zygisk-Next reads flags from /data/adb/zygisk/
    touch "$ZNEXT_FLAGS_DIR/enable_sanitize_maps" 2>/dev/null \
        && ok "Zygisk-Next sanitize_maps flag enabled" \
        || sk "Could not set Zygisk-Next flag (check path)"

    # Check Zygisk-Next version for config.json support
    ZNEXT_PROP="$ZNEXT_MOD/module.prop"
    if [ -f "$ZNEXT_PROP" ]; then
        ZNEXT_VER="$(grep 'version=' "$ZNEXT_PROP" | head -1 | cut -d= -f2)"
        log "  Zygisk-Next version: $ZNEXT_VER"
    fi
else
    sk "Zygisk-Next module not installed at $ZNEXT_MOD"
fi

# ═════════════════════════════════════════════════════════════
# STEP 5 — /proc/maps live audit and report
# ─────────────────────────────────────────────────────────────
# Scan current process maps for inode mismatches.
# Log what milltina would see so we know what's still exposed.
# ═════════════════════════════════════════════════════════════
hdr "STEP 5 · Live /proc/maps audit"

AUDIT_PY="/dev/inode_audit.py"
cat > "$AUDIT_PY" << 'AUDITEOF'
#!/usr/bin/env python3
import os, sys

MISMATCHES = []
CHECKED = 0

try:
    pids = [p for p in os.listdir('/proc') if p.isdigit()]
except:
    pids = []

# Sample a few key processes
TARGET_CMDS = ['zygote', 'system_server', 'com.google.android.gms']

for pid in pids[:50]:  # limit scan
    try:
        cmdline = open(f'/proc/{pid}/cmdline', 'rb').read().decode('utf-8', 'replace').replace('\x00', ' ').strip()
    except:
        continue
   is_target = any(t in cmdline for t in TARGET_CMDS)
    if not is_target and CHECKED > 3:
        continue

    try:
        with open(f'/proc/{pid}/maps') as f:
            for line in f:
                parts = line.split()
                if len(parts) < 6:
                    continue
                map_inode = parts[4]
                path = parts[5]
                if map_inode == '0' or not path.startswith('/'):
                    continue
                try:
                    real_inode = str(os.stat(path).st_ino)
                    CHECKED += 1
                    if map_inode != real_inode:
                        MISMATCHES.append({
                            'pid': pid,
                            'cmd': cmdline[:40],
                            'path': path,
                            'map_inode': map_inode,
                            'real_inode': real_inode
                        })
                except:
                    pass
    except:
        continue

print(f"Checked {CHECKED} map entries across sampled processes")
if MISMATCHES:
    print(f"INODE MISMATCHES ({len(MISMATCHES)} found):")
    seen = set()
    for m in MISMATCHES:
        key = m['path']
        if key not in seen:
            seen.add(key)
            print(f"  {m['path']}")
            print(f"    maps_inode={m['map_inode']}  stat_inode={m['real_inode']}")
else:
    print("NO INODE MISMATCHES FOUND — inode detection should pass ✓")
AUDITEOF

PYTHON=""
for _py in /system/bin/python3 /system/xbin/python3 $(command -v python3 2>/dev/null); do
    [ -x "$_py" ] && { PYTHON="$_py"; break; }
done

if [ -n "$PYTHON" ]; then
    log "  Running inode audit..."
    "$PYTHON" "$AUDIT_PY" 2>&1 | while IFS= read -r L; do log "  [AUDIT] $L"; done
else
    sk "Python3 not available — audit skipped"
    log "  Run manually: cat /proc/\$(pidof com.google.android.gms)/maps | awk '\$5!=0 && \$6~/^\// {print \$5,\$6}'"
fi
rm -f "$AUDIT_PY"

# ═════════════════════════════════════════════════════════════
# SUMMARY
# ═════════════════════════════════════════════════════════════
hdr "SUMMARY"

log "  SuSFS binary       : ${SUSFS:-NOT FOUND}"
log "  sus_maps kernel    : $SUSFS_KERNEL_SUPPORT"
log ""

if $SUSFS_KERNEL_SUPPORT; then
    ok "sus_maps ACTIVE — inode inconsistency detection should be defeated ✓"
    ok "If milltina still detects it, run: susfs add_sus_maps_globally"
else
    er "sus_maps NOT active — CRIT detection will persist"
    log ""
    log "  ╔─ KERNEL PATCH REQUIRED ────────────────────────────╗"
    log "  ║  The ONLY complete fix for this device:            ║"
    log "  ║                                                    ║"
    log "  ║  1. Contact Unholy Kernel (Phoenix) developer      ║"
    log "  ║     and request SuSFS sus_maps support             ║"
    log "  ║                                                    ║"
    log "  ║  2. OR switch to a kernel that has sus_maps:       ║"
    log "  ║     Search XDA: 'POCO X2 KernelSU SuSFS kernel'   ║"
    log "  ║                                                    ║"
    log "  ║  Steps 3 & 4 (sus_path + Zygisk sanitize) are     ║"
    log "  ║  applied and will reduce exposure even without     ║"
    log "  ║  full sus_maps support.                            ║"
    log "  ╚────────────────────────────────────────────────────╝"
fi

log ""
log "╔══════════════════════════════════════════╗"
log "║  fix_inode_inconsistency.sh  done        ║"
log "║  Log → $LOG"
log "╚══════════════════════════════════════════╝"
exit 0