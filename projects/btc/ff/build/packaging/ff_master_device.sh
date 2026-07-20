#!/system/bin/sh

export PATH=$PATH:/data/adb/ksu/bin

# ============================================
# LOCK — Prevent duplicate instances
# ============================================
LOCKFILE="/data/local/tmp/ff_master.lock"

# Atomic lock — noclobber fails if file already exists,
# preventing the TOCTOU race between check and write.
( set -o noclobber
  echo $$ > "$LOCKFILE"
) 2>/dev/null || {
  OLD_PID=$(cat "$LOCKFILE" 2>/dev/null)
  if [ -n "$OLD_PID" ] && \
     kill -0 "$OLD_PID" 2>/dev/null; then
    exit 0
  fi
  # Stale lock — take it over atomically
  ( set -o noclobber
    echo $$ > "$LOCKFILE"
  ) 2>/dev/null || exit 0
}
trap 'rm -f "$LOCKFILE"' EXIT INT TERM

# ============================================
# GUARD — keep our add_sus_maps-capable ksu_susfs authoritative
# The susfs4ksu module overwrites /data/adb/ksu/bin/ksu_susfs at boot with the
# stock universal binary (no add_sus_maps). Restore ours if the live binary lost
# the command. AK3 stashed a pristine copy at .ksu_susfs_ours. (memory #18)
# ============================================
if [ -x /data/adb/ksu/bin/.ksu_susfs_ours ] && \
   ! /data/adb/ksu/bin/ksu_susfs add_sus_maps --help >/dev/null 2>&1; then
  cp -f /data/adb/ksu/bin/.ksu_susfs_ours /data/adb/ksu/bin/ksu_susfs 2>/dev/null
  chmod 755 /data/adb/ksu/bin/ksu_susfs 2>/dev/null
  echo "restored add_sus_maps-capable ksu_susfs" >> "$LOG"
fi

BACKUP="/data/local/tmp/ff"
BACKUP2="/data/local/tmp/ff32"
# Per-package, per-arch backup dirs. MAX and Normal each get their OWN arm64/arm
# dir so they never collide by basename. You populate these MANUALLY: after
# installing the FF APK, copy its extracted libs into the matching dir
# (ff/max_arm64 for FF MAX 64-bit, ff/norm_arm64 for FF Normal 64-bit, etc.).
# The script applies open_redirect + kstat for each lib you placed; it never
# auto-copies (auto-copy drifted and served wrong bytes -> ban). Missing backup
# = lib not redirected (read real from disk) = safe.
BACKUP_MAX="$BACKUP/max_arm64"
BACKUP_MAX32="$BACKUP2/max_arm"
BACKUP_NORM="$BACKUP/norm_arm64"
BACKUP_NORM32="$BACKUP2/norm_arm"
CLEAN_PROC="/data/local/tmp/clean_proc"
LOG="$BACKUP/ff_master_log.txt"
SUSFS_DIR="/data/adb/susfs4ksu"
FF_PKG="com.dts.freefiremax"
FF_PKG2="com.dts.freefireth"
FF_CACHE="/data/user/0/com.dts.freefiremax/cache"
FF_CACHE2="/data/user/0/com.dts.freefireth/cache"
FF_FILES="/data/user/0/com.dts.freefiremax/files"
FF_FILES2="/data/user/0/com.dts.freefireth/files"
FF_PREFS="/data/user/0/com.dts.freefiremax/shared_prefs"
FF_PREFS2="/data/user/0/com.dts.freefireth/shared_prefs"
FF_LIB="/data/user/0/com.dts.freefiremax/lib"
FF_LIB2="/data/user/0/com.dts.freefireth/lib"
GMS_CACHE="/data/user/0/com.google.android.gms/cache"
GSF_CACHE="/data/user/0/com.google.android.gsf/cache"
PLAY_CACHE="/data/user/0/com.android.vending/cache"
SEARCH_CACHE="/data/user/0/com.google.android.googlequicksearchbox/cache"

mkdir -p $BACKUP_MAX $BACKUP_MAX32 $BACKUP_NORM $BACKUP_NORM32
mkdir -p $CLEAN_PROC
# Ensure per-package backup dirs exist (contents are populated MANUALLY by the
# user after each APK install — see BACKUP_* comments above). No auto-copy.
for d in $BACKUP_MAX $BACKUP_MAX32 $BACKUP_NORM $BACKUP_NORM32; do
  mkdir -p "$d"
done
> $LOG
echo "=== FF Master Script ===" >> $LOG
echo "Started: $(date)" >> $LOG

# ============================================
# LIB LIST
# ============================================

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

# ============================================
# FUNCTION — GET UID
# ============================================

get_uid() {
  PKG=$1
  grep "^$PKG " \
  /data/system/packages.list \
  2>/dev/null | awk '{print $2}'
}

# ============================================
# FUNCTION — APPLY UID HIDING
# ============================================

