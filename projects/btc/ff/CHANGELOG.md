# Changelog

## v2.3 — Unholy_V2.3-KSUNV3.0.0-SUSFSV1.5.9 (planned 2026-06-22)

- Kernel-side upgrade: legacy `tiann/KernelSU` (module-id 12851, ABI 0) → rifsxd KernelSU-Next `v3.0.0` (ABI `~13000+`).
- Kernel-side SUSFS upgraded `v1.5.5` → `v1.5.9` (NON-GKI, kernel 4.14).
- All 14 `CONFIG_KSU_SUSFS_*` flags remain enabled at compile time.
- Build uses Android clang `r416183b` (LLVM 12.0.5 / LLD 12.0.5), matching `/proc/version` compiler tags of the reference kernel.
- Source base: KBapna `Unholy_KSUN+SUSFS` tag `v2.2_Unholy_SUSFS` (Dec 7 2025). Overlaid with rifsxd/KernelSU-Next `v3.0.0` and sidex15/susfs4ksu-module `v1.5.9`.
- Build host migrated from local Windows (no compiler, no git, no magiskboot) → GitHub Actions `ubuntu-latest` runner.
- Flash preserves existing magisk-patched ramdisk; root + 17 modules expected to survive.
- Output: `kernel-phoenix-v2.3-KSUNV3.0.0_SUSFSV1.5.9-<YYYYMMDD>.img` + `AnyKernel3-*.zip` + `MANIFEST.json`.
