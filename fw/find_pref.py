#!/usr/bin/env python3
"""Find WHERE and HOW the GO 1 stores 'standby_duration' (the auto-power-off timer),
so we can set it locally from the root shell / bake it into the boot patch instead of
needing the phone app over BLE. All host-side: reads the firmware image, camera can be
asleep or unplugged."""
import re

data = open("InstaGoFW.bin", "rb").read()


def hits(label, pat, back=70, fwd=160, limit=20):
    print(f"===== {label} =====")
    n = 0
    seen = set()
    for m in re.finditer(pat, data):
        s = m.start()
        seg = data[s - back:s + fwd]
        txt = "".join(chr(b) if b in (9, 10, 13) or 32 <= b < 127 else "." for b in seg)
        txt = txt.replace("\n", " ").replace("\r", " ")
        key = txt.strip()
        if key in seen:
            continue
        seen.add(key)
        print(f"  @0x{s:x}: ...{txt}...")
        n += 1
        if n >= limit:
            break
    if not n:
        print("  (none)")
    print()


# 1. Candidate on-disk config / param file paths the firmware references.
hits("param/config file paths",
     rb"(/tmp|/mnt|/mmc|/usr/local|/etc|/home|c:|C:)[/\\][A-Za-z0-9_./\\-]*"
     rb"(param|pref|option|setting|config|\.conf|\.ini|\.bin|\.dat|\.pb)[A-Za-z0-9_./\\-]*")

# 2. Everything sitting next to 'standby_duration' (field table / struct layout).
hits("standby_duration context", rb"standby_duration")

# 3. The option-type enum block (shows the full option set order/index).
hits("STANDBY_DURATION enum", rb"STANDBY_DURATION")

# 4. The protobuf handler for setting standby (field names + resp).
hits("set_standby_mode proto", rb"set_standby_mode|SetStandbyMode|standby_mode:")

# 5. Numeric defaults / bounds hints, and any "0 = never / disable" semantics.
hits("default / min / max / never / disable near 'standby'",
     rb"[Ss]tandby[^\n]{0,40}(default|min|max|never|disable|infinite|forever|0)")
hits("APO / idle numeric knobs",
     rb"(apo|APO|idle|Idle|IDLE|power_off|PowerOff|standby|Standby)[ _]?"
     rb"(sec|second|time|timeout|duration|cnt|count|ms|min)[A-Za-z_]*")

# 6. Where instaAIP / preferences code reads or writes the store.
hits("instaAIP / S51pref file I/O clues",
     rb"(instaAIP|S51pref|load[_ ]?pref|save[_ ]?pref|read[_ ]?param|write[_ ]?param|"
     rb"fopen|Options?_?(Load|Save|Read|Write|Get|Set)|amba_?nvm|NVM|nvram)")

# 7. Any RTOS suspend/APO trigger command we could neutralise.
hits("RTOS suspend/APO trigger", rb"(suspend [0-9<]|do_?suspend|enter[_ ]?standby|AutoPowerOff|auto_power_off|arm[_ ]?apo)")
