#!/usr/bin/env python3
"""
Build a patched Insta360 GO firmware that adds a gated USB-serial root console.

- Input : InstaGoFW.bin        (stock image, left untouched)
- Output: InstaGoFW_patched.bin

The ONLY change is inside /etc/init.d/S60postservice (Linux rootfs = section 4).
Its dead comment block is overwritten, in place and at identical byte length, with
a console bring-up that runs ONLY when /tmp/SD0/NO_HIBER exists. That same file also
makes stock ambernation.sh skip hibernation, so init.d re-runs on every cold boot.

Sections 0-3 (bootloader, RTOS, kernel) stay byte-identical. Integrity is CRC32
(per section) + a whole-image MD5 trailer; both are recomputed. No signature exists.

Run:  python3 build_patch.py
"""
import struct, zlib, hashlib, sys

SRC = "InstaGoFW.bin"
DST = "InstaGoFW_patched.bin"

orig = bytearray(open(SRC, "rb").read())
N = len(orig)

# --- locate S60postservice slot in section 4 ---
S60 = 0x2837414
e = S60; z = 0
while e < N:
    if orig[e] == 0:
        z += 1
        if z >= 8:
            e -= z
            break
    else:
        z = 0
    e += 1
SLOT = e - S60

new = (
"#!/bin/sh\n"
"echo 'S60postservice is running...'\n"
"# Gated console+hook: active ONLY when /tmp/SD0/NO_HIBER exists (that file also\n"
"# makes ambernation.sh skip hibernation, so init.d re-runs every cold boot).\n"
"if [ -e /tmp/SD0/NO_HIBER ]; then\n"
"\texec >>/tmp/SD0/console_boot.log 2>&1\n"
"\tset -x\n"
"\tsleep 8\n"
"\tkillall syslogd 2>/dev/null\n"
"\techo device > /proc/ambarella/usbphy0\n"
"\tmodprobe usbcore\n"
"\tmodprobe udc-core\n"
"\tmodprobe ambarella_udc\n"
"\tmodprobe libcomposite\n"
"\tmodprobe u_serial\n"
"\tmodprobe usb_f_acm\n"
"\tmodprobe g_serial\n"
"\t( while true ; do /sbin/getty -n -L 115200 /dev/ttyGS0 ; sleep 1 ; done ) &\n"
"\tklogd 2>/dev/null\n"
"\t[ -e /tmp/SD0/goinit.sh ] && sh /tmp/SD0/goinit.sh &\n"
"fi\n"
"exit 0\n"
).encode()

if len(new) > SLOT:
    sys.exit(f"payload {len(new)} > slot {SLOT}; trim it")
pad = SLOT - len(new)
patch = new + (b"#" + b"\n" * (pad - 1) if pad > 0 else b"")
assert len(patch) == SLOT

patched = bytearray(orig)
patched[S60:S60 + SLOT] = patch

# --- recompute section 4 CRC32 (payload starts 0x100 after the header) ---
S4hdr = 0x1b1f714
crc, vn, vd, ilen, mem, flag, mg = struct.unpack_from("<IIIIIII", patched, S4hdr)
p0 = S4hdr + 0x100
newcrc = zlib.crc32(bytes(patched[p0:p0 + ilen])) & 0xffffffff
struct.pack_into("<I", patched, S4hdr, newcrc)

# --- recompute whole-image MD5 trailer (last 16 bytes) ---
md5 = hashlib.md5(bytes(patched[:N - 16])).digest()
patched[N - 16:N] = md5

open(DST, "wb").write(patched)

# ---------------- VERIFY ----------------
d = bytes(patched)
print("S60 slot:", SLOT, "  payload used:", len(new), "  padded:", len(patch))
print("=== VERIFY ===")
i = 0; mags = []
while True:
    i = d.find(b"\x90\xeb\x24\xa3", i)
    if i < 0:
        break
    mags.append(i - 0x18); i += 1
allok = True
for h in mags:
    c, _, _, il, _, _, _ = struct.unpack_from("<IIIIIII", d, h)
    cc = zlib.crc32(d[h + 0x100:h + 0x100 + il]) & 0xffffffff
    ok = (c == cc); allok &= ok
    print(f"  section hdr@0x{h:07x} crc {'OK' if ok else 'BAD'} (0x{c:08x})")
md5ok = hashlib.md5(d[:N - 16]).digest() == d[N - 16:]
print("  md5 trailer:", "OK" if md5ok else "BAD")
sec03 = d[:0x1b1f714] == bytes(orig[:0x1b1f714])
print("  sections 0-3 byte-identical to stock:", sec03)
diff = [k for k in range(0x1b1f714 + 4, N - 16) if d[k] != orig[k]]
print(f"  section 4 changed bytes: {len(diff)}  range 0x{min(diff):x}..0x{max(diff):x}"
      f"  (S60 slot 0x{S60:x}..0x{S60 + SLOT:x})")
print("  file size unchanged:", len(d) == N)
print("  ALL CRCs OK:", allok, " MD5 OK:", md5ok)
print()
print("--- patched S60postservice ---")
print(patch.split(b"\nexit 0\n")[0].decode() + "\nexit 0")
print()
print("RESULT:", "PASS - InstaGoFW_patched.bin is valid" if (allok and md5ok and sec03 and len(d) == N)
      else "FAIL - do not flash")
