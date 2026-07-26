#!/usr/bin/env python3
"""Build a proper v1 Android boot.img: stock ramdisk + custom kernel + init.kernelSU.rc injection."""
import struct, gzip, io, os, sys, zipfile

PAGE = 4096
ANDROID_BOOT_MAGIC = b"ANDROID!"

def align(x):
    return (x + PAGE - 1) & ~(PAGE - 1)

def pack_boot(kernel_gz, ramdisk_gz, out_path):
    ksize = len(kernel_gz)
    rsize = len(ramdisk_gz)

    # v1 header: 10 fields = 44 bytes
    # magic(8) + kernel_size(4) + kernel_addr(4) + ramdisk_size(4) + ramdisk_addr(4)
    # + dtb_size(4) + dtb_addr(4) + tags_addr(4) + page_size(4) + header_size(4)
    header = struct.pack(
        "<8sIIIIIIIII",
        ANDROID_BOOT_MAGIC,
        ksize, 0x00008000,
        rsize, 0x1000000,
        0, 0x0,
        0x01100000,
        PAGE,
        44   # header_size
    )

    hdr_pad = PAGE - (len(header) % PAGE)
    if hdr_pad == PAGE: hdr_pad = 0
    header_padded = header + b"\x00" * hdr_pad

    kernel_padded = kernel_gz + b"\x00" * (align(ksize) - ksize)
    ramdisk_padded = ramdisk_gz + b"\x00" * (align(rsize) - rsize)

    boot_img = header_padded + kernel_padded + ramdisk_padded

    with open(out_path, "wb") as f:
        f.write(boot_img)
    print(f"boot.img: {len(boot_img)} bytes (kernel={ksize}, ramdisk={rsize})")
    return out_path

def inject_cpio(ramdisk_data, init_rc_path):
    """Inject init.kernelSU.rc into ASCII cpio ramdisk and patch init.rc."""
    entries = {}
    pos = 0
    data = ramdisk_data

    # Parse ASCII cpio (newc) entries
    # Header: magic(6) + 13 fields x 8 bytes = 110 bytes
    # This Xiaomi cpio uses hex encoding and no name/data padding — scan for next magic
    HEADER_SIZE = 110
    while pos + HEADER_SIZE <= len(data):
        magic = data[pos:pos+6]
        if magic not in (b'070707', b'070701'):
            print(f"  Bad magic at pos {pos}: {magic.hex()}")
            break
        # Hex-encoded fields (newc hex mode)
        size = int(data[pos+54:pos+62], 16)
        name_len = int(data[pos+94:pos+102], 16)
        name_start = pos + HEADER_SIZE
        name = data[name_start:name_start + name_len].decode('utf-8', errors='replace').rstrip('\x00')

        if name == 'TRAILER!!!':
            break

        # Find next entry by scanning for next magic (no padding in this cpio)
        search_from = name_start + size
        next_pos = None
        for i in range(search_from, min(search_from + size + 512, len(data) - 6)):
            if data[i:i+6] in (b'070707', b'070701'):
                next_pos = i
                break
        if next_pos is None:
            next_pos = len(data)

        file_data = data[name_start:name_start + size]

        # Mode: try hex first (dirs use hex), fallback to octal
        mode_raw = data[pos+14:pos+22]
        try:
            mode = int(mode_raw, 16) & 0o7777
        except ValueError:
            try:
                mode = int(mode_raw, 8) & 0o7777
            except ValueError:
                mode = 0o644

        entries[name] = {'data': file_data, 'mode': mode}
        pos = next_pos

    print(f"Parsed {len(entries)} cpio entries")

    # Read and add init.kernelSU.rc
    with open(init_rc_path, 'rb') as f:
        ksu_rc = f.read()
    entries['init.kernelSU.rc'] = {'data': ksu_rc, 'mode': 0o644}
    print(f"Added init.kernelSU.rc ({len(ksu_rc)} bytes)")

    # Patch init.rc
    if 'init.rc' in entries:
        init_rc = entries['init.rc']['data'].decode('utf-8', errors='replace')
        if 'import /init.kernelSU.rc' not in init_rc:
            init_rc = init_rc.replace("import /init.environ.rc",
                "import /init.environ.rc\nimport /init.kernelSU.rc", 1)
            entries['init.rc']['data'] = init_rc.encode('utf-8')
            print("Patched init.rc to import init.kernelSU.rc")

    # Rebuild cpio (ASCII format)
    cpio_out = io.BytesIO()
    for name, info in entries.items():
        size = len(info['data'])
        name_bytes = name.encode('utf-8') + b'\x00'
        name_len = len(name_bytes)
        header = (f"070701{0:08o}{info['mode']:08o}{0:08o}{0:08o}{1:08o}"
                  f"{0:08o}{size:08o}{0:08o}{0:08o}{0:08o}{0:08o}{name_len:08o}{0:08o}"
                  ).encode('ascii')
        cpio_out.write(header)
        cpio_out.write(name_bytes)
        cpio_out.write(info['data'])
        entry_size = 76 + name_len + size
        if entry_size % 4:
            cpio_out.write(b'\x00' * (4 - entry_size % 4))

    # TRAILER
    trailer = b'070701' + b'0'*64 + b'TRAILER!!!\x00'
    cpio_out.write(trailer)

    new_ramdisk = cpio_out.getvalue()
    print(f"New ramdisk: {len(new_ramdisk)} bytes (was {len(ramdisk_data)})")

    with open('patched_ramdisk.gz', 'wb') as f:
        f.write(gzip.compress(new_ramdisk, mtime=0))
    print(f"Ramdisk recompressed: {os.path.getsize('patched_ramdisk.gz')} bytes")
    return 'patched_ramdisk.gz'

