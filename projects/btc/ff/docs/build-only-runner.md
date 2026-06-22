# Build-only offline runner (no ADB)

> These steps assume the GA `build.yml` workflow has already produced `Image.gz-dtb`
> and `dtbs` (artifacts downloaded to your Windows laptop).

## 0. Prepare

```
# 1. Clone this repo onto a Linux machine that has ADB access to the device
#    (WSL2 works, or a spare Linux box / VM on the same LAN).
git clone <this-repo-url>
cd <repo>

# 2. Install the host tools you'll need:
#    - adb   (Android Platform Tools)
#    - magiskboot  (from Magisk releases, or `magiskboot` standalone)
#    - mkbootimg   (apt install android-sdk-libsparse-utils, or use the one in build/bin/)
#    - lz4 / cpio  (apt install lz4, cpio)
```

## 1. Pull the current boot (pre-flash backup — always do this first)

```bash
ADB_SERIAL=<your serial, e.g. 5b389e4c>
adb -s "$ADB_SERIAL" wait-for-device
adb -s "$ADB_SERIAL" root
adb -s "$ADB_SERIAL" remount

# Save the existing boot partition on the device in case of emergency.
adb -s "$ADB_SERIAL" shell "dd if=/dev/block/by-name/boot of=/sdcard/boot_backup_v2.2.img bs=4096"

# Pull both the boot partition AND the backup (off-device copy).
adb -s "$ADB_SERIAL" pull /dev/block/bootdevice/by-name/boot ./current_boot.img
adb -s "$ADB_SERIAL" pull /sdcard/boot_backup_v2.2.img ./boot_backup_v2.2.img
```

Rollback command if the new kernel bricks:
```bash
adb reboot bootloader
fastboot flash boot boot_backup_v2.2.img
fastboot reboot
```

## 2. Extract ramdisk from current_boot.img

```bash
mkdir -p ./build/boot
cp ./current_boot.img ./build/boot/
cd ./build/boot

magiskboot unpack ./current_boot.img
# Files produced: kernel, ramdisk.cpio, dtb, hdr

# Apply magisk patch (re-roots the ramdisk so root survives the kernel swap).
magiskboot cpio ramdisk.cpio patch

cd ../../..
```

## 3. Repack boot.img with new kernel

```bash
# Replace <DOWNLOAD_DIR>/Image.gz-dtb with the path to the GA artifact.
NEW_KERNEL=<DOWNLOAD_DIR>/Image.gz-dtb
NEW_DTB=./build/boot/dtb     # Use the dtb extracted earlier (sm6150-*.dtb). Rename to dtb.
SIGNED_BOOT=./kernel-phoenix-v2.3-magisk-rooted.img

mkbootimg \
  --kernel  "$NEW_KERNEL" \
  --ramdisk  "./build/boot/ramdisk.cpio" \
  --dtb     "$NEW_DTB" \
  --os_version 11.0.0.0 \
  --header_version 4 \
  --pagesize 4096 \
  --base     0x00000000 \
  --output   "$SIGNED_BOOT"
```

Notes:
- `--header_version 4` matches Android 11 boot format.
- `--os_version 11.0.0.0` is the current device base.
- dtb selector: the build produces `arch/arm64/boot/dts/qcom/sm6150-*.dtb`.
  Pick the one matching your device's exact model string (use `adb shell getprop ro.product.model`
  to confirm).

## 4. Flash

```bash
cd <repo>
adb -s "$ADB_SERIAL" reboot bootloader
fastboot flash boot "$SIGNED_BOOT"
fastboot reboot
```

Hold POWER + VOL- during boot if the device does not auto-reboot into the new slot
(that's the bootloader splash trigger on most Xiaomi phones).

## 5. First-boot expectations

- First boot will take longer (new kernel, SELinux relabelling).
- `dmesg` may show SELinux denials — that is expected; they typically clear after 1–2 reboots.
- FreeFire should launch cleanly (no Zygisk loader changes).
- Run `docs/postflash_smoke.sh` against the device to verify the upgrade.

## 6. Rollback

If anything is wrong after boot (bootloop, soft-brick, SUSFS logic errors):

```bash
adb reboot bootloader
fastboot flash boot ./boot_backup_v2.2.img
fastboot reboot
```

The pre-flash backup is still on `/sdcard/boot_backup_v2.2.img` (device side) and
`./boot_backup_v2.2.img` (host side) — keep both until you've run the smoke script
successfully.
