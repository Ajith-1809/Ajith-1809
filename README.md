# phoenix-r-oss (KSUN + SUSFS)

Kernel build sources for the POCO X2 / Redmi K30 (phoenixin, SM6150) kernel.

- Base: tillua467 android_kernel_xiaomi_phoenix tag v2.4 (CAF 4.14)
- KernelSU-Next legacy branch (KSUN v3.2.0-legacy)
- Stock SUSFS v1.5.5 (kernel-4.14) + GKI-backport SUS_MAP/MEMFD/PROC_FD_LINK

## Layout

- `.github/workflows/build.yml` — full kernel build (clone source, patch, compile, package AnyKernel3 ZIP)
- `.github/workflows/compile-helper.yml` — cross-compile the `ksu_susfs` userspace binary (`add_sus_maps`) via NDK r25b
- `projects/btc/ff/build/patches/` — KSUN/SUSFS integration patches and dispatch glue
- `projects/btc/ff/build/config/` — defconfig fragments and SUSFS Kconfig menu
- `projects/btc/ff/build/packaging/` — AK3 template + device stealth scripts

## CI

Trigger via `workflow_dispatch` (or push to a path the workflows watch). Build
artifacts (kernel image, `ksu_susfs` binary, flashable ZIP) are uploaded to the
run's artifacts.

## Notes

- `ksud` is downloaded at build time; `build/artifacts/`, `build/sources/`, and
  `build/out/` are generated at CI runtime and are git-ignored.