apply_uid_hiding() {
  echo "Applying UID hiding..." >> $LOG

  FF_PATHS="
/data/adb/ksu
/data/adb/ksud
/data/adb/ksu/bin
/data/adb/ksu/bin/ksu_susfs
/data/adb/ksu/bin/sus_su
/data/adb/ksu/bin/susfsd
/data/adb/susfs4ksu
/data/adb/tricky_store
/data/adb/anti_safetycore
/data/adb/zygisk-detach
/data/adb/VerifiedBootHash
/data/adb/boot_hash
/data/adb/pif.prop
/debug_ramdisk
/proc/version
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

  # Note: this kernel does NOT support per-UID path hiding,
  # so we use global add_sus_path instead — hides from all apps.
  for P in $FF_PATHS; do
    ksu_susfs add_sus_path "$P" 2>/dev/null
  done
  echo "FF paths hidden!" >> $LOG

  for P in $GMS_PATHS; do
    ksu_susfs add_sus_path "$P" 2>/dev/null
  done
  echo "GMS/Play paths hidden!" >> $LOG

  ksu_susfs add_try_umount \
  /data/adb/modules_update 0 2>/dev/null
  ksu_susfs add_try_umount \
  /data/adb/zygisk 0 2>/dev/null
  ksu_susfs add_try_umount \
  /data/adb/zygisksu 0 2>/dev/null

  # ── SUS_MAP: hide injected zygisk/root .so from /proc/pid/maps ──────────
  # SUS_MAP hides by PATH (deletes the vma line for that file); it is NOT
  # add_sus_path (which returns ENOENT on stat/getdents and would break the
  # zygisk loader's per-start rescan of /data/adb/modules). The loader already
  # has each lib mapped into zygote, so hiding the mapping from OTHER processes
  # (FF) does NOT unmap it from the loader — no self-sabotage. Kernel gained
  # SUS_MAP at build #234/235. Every entry guarded; 2>/dev/null.
  for so in \
    /data/adb/modules/zygisksu/lib64/libzygisk.so \
    /data/adb/modules/zygisksu/lib64/libpayload.so \
    /data/adb/modules/zygisksu/lib64/libzn_loader.so \
    /data/adb/modules/zygisksu/lib/libzn_loader.so \
    /data/adb/modules/zygisksu/lib/libzygisk.so \
    /data/adb/modules/zygisk-maphide/zygisk/arm64-v8a.so \
    /data/adb/modules/zygisk_prosphoron/zygisk/arm64-v8a.so \
    /data/adb/modules/zygisk-detach/zygisk/arm64-v8a.so \
    /data/adb/modules/hma_oss_zygisk/zygisk/arm64-v8a.so \
    /data/adb/modules/playintegrityfix/zygisk/arm64-v8a.so \
    /data/adb/modules/auditpatch/lib/libauditpatch.so ; do
    [ -e "$so" ] && ksu_susfs add_sus_map "$so" 2>/dev/null
  done
  # runtime glob expansion (SUS_MAP takes no wildcards): enumerate zygisk .so
  if [ -d /data/adb/modules ]; then
    find /data/adb/modules -path '*/zygisk/*.so' 2>/dev/null | \
      while read -r so; do
        ksu_susfs add_sus_maps "$so" /system/lib64/libc.so 2>/dev/null
      done
  fi

  # ── lineage/ROM artifacts: sanitize shown pathname in /proc/pid/maps ──
  # The "suspicious memory mapping (lineage os)" check reads org.lineageos paths
  # out of process maps. SUS_MAP (Mode-1 inode match) rewrites the SHOWN pathname
  # to a benign real path; the real file/inode is untouched. Keep add_sus_path too
  # (hides the on-disk file from readdir listings). Both work on erofs /system /vendor.
  # Spoof target must be a *real* path so the maps line still looks legit.
  SPOOF_SO=/system/lib64/libc.so
  SPOOF_JAR=/system/framework/framework.jar
  LINEAGE_PATHS="
/system/framework/org.lineageos.platform.jar
/system/framework/org.lineageos.platform-res.apk
/system/lib64/liblineage_os_utils.so
/system/lib64/liblineage_compat.so
/system/lib64/liblineage_camera.so
/vendor/lib64/liblineage_media.so
"
  for P in $LINEAGE_PATHS; do
    if [ -e "$P" ]; then
      ksu_susfs add_sus_path "$P" 2>/dev/null
      case "$P" in
        *.so)  ksu_susfs add_sus_maps "$P" "$SPOOF_SO" 2>/dev/null ;;
        *)     ksu_susfs add_sus_maps "$P" "$SPOOF_JAR" 2>/dev/null ;;
      esac
    fi
  done
  find /system /vendor -path '*org.lineageos*' 2>/dev/null | \
    while read -r P; do
      ksu_susfs add_sus_path "$P" 2>/dev/null
      case "$P" in
        *.so)  ksu_susfs add_sus_maps "$P" "$SPOOF_SO" 2>/dev/null ;;
        *)     ksu_susfs add_sus_maps "$P" "$SPOOF_JAR" 2>/dev/null ;;
      esac
    done

  echo "All UID rules applied!" >> $LOG
}

# ============================================
# FUNCTION — UPDATE SUSFS FILES
# ============================================

