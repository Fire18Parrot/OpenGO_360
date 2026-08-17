#!/usr/bin/env python3
"""Pull /etc/passwd and /etc/shadow (and hostname) out of the firmware image so we
know the real console login and whether accounts have a password."""
import re

data = open("InstaGoFW.bin", "rb").read()

def show(label, pat):
    print(f"===== {label} =====")
    hits = 0
    for m in re.finditer(pat, data):
        s = m.start()
        # print the whole line the match sits on
        ls = data.rfind(b"\n", max(0, s - 200), s) + 1
        le = data.find(b"\n", s, s + 300)
        if le < 0:
            le = s + 200
        line = data[ls:le]
        txt = "".join(chr(b) if 32 <= b < 127 else "." for b in line)
        print(f"  @0x{s:x}: {txt}")
        hits += 1
        if hits > 12:
            break
    if not hits:
        print("  (none)")
    print()

# passwd lines:  name:x:uid:gid:...:/home:/bin/sh   or   name::0:0:...
show("passwd-style (uid/gid fields)", rb"[a-z_][a-z0-9_-]*:[^:\n]*:[0-9]+:[0-9]+:[^\n]{0,80}")
# shadow-style:  name:$1$....  or name::  or name:!:
show("shadow-style ($ hash / empty / locked)", rb"(root|default|admin|user)::?[!*]?\$?[0-9A-Za-z./$!*]{0,60}:[0-9]")
# explicit root entries
show("root entries", rb"root:[^\n]{0,80}")
# md5/sha crypt hashes anywhere ($1$, $5$, $6$)
show("crypt hashes", rb"\$[1568][a-z]?\$[0-9A-Za-z./]{1,16}\$[0-9A-Za-z./]{10,90}")
# hostname
show("hostname 'a12' context", rb"a12")
