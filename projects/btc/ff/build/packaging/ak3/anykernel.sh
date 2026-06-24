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
write_boot;

## end install
