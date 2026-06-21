# Kernel Rebuild for POCO X2 (sm6150, kernel 4.14) with Latest KernelSU-Next + SUSFS

**Date:** 2026-06-21
**Status:** Approved — proceeding to implementation plan
**Owner:** Ajith
**Spec slug:** kernel-rebuild-poco-x2
**Target release:** `4.14.356-Unholy_V2.3-KSUN_V3.0.0_SUSFS_V1.5.9-${YYYYMMDD}`

---

## 1. Problem statement

The user's POCO X2 currently runs `4.14.356-Unholy_V2.2` (built 2025-12-07 by KBapna). That kernel image statically embeds legacy `tiann/KernelSU` (module-id `(12851)`, ABI version `0`) and `SUSFS v1.5.5` (NON-GKI, 14 features). The user-space `ksud v3.2.0` upgrade showed the kernel module ABI was already mismatched before this project began (`ksud: log: "KernelSU Next not available, exiting services"`).

The user wants a kernel rebuilt **from source** with the latest KernelSU-Next and SUSFS that supports kernel 4.x. Constraints dictate this remains a Windows project, so the build must run off-host on Linux.

## 2. Goals & non-goals

### Goals
- Same kernel base (`4.14.356-Unholy_V2.2` lineage), same sm6150 device, same Android 11 ramdisk base.
- Replace kernel-side `tiann/KernelSU` with `KernelSU-Next v3.0.0` (last v3 with 4.x support; v3.0.1 pruned 4.x).
- Replace kernel-side `SUSFS v1.5.5` with `SUSFS v1.5.9` (latest NON-GKI 4.14-compatible, used by ravindu644 fork).
- All 14 `CONFIG_KSU_SUSFS_*` features remain `y` at compile time.
- Root (magisk-managed, KSUN-managed) preserved across the flash.
- All 17 installed modules remain operational.
- FreeFire still launches (no `libmain.so` swap).
- Reproducible build via a single GitHub Actions workflow.

### Non-goals
- No Zygisk loader work for FreeFire (per existing USER DIRECTIVE).
- No migration to kernel 5.10+ (would require different device/KMI).
- No source refactor beyond what's needed to land v3.0.0/v1.5.9.
- No manager-APK changes (we already have v3.2.0 manager installed).

## 3. Constraints (host / runtime / scope)

| Layer | What we have / must accept |
|---|---|
| Host | Windows 10 Pro Education 10.0.19045 |
| Toolchain locally | NDK r26d `clang-17` only — **not** the Android clang-12 that built v2.2 |
| Internet | Direct HTTPS to GitHub + Google Source reachable |
| Disk free | C: ≈ 25 GB |
| Build site | GitHub Actions hosted `ubuntu-latest` runner (~7 GB RAM, 4 vCPU) — chosen by user |
| Kernel tree | None on disk; KBapna `Unholy_KSUN+SUSFS` branch chosen as base |
| Device | `5b389e4c`, rooted via KSUN + magisk coexistence, currently on `4.14.356-Unholy_V2.2` |
| Backup | `/sdcard/ksud_backup_pre_v3.2.0_20260621` (userspace ksud v1.1.1) |
| Rollback | Pre-flash full `boot.img` dump via `adb` to host — must be done before flash |

## 4. Solution overview

A single GitHub Actions workflow (`build.yml`) runs a sequential Linux pipeline that:

1. Clones KBapna's `Unholy_KSUN+SUSFS` branch.
2. Replaces the in-tree `KernelSU-Next/` directory with the rifsxd/KernelSU-Next `v3.0.0` source.
3. Replaces SUSFS patches (`fs/susfs.c`, `fs/susfs.h`, `include/linux/susfs.h`, `include/linux/susfs_def.h`) with the v1.5.9 implementations tuned for kernel `4.14 NON-GKI`.
4. Re-applies (or strips only replaced files) KBapna's sm6150-specific tweaks (DTS passthrough, dtb-tools, ramdisk hook ordering).
5. Builds using Android `clang r416183b` toolchain (matches `/proc/version` reported LLD-12.0.5).
6. Repacks the new kernel into a `boot.img` using `mkbootimg` (Linux) + `magiskboot` repatch rooted from the device's existing ramdisk to keep root and kernel tier features intact.
7. Records SHA-256, build date, and an inventory of all `CONFIG_KSU_SUSFS_*` flags into `MANIFEST.json`.
8. Uploads artifacts as: `kernel-phoenix-v2.3...img` + `AnyKernel3-phoenix-v2.3...zip` + `MANIFEST.json`.