update_susfs_files() {
  echo "Updating SuSFS files..." >> $LOG

  cat > $SUSFS_DIR/sus_path.txt << EOF
# Auto generated — no global hiding
EOF

  cat > $SUSFS_DIR/sus_path_loop.txt << EOF
# Auto generated
EOF

  FF_LOOP="
/data/adb/ksu
/data/adb/ksud
/data/adb/ksu/bin
/data/adb/ksu/bin/ksu_susfs
/data/adb/susfs4ksu
/data/adb/tricky_store
/data/adb/anti_safetycore
/data/adb/zygisk-detach
/data/adb/VerifiedBootHash
/data/adb/pif.prop
/debug_ramdisk
/proc/version
/proc/kallsyms
/proc/config.gz
"

  GMS_LOOP="
/data/adb/ksu
/data/adb/ksud
/data/adb/susfs4ksu
/data/adb/tricky_store
/data/adb/pif.prop
/debug_ramdisk
/proc/version
"

  if [ -n "$FF_UID" ]; then
    for P in $FF_LOOP; do
      echo "$FF_UID $P" \
      >> $SUSFS_DIR/sus_path_loop.txt
    done
  fi

  if [ -n "$FF2_UID" ]; then
    for P in $FF_LOOP; do
      echo "$FF2_UID $P" \
      >> $SUSFS_DIR/sus_path_loop.txt
    done
  fi

  if [ -n "$GMS_UID" ]; then
    for P in $GMS_LOOP; do
      echo "$GMS_UID $P" \
      >> $SUSFS_DIR/sus_path_loop.txt
    done
  fi

  if [ -n "$PLAY_UID" ]; then
    for P in $GMS_LOOP; do
      echo "$PLAY_UID $P" \
      >> $SUSFS_DIR/sus_path_loop.txt
    done
  fi

  # Per-UID filesystem hides for the disclosure detector app.
  # NOTE: sus_path hides filesystem paths only — it does NOT remove packages
  # from `pm list packages` (that reads system_server's package DB). So this
  # hides the KSU *directories* and *APK files* from the app's file scans, but
  # the package *names* themselves (if the app uses PackageManager) need a
  # different mechanism (HMA / KSU hide). Hide both the apk paths and the
  # /data/adb KSU dirs so any file-based scan misses them.
  if [ -n "$DISC_UID" ]; then
    for pkg in com.rifsxd.ksunext io.github.a13e300.ksuwebui; do
      _apk=$(ls -d /data/app/*/"$pkg"-*/base.apk 2>/dev/null | head -1)
      [ -n "$_apk" ] && echo "$DISC_UID $_apk" \
        >> $SUSFS_DIR/sus_path_loop.txt
    done
    # KSU / root-manager artifact directories — hidden from the detector's uid.
    for d in /data/adb/ksu /data/adb/ksud /data/adb/susfs4ksu \
             /data/adb/tricky_store /data/adb/zygisk /data/adb/zygisksu \
             /data/adb/anti_safetycore /data/adb/modules \
             /sdcard/.ksunext /data/local/tmp/ff; do
      [ -e "$d" ] && echo "$DISC_UID $d" >> $SUSFS_DIR/sus_path_loop.txt
    done
  fi

  cat > $SUSFS_DIR/sus_mount.txt << EOF
# Auto generated — empty
EOF

  cat > $SUSFS_DIR/try_umount.txt << EOF
# Auto generated
/data/adb/modules_update 0
/data/adb/zygisk 0
/data/adb/zygisksu 0
EOF

  cat > $SUSFS_DIR/sus_maps.txt << EOF
# Auto generated — root paths only
/data/adb/ksu
/data/adb/ksu/bin
/data/adb/susfs4ksu
/debug_ramdisk
EOF

  echo "All SuSFS files updated!" >> $LOG
}

# ============================================
# FUNCTION — BACKUP DIRS (manual populate)
# No auto-copy: the user copies FF's extracted libs into the per-package dirs
# after each APK install. Auto-copy historically drifted (served stale/foreign
# bytes -> server tamper ban). We only ensure the dirs exist.
ensure_backup_dirs() {
  echo "Backup dirs (manual populate):" >> $LOG
  for d in $BACKUP_MAX $BACKUP_MAX32 $BACKUP_NORM $BACKUP_NORM32; do
    mkdir -p "$d"
    echo "  $d ($(ls "$d" 2>/dev/null | grep -c '\.so') .so present)" >> $LOG
  done
}

# ============================================
# FUNCTION — PROC REDIRECTS
# ============================================

