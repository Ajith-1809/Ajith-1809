#!/system/bin/sh
# postflash_smoke.sh
# One-shot binary pass/fail verification for the v2.3 KSUNv3.0.0+SUSFSv1.5.9 kernel.
# Usage (from host):  adb shell sh -s docs/postflash_smoke.sh
# Usage (on-device):  sh /data/local/tmp/postflash_smoke.sh
PASS=0
FAIL=0
check() {
  desc="$1"
  got="$2"
  expect="$3"
  if echo "$got" | grep -qE "$expect"; then
    echo "PASS  $desc: $got"
    PASS=$((PASS + 1))
  else
    echo "FAIL  $desc: expected /$expect/ — got: $got"
    FAIL=$((FAIL + 1))
  fi
}

echo "=============================================="
echo " postflash_smoke.sh  —  v2.3 KSUNv3.0.0+SUSFSv1.5.9"
echo "=============================================="
echo

echo "== 1. uname -r  (expect *Unholy*KSUN*V3*) =="
check uname "$(uname -r)" 'Unholy.*KSUN.*V3'
echo

echo "== 2. /proc/version  (expect clang 12.0.5 / r416183b) =="
check proc_ver "$(cat /proc/version)" 'clang version 12\.[0-9]+\.[0-9]+.*r416183b'
echo

echo "== 3. ksud debug version  (expect Kernel Version >= 13000) =="
KSU_RAW=$(ksud debug version 2>/dev/null || true)
# Output format: "Kernel Version: 0" or "Kernel Version: 13000"
check ksu "$KSU_RAW" 'Kernel Version: 1[3-9][0-9]{2,}'
echo

echo "== 4. susfs variant  (expect NON-GKI) =="
SUS_VAR=$(ksu_susfs show variant 2>/dev/null || true)
check susfs_variant "$SUS_VAR" 'NON-GKI'
echo

echo "== 5. susfs version  (expect v1.5.9) =="
SUS_VER=$(ksu_susfs show version 2>/dev/null || true)
check susfs_ver "$SUS_VER" 'v1\.5\.9'
echo

echo "== 6. susfs enabled_features  (expect 14 lines) =="
FEATURES=$(ksu_susfs show enabled_features 2>/dev/null | wc -l)
check features "$FEATURES" '^14$'
echo

echo "== 7. manager package present  (expect /data/app/) =="
PM_PATH=$(pm path com.rifsxd.ksunext 2>/dev/null || true)
check pm_path "$PM_PATH" '/data/app/'
echo

echo "== 8. manager versionCode  (expect 33129, i.e. v3.2.0) =="
VERCODE=$(pm dump com.rifsxd.ksunext 2>/dev/null \
  | grep -E 'versionCode' | head -1 | sed 's/.*=//' | tr -d '[:space:]')
check mgr_ver "$VERCODE" '^33129$'
echo

echo "== 9. 17 modules all enabled =="
MOD_JSON=$(sudo ksud module list 2>/dev/null || true)
ENABLED_COUNT=$(echo "$MOD_JSON" | grep -c '"enabled": *true' || true)
check modules "$ENABLED_COUNT" '^17$'
echo

echo "== 10. boot-time susfs log  (expect CMD_SUSFS_SHOW_VERSION in dmesg) =="
DMESG_SUSFS=$(dmesg 2>/dev/null | grep -i 'CMD_SUSFS_SHOW_VERSION' | tail -1 || true)
check susfs_log "$DMESG_SUSFS" 'CMD_SUSFS_SHOW_VERSION'
echo

echo "=============================================="
echo " RESULT: $PASS passed, $FAIL failed"
echo "=============================================="

if [[ "$FAIL" -gt 0 ]]; then
  echo "ROLLBACK: fastboot flash boot boot_backup_v2.2.img && fastboot reboot"
fi
exit "$FAIL"
