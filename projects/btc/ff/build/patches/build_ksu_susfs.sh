#!/usr/bin/env bash
# Cross-compile a custom ksu_susfs (SUSFS v1.5.5, ABI sys_reboot) that adds the
# GKI-backport commands (add_sus_maps / update_sus_maps). The stock v1.5.5 userspace
# tool never sends 0x5556d, so we compile our own to drive the already-wired kernel
# SUS_MAP display hook.
#
# Requires the Android NDK. Two ways to supply it:
#   1. NDK_HOME / ANDROID_NDK_HOME env var pointing at an NDK install.
#   2. (CI) actions/setup-ndk, which exports ANDROID_NDK_HOME.
#   3. (CI fallback) run with --download to fetch r25b linux zip into ./ndk.
set -euo pipefail

SRC_DIR="$(cd "$(dirname "$0")/susfs_userspace" && pwd)"
OUT="${1:-ksu_susfs}"

# --- locate NDK clang ---
CLANG=""
if [ -n "${ANDROID_NDK_HOME:-}" ]; then
  CLANG="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang"
elif [ -n "${NDK_HOME:-}" ]; then
  CLANG="$NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang"
fi

if [ "${1:-}" = "--download" ] || [ -z "$CLANG" ]; then
  echo "[build_ksu_susfs] NDK not found in env; downloading r25b (linux-x86_64)..."
  TMP="$(mktemp -d)"
  curl -fL --retry 3 -o "$TMP/ndk.zip" \
    "https://dl.google.com/android/repository/android-ndk-r25b-linux.zip"
  unzip -q "$TMP/ndk.zip" -d "$TMP"
  NDK="$TMP/android-ndk-r25b"
  CLANG="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang"
fi

[ -x "$CLANG" ] || { echo "[build_ksu_susfs] clang not found: $CLANG"; exit 1; }

echo "[build_ksu_susfs] compiling with $CLANG"
"$CLANG" -static -O2 -D__ANDROID_API__=21 \
  -I "$SRC_DIR" \
  "$SRC_DIR/main.c" -o "$OUT"

chmod 755 "$OUT"
echo "[build_ksu_susfs] built -> $OUT ($(wc -c < "$OUT") bytes)"

# sanity: binary must expose add_sus_maps
if "$OUT" 2>&1 | grep -q "add_sus_maps"; then
  echo "[build_ksu_susfs] add_sus_maps present OK"
else
  echo "[build_ksu_susfs] ERROR: add_sus_maps missing from built binary"; exit 1
fi
