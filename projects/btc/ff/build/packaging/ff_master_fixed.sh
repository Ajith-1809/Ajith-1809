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

BACKUP="/data/local/tmp/ff"
BACKUP2="/data/local/tmp/ff32"
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

mkdir -p $BACKUP
mkdir -p $BACKUP2
mkdir -p $CLEAN_PROC
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
/proc/cmdline
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
# FUNCTION — AUTO BACKUP LIBS
#
# 32-bit:
#   FFPATH (arm)  → BACKUP2
#   FF_LIB        → BACKUP2
#   FF2PATH (arm) → BACKUP2
#   FF_LIB2       → BACKUP2
#
# 64-bit:
#   FFPATH (arm64)  → BACKUP
#   FF2PATH (arm64) → BACKUP
# ============================================

auto_backup_libs() {
  echo "Auto backing up libs..." >> $LOG

  if [ "$IS_32BIT" = "1" ]; then

    # FFPATH arm → BACKUP2
    if [ -n "$FFPATH" ]; then
      for LIB in $LIBS; do
        if [ ! -f "$BACKUP2/$LIB" ] && \
           [ -f "$FFPATH/$LIB" ]; then
          cp "$FFPATH/$LIB" "$BACKUP2/$LIB"
          echo "32bit arm: $LIB" >> $LOG
        fi
      done
    fi

    # FF_LIB extracted → BACKUP2
    if [ -d "$FF_LIB" ]; then
      for LIB in $LIBS; do
        if [ ! -f "$BACKUP2/$LIB" ] && \
           [ -f "$FF_LIB/$LIB" ]; then
          cp "$FF_LIB/$LIB" "$BACKUP2/$LIB"
          echo "32bit lib: $LIB" >> $LOG
        fi
      done
    fi

    # FF Normal arm → BACKUP2
    if [ -n "$FF2PATH" ]; then
      for LIB in $LIBS; do
        if [ ! -f "$BACKUP2/$LIB" ] && \
           [ -f "$FF2PATH/$LIB" ]; then
          cp "$FF2PATH/$LIB" "$BACKUP2/$LIB"
          echo "32bit FF2 arm: $LIB" >> $LOG
        fi
      done
    fi

    # FF_LIB2 extracted → BACKUP2
    if [ -d "$FF_LIB2" ]; then
      for LIB in $LIBS; do
        if [ ! -f "$BACKUP2/$LIB" ] && \
           [ -f "$FF_LIB2/$LIB" ]; then
          cp "$FF_LIB2/$LIB" "$BACKUP2/$LIB"
          echo "32bit FF2 lib: $LIB" >> $LOG
        fi
      done
    fi

  else

    # FFPATH arm64 → BACKUP
    if [ -n "$FFPATH" ]; then
      for LIB in $LIBS; do
        if [ ! -f "$BACKUP/$LIB" ] && \
           [ -f "$FFPATH/$LIB" ]; then
          cp "$FFPATH/$LIB" "$BACKUP/$LIB"
          echo "64bit: $LIB" >> $LOG
        fi
      done
    fi

    # FF Normal arm64 → BACKUP
    if [ -n "$FF2PATH" ]; then
      for LIB in $LIBS; do
        if [ ! -f "$BACKUP/$LIB" ] && \
           [ -f "$FF2PATH/$LIB" ]; then
          cp "$FF2PATH/$LIB" "$BACKUP/$LIB"
          echo "64bit FF2: $LIB" >> $LOG
        fi
      done
    fi

  fi

  T64=$(ls $BACKUP/*.so 2>/dev/null | wc -l)
  T32=$(ls $BACKUP2/*.so 2>/dev/null | wc -l)
  echo "64bit total: $T64" >> $LOG
  echo "32bit total: $T32" >> $LOG
  echo "Auto backup done!" >> $LOG
}

# ============================================
# FUNCTION — PROC REDIRECTS
# ============================================

setup_proc_redirect() {
  echo "Setting up proc redirects..." >> $LOG

  cat > $CLEAN_PROC/version << EOF
Linux version 4.14.186-perf+-android-15-00224-g870f7ff8f5ed (android-build@abfarm-us-east1-c-0097) (Android (7284624, based on r416183b) clang version 12.0.5) #1 SMP PREEMPT Mon Jan 10 12:00:00 CST 2022
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

# ============================================
# FUNCTION — APPLY ALL REDIRECTS + KSTAT
#
# 32-bit: redirect arm path + FF_LIB path
#         (both are used by Android loader)
#
# 64-bit: redirect arm64 path only
#         (FF_LIB not used for 64-bit)
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

  if [ "$IS_32BIT" = "1" ]; then

    # FF MAX arm path → BACKUP2
    if [ -n "$FFPATH" ]; then
      echo "FF MAX 32bit (arm)..." >> $LOG
      for LIB in $LIBS; do
        process_lib \
        "$FFPATH/$LIB" \
        "$BACKUP2/$LIB"
      done
    fi

    # FF MAX extracted lib → BACKUP2
    echo "FF MAX 32bit (lib)..." >> $LOG
    for LIB in $LIBS; do
      process_lib \
      "$FF_LIB/$LIB" \
      "$BACKUP2/$LIB"
    done

    # FF Normal arm path → BACKUP2
    if [ -n "$FF2PATH" ]; then
      echo "FF Normal 32bit (arm)..." >> $LOG
      for LIB in $LIBS; do
        process_lib \
        "$FF2PATH/$LIB" \
        "$BACKUP2/$LIB"
      done
    fi

    # FF Normal extracted lib → BACKUP2
    if [ -d "$FF_LIB2" ]; then
      echo "FF Normal 32bit (lib)..." >> $LOG
      for LIB in $LIBS; do
        process_lib \
        "$FF_LIB2/$LIB" \
        "$BACKUP2/$LIB"
      done
    fi

  else

    # FF MAX arm64 → BACKUP
    if [ -n "$FFPATH" ]; then
      echo "FF MAX 64bit..." >> $LOG
      for LIB in $LIBS; do
        process_lib \
        "$FFPATH/$LIB" \
        "$BACKUP/$LIB"
      done
    fi

    # FF Normal arm64 → BACKUP
    if [ -n "$FF2PATH" ]; then
      echo "FF Normal 64bit..." >> $LOG
      for LIB in $LIBS; do
        process_lib \
        "$FF2PATH/$LIB" \
        "$BACKUP/$LIB"
      done
    fi

  fi

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

echo "FF MAX UID:  $FF_UID" >> $LOG
echo "FF Norm UID: $FF2_UID" >> $LOG
echo "GMS UID:     $GMS_UID" >> $LOG
echo "Play UID:    $PLAY_UID" >> $LOG
echo "GSF UID:     $GSF_UID" >> $LOG

# ============================================
# STEP 2 — HIDE KERNEL AND ROM
# ============================================

echo "Hiding ROM..." >> $LOG

ksu_susfs set_uname \
"4.14.186-perf+-android-15-00224-g870f7ff8f5ed" \
"PREEMPT Mon Jan 10 12:00:00 CST 2022"

resetprop ro.build.type "user"
resetprop ro.build.tags "release-keys"
resetprop ro.debuggable "0"
resetprop ro.adb.secure "1"
resetprop ro.boot.selinux "enforcing"
resetprop ro.boot.verifiedbootstate "green"
resetprop ro.boot.flash.locked "1"
resetprop ro.boot.vbmeta.device_state "locked"
resetprop ro.lineage.version ""
resetprop ro.matrixx.version ""
resetprop ro.kernel.version ""
resetprop ro.build.fingerprint \
"POCO/phoenixin/phoenix:11/RKQ1.200826.002/Z1.9.28:user/release-keys"
resetprop ro.bootimage.build.fingerprint \
"POCO/phoenixin/phoenix:11/RKQ1.200826.002/Z1.9.28:user/release-keys"
resetprop ro.product.brand "POCO"
resetprop ro.product.model "POCO X2"
resetprop ro.product.device "phoenix"
resetprop ro.product.manufacturer "Xiaomi"

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
# Try arm64 first (64-bit device)
# Fall back to arm (32-bit device)
# IS_32BIT flag controls all later logic
# ============================================

echo "Finding FF paths..." >> $LOG

IS_32BIT=0
FFPATH=""
RETRY=0

while [ -z "$FFPATH" ] && \
      [ $RETRY -lt 15 ]; do

  # Try 64-bit first
  FFPATH=$(find /data/app -type d \
    -name "arm64" 2>/dev/null | \
    grep "freefiremax" | head -1)

  if [ -n "$FFPATH" ]; then
    IS_32BIT=0
    break
  fi

  # Fall back to 32-bit
  FFPATH=$(find /data/app -type d \
    -name "arm" 2>/dev/null | \
    grep "freefiremax" | head -1)

  if [ -n "$FFPATH" ]; then
    IS_32BIT=1
    break
  fi

  RETRY=$((RETRY+1))
  echo "Retrying FF MAX... ($RETRY/15)" \
  >> $LOG
  sleep 2
done

if [ -z "$FFPATH" ]; then
  echo "FF MAX path not found! Assuming 32-bit." \
  >> $LOG
  IS_32BIT=1
fi

echo "FF MAX: $FFPATH" >> $LOG
if [ "$IS_32BIT" = "1" ]; then
  echo "Mode: 32-bit" >> $LOG
else
  echo "Mode: 64-bit" >> $LOG
fi

# FF Normal path — match same arch as FF MAX
FF2PATH=""
if [ "$IS_32BIT" = "1" ]; then
  FF2PATH=$(find /data/app -type d \
    -name "arm" 2>/dev/null | \
    grep "freefireth" | head -1)
else
  FF2PATH=$(find /data/app -type d \
    -name "arm64" 2>/dev/null | \
    grep "freefireth" | head -1)
fi

if [ -n "$FF2PATH" ]; then
  echo "FF Normal: $FF2PATH" >> $LOG
else
  echo "FF Normal not installed" >> $LOG
fi

echo "FF MAX LIB: $FF_LIB" >> $LOG
echo "FF Norm LIB: $FF_LIB2" >> $LOG

# ============================================
# STEP 6 — AUTO BACKUP LIBS
# ============================================

auto_backup_libs

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
