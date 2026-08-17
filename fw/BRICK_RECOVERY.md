# GO 1 brick — full firmware analysis + recovery map

Camera state: stuck in factory/burn-in mode. USB = full-speed pull-up asserted
but **-71 / zero bytes to every GET_DESCRIPTOR**. No BLE. Cause: a
`C:\factory_script.json` (burn_in, times:0) placed on the eMMC forced the RTOS
into burn-in mode, which brings up **no** USB command channel and **no** BLE.

Image: `InstaGoFW.bin` (48,920,612 B, md5 fb13a4…). No cryptographic signature;
integrity = per-section CRC32 + whole-image MD5 trailer.

## Container layout (5 sections, 256-byte headers, magic 0xA324EB90 @+0x18)

| # | file hdr | load addr | size | contents |
|---|----------|-----------|------|----------|
| 0 | 0x000fc | 0xa0001000 | 6.7 MB | **RTOS (ThreadX)** — factory mode, cJSON, USB MSC, FwUpdater |
| 1 | 0x68a69c | — | 5.0 MB | DSP orccode |
| 2 | 0xb6279c | — | 11.5 MB | DSP #2 |
| 3 | 0x165d89c | 0x1c608000 | 4.9 MB | Linux kernel |
| 4 | 0x1b1f714 | — | 20 MB | Linux rootfs (ext2, BusyBox) — S60postservice lives here |

No BST/BLD (amboot) section in this image → **the on-camera bootloader is intact**
(good: a boot-ROM/amboot download path, if triggered, is not corrupted).

## Why the camera is dark (confirmed from strings)

- Factory mode is entered **only** if `C:\factory_script.json` exists. The normal
  branch prints `Factory script has not found` and boots normally.
- Burn-in mode does **not** start the MSC app or BLE. `MSC`/`BLE` are *app modes*
  (`[SM]<Msc Init> app mode switch failed`, `App Msc`). Factory is a different
  mode → no USB gadget serviced → host sees pull-up but gets -71. Matches reality.
- Our JSON used `times:0` → `Timer start failed` / no `Burn Time Runout!` → it
  never times out and never reboots. Stuck indefinitely.

Net: **in the current state the camera runs no command interface at all** — not
USB, not BLE, not serial (production kernel bootargs have no `console=`). There is
**no software-only entrypoint**. Recovery must be at the storage or boot level.

## The fix, stated exactly

Deleting the single file `C:\factory_script.json` from the eMMC FAT partition
returns the camera to normal boot → MSC comes up → fully recovered. Everything
below is a way to reach that file (or to reflash around it).

## Entrypoints found in firmware (and whether reachable NOW)

1. **RTOS FwUpdater** (`AmbaFwUpdaterTask`, `FwUpdater_WriteFwImage`)
   - Reads **`C:\InstaGoFW.bin`** from the eMMC FAT partition.
   - Checks model name, per-section CRC32, whole-image MD5; needs **battery >15%**
     (`Power Level Lower Then 15%, Can Not Update`).
   - `Backup DtbBlock` → `Program "%s" to eMMC` → `erase hiber...` →
     `Remove firware file` → `Reboot After Fw Update`.
   - Reachable now? **No** — needs the file written to eMMC (needs USB or ISP).
   - Once we have eMMC write access, dropping a valid `InstaGoFW.bin` is a robust
     reflash *and* it erases hiber (forces clean cold boot).

2. **USB MSC vendor "host command" channel (SCSI CDBs, Bulk-Only)**
   - `SG_HOST_CMD_ERASE_SD_CARD`, `_RESTORE_FACTORY_SETTINGS`, `_DELETE_FILES`,
     `_REBOOT_CAMERA`, `_SET_OPTIONS`, … plus `setmode [video/photo/power/msc/fw_update]`.
   - A working host could send ERASE_SD_CARD / DELETE_FILES(factory_script.json) /
     REBOOT_CAMERA directly. **But only when the MSC app mode is running** — i.e.
     normal boot, not factory mode. Not reachable now.

3. **Factory/burn-in button + LED** (`Button is not init.`, `Led is not init.`,
   `[AppFactory] Execute msg_dev:%d cmd:%d`). The button is referenced in factory
   mode. Unknown whether a press exits burn-in (needs disassembly). Cheap to try in
   hardware since the button is accessible.