def main():
    stock_boot = r"E:\webtech\projects\btc\ff\build\artifacts\stock_boot.img"
    zip_path = r"E:\webtech\projects\btc\ff\build\artifacts\dl243\Unholy_Phoenix_KSUN-Legacy_SUSFS-v1.5.5_phoenix-243.zip"
    init_rc = r"E:\webtech\projects\btc\ff\build\packaging\ak3\bin\init.kernelSU.rc"
    out_boot = r"E:\webtech\projects\btc\ff\build\artifacts\custom_boot.img"

    # Extract zip
    with zipfile.ZipFile(zip_path, 'r') as z:
        z.extractall(r"E:\webtech\projects\btc\ff\build\artifacts\ak3")
    custom_kernel = r"E:\webtech\projects\btc\ff\build\artifacts\ak3\Image.gz-dtb"

    # Parse stock boot.img (v1: kernel at offset 4096)
    with open(stock_boot, "rb") as f:
        hdr = f.read(52)
        vals = struct.unpack("<8sIIIIIIIII", hdr[:44])
        ksize = vals[1]
        rsize = vals[3]
        f.seek(4096)
        stock_kernel = f.read(ksize)
        rd_off = 4096 + align(ksize)
        f.seek(rd_off)
        stock_ramdisk = f.read(rsize)

    print(f"Stock kernel: {len(stock_kernel)} bytes")
    print(f"Stock ramdisk: {len(stock_ramdisk)} bytes")

    # Decompress ramdisk
    ramdisk_data = gzip.decompress(stock_ramdisk)
    print(f"Ramdisk decompressed: {len(ramdisk_data)} bytes")

    # Inject init.kernelSU.rc
    ramdisk_gz_path = inject_cpio(ramdisk_data, init_rc)

    # Use custom kernel
    with open(custom_kernel, "rb") as f:
        custom_kernel_data = f.read()
    print(f"Custom kernel: {len(custom_kernel_data)} bytes")

    # Pack final boot.img
    with open(ramdisk_gz_path, 'rb') as f:
        ramdisk_gz = f.read()
    pack_boot(custom_kernel_data, ramdisk_gz, out_boot)
    print(f"Written: {out_boot}")

if __name__ == "__main__":
    main()
