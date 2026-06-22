#!/usr/bin/env bash
# pull_config.sh
# Pull the running device's /proc/config.gz back into build/config/
# Usage: pull_config.sh [device_serial]
# If no serial is supplied, uses whatever adb device is currently online.
set -euo pipefail

usage() {
  echo "Usage: $0 [device_serial]"
  echo "  device_serial: optional ADB serial (e.g. 5b389e4c or 192.168.x.x:5555)"
  exit 1
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
fi

ADB_SERIAL="${1:-}"
if [[ -z "$ADB_SERIAL" ]]; then
  ADB_CMD=(adb)
else
  ADB_CMD=(adb -s "$ADB_SERIAL")
fi

# Resolve the repo root: use git if available, otherwise fall back to script location.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || cd "$SCRIPT_DIR/../.." && pwd)"
OUT_DIR="$REPO_ROOT/build/config"
mkdir -p "$OUT_DIR"

echo "[pull_config] ADB base: ${ADB_CMD[*]}"

# Wait for device to come online.
"${ADB_CMD[@]}" wait-for-device

# Ensure we have root so we can read /proc/config.gz.
"${ADB_CMD[@]}" root || true
sleep 1
"${ADB_CMD[@]}" wait-for-device

# Pull /proc/config.gz to the host. The device-side zcat fallback ports
# the gzipped blob through stdout so we can decompress locally.
OUT_FILE="$OUT_DIR/device_config.gz"
REMOTE_TMP="/data/local/tmp/device_config.gz"

set +e
"${ADB_CMD[@]}" pull /proc/config.gz "$OUT_FILE"
PULL_RC=$?
set -e

if [[ $PULL_RC -ne 0 ]]; then
  echo "[pull_config] direct pull failed, trying adb shell zcat …"
  "${ADB_CMD[@]}" shell "zcat /proc/config.gz" > "$OUT_FILE" 2>/dev/null \
    || "${ADB_CMD[@]}" shell "cat /proc/config.gz" > "$OUT_FILE" 2>/dev/null \
    || { echo "[pull_config] ERROR: could not read /proc/config.gz from device"; exit 1; }
fi

# Canonify: gunzip and feed through merge_config.sh so we get a clean flat .config.
FLAT_CONFIG="$OUT_DIR/device_config"
gunzip -c "$OUT_FILE" > "$FLAT_CONFIG" 2>/dev/null || cp "$OUT_FILE" "$FLAT_CONFIG"

# Line-count sanity check — a typical 4.14 config is ~4000–7000 lines.
LINES=$(wc -l < "$FLAT_CONFIG")
echo "[pull_config] device config: $LINES lines -> $FLAT_CONFIG"

if [[ "$LINES" -lt 500 ]]; then
  echo "[pull_config] WARNING: config looks unusually short; double-check the result."
fi

echo "[pull_config] done."