setup_proc_redirect() {
  echo "Setting up proc redirects..." >> $LOG

  cat > $CLEAN_PROC/version << EOF
Linux version 5.10.186-android13-4-00224-g870f7ff8f5ed (android-build@abfarm-us-east1-c-0097) (Android (7284624, based on r416183b) clang version 12.0.5) #1 SMP PREEMPT Mon Sep 5 12:00:00 CST 2023
EOF

  cat > $CLEAN_PROC/cmdline << EOF
rcupdate.rcu_expedited=1 androidboot.hardware=qcom androidboot.verifiedbootstate=green androidboot.keymaster=1 androidboot.bootdevice=1d84000.ufshc androidboot.secureboot=1 androidboot.serialno=5b389e4c
EOF

  > $CLEAN_PROC/kallsyms

  cat > $CLEAN_PROC/cpuinfo << EOF
Processor : AArch64 Processor rev 14 (aarch64)
Hardware  : Qualcomm Technologies, Inc SDMMAGPIE
EOF

  cat >> $SUSFS_DIR/sus_open_redirect.txt \
  << EOF
/proc/version $CLEAN_PROC/version 0
/proc/cmdline $CLEAN_PROC/cmdline 0
/proc/kallsyms $CLEAN_PROC/kallsyms 0
/proc/cpuinfo $CLEAN_PROC/cpuinfo 0
EOF

  ksu_susfs add_open_redirect \
  /proc/version \
  $CLEAN_PROC/version 2>/dev/null
  ksu_susfs add_open_redirect \
  /proc/cmdline \
  $CLEAN_PROC/cmdline 2>/dev/null
  ksu_susfs add_open_redirect \
  /proc/kallsyms \
  $CLEAN_PROC/kallsyms 2>/dev/null
  ksu_susfs add_open_redirect \
  /proc/cpuinfo \
  $CLEAN_PROC/cpuinfo 2>/dev/null

  # ── ON-DISK PROP FILES (resetprop can't reach file-readers) ────────────
  # Garena/fopen()s the real build.prop and greps ro.build.tags/ro.debuggable/
  # ro.secure/ro.build.type/ro.boot.verifiedbootstate. resetprop only rewrites
  # the kernel prop tree, not the file bytes — redirect to sanitized decoys.
  # _FP: consistent Android 15 POCO stock build (matches resetprop memory tree).
  _FP="POCO/phoenixin/phoenix:15/BP1A.250505.005/Z1.9.28:user/release-keys"
  sanitize_prop() {  # $1=src $2=decoy
    if [ -e "$1" ]; then
      sed \
        -e "s|^ro\.build\.tags=.*|ro.build.tags=release-keys|" \
        -e "s|^ro\.debuggable=.*|ro.debuggable=0|" \
        -e "s|^ro\.secure=.*|ro.secure=1|" \
        -e "s|^ro\.build\.type=.*|ro.build.type=user|" \
        -e "s|^ro\.build\.flavor=.*|ro.build.flavor=phoenix-user|" \
        -e "s|^ro\.system\.build\.type=.*|ro.system.build.type=user|" \
        -e "s|^ro\.vendor\.build\.type=.*|ro.vendor.build.type=user|" \
        -e "s|^ro\.build\.fingerprint=.*|ro.build.fingerprint=${_FP}|" \
        -e "s|^ro\.product\.system\.name=.*|ro.product.system.name=phoenixin|" \
        -e "s|^ro\.product\.vendor\.name=.*|ro.product.vendor.name=phoenixin|" \
        -e "s|^ro\.product\.odm\.name=.*|ro.product.odm.name=phoenixin|" \
        -e "s|^ro\.boot\.verifiedbootstate=.*|ro.boot.verifiedbootstate=green|" \
        -e "s|^ro\.adb\.secure=.*|ro.adb.secure=1|" \
        -e "s|^ro\.build\.display\.id=.*|ro.build.display.id=${_FP}|" \
        -e "s|^ro\.lineage\..*=.*||g" \
        -e "s|^ro\.matrixx\..*=.*||g" \
        "$1" \
        | sed -e '/lineage/d' -e '/lineageos/d' -e '/matrixx/d' \
              -e '/userdebug/d' -e '/perf+/d' -e '/eng\./d' \
              -e '/^$/d' > "$2"
    else
      printf 'ro.build.tags=release-keys\nro.debuggable=0\nro.secure=1\nro.build.type=user\nro.build.flavor=phoenix-user\nro.build.fingerprint=%s\nro.product.system.name=phoenixin\nro.product.vendor.name=phoenixin\nro.boot.verifiedbootstate=green\nro.adb.secure=1\nro.build.display.id=%s\n' "$_FP" "$_FP" > "$2"
    fi
  }
  for pf in \
    /system/build.prop \
    /system/etc/prop.default \
    /default.prop \
    /vendor/build.prop \
    /product/build.prop ; do
    decoy="$CLEAN_PROC/$(echo "$pf" | tr '/' '_')"
    sanitize_prop "$pf" "$decoy"
    [ -e "$pf" ] && ksu_susfs add_open_redirect "$pf" "$decoy" 2>/dev/null
    echo "$pf $decoy 0" >> $SUSFS_DIR/sus_open_redirect.txt
  done

  # ── PER-PROCESS /proc/self/* (tracer/cap/env detection) ────────────────
  # FF fopen()s /proc/self/status (TracerPid, CapEff) and /proc/self/environ
  # (injected env). Decoys defeat both. (/proc/self/* is per-opener, so this
  # affects only processes that explicitly open it — not ps/top.)
  printf 'Name:\tff_decoy\nState:\tS (sleeping)\nTgid:\t1\nPid:\t1\nPPid:\t0\nTracerPid:\t0\nUid:\t0\t0\t0\t0\nGid:\t0\t0\t0\t0\nFDSize:\t64\nGroups:\t\nCapInh:\t0000000000000000\nCapPrm:\t0000000000000000\nCapEff:\t0000000000000000\nCapBnd:\t0000000000000000\nCapAmb:\t0000000000000000\n' > "$CLEAN_PROC/self_status"
  : > "$CLEAN_PROC/self_environ"
  ksu_susfs add_open_redirect /proc/self/status "$CLEAN_PROC/self_status" 2>/dev/null
  ksu_susfs add_open_redirect /proc/self/environ "$CLEAN_PROC/self_environ" 2>/dev/null
  echo "/proc/self/status $CLEAN_PROC/self_status 0" >> $SUSFS_DIR/sus_open_redirect.txt
  echo "/proc/self/environ $CLEAN_PROC/self_environ 0" >> $SUSFS_DIR/sus_open_redirect.txt

  # ── SUS_MEMFD: hide anonymous staging memfds from /proc/pid/maps+fd ─────
  # memfd:NAME entries have no path/inode, so SUS_MAP/SUS_PATH can't hide them.
  # add_sus_memfd is GLOBAL, idempotent, non-fatal. Names are runtime-only;
  # these are the common KSU/zygisk staging names (verified-on-device-safe:
  # if a name never appears, it simply matches nothing).
  for mn in zygisk zygisk-loader libzygisk kernelsu ksu; do
    ksu_susfs add_sus_memfd "$mn" 2>/dev/null
  done

  echo "Proc redirects done!" >> $LOG
}

# ============================================
# FUNCTION — PROCESS SINGLE LIB
# ============================================

FIRST=1

