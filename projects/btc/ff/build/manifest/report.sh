#!/bin/bash
# Generate MANIFEST.json for the kernel build
# Usage: report.sh <kernel_source_dir>
# Output: $kernel_source_dir/build/manifest/MANIFEST.json

set -euo pipefail

KERNEL_SRC="${1:-$PWD}"
CONFIG="$KERNEL_SRC/.config"
OUTDIR="$KERNEL_SRC/build/manifest"
OUTFILE="$OUTDIR/MANIFEST.json"

mkdir -p "$OUTDIR"

# Build timestamp
BUILT_AT=$(date -u +%Y%m%dT%H%M%SZ)

# Extract SUSFS flags from .config
SUSFS_FLAGS=$(grep "^CONFIG_KSU_SUSFS_" "$CONFIG" 2>/dev/null | grep "=y$" | sort || true)
FLAGS_COUNT=$(echo "$SUSFS_FLAGS" | wc -l)

# KSU source tag (from env or detected)
KSU_TAG="${KSU_SOURCE_TAG:-v3.2.0-legacy}"

# SUSFS version (from env or detected)
SUSFS_VER="${SUSFS_SOURCE_VERSION:-v1.5.5 (kernel-4.14 + GKI backport)}"

# Build JSON
{
  printf '{\n'
  printf '  "kernel_source": "tillua467",\n'
  printf '  "built_at": "%s",\n' "$BUILT_AT"
  printf '  "ksu_source_tag": "%s",\n' "$KSU_TAG"
  printf '  "susfs_version": "%s",\n' "$SUSFS_VER"
  printf '  "toolchain_sha": "unknown",\n'
  printf '  "susfs_flags_count": %d,\n' "$FLAGS_COUNT"
  printf '  "susfs_flags": {\n'

  FIRST=1
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    key=$(echo "$line" | cut -d= -f1)
    val=$(echo "$line" | cut -d= -f2)
    if [ "$FIRST" -eq 1 ]; then
      FIRST=0
    else
      printf ',\n'
    fi
    printf '    "%s": "%s"' "$key" "$val"
  done <<< "$SUSFS_FLAGS"

  printf '\n'
  printf '  },\n'
  printf '  "uname_r_pattern": "4.14.*-KSUNV3.2.0_SUSFSV1.5.5*"\n'
  printf '}\n'
} > "$OUTFILE"

echo "MANIFEST.json written: $OUTFILE ($FLAGS_COUNT flags)"
cat "$OUTFILE"
