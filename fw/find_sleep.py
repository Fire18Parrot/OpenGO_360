#!/usr/bin/env python3
"""Locate the GO 1 idle auto-power-off / sleep mechanism in the firmware image, so we
can disable it. Prints string hits with context and any config-file knobs."""
import re

data = open("InstaGoFW.bin", "rb").read()

def hits(label, pat, ctxback=60, ctxfwd=120, limit=14):
    print(f"===== {label} =====")
    n = 0
    for m in re.finditer(pat, data):
        s = m.start()
        seg = data[s - ctxback:s + ctxfwd]
        txt = "".join(chr(b) if b in (9, 10, 13) or 32 <= b < 127 else "." for b in seg)
        txt = txt.replace("\n", " ").replace("\r", " ")
        print(f"  @0x{s:x}: ...{txt}...")
        n += 1
        if n >= limit:
            break
    if not n:
        print("  (none)")
    print()

for lbl, pat in [
    ("auto power off",        rb"[Aa]uto[ _]?[Pp]ower[ _]?[Oo]ff"),
    ("APO / power_off",       rb"(APO|power_off|poweroff|PowerOff|PWROFF)"),
    ("idle timer",            rb"[Ii]dle[ _]?(time|timer|timeout|sec|cnt|count)?"),
    ("standby / sleep",       rb"(standby|Standby|STANDBY|auto_sleep|AutoSleep|sleep_time)"),
    ("shutdown timer",        rb"(shutdown|Shutdown)[ _]?(time|timer|timeout|delay|sec)"),
    ("SendToRTOS args",       rb"SendToRTOS [a-z_]+"),
    ("config knobs (.conf)",  rb"[A-Z_]{3,}(POWER|SLEEP|IDLE|STANDBY|TIMEOUT|OFF)[A-Z_]*[ =:]"),
    ("no-sleep style flags",  rb"(NO_SLEEP|NO_POWEROFF|STAY_AWAKE|KEEP_AWAKE|NO_APO|disable_apo)"),
]:
    hits(lbl, pat)