process_lib() {
  SRCPATH="$1"
  BACKPATH="$2"

  [ -f "$SRCPATH" ] || return
  [ -f "$BACKPATH" ] || return

  # STRICT mode: the backup folder is the AUTHORITATIVE source for the game.
  # Whenever a backup file exists it is served to the game INSTEAD of the on-disk
  # lib, no matter how it differs (size/hash). No fall-through to the real lib.
  # WARN (don't block) if the backup differs from the on-disk lib, so a
  # wrong-arch/wrong-version paste is visible in the log but still served.
  _rsz=$(stat -c %s "$SRCPATH" 2>/dev/null)
  _bsz=$(stat -c %s "$BACKPATH" 2>/dev/null)
  if [ "$_rsz" != "$_bsz" ] || \
     [ "$(sha256sum "$SRCPATH" 2>/dev/null | cut -d' ' -f1)" != \
       "$(sha256sum "$BACKPATH" 2>/dev/null | cut -d' ' -f1)" ]; then
    echo "WARN backup differs (served anyway) $SRCPATH real=$_rsz backup=$_bsz" >> $LOG
  fi

  echo "$SRCPATH $BACKPATH 0" \
  >> $SUSFS_DIR/sus_open_redirect.txt

  ksu_susfs add_open_redirect \
  "$SRCPATH" "$BACKPATH" 2>/dev/null

  ORIG_SIZE=$(stat -c %s \
  "$BACKPATH" 2>/dev/null)
  ORIG_BLOCKS=$(stat -c %b \
  "$BACKPATH" 2>/dev/null)
  GAME_INO=$(stat -c %i \
  "$SRCPATH" 2>/dev/null)

  ksu_susfs add_sus_kstat \
  "$SRCPATH" 2>/dev/null
  ksu_susfs update_sus_kstat \
  "$SRCPATH" 2>/dev/null

  if [ "$FIRST" = "0" ]; then
    echo "," >> \
    $SUSFS_DIR/sus_kstat_statically.json
  fi
  FIRST=0

  cat >> \
  $SUSFS_DIR/sus_kstat_statically.json \
  << EOF
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

# Per-package redirect of FF's OWN libs. Each FF app has its OWN arch (MAX and
# Normal can be 32-bit arm, 64-bit arm64, or BOTH independently). $1 = space-
# separated list of installed arch-lib dirs; the matching backup dir ($3=arm64,
# $4=arm) holds the lib the user manually placed. A lib with NO backup in the
# matching dir is NOT redirected (read real from disk) — so a missing manual
# copy is safe, never wrong-bytes.
# ponytail: backups are populated MANUALLY (user copies after APK install), not
# auto-copied — auto-copy drifted and served stale/foreign bytes (ban).
REDIRECT_FF_LIBS=1
# ENUMERATE_FIX_V2: redirect every game *.so by name to its same-named backup

# Redirect + kstat a package's libs. Enumerate the GAME's own *.so names in each
# installed arch dir and map each to the SAME-NAMED backup file in the matching
# backup dir (arm64->arm64, arm->arm). This guarantees every game lib is covered
# by name, including ones the hardcoded LIBS list omitted (libffutil.so,
# libAkSoundEngine.so, libjingle_peerconnection_so.so). A lib with no same-named
# backup is not redirected (game reads its own bytes).
redirect_pkg() {
  _dst64="$3"; _dst32="$4"
  [ -z "$1" ] && [ ! -d "$2" ] && return
  for d in $1; do
    case "$d" in */arm|*/arm/) dst="$_dst32";; *) dst="$_dst64";; esac
    [ -d "$d" ] || continue
    for LIB in "$d"/*.so; do
      LIB=$(basename "$LIB")
      [ -f "$dst/$LIB" ] && process_lib "$d/$LIB" "$dst/$LIB"
    done
  done
}

# ============================================
# FUNCTION — APPLY ALL REDIRECTS + KSTAT
# Per-package arch (MAX=arm32, Normal=arm64 may differ)
# ============================================

REDIRECT_LOCK="/data/local/tmp/ff_redirect.lock"

apply_redirects_and_kstat() {
  # Serialize: only one instance writes redirect/kstat files at a time
  while ! ( set -o noclobber
    echo $$ > "$REDIRECT_LOCK"
  ) 2>/dev/null; do
    sleep 1
  done
  trap 'rm -f "$REDIRECT_LOCK"' EXIT INT TERM

  echo "Applying redirects+kstat..." >> $LOG

  > $SUSFS_DIR/sus_open_redirect.txt
  echo "[" > \
  $SUSFS_DIR/sus_kstat_statically.json
  FIRST=1

  echo "FF MAX arch dirs: $FFPATHS" >> $LOG
  redirect_pkg "$FFPATHS"  "$FF_LIB"  "$BACKUP_MAX"  "$BACKUP_MAX32"

  echo "FF Normal arch dirs: $FF2PATHS" >> $LOG
  redirect_pkg "$FF2PATHS" "$FF_LIB2" "$BACKUP_NORM" "$BACKUP_NORM32"

  echo "]" >> \
  $SUSFS_DIR/sus_kstat_statically.json

  setup_proc_redirect

  RCOUNT=$(grep -c "\.so" \
  $SUSFS_DIR/sus_open_redirect.txt \
  2>/dev/null)
  echo "Total redirects: $RCOUNT" >> $LOG
  echo "All redirects done!" >> $LOG

  rm -f "$REDIRECT_LOCK"
}

# ============================================
# STEP 1 — FETCH UIDs
# ============================================

echo "Fetching UIDs..." >> $LOG

FF_UID=""
RETRY=0
while [ -z "$FF_UID" ] && \
      [ $RETRY -lt 20 ]; do
  FF_UID=$(get_uid com.dts.freefiremax)
  RETRY=$((RETRY+1))
  [ -z "$FF_UID" ] && sleep 3
done

FF2_UID=$(get_uid com.dts.freefireth)
GMS_UID=$(get_uid com.google.android.gms)
PLAY_UID=$(get_uid com.android.vending)
GSF_UID=$(get_uid com.google.android.gsf)
DISC_UID=$(get_uid com.rem01gaming.disclosure)

echo "FF MAX UID:  $FF_UID" >> $LOG
echo "FF Norm UID: $FF2_UID" >> $LOG
echo "GMS UID:     $GMS_UID" >> $LOG
echo "Play UID:    $PLAY_UID" >> $LOG
echo "GSF UID:     $GSF_UID" >> $LOG
echo "Disclosure UID: $DISC_UID" >> $LOG

# ============================================
# STEP 2 — HIDE KERNEL AND ROM
# ============================================

echo "Hiding ROM..." >> $LOG

# Early-boot race: service.d fires before ksu_susfs module/binary is fully
# ready, so the first set_uname may no-op. Retry a few times with a short
# backoff until the spoof actually lands (verified via uname -r).
#
# NOTE: _SPOOF_REL/_SPOOF_VER MUST MATCH the /proc/version decoy written in
# setup_proc_redirect() (line ~338) EXACTLY. A mismatch between the uname()
# syscall spoof and the /proc/version file decoy is itself a 64-bit detection
# vector. Use the SAME plausible stock POCO/phoenixin kernel version string for
# both. This value (5.10.186-android13-4-00224-g870f7ff8f5ed) is a plausible
# GKI Android 13 kernel release chosen to clear the "booting with deprecated
# kernel" check (the real POCO phoenixin kernel is 4.14, which detectors flag).
# Display-only: SUSFS set_uname + /proc/version decoy; no ABI impact on the
# actual 4.14 kernel.
_SPOOF_REL="5.10.186-android13-4-00224-g870f7ff8f5ed"
_SPOOF_VER="PREEMPT Mon Sep 5 12:00:00 CST 2023"
_i=0
while [ "$_i" -lt 10 ]; do
  ksu_susfs set_uname "$_SPOOF_REL" "$_SPOOF_VER" 2>/dev/null
  if uname -r 2>/dev/null | grep -q "$_SPOOF_REL"; then
    echo "ROM uname spoofed (attempt $((_i+1)))" >> $LOG
    break
  fi
  _i=$((_i+1))
  sleep 2
done
if [ "$_i" -ge 10 ]; then
  echo "WARN: set_uname did not take after 10 retries" >> $LOG
fi

# /proc/cmdline leaks REAL androidboot.verifiedbootstate=orange even though the
# props are spoofed green — ACE reads bootloader_prop AND cmdline. Feed SUSFS a
# cleaned cmdline so the read hook (fs/proc/cmdline.c) serves green/locked.
# ponytail: string-swap only the known leak tokens; add new tokens here if ACE
# starts reading others (e.g. androidboot.veritymode).
_FAKE_CMDLINE=$(sed \
  -e 's/verifiedbootstate=orange/verifiedbootstate=green/g' \
  -e 's/verifiedbootstate=yellow/verifiedbootstate=green/g' \
  -e 's/verifiedbootstate=red/verifiedbootstate=green/g' \
  -e 's/androidboot.flash.locked=0/androidboot.flash.locked=1/g' \
  -e 's/device_state=unlocked/device_state=locked/g' /proc/cmdline)
_i=0
while [ "$_i" -lt 10 ]; do
  ksu_susfs set_cmdline "$_FAKE_CMDLINE" 2>/dev/null
  if tr ' ' '\n' < /proc/cmdline | grep -q 'verifiedbootstate=green'; then
    echo "cmdline spoofed green (attempt $((_i+1)))" >> $LOG
    break
  fi
  _i=$((_i+1))
  sleep 2
done
if [ "$_i" -ge 10 ]; then
  echo "WARN: set_cmdline did not take after 10 retries" >> $LOG
fi

# Spoof a coherent stock-like build. The detector cross-checks fingerprint
# against ro.build.version.sdk/release and scans for lineage/userdebug/Matrixx/
# test-keys/eng tokens. A fake Android-11 fingerprint on an Android-15 device is
# WORSE (SDK mismatch). Use one consistent Android-15 POCO fingerprint and scrub
# every custom-ROM token.
_FP="POCO/phoenixin/phoenix:15/BP1A.250505.005/Z1.9.28:user/release-keys"
resetprop ro.build.type "user"
resetprop ro.build.tags "release-keys"
resetprop ro.debuggable "0"
resetprop ro.force.debuggable "0"
resetprop ro.adb.secure "1"
resetprop ro.boot.selinux "enforcing"
resetprop ro.boot.verifiedbootstate "green"
resetprop ro.boot.flash.locked "1"
resetprop ro.boot.vbmeta.device_state "locked"
resetprop ro.boot.bootmode "normal"
resetprop ro.bootmode "normal"
# Disclosure flags a BLANK custom-ROM key as suspicious ("ro.lineage.device=")
# — blank is not the same as absent. Stock ROMs have no such key at all, so
# delete the keys entirely instead of blanking them. resetprop -d removes the
# property from the live prop tree; combined with the SUSFS path hides below
# this makes the keys both unreadable and non-existent to the detector.
for _k in ro.lineage.version ro.lineage.device ro.lineage.build.version \
          ro.matrixx.version ro.matrixx.build.version ro.matrixx.build.variant \
          ro.matrixx.device ro.matrixx.display.version ro.matrixx.display_resolution \
          ro.matrixx.chipset ro.matrixx.battery ro.matrixx.release.code \
          ro.matrixx.release.type ro.kernel.version; do
  resetprop -d "$_k" 2>/dev/null || resetprop "$_k" ""
done
resetprop ro.build.fingerprint "$_FP"
resetprop ro.build.description "phoenix-user 15 BP1A.250505.005 Z1.9.28 release-keys"
resetprop ro.build.display.id "$_FP"
resetprop ro.build.flavor "phoenix-user"
resetprop ro.build.id "BP1A.250505.005"
resetprop ro.build.version.incremental "Z1.9.28"
resetprop ro.bootimage.build.fingerprint "$_FP"
resetprop ro.system.build.fingerprint "Redmi/phoenix/phoenix:15/BP1A.250505.005/21.9.28:user/release-keys"
resetprop ro.system_ext.build.fingerprint "Redmi/phoenix/phoenix:15/BP1A.250505.005/21.9.28:user/release-keys"
resetprop ro.product.build.fingerprint "Redmi/phoenix/phoenix:15/BP1A.250505.005/21.9.28:user/release-keys"
resetprop ro.vendor.build.fingerprint "Redmi/phoenix/phoenix:15/BP1A.250505.005/21.9.28:user/release-keys"
resetprop ro.odm.build.fingerprint "Redmi/phoenix/phoenix:15/BP1A.250505.005/21.9.28:user/release-keys"
resetprop ro.vendor_dlkm.build.fingerprint "Redmi/phoenix/phoenix:15/BP1A.250505.005/21.9.28:user/release-keys"
resetprop ro.product.brand "POCO"
resetprop ro.product.model "POCO X2"
resetprop ro.product.device "phoenix"
resetprop ro.product.name "phoenixin"
resetprop ro.product.system.name "phoenixin"
resetprop ro.product.system_ext.name "phoenixin"
resetprop ro.product.vendor.name "phoenixin"
resetprop ro.product.odm.name "phoenixin"
resetprop ro.product.product.name "phoenixin"
resetprop ro.product.vendor_dlkm.name "phoenixin"
resetprop ro.product.manufacturer "Xiaomi"

# ── lineage/crdroid ROM tell: ro.lineage.* props ──
# The ROM ships these (even when empty, the property NAMES are the tell
# detectors read via __system_property_get). Mask the high-signal ones to
# POCO stock values so the "found suspicious prop (ro.lineage.device=)" check
# can't match. Keep as resetprop (runtime memory tree), not file edits.
for _lp in \
    ro.lineage.device ro.lineage.version ro.lineage.build.version \
    ro.lineage.display.version ro.lineage.releasetype ro.lineage.build.date \
    ro.lineage.build.date.utc ro.lineage.build.id ro.lineage.build.type \
    ro.lineage.build.zip_type ro.lineagelegal.url ro.modversion \
    ro.crdroidlegal.url ro.build.lineage.version; do
    resetprop -d "$_lp" 2>/dev/null || resetprop "$_lp" ""
done

echo "ROM hidden!" >> $LOG

# ============================================
# STEP 3 — UPDATE SUSFS FILES
# ============================================

update_susfs_files

# ============================================
# STEP 4 — LIVE APPLY UID HIDING
# ============================================

apply_uid_hiding

# ============================================
# STEP 5 — FIND GAME PATHS
#
# Each FF package is detected FULLY INDEPENDENTLY and may ship 32-bit (arm),
# 64-bit (arm64), or BOTH — whichever ABIs are actually installed for that
# app. FFPATHS / FF2PATHS hold the SPACE-SEPARATED list of every installed
# arch-lib dir for MAX / Normal. Nothing is shared between the two apps.
# ============================================

# List-returning detector: every installed ABI lib dir for a package.
# Anchored to */lib/arm* so the per-app oat/arm dirs are skipped.
detect_ff() {
  _pkg="$1"; _pvar="$2"
  _list=""
  for d in $(find /data/app -type d -name arm64 -path '*/lib/arm64' 2>/dev/null | grep "$_pkg"); do
    _list="$_list $d"
  done
  for d in $(find /data/app -type d -name arm  -path '*/lib/arm'  2>/dev/null | grep "$_pkg"); do
    _list="$_list $d"
  done
  eval "$_pvar=\"$_list\""
}