This design avoids any new compiler toolchain on the user's Windows host. The entire build chain lives in the workflow YAML and is reproducible from a fresh checkout.

## 5. Component design

### 5.1 Source layout

```
android_kernel_poco_x2_phoenix/      ← KBapna's Unholy_KSUN+SUSFS, ~3 GB unpacked
├── KernelSU-Next/                    ← REPLACED with rifsxd/KernelSU-Next v3.0.0
├── fs/susfs.{c,h}                    ← REPLACED with SUSFS v1.5.9
├── include/linux/susfs.h             ← REPLACED with SUSFS v1.5.9
├── include/linux/susfs_def.h         ← REPLACED with SUSFS v1.5.9
├── arch/arm64/configs/vendor/phoenix_defconfig ← base config
├── (KBapna's)50_add_susfs_in_kernel-4.14.patch ← REMOVED (v1.5.9 baked)
└── ANYKERNEL/                        ← still optional via AnyKernel3 packaging
```

### 5.2 Toolchain

- **Compiler:** clang from `android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r416183b.tar.gz`. Verified to match `/proc/version` compiler tags on the running kernel (`Android (7284624, based on r416183b) clang version 12.0.5`).
- **Linker:** LLD 12.0.5 (bundled in the same toolchain).
- **Cross ar/objcopy/nm:** `llvm-ar`, `llvm-objcopy`, `llvm-nm` shipped in the same clang archive. Utilised via `CROSS_COMPILE=aarch64-linux-gnu-` plus `LLVM=1` so make pulls LLVM tools.
- **Build host libs:** `libelf-dev libssl-dev liblz4-tool device-tree-compiler` (`apt-installed` in workflow).

Cached via `actions/cache@v3` keyed on URL SHA-256 to avoid re-pulling ~1.4 GB on every run.

### 5.3 Configuration

`arch/arm64/configs/vendor/phoenix_defconfig` is the baseline. Workflow appends `arch/arm64/configs/phoenix_v2.3.fragment`:

```
CONFIG_KSU=y
CONFIG_KSU_DEBUG=y
CONFIG_KSU_SUSFS_SUS_PATH=y
CONFIG_KSU_SUSFS_SUS_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SUS_KSTAT=y
CONFIG_KSU_SUSFS_SUS_OVERLAYFS=y
CONFIG_KSU_SUSFS_TRY_UMOUNT=y
CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT=y
CONFIG_KSU_SUSFS_SPOOF_UNAME=y
CONFIG_KSU_SUSFS_ENABLE_LOG=y
CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS=y
CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG=y
CONFIG_KSU_SUSFS_OPEN_REDIRECT=y
CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT=y
```

The `CONFIG_KSU_DEBUG=y` enables `ksud debug su/version/test/mark/insmod` reliably (used by our verification stage post-flash).

### 5.4 Build invocation

```bash
set -euo pipefail
export PATH="$PWD/clang-r416183b/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
export CC=clang
export LD=ld.lld
export CLANG_TRIPLE=aarch64-linux-gnu-

make vendor/phoenix_defconfig phoenix_v2.3.fragment
make prepare
make -j"$(nproc)" Image.gz-dtb dtbs
```

Expected outputs (~30-45 min build on 4 vCPU):
- `arch/arm64/boot/Image.gz-dtb`
- `arch/arm64/boot/dts/qcom/sm6150-*.dtb`

### 5.5 Boot.img packing

```bash
# Pull current boot.img from device BEFORE the build (in a separate job)
adb -s "$ADB_SERIAL" pull /dev/block/bootdevice/by-name/boot current_boot.img

# Extract ramdisk
magiskboot unpack current_boot.img
# → kernel, ramdisk.cpio, dtb, hdr

# Build new boot.img
mkbootimg \
  --kernel  Image.gz-dtb \
  --ramdisk ramdisk.cpio \
  --dtb     sm6150.dtb \
  --header_version 2 \
  --base    0x0 \
  --os_version 11.0.0 \
  --output  kernel-phoenix-v2.3.img

# Magisk repatch the ramdisk
magiskboot cpio ramdisk.cpio patch
# Re-pack with patched ramdisk
mkbootimg ... → kernel-phoenix-v2.3-magisk-rooted.img
```

