#!/bin/sh
# ---------------------------------------------------------------------------
# GO 1 console keep-alive + recon.  Runs as root from the patched
# S60postservice on every NO_HIBER cold boot.  Drop this at the ROOT of the
# camera card (same folder as NO_HIBER and DCIM/).  Edit KA below and reboot
# to try a different keep-alive -- NO reflash needed, it's just a text file.
# All output lands on the card, so you read it on the desktop; the short
# serial window no longer matters.
# ---------------------------------------------------------------------------
SD=/tmp/SD0

# Keep-alive command under test. Candidates to try, one per boot:
#   SendToRTOS net_ready 1     (tell RTOS a link/app is up -> stay awake)
#   SendToRTOS net_ready 2
#   SendToRTOS boot_done       (nudge activity every few seconds)
#   SendToRTOS record          (LAST resort: actually records video)
# For the factory_script.json test this is a NO-OP so the ONLY variable is the
# JSON file -- goinit just timestamps uptime so we see exactly if/when it sleeps.
KA="true"

# ---- one-shot recon: dump the power interface so we can see it on desktop ----
{
  echo "===== recon $(date) uptime=$(cat /proc/uptime) ====="
  echo "--- /proc/ambarella ---"; ls -la /proc/ambarella/ 2>&1
  echo "--- /sys/power ---"; ls -la /sys/power/ 2>&1; cat /sys/power/state 2>&1
  echo "--- ps ---"; ps 2>&1
  for f in /proc/ambarella/*; do
    case "$f" in
      *power*|*standby*|*apo*|*mode*|*sys*|*hiber*)
        echo "--- cat $f ---"; cat "$f" 2>&1 ;;
    esac
  done
} > "$SD/recon.log" 2>&1
sync

# ---- keep-alive loop: hit the RTOS every 4s, log uptime each time so we can
#      see exactly IF and WHEN it still sleeps (log survives on the card) ----
: > "$SD/keepalive.log"
i=0
while [ "$i" -lt 45 ]; do
  $KA >/dev/null 2>&1
  echo "$i  uptime=$(cat /proc/uptime)  KA=[$KA]" >> "$SD/keepalive.log"
  sync
  i=$((i + 1))
  sleep 4
done
echo "LOOP FINISHED still awake uptime=$(cat /proc/uptime)" >> "$SD/keepalive.log"
sync