## Recovery paths, prioritised (all hardware — firmware confirms nothing else)

### P0 — Direct-solder USB, rule out contact (cheap, ~20 min)
Board is out of its shell; the last successful enumeration was through pogo pins.
Solder VBUS / D+ / D- / GND from the dock pads straight to a cut USB cable.
- If -71 **changes** → it was contact; the drive mounts, `rm factory_script.json`, done.
- If -71 **persists** → confirms firmware prediction (no MSC in factory mode). Move on.

### P1 — Force Ambarella boot-ROM USB download ("the flasher"), then DirectUSB
THE canonical A12 unbrick (this is what the EKEN A12 unbrick post did). Bypasses
the eMMC entirely, un-brickable (mask ROM). The A12 boot ROM supports USB boot as a
recovery: if it cannot read a valid BST from the selected boot medium, it drops to
USB download. So **starve the eMMC boot read at power-on**:
- Momentarily short **sd_clk (H22)**, **sd_cmd (J22)**, or **sd_d0 (P21)** to GND
  — or short **CMD↔CLK** together — during the first ~1 s after applying power,
  so the ROM's eMMC BST read fails → falls to USB download.
- Release the short immediately once DirectUSB detects the device (so DRAM/eMMC
  writes during flashing aren't disturbed).
- DirectUSB should then show "Ambarella …" instead of `USB0: Unknown`. Board
  profile `A12.LPDDR3.EMMC`, flash stock `InstaGoFW.bin`.
The eMMC lines above are the A12 SD0 balls; on the board they run to the eMCP —
target the short traces / test-point vias between A12 and the 08EMCP04, or the
eMCP's own CLK/CMD/DAT0 balls. VBUS-present on USB0 (DETECT_VBUS = W6) is required,
so keep the USB cable plugged while power-cycling.

### P2 — eMMC ISP: read/write the FAT partition directly
Find eMMC **CLK, CMD, DAT0, VCC, VCCQ, VSS, RST_N** on the eMCP. Hold the A12 in
**reset via POR_L (V8, pull low)** so it releases the SD0 bus, then drive the eMMC
from an external eMMC/SD reader, mount the FAT partition on a PC, `rm
factory_script.json` (and/or copy a good `InstaGoFW.bin` on). DAT0 alone (1-bit) is
enough. eMCP (08EMCP04) balls are inner-layer — hardest path, but definitive.

## A12S75 pin reference (from datasheet; identical across 1-/2-core variants)
- eMMC = SD0 controller (SMIO pins): sd_clk **H22**, sd_cmd **J22**,
  sd_d0 **P21**, sd_d1 **K21**, sd_d2 **J21**, sd_d3 **H21**, sd_d4 **J20**,
  sd_d5 **K20**, sd_d6 **L19**, sd_d7 **H20**, sd_cd **M22**, sd_wp **K22**.
  (SD_VDDO IO power = M18/N18.) SD1/SDIO and SD2/SDXC also exist if eMMC isn't SD0.
- Reset: **POR_L V8** (power-on reset, active-low IN — pull low to hold in reset),
  **PWC_RSTOB A5** (reset out / power up-down).
- USB0 device: **USB0_DP AB5**, **USB0_DM AA5**, USB0_REXT AA4, **DETECT_VBUS W6**.
- Boot options: NOR-SPI, NAND, USB, eMMC. POC boot straps are on the VOUT pins
  (VD0_OUT_*), sampled at reset; exact table is in the HPRM, not the datasheet.

## Key firmware offsets (section 0 / RTOS, file-relative)
- `C:\factory_script.json`            @0x48e1e8  (the file to delete)
- `Factory script has not found`      @0x48e2ec  (normal-boot branch)
- burn keys burn_in/power_mgr/…       @0x48e270
- `C:\InstaGoFW.bin`                   @0x47aeb8  (updater input file)
- FwUpdater strings                    @0x47 abac..0x47b0f4
- SG_HOST_CMD_* table                  @0x48e9bf..0x49006f
- `setmode [video/photo/power/msc/fw_update]` @0x4ac030
- Linux-side same FAT partition mounts at `/tmp/SD0` (`/tmp/SD0/InstaGoFW.bin`)