### 5.6 AnyKernel3 packaging

In conjunction with the `AnyKernel3-poco-x2` template, the artifact is bundled as a flashable ZIP:

```
AnyKernel3-phoenix-v2.3-KSUNV3.0.0_SUSFSV1.5.9-20260621.zip
├── anykernel.sh
├── META-INF/com/google/android/update-binary
├── tools/ak3-core.sh
├── ramdisk-patched.cpio
├── Image.gz-dtb
├── dtb.img
└── MANIFEST.json
```

### 5.7 Verification checklist (run post-flash on device)

The user will execute after first boot. Each step has a binary expected result:

| Step | Expected value | Pass criterion |
|---|---|---|
| `uname -r` | `4.14.356-Unholy_V2.3-KSUNV3.0.0_SUSFSV1.5.9…` | matches `*Unholy*KSUN*V3*` |
| `/proc/version` | contains `clang version 12.0.5 (…r416183b)` | exact match |
| `cat /proc/ksu_module_version` (via `ksud debug version`) | non-zero integer | `Kernel Version: 13000+` (v3.0.0 era) |
| `ksu_susfs show version` | `v1.5.9` | exact match |
| `ksu_susfs show variant` | `NON-GKI` | exact match |
| `ksu_susfs show enabled_features` | 14 lines | exact count |
| `sudo ksud module list` | JSON list, 17 enabled entries | JSON parses, all `"enabled":true` |
| `pm path com.rifsxd.ksunext` | path under `/data/app/...` | present |
| Manager version | `3.2.0` | `pm dump` shows `versionCode=33129` |
| Boot-time susfs logs | `KernelSU: susfs: CMD_SUSFS_SHOW_VERSION -> ret: 0` | appears in dmesg |

## 6. Data flow

```
                 ┌────────────────────────────────────────────────────────┐
                 │                    WORKFLOW RUN                       │
                 │                                                        │
   ┌──── KBapna Unholy ──────┐    (1) git clone                   │
   │  Unholy_KSUN+SUSFS       │──→  Pulls base kernel src          │
   └──────────────────────────┘      ↓                                │
                                    (2) Overlay rifsxd/KernelSU-Next @ v3.0.0
                                    ↓                                │
                                    (3) Overlay sidex15 susfs src @ v1.5.9
                                    ↓                                │
   ┌──── adb pull current ────┐    (4) Pull current boot.img       │
   │  boot.img from device   │──→  Extracted ramdisk             │
   └──────────────────────────┘      ↓                                │
                                    (5) make Image.gz-dtb
                                    ↓                                │
   ┌───── Android clang 12 ───┐    (6) compile + magiskpatch       │
   │  (r416183b)               │──→  re-packed boot.img             │
   └────────────────────────────┘      ↓                                │
                                    (7) AnyKernel3 wrapper ZIP        │
                                    ↓                                │
   ┌───── actions/upload ──────┐    (8) artifacts out               │
   │                          │──→  user downloads, adb flashes     │
   └────────────────────────────┘                                    │
                                                                     │
   Pre-flash step (user side, manual): adb shell dd > boot_backup.img │
   Post-flash verification (section 5.7)                              │
   ┌────────────────────────────────────────────────────────┘
   │
   ▼
 Verification outputs (table 5.7)
```

## 7. Error handling

| Stage | Failure mode | Reaction |
|---|---|---|
| Network-HTTP fetch (toolchain, source) | 5xx, 404, partial | Retry x3 with exponential backoff; on persistent 404, mark run failed with clear error |
| Source overlay conflicts | Patch fails | Run `git apply --check` first; print patch traceback; mark red |
| Make errors | Generic compile fail | Emit last 200 lines; mark red with link to `kernel-build.log` artifact |
| `mkbootimg` not present | Tool missing | Workflow installs cli11-utils + apt; re-runs |
| Magisk repatch reporting warned | non-zero `magiskboot cpio patch` | Mark warning, do not silently ignore — user must choose to flash or revert |
| Artifact upload error | infra | Action retries 3 times then fails; user can re-run workflow |

## 8. Testing strategy

- **Pre-flash smoke (off-device):** Extract `Image.gz-dtb`, verify with `scripts/extract-ikconfig.sh` to confirm all 14 `CONFIG_KSU_SUSFS_*=y` flags present in the embedded kernel config. Confirm `uname -r` string inside matches target version.
- **Post-flash verification (on-device):** steps in §5.7. Each step is a single bash command with binary pass/fail status.
- **Rollback plan:** if any step fails after flash, hold VOL- during reboot, boot into fastboot, `fastboot flash boot /sdcard/boot_backup.img` from pre-flash dump.

