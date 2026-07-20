#!/usr/bin/env python3
"""Reference implementation of the binder AIDL IServiceManager.listServices(4)
reply-parcel scrub, used to validate the kernel C before shipping.

Reply parcel layout (offsets_size == 0, no binder objects):
  [0]  int32  status        (0 = EX_NONE)
  [4]  int32  N             (entry count)
  then N entries, each:
    [+0] int32  utf16_len   (UTF-16 code units INCLUDING null terminator)
    [+4]       utf16_len*2  bytes  (UTF-16LE chars; ASCII names => low byte is the char)

We remove entries whose ASCII name contains "lineage" (case-insensitive),
compact the remaining entries down, decrement N, and shrink total size.
"""
import struct, io, sys

HIDE_SUBSTR = b"lineage"  # case-insensitive on ASCII


def encode_string16(s: str) -> bytes:
    chars = s.encode("utf-16-le")  # no BOM
    # Parcel writes len INCLUDING the null terminator code unit
    arr = struct.pack("<I", len(s) + 1) + chars + b"\x00\x00"
    return arr


def build_reply(names):
    buf = bytearray()
    buf += struct.pack("<i", 0)        # status
    buf += struct.pack("<i", len(names))  # N
    for n in names:
        buf += encode_string16(n)
    return bytes(buf)


def decode_reply(data: bytes):
    status, n = struct.unpack_from("<ii", data, 0)
    off = 8
    out = []
    for _ in range(n):
        (ulen,) = struct.unpack_from("<I", data, off)
        off += 4
        raw = data[off:off + ulen * 2]
        off += ulen * 2
        # strip trailing null code unit
        chars = raw[:-2] if ulen > 0 else b""
        out.append(chars.decode("utf-16-le", "replace"))
    return status, out


def scrub(data: bytes):
    """Return (new_parcel, removed_count). Raises ValueError on malformed input."""
    if len(data) < 8:
        raise ValueError("too short")
    status, n = struct.unpack_from("<ii", data, 0)
    # parse entries
    entries = []
    off = 8
    for _ in range(n):
        if off + 4 > len(data):
            raise ValueError("entry len oob")
        (ulen,) = struct.unpack_from("<I", data, off)
        if ulen == 0:
            raise ValueError("zero utf16 len")
        entry_bytes = data[off: off + 4 + ulen * 2]
        if len(entry_bytes) < 4 + ulen * 2:
            raise ValueError("entry body oob")
        name_raw = entry_bytes[4: 4 + (ulen - 1) * 2]
        name_ascii = bytes(c for c in name_raw[0::2])  # low bytes
        keep = HIDE_SUBSTR not in name_ascii.lower()
        entries.append((keep, entry_bytes))
        off += 4 + ulen * 2
    kept = [e for keep, e in entries if keep]
    removed = len(entries) - len(kept)
    out = bytearray()
    out += struct.pack("<ii", status, len(kept))
    for e in kept:
        out += e
    return bytes(out), removed


def main():
    names = [
        "activity", "lineagehardware", "power", "lineagetrust",
        "package", "vendor.lineage.health.IChargingControl/default",
        "telephony.registry", "lineagelivedisplay",
    ]
    pkt = build_reply(names)
    print("INPUT  names:", decode_reply(pkt)[1])
    out, removed = scrub(pkt)
    status, rest = decode_reply(out)
    print("OUTPUT names:", rest)
    print("removed:", removed)
    assert removed == 4, removed
    assert all("lineage" not in n.lower() for n in rest), rest
    assert "activity" in rest and "power" in rest and "package" in rest
    # roundtrip: re-encode the scrubbed output and scrub again -> removed 0
    _, r2 = scrub(out)
    assert r2 == 0, r2
    print("SELF-TEST OK")


if __name__ == "__main__":
    main()
