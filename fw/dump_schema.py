#!/usr/bin/env python3
"""
Dump protobuf-c schemas out of the Insta360 GO firmware.

The image is a raw ARM blob (no ELF) loaded such that  vaddr = file_offset + DELTA,
with DELTA solved by intersecting pointer candidates across known field-name strings.
"""
import struct
import sys
import re
import numpy as np

DELTA = 0xA0000E04
LABEL = {1: "required", 2: "optional", 3: "repeated"}
PTYPE = {
    0: "int32", 1: "sint32", 2: "sfixed32", 3: "int64", 4: "sint64", 5: "sfixed64",
    6: "uint32", 7: "fixed32", 8: "uint64", 9: "fixed64", 10: "float", 11: "double",
    12: "bool", 13: "enum", 14: "string", 15: "bytes", 16: "message",
}
IDENT = re.compile(rb"[A-Za-z_][A-Za-z0-9_.]{1,80}\x00")

d = open(sys.argv[1] if len(sys.argv) > 1 else "InstaGoFW.bin", "rb").read()
words = np.frombuffer(d[:len(d) // 4 * 4], dtype="<u4")


def v2o(v):
    return v - DELTA


def o2v(o):
    return o + DELTA


def cstr(off, limit=96):
    if off is None or off < 0 or off >= len(d):
        return None
    e = d.find(b"\x00", off, off + limit)
    if e < 0:
        return None
    try:
        return d[off:e].decode("ascii")
    except UnicodeDecodeError:
        return None


def stroff(s):
    """file offset of an exact NUL-delimited string"""
    pat = b"\x00" + s.encode() + b"\x00"
    i = d.find(pat)
    return i + 1 if i >= 0 else None


def find_word(val):
    """all 4-byte-aligned file offsets holding this LE u32"""
    return (np.nonzero(words == np.uint32(val))[0] * 4).tolist()


def detect_stride(name_a, name_b):
    a, b = stroff(name_a), stroff(name_b)
    if a is None or b is None:
        return None, []
    pa, pb = find_word(o2v(a)), find_word(o2v(b))
    out = []
    for x in pa:
        for y in pb:
            if 0 < y - x <= 128:
                out.append((y - x, x))
    return (out[0] if out else (None, None)), out


def read_fields(start, count, stride):
    res = []
    for k in range(count):
        o = start + k * stride
        if o + 16 > len(d):
            break
        ptr, fid, label, ftype = struct.unpack_from("<IIII", d, o)
        nm = cstr(v2o(ptr))
        if nm is None or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", nm or ""):
            break
        if label not in LABEL or ftype not in PTYPE:
            break
        res.append((nm, fid, LABEL[label], PTYPE[ftype]))
    return res


def dump_message(first_field, title, stride, max_fields=200):
    a = stroff(first_field)
    if a is None:
        print(f"\n### {title}: string {first_field!r} not found")
        return []
    starts = find_word(o2v(a))
    for s in starts:
        f = read_fields(s, max_fields, stride)
        if len(f) >= 2:
            print(f"\n### {title}   (descriptor array at file 0x{s:x}, {len(f)} fields)")
            for nm, fid, lab, ty in f:
                print(f"  {fid:>4}  {lab:<8} {ty:<8} {nm}")
            return f
    print(f"\n### {title}: no descriptor array found for {first_field!r}")
    return []


def dump_enum(type_name, title):
    """ProtobufCEnumValue { const char *name; const char *c_name; int value; } = 12 bytes"""
    a = stroff(type_name)
    if a is None:
        print(f"\n### {title}: {type_name!r} not found")
        return []
    print(f"\n### {title}   (type string at 0x{a:x})")
    # enum value tables sit near the type name; scan a window for 12-byte runs
    lo, hi = max(0, a - 0x8000), min(len(d), a + 0x8000)
    best = []
    for s in range(lo & ~3, hi, 4):
        vals = []
        for k in range(400):
            o = s + k * 12
            if o + 12 > len(d):
                break
            p1, p2, val = struct.unpack_from("<IIi", d, o)
            n1, n2 = cstr(v2o(p1)), cstr(v2o(p2))
            if not n1 or not n2:
                break
            if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", n1):
                break
            vals.append((n1, val))
        if len(vals) > len(best):
            best = vals
    for n, v in best:
        print(f"  {v:>4}  {n}")
    return best


if __name__ == "__main__":
    print("DELTA = 0x%08x" % DELTA)
    (stride, first), all_hits = detect_stride("video_resolution", "photo_size")
    print("detected descriptor stride: %s bytes (candidates: %s)"
          % (stride, sorted({s for s, _ in all_hits})))
    if not stride:
        sys.exit("could not detect stride")

    dump_message("video_resolution", "insta360.messages.Options", stride)
    dump_enum("OPTION_TYPE_BATTERY_STATUS", "OptionType enum")
