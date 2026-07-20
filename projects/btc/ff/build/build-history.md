# Build history (reconstructed)

Reconstructed 2026-07-20 from local backups after `Ajith-1809/Ajith-1809` was
deleted + recreated. **Server-side data is gone** — GitHub Actions run logs,
run numbers, and the uploaded-artifact store live only on GitHub and are NOT in
any bundle. This file records what the backups actually retain.

## Sources
- `E:\ff_full_backup_202607192101.bundle` (310.8 MB) — full git history (workflow YAML evolution).
- `E:\ff_keep_latest\ff\build\artifacts\` — partial local cache of build outputs.

## Workflow files (from bundle)
| File | Role |
|---|---|
| `.github/workflows/build.yml` | full kernel build: clone → patch → compile → AK3 zip |
| `.github/workflows/compile-helper.yml` | NDK cross-compile `ksu_susfs` (`add_sus_maps`); ELF-grep gate |
| `.github/workflows/ci.yml` | early/alt CI (superseded) |

Key commits (newest first): `300a4d1` verify `add_sus_maps` string in ELF (not exec on x86_64) ·
`efd95d3` add `build-ksu-susfs` NDK job · `af4b274` port cmdline read-hook awk to root workflow ·
`e3d215a` SUSFS GKI backport step in root `build.yml` · `fec302c` KSUN init.rc RC-injection hooks.

Bundle refs: `main` @ `00a90e6` (79 build sources) · `phoenix-r-oss-ksun-susfs` @ `8bf0146` (ELF-grep-fixed `.github`).
Tags: `pre-237-rewind-main` `ffbf867`, `pre-237-rewind-phoenix` `4841d5d`.

## Build metadata (from MANIFEST.json)
- kernel: `tillua467` · KSU: `v3.2.0-legacy` · SUSFS: `v1.5.5` (kernel-4.14 + GKI backport)
- 17 SUSFS flags incl `CONFIG_KSU_SUSFS_SUS_MAP=y`
- uname pattern: `4.14.*-KSUNV3.2.0_SUSFSV1.5.5*`
- timestamps: base `20260702T082226Z`; build-241 `20260719T054002Z`

## Local artifact cache (partial)
Flashable zips present: `phoenix-195,196,200,201,202,203,209,210,214,215`.
Boot/kernel imgs: `boot_217.img`, `boot_218.img`, `vmlinux_217.bin`, `Image-dtb-dec`.
Build/working dirs: `108,125,126,127,138,204,207,212,213,218,220,221,222,226,228,229,232`,
`dl216,217,242,243`, `ak3-241`, `anykernel3-210`, `build_uname_fix`, `build_race_fix`.

## Known-bad
- **#245** — KNOWN-BAD. Stale `workflow_dispatch` cache served pre-NDK `build.yml`;
  no `bin/ksu_susfs` (`add_sus_maps`) in zip. Not in local cache (server-only). **Never flash.**

## Not recoverable
- CI run numbers / statuses / step logs for #207–#245 (server-only).
- Any artifact not in the local cache above.
- After repo recreate, `github.run_number` reset to 1 → new builds are `phoenix-1`, `phoenix-2`, …
