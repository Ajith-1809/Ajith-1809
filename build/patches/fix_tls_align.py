#!/usr/bin/env python3
"""Patch ARM64 ELF PT_TLS program header p_align 8 -> 64 (Bionic requires >=64).

NDK r25b `-static` emits PT_TLS with p_align=8; the ARM64 Bionic loader rejects
anything <64 ("TLS segment is underaligned"), so the binary can't exec on device.

Usage: fix_tls_align.py <elf> [--verify]
  --verify  after patching, assert every PT_TLS p_align >= 64 (exit 1 otherwise).
            Use in CI so a regression fails the build instead of shipping a
            non-executable ksu_susfs.
"""
import struct
import sys

MIN_ALIGN = 64
PT_TLS = 7


def phdr_tls(d):
    """Yield (le, offset_of_p_align, p_align) per PT_TLS phdr. ELF64 only."""
    if d[:4] != b"\x7fELF":
        raise SystemExit("not an ELF file")
    if d[4] != 2:
        raise SystemExit("not ELF64")
    le = "<" if d[5] == 1 else ">"
    e_phoff = struct.unpack_from(le + "Q", d, 0x20)[0]
    e_phentsize = struct.unpack_from(le + "H", d, 0x36)[0]
    e_phnum = struct.unpack_from(le + "H", d, 0x38)[0]
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        if struct.unpack_from(le + "I", d, off)[0] == PT_TLS:
            a_off = off + 0x30  # p_align is the last Elf64_Phdr field
            yield le, a_off, struct.unpack_from(le + "Q", d, a_off)[0]


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    verify = "--verify" in sys.argv[2:]

    with open(path, "rb") as f:
        d = bytearray(f.read())

    patched = 0
    for le, a_off, p_align in phdr_tls(d):
        print("PT_TLS p_align =", p_align)
        if p_align < MIN_ALIGN:
            struct.pack_into(le + "Q", d, a_off, MIN_ALIGN)
            patched += 1
            print("  -> patched to", MIN_ALIGN)

    if patched:
        with open(path, "wb") as f:
            f.write(d)
        print("wrote", patched, "patched header(s)")
    else:
        print("nothing to patch (no underaligned PT_TLS)")

    if verify:
        bad = [a for _, _, a in phdr_tls(bytes(d)) if a < MIN_ALIGN]
        if bad:
            raise SystemExit(
                "::error::PT_TLS p_align still <%d after patch: %r" % (MIN_ALIGN, bad))
        print("verify OK: all PT_TLS p_align >=", MIN_ALIGN)


if __name__ == "__main__":
    main()
