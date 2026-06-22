# Release checklist â€” phoenix-v2.3 KSUNv3.0.0+SUSFSv1.5.5

Reproducible release steps for a fresh checkout of this repo on a new day.

## A. Pre-flight

- [ ] You have a clean checkout of the repo with no uncommitted changes.
- [ ] Your Windows laptop has Git and Python 3 (to host the GA triggers).
- [ ] You have a GitHub account; the repo is private or public â€” GA will run on it.
- [ ] You know your device's ADB serial (from `adb devices`): `5b389e4c` (or IP:port for wireless).
- [ ] Your Windows machine and the device are on the same LAN.

## B. Trigger the GA build

- [ ] Push the latest commit to GitHub (via `git push origin main`).
- [ ] Open the GitHub repo's **Actions** tab â†’ select **Build Phoenix KSUN v3.0.0 / SUSFS v1.5.9**.
- [ ] Click **Run workflow** â†’ fill in `adb_serial` (your serial) â†’ leave `upload_target` as `direct`.
- [ ] Watch the jobs: `host-prep` (~5 min) â†’ `source-prep` (~3 min) â†’ `build` (~45 min).
- [ ] When all three pass, click into the run â†’ download these artifacts:
  - `kernel-image-<N>.tar.gz` (contains `Image.gz-dtb`)
  - `kernel-build-log-<N>.tar.gz` (contains `kernel-build.log`)
  - `manifest-<N>.tar.gz` (contains `MANIFEST.json`)

## C. Prepare the device (offline / Linux or WSL2)

- [ ] `adb -s <serial> wait-for-device`
- [ ] `adb -s <serial> root`
- [ ] `adb -s <serial> remount`

## D. Pre-flash backup (MANDATORY)

```bash
adb -s <serial> shell "dd if=/dev/block/by-name/boot of=/sdcard/boot_backup_v2.2.img bs=4096"
adb -s <serial> pull /sdcard/boot_backup_v2.2.img ./boot_backup_v2.2.img
adb -s <serial> pull /dev/block/bootdevice/by-name/boot ./current_boot.img
```

- [ ] Confirm `boot_backup_v2.2.img` exists locally (file size â‰ˆ current boot size, ~65â€“90 MB).

## E. Extract magisk-patched ramdisk

```bash
magiskboot unpack ./current_boot.img
# â†’ kernel, ramdisk.cpio, dtb, hdr
magiskboot cpio ramdisk.cpio patch
```

- [ ] Confirm `ramdisk.cpio` exists and is non-empty (â‰¥50 KB).

## F. Repack with new kernel image

```bash
NEW_KERNEL=<path-to-downloaded-Image.gz-dtb>
NEW_DTB=./dtb          # Use the sm6150-*.dtb matching your device
SIGNED_BOOT=./kernel-phoenix-v2.3-magisk-rooted.img

mkbootimg \
  --kernel  "$NEW_KERNEL" \
  --ramdisk  "./ramdisk.cpio" \
  --dtb     "$NEW_DTB" \
  --os_version 11.0.0.0 \
  --header_version 4 \
  --pagesize 4096 \
  --base     0x00000000 \
  --output   "$SIGNED_BOOT"
```

- [ ] Confirmed `SIGNED_BOOT` exists, size â‰ˆ combined `Image.gz-dtb` + `ramdisk.cpio` (~70â€“100 MB).

## G. Flash and boot

```bash
adb reboot bootloader
fastboot flash boot "$SIGNED_BOOT"
fastboot reboot
```

- [ ] First boot complete (home screen visible) before proceeding.

## H. Smoke test

```bash
adb shell "sh -s docs/postflash_smoke.sh"
```

- [ ] 10/10 PASS. If any FAIL â†’ rollback (see Â§I).

## I. Rollback

```bash
adb reboot bootloader
fastboot flash boot ./boot_backup_v2.2.img
fastboot reboot
```

- [ ] Device boots back to v2.2 stock state.

## J. Post-success

- [ ] Tag the release on GitHub: `git tag phoenix-v2.3-YYYYMMDD && git push --tags`
- [ ] Upload `kernel-phoenix-v2.3-KSUNV3.0.0_SUSFSV1.5.5-YYYYMMDD.img` as a GitHub Release asset.
- [ ] Keep `boot_backup_v2.2.img` on the device's `/sdcard/` for 30 days, then delete.
