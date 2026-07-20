# AnyKernel3 Ramdisk Mod Script
# osm0sis @ xda-developers

## AnyKernel setup
# begin properties
properties() { '
kernel.string=Unholy Phoenix KSUN v3.0.0 / SUSFS v1.5.5
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=phoenix
device.name2=phoenixin
supported.versions=
supported.patchlevels=
'; } # end properties

# shell variables
block=/dev/block/bootdevice/by-name/boot;
is_slot_device=0;
ramdisk_compression=auto;
patch_vbmeta_flag=auto;

# import functions / init
. tools/ak3-core.sh;

# begin attributes
attributes() {
  set_perm_recursive 0 0 755 644 $ramdisk/*;
  set_perm_recursive 0 0 750 750 $ramdisk/init* $ramdisk/sbin;
} # end attributes

# begin dump/boot/install
dump_boot;

# ── Inject ksud into ramdisk ──
ui_print " ";
ui_print " Injecting ksud daemon into boot ramdisk...";
cp "$AKHOME/bin/ksud" "$RAMDISK/sbin/ksud" 2>/dev/null
chmod 755 "$RAMDISK/sbin/ksud" 2>/dev/null
ui_print " ksud binary placed at /sbin/ksud";

# ── Add init service to auto-start ksud ──
cp "$AKHOME/bin/init.kernelSU.rc" "$RAMDISK/init.kernelSU.rc" 2>/dev/null
insert_line "$RAMDISK/init.rc" "import /init.kernelSU.rc" \
    after "import /init.environ.rc" "import /init.kernelSU.rc"
ui_print " init.kernelSU.rc injected, init.rc patched";

# ── Pre-register the KSU Next Manager appid so the [ksu_driver] fd is delivered ──
# On CAF 4.14 (MANUAL_HOOK, no kprobes) the per-process [ksu_driver] fd is installed
# by ksu_handle_setresuid() -> task_work -> ksu_install_fd() ONLY when is_uid_manager()
# passes, i.e. when ksu_manager_appid == uid % 100000. That appid is normally populated
# by the Manager's CHANGE_MANAGER_UID reboot-magic call — which is blocked on this fork
# (app-domain seccomp forbids the reboot syscall, and the Manager never registers itself).
# Because CONFIG_KSU_DEBUG=y, the ksu_debug_manager_appid module param is available:
# passing it on the cmdline makes the kernel call ksu_set_manager_appid(10583) at boot,
# BEFORE the Manager starts, so the setresuid hook fires and delivers the fd.
# IMPORTANT: the param is registered with the "kernelsu." module prefix, so the cmdline
# key MUST be exactly "kernelsu.ksu_debug_manager_appid" (verified in the compiled Image:
# the kernel matches the fully-prefixed name). A bare "ksu_debug_manager_appid" key is
# silently ignored, and a DOUBLED "kernelsu.kernelsu.ksu_debug_manager_appid" key ALSO
# fails to match (that is what the idempotent strip below prevents on re-flash).
# Manager appid is stable unless the device is wiped/reinstalled; this is the supported
# debug bootstrap and is fully reversible (remove the param => appid stays at -1).
ui_print " ";
ui_print " Pre-registering KSU Manager appid (kernelsu.ksu_debug_manager_appid=10583)...";
# Idempotent pin: AK3 re-reads the boot partition's EXISTING cmdline on every
# flash, so a naive patch_cmdline accumulates a doubled "kernelsu." prefix
# (kernelsu.kernelsu.ksu_debug_manager_appid) across re-flashes. That doubled
# key no longer matches the kernel's registered param (kernelsu.ksu_debug_
# manager_appid) and silently fails to set ksu_manager_appid. So first strip
# ANY prior appid-pin token, then append exactly one correct single-prefix key.
if [ -f "$SPLITIMG/cmdline.txt" ]; then
  sed -i -E "s/[ ]*[^ ]*ksu_debug_manager_appid=[0-9]+//g" "$SPLITIMG/cmdline.txt"
  echo "$(cat "$SPLITIMG/cmdline.txt") kernelsu.ksu_debug_manager_appid=10583" > "$SPLITIMG/cmdline.txt"
  sed -i -e 's/^[ \t]*//' -e 's/  */ /g' -e 's/[ \t]*$//' "$SPLITIMG/cmdline.txt"
else
  CMDFILE="$AKHOME/cmdtmp"
  grep "^cmdline=" "$SPLITIMG/header" | cut -d= -f2- > "$CMDFILE"
  sed -i -E "s/[ ]*[^ ]*ksu_debug_manager_appid=[0-9]+//g" "$CMDFILE"
  echo "$(cat "$CMDFILE") kernelsu.ksu_debug_manager_appid=10583" > "$CMDFILE"
  sed -i -e 's/^[ \t]*//' -e 's/  */ /g' -e 's/[ \t]*$//' "$CMDFILE"
  sed -i "s|^cmdline=.*|cmdline=$(cat "$CMDFILE")|" "$SPLITIMG/header"
  rm -f "$CMDFILE"
fi
ui_print " Manager appid pinned to 10583 via cmdline";

repack_ramdisk;
write_boot;

# ── Set up /data/adb/ (silent — may fail if /data unavailable) ──
if ! mountpoint -q /data; then
  mount /dev/block/bootdevice/by-name/userdata /data 2>/dev/null || true
fi
if [ -d /data ] && [ ! -f /data/adb/ksu/bin/ksud ]; then
  mkdir -p /data/adb/ksu/bin 2>/dev/null
  cp "$AKHOME/bin/ksud" /data/adb/ksu/bin/ksud 2>/dev/null
  chmod 755 /data/adb/ksu/bin/ksud 2>/dev/null
  chown 0:0 /data/adb/ksu/bin/ksud 2>/dev/null
  ln -sf ksu/bin/ksud /data/adb/ksud 2>/dev/null
  ui_print " ksud also copied to /data/adb/ksu/bin/";
fi

# ── Install custom ksu_susfs (with add_sus_maps) ──
# Our build drops a ksu_susfs that issues the SUS_MAP GKI-backport command (0x5556d);
# the susfs4ksu module otherwise overwrites it at boot with the stock universal binary
# (which lacks add_sus_maps). Stash a pristine copy so ff_master.sh can restore ours
# regardless of module boot order (memory #18).
if [ -f "$AKHOME/bin/ksu_susfs" ]; then
  mkdir -p /data/adb/ksu/bin 2>/dev/null
  cp "$AKHOME/bin/ksu_susfs" /data/adb/ksu/bin/.ksu_susfs_ours 2>/dev/null
  chmod 755 /data/adb/ksu/bin/.ksu_susfs_ours 2>/dev/null
  chown 0:0 /data/adb/ksu/bin/.ksu_susfs_ours 2>/dev/null
  # Only overwrite the live binary if it lacks add_sus_maps (don't clobber a newer build)
  if ! /data/adb/ksu/bin/ksu_susfs add_sus_maps --help >/dev/null 2>&1; then
    cp "$AKHOME/bin/ksu_susfs" /data/adb/ksu/bin/ksu_susfs 2>/dev/null
    chmod 755 /data/adb/ksu/bin/ksu_susfs 2>/dev/null
    chown 0:0 /data/adb/ksu/bin/ksu_susfs 2>/dev/null
    ui_print " custom ksu_susfs (add_sus_maps) installed";
  else
    ui_print " ksu_susfs already supports add_sus_maps, left as-is";
  fi
fi

## end install