echo "Finding FF paths..." >> $LOG

FFPATHS=""
FF2PATHS=""
RETRY=0

while [ -z "$FFPATHS" ] && \
      [ $RETRY -lt 15 ]; do
  detect_ff freefiremax FFPATHS
  [ -n "$FFPATHS" ] && break
  RETRY=$((RETRY+1))
  echo "Retrying FF MAX... ($RETRY/15)" >> $LOG
  sleep 2
done

RETRY=0
while [ -z "$FF2PATHS" ] && \
      [ $RETRY -lt 15 ]; do
  detect_ff freefireth FF2PATHS
  [ -n "$FF2PATHS" ] && break
  RETRY=$((RETRY+1))
  echo "Retrying FF Normal... ($RETRY/15)" >> $LOG
  sleep 2
done

echo "FF MAX arch dirs: $FFPATHS" >> $LOG
echo "FF Normal arch dirs: $FF2PATHS" >> $LOG
echo "FF MAX LIB: $FF_LIB" >> $LOG
echo "FF Norm LIB: $FF_LIB2" >> $LOG

# ============================================
# STEP 6 — BACKUP DIRS (manual populate)
# ============================================

ensure_backup_dirs

# ============================================
# STEP 7 — APPLY REDIRECTS + KSTAT + PROC
# ============================================

