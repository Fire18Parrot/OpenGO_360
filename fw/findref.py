#!/usr/bin/env python3
"""
Find ARM code that materialises the address of a string.

ARMv7 builds rarely keep a literal pool entry; they emit
    movw Rd, #(addr & 0xffff)      ->  cond 0011 0000 imm4 Rd imm12
    movt Rd, #(addr >> 16)         ->  cond 0011 0100 imm4 Rd imm12
so the address only exists split across two instruction encodings.
"""
import struct
import sys

DELTA = 0xA0000E04
d = open("InstaGoFW.bin", "rb").read()


def str_start(sub):
    """file offset of the NUL-terminated string containing `sub`"""
    i = d.find(sub.encode())
    if i < 0:
        return None
    s = d.rfind(b"\x00", 0, i)
    return s + 1


def enc_movw(rd, imm16):
    return 0xE3000000 | ((imm16 >> 12) << 16) | (rd << 12) | (imm16 & 0xFFF)


def enc_movt(rd, imm16):
    return 0xE3400000 | ((imm16 >> 12) << 16) | (rd << 12) | (imm16 & 0xFFF)


def find_pairs(vaddr, window=64):
    lo, hi = vaddr & 0xFFFF, (vaddr >> 16) & 0xFFFF
    hits = []
    for rd in range(13):
        w = struct.pack("<I", enc_movw(rd, lo))
        t = struct.pack("<I", enc_movt(rd, hi))
        i = 0
        while True:
            i = d.find(w, i)
            if i < 0:
                break
            if i % 4 == 0:
                j = d.find(t, i, i + window)
                if j >= 0 and j % 4 == 0:
                    hits.append((i, j, rd))
            i += 1
    return hits


if __name__ == "__main__":
    targets = sys.argv[1:] or [
        "Extra get. Unspported type",
        "Extra get. format : %d",
        "Extra get. no extra data.",
        "Extra get. no match extra data.",
    ]
    for t in targets:
        s = str_start(t)
        if s is None:
            print(f"{t!r}: not found")
            continue
        va = s + DELTA
        hits = find_pairs(va)
        full = d[s:d.find(b"\x00", s)].decode("ascii", "replace")
        print(f"\n=== {full!r}")
        print(f"    string file@0x{s:06x}  vaddr=0x{va:08x}")
        for i, j, rd in hits:
            print(f"    movw/movt r{rd} at file 0x{i:06x} / 0x{j:06x}  (vaddr 0x{i+DELTA:08x})")
        if not hits:
            print("    no movw/movt pair found")
