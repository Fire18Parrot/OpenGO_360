#!/usr/bin/env python3
"""Disassemble a slice of the firmware and annotate movw/movt string loads."""
import subprocess
import sys
import re

DELTA = 0xA0000E04
OBJDUMP = "/opt/gcc-arm-none-eabi-10-2020-q4-major/bin/arm-none-eabi-objdump"
d = open("InstaGoFW.bin", "rb").read()


def cstr(vaddr, limit=90):
    o = vaddr - DELTA
    if o < 0 or o >= len(d):
        return None
    e = d.find(b"\x00", o, o + limit)
    if e < 0:
        return None
    try:
        s = d[o:e].decode("ascii")
    except UnicodeDecodeError:
        return None
    return s if s.isprintable() and len(s) > 3 else None


def dis(lo, length):
    open("/tmp/_s.bin", "wb").write(d[lo:lo + length])
    out = subprocess.run(
        [OBJDUMP, "-D", "-b", "binary", "-m", "arm",
         f"--adjust-vma={hex(lo + DELTA)}", "/tmp/_s.bin"],
        capture_output=True, text=True).stdout.splitlines()

    pend = {}          # reg -> low half
    for line in out:
        m = re.match(r"\s*([0-9a-f]+):\s+([0-9a-f]{8})\s+(.*)", line)
        note = ""
        if m:
            txt = m.group(3)
            mw = re.match(r"movw\s+(r\d+), #(\d+)", txt)
            mt = re.match(r"movt\s+(r\d+), #(\d+)", txt)
            if mw:
                pend[mw.group(1)] = int(mw.group(2))
            elif mt:
                reg = mt.group(1)
                if reg in pend:
                    va = (int(mt.group(2)) << 16) | pend.pop(reg)
                    s = cstr(va)
                    note = f"      ; 0x{va:08x}" + (f'  "{s}"' if s else "")
        print(line + note)


if __name__ == "__main__":
    lo = int(sys.argv[1], 16)
    ln = int(sys.argv[2], 16) if len(sys.argv) > 2 else 0x200
    dis(lo, ln)
