#!/usr/bin/env python3
"""
Locate protobuf-c ProtobufCFieldDescriptor arrays structurally, then solve the
virtual-address -> file-offset delta by requiring that EVERY name pointer in a run
resolves to a real NUL-terminated ASCII identifier.

Entry layout (32-bit): name*, id, label, type, quantifier_offset, offset, ...  = 48 bytes
"""
import struct
import sys
import re

FIELD_SZ = 48
LABEL = {1: "required", 2: "optional", 3: "repeated"}
PTYPE = {
    0: "int32", 1: "sint32", 2: "sfixed32", 3: "int64", 4: "sint64", 5: "sfixed64",
    6: "uint32", 7: "fixed32", 8: "uint64", 9: "fixed64", 10: "float", 11: "double",
    12: "bool", 13: "enum", 14: "string", 15: "bytes", 16: "message",
}
IDENT = re.compile(rb"[A-Za-z_][A-Za-z0-9_]{1,63}\x00")


def load(path):
    return open(path, "rb").read()


def entry_ok(d, o):
    """Structural plausibility of one descriptor entry."""
    if o + FIELD_SZ > len(d):
        return False
    ptr, fid, label, ftype = struct.unpack_from("<IIII", d, o)
    return (ptr > 0x1000 and 1 <= fid <= 5000
            and label in (1, 2, 3) and ftype in PTYPE)


def find_runs(d, min_len=5):
    """Runs of consecutive plausible entries at 48-byte stride."""
    runs = []
    o = 0
    n = len(d)
    while o + FIELD_SZ <= n:
        if entry_ok(d, o):
            k = 1
            while entry_ok(d, o + k * FIELD_SZ):
                k += 1
            if k >= min_len:
                runs.append((o, k))
            o += k * FIELD_SZ
        else:
            o += 4
    return runs


def is_str_at(d, off):
    if off is None or off < 1 or off >= len(d):
        return None
    if d[off - 1] != 0:
        return None
    m = IDENT.match(d, off)
    if not m:
        return None
    return m.group()[:-1].decode()


def solve_delta_for_run(d, off, count):
    """
    Try deltas implied by matching the run's first name pointer against every
    ASCII identifier in the image is far too slow; instead use the fact that the
    delta is shared image-wide. Caller supplies candidate deltas.
    """
    return None


def validate(d, off, count, delta):
    names = []
    for k in range(count):
        o = off + k * FIELD_SZ
        ptr = struct.unpack_from("<I", d, o)[0]
        s = is_str_at(d, ptr - delta)
        if s is None:
            return None
        names.append(s)
    return names


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "InstaGoFW.bin"
    d = load(path)
    print("scanning for descriptor runs ...")
    runs = find_runs(d)
    print("found %d candidate runs (>=5 entries)" % len(runs))

    # Candidate deltas: pair each run's first name pointer with nearby identifier
    # strings, then score the delta by how many runs it validates image-wide.
    from collections import Counter
    votes = Counter()
    for off, count in runs[:400]:
        ptr = struct.unpack_from("<I", d, off)[0]
        # the string almost certainly lives within a few MB of the descriptor
        lo = max(1, off - (6 << 20))
        hi = min(len(d), off + (6 << 20))
        for m in IDENT.finditer(d, lo, hi):
            s_off = m.start()
            if s_off >= 1 and d[s_off - 1] == 0:
                votes[ptr - s_off] += 1
    if not votes:
        print("no delta candidates")
        return

    print("\ntop delta candidates (by how many runs they validate):")
    scored = []
    for delta, _ in votes.most_common(4000):
        good = 0
        total_fields = 0
        for off, count in runs:
            n = validate(d, off, count, delta)
            if n:
                good += 1
                total_fields += count
        if good:
            scored.append((good, total_fields, delta))
    scored.sort(reverse=True)
    for good, tf, delta in scored[:5]:
        print("  delta=0x%08x  validates %d runs / %d fields" % (delta & 0xffffffff, good, tf))

    if not scored:
        print("  none validated")
        return

    best = scored[0][2]
    print("\nusing delta=0x%08x" % (best & 0xffffffff))
    with open("delta.txt", "w") as fh:
        fh.write(str(best))

    # dump every validated run
    out = []
    for off, count in runs:
        names = validate(d, off, count, best)
        if not names:
            continue
        fields = []
        for k in range(count):
            o = off + k * FIELD_SZ
            ptr, fid, label, ftype = struct.unpack_from("<IIII", d, o)
            fields.append((names[k], fid, LABEL[label], PTYPE[ftype]))
        out.append((off, fields))
    print("validated %d runs" % len(out))
    import json
    with open("descriptors.json", "w") as fh:
        json.dump([{"off": o, "fields": f} for o, f in out], fh, indent=1)
    print("wrote descriptors.json")


if __name__ == "__main__":
    main()
