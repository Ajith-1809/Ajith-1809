#!/usr/bin/env python3
"""Pack a raw Image.gz-dtb kernel + stock ramdisk into an Android boot.img."""
import struct, sys, os, gzip, io

PAGE_SIZE = 4096

# Android boot.img v0 header (little-endian)
# magic(8) + kernel_size(4) + kernel_addr(4) + ramdisk_size(4) + ramdisk_addr(4)
# + dtb_size(4) + dtb_addr(4) + tags_addr(4) + page_size(4) + header_size(4) = 52 bytes
BOOT_IMG_HEADER_FMT = "<8sIIIIIIIIII"
KERNEL_OFFSET = 0x00008000
RAMDISK_OFFSET = 0x02000000
HEADER_SIZE = struct.calcsize(BOOT_IMG_HEADER_FMT)  # 52 bytes
EXTRA_SIZE = 2048  # cmdline space after header

def _pad(data, size):
    if len(data) > size:
        raise ValueError(f"Data {len(data)} exceeds pad size {size}")
    return data + b"\x00" * (size - len(data))

def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <Image.gz-dtb> <stock_ramdisk.gz> <boot.img>")
        sys.exit(1)

    img_path = sys.argv[1]
    ramdisk_path = sys.argv[2]
    out_path = sys.argv[3]

    cmdline = os.environ.get("BOOT_CMDLINE", "").encode("utf-8")

    with open(img_path, "rb") as f:
        kernel_data = f.read()
    if kernel_data[:2] != b"\x1f\x8b":
        print(f"Error: kernel is not gzip")
        sys.exit(1)

    with open(ramdisk_path, "rb") as f:
        ramdisk_data = f.read()
    if ramdisk_data[:2] != b"\x1f\x8b":
        print(f"Error: ramdisk is not gzip")
        sys.exit(1)

    kernel_size = len(kernel_data)
    ramdisk_size = len(ramdisk_data)
    dtb_size = 0

    # Build header
    header = struct.pack(
        BOOT_IMG_HEADER_FMT,
        b"ANDROID!",   # magic[8]
        kernel_size,   # kernel_size
        0x00008000,    # kernel_addr
        ramdisk_size,  # ramdisk_size
        0x02000000,    # ramdisk_addr
        dtb_size,      # dtb_size
        0x02000000,    # dtb_addr (reuse ramdisk_addr)
        0x01100000,    # tags_addr
        PAGE_SIZE,     # page_size
        HEADER_SIZE,   # header_size
    )

    # Pad each section to page boundary
    kernel_padded = _pad(kernel_data, _align(kernel_size))
    ramdisk_padded = _pad(ramdisk_data, _align(ramdisk_size))

    # Layout: header on page 0, kernel starts at page 0x08 (0x8000/4096=32 bytes offset)
    extra_padded = _pad(cmdline + b"\x00" * (1024 - len(cmdline)), PAGE_SIZE)
    boot_img = header + kernel_padded + extra_padded + ramdisk_padded

    with open(out_path, "wb") as f:
        f.write(boot_img)
    print(f"boot.img: {len(boot_img)} bytes (kernel={kernel_size}, ramdisk={ramdisk_size})")

def _align(x):
    return (x + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1)

if __name__ == "__main__":
    main()