apply_redirects_and_kstat

# ============================================
# STEP 8 — ANDROID ID + CACHE CLEAR
# ============================================

NEW_ID=$(cat /dev/urandom | \
tr -dc 'a-f0-9' | head -c 16)
settings put secure android_id $NEW_ID
echo "Boot ID: $NEW_ID" >> $LOG

rm -rf $FF_CACHE/* 2>/dev/null
rm -rf $FF_FILES/sdk_validate.cfg 2>/dev/null
rm -rf $FF_FILES/*.log 2>/dev/null
rm -rf $FF_FILES/crash* 2>/dev/null
rm -rf $FF_PREFS/crash* 2>/dev/null
rm -rf $FF_PREFS/firebase* 2>/dev/null
rm -rf $FF_PREFS/Adjust* 2>/dev/null
rm -rf $FF_CACHE2/* 2>/dev/null
rm -rf $FF_FILES2/sdk_validate.cfg 2>/dev/null
rm -rf $FF_FILES2/*.log 2>/dev/null
rm -rf $FF_FILES2/crash* 2>/dev/null
rm -rf $FF_PREFS2/crash* 2>/dev/null
rm -rf $FF_PREFS2/firebase* 2>/dev/null
rm -rf $FF_PREFS2/Adjust* 2>/dev/null
rm -rf $GMS_CACHE/* 2>/dev/null
rm -rf $GSF_CACHE/* 2>/dev/null
rm -rf $PLAY_CACHE/* 2>/dev/null
rm -rf $SEARCH_CACHE/* 2>/dev/null
rm -f /data/user/0/com.android.vending/shared_prefs/finsky.xml 2>/dev/null
rm -f /data/user/0/com.android.vending/shared_prefs/vending_preferences.xml 2>/dev/null
rm -rf /data/user/0/com.android.vending/shared_prefs/Firebase* 2>/dev/null
rm -f /data/user/0/com.android.vending/files/finsky/shared/apk_processor_valuestore.pb 2>/dev/null
rm -rf /data/user/0/com.google.android.googlequicksearchbox/shared_prefs/Firebase* 2>/dev/null
rm -f /data/user/0/com.google.android.settings.intelligence/shared_prefs/pref_index_state.xml 2>/dev/null
rm -f /data/user/0/com.google.android.settings.intelligence/shared_prefs/app_search_index_prefs.xml 2>/dev/null
rm -f /data/user/0/com.google.android.settings.intelligence/shared_prefs/slice_index_prefs.xml 2>/dev/null
rm -f /data/data/com.android.vending/shared_prefs/finsky.xml 2>/dev/null
rm -f /data/data/com.android.vending/shared_prefs/vending_preferences.xml 2>/dev/null
rm -rf /data/data/com.android.vending/shared_prefs/Firebase* 2>/dev/null
rm -f /data/data/com.android.vending/files/finsky/shared/apk_processor_valuestore.pb 2>/dev/null
rm -rf /data/data/com.google.android.googlequicksearchbox/shared_prefs/Firebase* 2>/dev/null
rm -f /data/data/com.google.android.settings.intelligence/shared_prefs/pref_index_state.xml 2>/dev/null
rm -f /data/data/com.google.android.settings.intelligence/shared_prefs/app_search_index_prefs.xml 2>/dev/null
rm -f /data/data/com.google.android.settings.intelligence/shared_prefs/slice_index_prefs.xml 2>/dev/null

echo "Caches cleared!" >> $LOG

# Re-assert the uname spoof after a short delay. The early service.d window
# applies it (logged above) but KSU/Manager may reset utsname during late
# boot, reverting the spoof. Re-applying once things have settled makes the
# spoof stick for the steady-state session.
sleep 8
ksu_susfs set_uname "$_SPOOF_REL" "$_SPOOF_VER" 2>/dev/null
if uname -r 2>/dev/null | grep -q "$_SPOOF_REL"; then
  echo "ROM uname re-asserted post-boot" >> $LOG
else
  echo "WARN: set_uname re-assert did not take" >> $LOG
fi

echo "=== Boot setup complete ===" >> $LOG
echo "=== Starting main loop ===" >> $LOG

# ============================================
# STEP 9 — MAIN LOOP
# ============================================

FF_WAS_RUNNING=0

while true; do

  FF_PID=$(pidof $FF_PKG)
  FF2_PID=$(pidof $FF_PKG2)

  if [ -n "$FF_PID" ] || \
     [ -n "$FF2_PID" ]; then

    FF_WAS_RUNNING=1

    NEW_ID=$(cat /dev/urandom | \
    tr -dc 'a-f0-9' | head -c 16)
    settings put secure android_id $NEW_ID
    echo "ID: $NEW_ID" >> $LOG

    rm -rf $FF_CACHE/* 2>/dev/null
    rm -rf $FF_PREFS/firebase* 2>/dev/null
    rm -rf $FF_PREFS/Adjust* 2>/dev/null
    rm -rf $FF_CACHE2/* 2>/dev/null
    rm -rf $FF_PREFS2/firebase* 2>/dev/null
    rm -rf $FF_PREFS2/Adjust* 2>/dev/null

    echo "In-game clean!" >> $LOG
    sleep 5

  else

    if [ "$FF_WAS_RUNNING" = "1" ]; then

      # Debounce: confirm game is really gone, not just a
      # brief pidof miss between restarts or screen transitions
      sleep 3
      FF_PID=$(pidof $FF_PKG)
      FF2_PID=$(pidof $FF_PKG2)
      if [ -n "$FF_PID" ] || [ -n "$FF2_PID" ]; then
        FF_WAS_RUNNING=1
        sleep 10
        continue
      fi

      echo "FF closed! Cleaning..." >> $LOG

      rm -f /data/user/0/com.android.vending/shared_prefs/finsky.xml 2>/dev/null
      rm -f /data/user/0/com.android.vending/shared_prefs/vending_preferences.xml 2>/dev/null
      rm -rf /data/user/0/com.android.vending/shared_prefs/Firebase* 2>/dev/null
      rm -f /data/user/0/com.android.vending/files/finsky/shared/apk_processor_valuestore.pb 2>/dev/null
      rm -rf /data/user/0/com.google.android.googlequicksearchbox/shared_prefs/Firebase* 2>/dev/null
      rm -f /data/user/0/com.google.android.settings.intelligence/shared_prefs/pref_index_state.xml 2>/dev/null
      rm -f /data/user/0/com.google.android.settings.intelligence/shared_prefs/app_search_index_prefs.xml 2>/dev/null
      rm -f /data/user/0/com.google.android.settings.intelligence/shared_prefs/slice_index_prefs.xml 2>/dev/null
      rm -rf $FF_CACHE/* 2>/dev/null
      rm -rf $FF_FILES/sdk_validate.cfg 2>/dev/null
      rm -rf $FF_FILES/*.log 2>/dev/null
      rm -rf $FF_FILES/crash* 2>/dev/null
      rm -rf $FF_PREFS/* 2>/dev/null
      rm -rf $FF_CACHE2/* 2>/dev/null
      rm -rf $FF_FILES2/sdk_validate.cfg 2>/dev/null
      rm -rf $FF_FILES2/*.log 2>/dev/null
      rm -rf $FF_FILES2/crash* 2>/dev/null
      rm -rf $FF_PREFS2/* 2>/dev/null
      rm -rf $GMS_CACHE/* 2>/dev/null
      rm -rf $GSF_CACHE/* 2>/dev/null
      rm -rf $PLAY_CACHE/* 2>/dev/null
      rm -rf $SEARCH_CACHE/* 2>/dev/null

      NEW_ID=$(cat /dev/urandom | \
      tr -dc 'a-f0-9' | head -c 16)
      settings put secure android_id $NEW_ID
      echo "Post ID: $NEW_ID" >> $LOG

      resetprop ro.build.type "user"
      resetprop ro.debuggable "0"
      resetprop ro.boot.verifiedbootstate \
      "green"

      apply_uid_hiding
      apply_redirects_and_kstat

      FF_WAS_RUNNING=0
      echo "Cleanup done!" >> $LOG
    fi

    sleep 10
  fi

done