## 9. Rollout steps (user-side manual sequence)

1. **Pre-flash:** `adb shell dd if=/dev/block/bootdevice/by-name/boot of=/sdcard/boot_backup_v2.2.img` (or by-name alternatives; will be discovered at runtime).
2. **Cross-check:** Boot partition block name via `getprop ro.boot.bootdevice` and `ls -la /dev/block/by-name/`.
3. **Download artifact:** from GitHub Actions run × `kernel-phoenix-build-phoenix-v2.3-..zip`.
4. **Verify SHA-256:** `Get-FileHash anykernel.zip`.
5. **Flash:** `adb push anykernel.zip /sdcard && adb shell flash-ksu anykernel.zip` (or sideload via TWRP if available — POCO X2 doesn't ship TWRP, so direct).
6. **Wait + reboot:** hold POWER for 15 s, release, expect first-boot SELinux denial warnings (free of AndroidRuntime FATAL).
7. **Verify:** §5.7 table.

## 10. Acceptance criteria for design approval

- [x] Source base pinned (KBapna Unholy_KSUN+SUSFS, user-confirmed)
- [x] KSU-Next version pinned (v3.0.0, user-confirmed)
- [x] SUSFS version intent (v1.5.9; latest 4.14 NON-GKI; not yet user-confirmed but consistent with selection)
- [x] Toolchain path (off-host Linux via GitHub Actions, user-confirmed)
- [x] Build sequence (Steps S1-S7)
- [x] Verification table (§5.7)
- [x] Rollback plan (§9)

## 11. Open assumptions / decisions

### Resolved by user (2026-06-21)
- **SUSFS target = v1.5.9** (latest 4.14 NON-GKI source; ravindu644 fork reference)
- **Build site = GitHub Actions `ubuntu-latest`** (Windows host compiled out)
- **Source base = KBapna `Unholy_KSUN+SUSFS`** (lineage preserved)
- **KSU-Next = v3.0.0** (Dec 2025; last v3 with 4.x source support)

### Investigation result: there is no SUSFS v2.x kernel-source release
- Confirmed via sidex15/susfs4ksu-module R24 changelog: "add support for susfs v2.0.0+" is **forward-compat plumbing**, not a release. The only v2.0.0 artifact is a private compiled blob ("local-binaries: add susfs v2.0.0 local binary").
- Confirmed via ravindu644/android_kernel_poco_x2_phoenix forks: only "[BACKPORT] fs: implement SUSFS v1.5.9" appears; no v2.0 commits.
- Confirmed via KernelSU-Next GitHub: no v2.x exists; major jumped 1.x → 3.x. v3.0.0 is the latest source with 4.x support; v3.0.1+ ships prebuilts only for kernels 5.10+.
- Additional finding: KernelSU-Next v3.0.0 has **no in-tree susfs source code** (`kernel/` directory contains no `susfs/` folder). SUSFS is always overlaid as external patches — already matches the design's overlay approach.
- Conclusion: **v3.0.0 + v1.5.9 is the latest achievable build target** at this point in time.

### Open (not blocking; workflow adapts automatically)
1. **GitHub repo availability** — workflow YAML is written portable. If user has a repo, drop `.github/workflows/build.yml` in there. If not, the spec + plan can be applied to any fresh repo without modification.
2. **Ramdisk variants** — device currently on `4.14.356-Unholy_V2.2` boot base; existing ramdisk + magisk state is reused via `magiskboot cpio patch`. If user MIUI-flashes a different base between now and flash time, the workflow re-detects via `getprop ro.boot.bootdevice` and re-pulls the boot partition.

## 12. References
- https://github.com/KBapna/Unholy_Phoenix_Redmi_K30_Kernel
- https://github.com/rifsxd/KernelSU-Next
- https://github.com/tiann/KernelSU/issues?q=4.14
- https://github.com/sidex15/susfs4ksu-module
- https://github.com/sidex15/ksu_module_susfs
- KBapna's v2.2_Unholy_SUSFS (Dec 7 2025) tag
- ravindu644/android_kernel_poco_x2_phoenix (Nov 16 2025, "SuSFS v1.5.9")
