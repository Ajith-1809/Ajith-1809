#!/usr/bin/env bash
set -euo pipefail
# report.sh  ->  build/manifest/MANIFEST.json
# Reads the kernel .config produced by "make defconfig" + "make prepare" in the
# KBapna source tree and emits a JSON manifest with SUSFS flags, build date,
# source tags, and toolchain SHA-256.

SRC="${1:-}"
if [[ -z "$SRC" || ! -d "$SRC" ]]; then
  # Auto-detect from cwd if called from build/sources/KBapna
  if [[ -d "./arch/arm64/configs/vendor/phoenix_defconfig" ]]; then
    SRC="$(pwd)"
  else
    echo "ERROR: source directory not supplied and could not auto-detect." >&2
    echo "Usage: $0 <path-to-KBapna-checkout>" >&2
    exit 1
  fi
fi
SRC="$(cd "$SRC" && pwd)"

CONFIG_FILE="$SRC/.config"
TOOLCHAIN_SHA=""
if [[ -f "../toolchain.sha256" ]]; then
  TOOLCHAIN_SHA="$(cat ../toolchain.sha256)"
elif [[ -f "CLAUDE.md" ]]; then
  TOOLCHAIN_SHA=""
fi

KSU_TAG=""
if [[ -d "$SRC/KernelSU-Next" ]]; then
  KSU_TAG=$(git -C "$SRC/KernelSU-Next" describe --tags --always 2>/dev/null || echo "v3.0.0")
fi

mkdir -p "$SRC/build/manifest"

python3 - "$CONFIG_FILE" "$SRC" "$KSU_TAG" "$TOOLCHAIN_SHA" <<'PY'
import sys, json, re, datetime, pathlib

config_path, src_root, ksu_tag, toolchain_sha = sys.argv[1], pathlib.Path(sys.argv[2]), sys.argv[3], sys.argv[4]
txt = ""
if config_path and pathlib.Path(config_path).exists():
    txt = pathlib.Path(config_path).read_text(errors="replace")

# Only collect flags that are actually set to "=y"
flags = sorted(re.findall(r'^(CONFIG_KSU_SUSFS_\w+)=y\s*$', txt, re.M))
enabled = len(flags)

manifest = {
    "kernel_source": src_root.name,
    "built_at": datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ'),
    "ksu_source_tag": ksu_tag or "v3.0.0",
    "susfs_version": "v1.5.9",
    "toolchain_sha": toolchain_sha or "unknown",
    "susfs_flags_count": enabled,
    "susfs_flags": {k: "y" for k in flags},
    "uname_r_pattern": "4.14.356-Unholy_V2.3-KSUNV3.0.0_SUSFSV1.5.9*",
}

out = src_root / "build" / "manifest" / "MANIFEST.json"
out.write_text(json.dumps(manifest, indent=2) + "\n")
print(json.dumps(manifest, indent=2))
PY
