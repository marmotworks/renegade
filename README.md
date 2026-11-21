# ROC-RK3399-PC — headless Ubuntu LTS on eMMC with SSH over USB-OTG

Guidance for setting up a Libre Computer **ROC-RK3399-PC** ("Renegade Elite") with an
eMMC module installed, running a minimal Ubuntu LTS server (no GUI), reachable over SSH
through its USB-OTG port from a macOS host.

---

## Context

| Fact | Consequence |
|---|---|
| The board has 16 MB SPI NOR holding UEFI U-Boot. | Vendor states SNOR boards boot **stock, unmodified generic Ubuntu arm64 images** — no board-specific image needed, no bootloader to write. |
| BootROM order is **SPI → eMMC → microSD → USB** ([#92](https://hub.libre.computer/t/roc-rk3399-pc-board-boot-media-detection-sequence/92)). | SPI firmware always wins; the OS disk is chosen by U-Boot. |
| Board requires **5.0V–5.5V up to 15W** ([#2846](https://hub.libre.computer/t/roc-rk3399-pc-renegade-elite-overview-resources-and-guides/2846)). | USB-C port on Mac or standard dumb 5V/3A supply works. Smart PD chargers can drop/reset during boot. |
| Latest Libre Ubuntu image is **22.04.3 (Sep 2023)**, and Jammy left standard support in 2025. | Use the current generic Ubuntu LTS preinstalled server image instead (**26.04**), keeping Libre 22.04 only as last resort. |
| The official Ubuntu **installer ISO** is listed by the vendor as "NOK — reboot loop" on these boards. | Use **preinstalled** images (`.img.xz`), never the live-server ISO. |
| The Type-C port **next to HDMI** is both the USB-OTG data port and the only power input ([#2087](https://hub.libre.computer/t/roc-rk3399-pc-renegade-elite-usb-device-tree/2087)). | One C-to-C cable carries power and data; `poweroff` needs an unplug/replug to come back on. |
| macOS cannot mount ext4/BTRFS. | All post-write work on the board's root filesystem happens on the board. |
| macOS Internet Sharing runs its **own DHCP server** on the shared link. | The board is a DHCP *client* on `usb0`; reach it by mDNS at `renegade.local`. |
| Gadget class: **CDC-ECM** is the one that works on macOS and Linux (RNDIS is Windows-only; NCM has had macOS-host lockups). | Gadget exposes an ECM Ethernet function. |

## Objectives

1. SPI firmware current.
2. Ubuntu 26.04 LTS server (no GUI) installed on the eMMC at full module capacity.
3. Headless: no display, ever. Access = `ssh admin@renegade.local` over the OTG cable.
4. Repeatable: unplugging and replugging the cable yields SSH again with no intervention.

**Non-goals:** GUI, Docker, hardware acceleration/VP9 tuning, firmware self-update, a
second network path. Diagnostics are added only when something fails.

## Prerequisites

- ROC-RK3399-PC with eMMC module seated.
- Fresh microSD card (≥ 8 GB) — SPI flasher, then trial boot, then kept as rescue.
- USB-C flash drive (≥ 4 GB) — formatted FAT32, **never raw-written**: holds the cloud-init
  seed and the OS image.
- **USB-C to USB-C data** cable, into a real USB-C/Thunderbolt port on the Mac. A USB-A
  adapter declares 500 mA and browns the board out.
- Assumes the Mac port/cable supply enough power (board can draw up to ~15 W).
- macOS host with `curl`, `shasum`, `diskutil`, `dd`.
- Roughly 30 minutes plus a 2.2 GB download.

### Files — agent-driven, no hardware involved

Assets can be fetched and verified automatically with:

```bash
cd ~/Workspaces/renegade
./download-assets.sh
```

Or manually:

```bash
cd ~/Workspaces/renegade
curl -LO https://cdimage.ubuntu.com/releases/26.04.1/release/ubuntu-26.04.1-preinstalled-server-arm64.img.xz
echo '189b1aec3eaf9544a51dba4e6ac3f4d5d24fd1031ed0263fa5ea78f1824934c1  ubuntu-26.04.1-preinstalled-server-arm64.img.xz' | shasum -a 256 -c -
curl -LO https://boot.libre.computer/release/roc-rk3399-pc/roc-rk3399-pc-spiflash.img
ssh-keygen -t ed25519 -f ./id_renegade -N '' -C 'mac-host'
sed -i '' "s|REPLACE-WITH-CONTENT-OF-id_renegade.pub|$(cat id_renegade.pub)|" user-data
pmset -c sleep 0 disksleep 0      # needs sudo, and the Mac must not sleep mid-write
```

Everything above is software-only and can be run by the agent; the user only needs to
approve the two `sudo`s (`pmset`, and later every `dd`). From step 1 onward every step
touches physical media, so it is user-driven with the agent verifying results over SSH.

[`user-data`](./user-data), [`network-config`](./network-config) and
[`meta-data`](./meta-data) live in this directory — they are the cloud-init seed and are
copied to the seed drive unchanged, apart from pasting your public key into `user-data`.

---

## Process

### 1. Update SPI firmware

Write the flasher to the microSD card:

```bash
diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=roc-rk3399-pc-spiflash.img of=/dev/rdiskN bs=4m status=progress; sync
```

Leave the eMMC module **in** — SPI outranks it, so the flasher boots regardless. Insert the
card and apply power by plugging the cable into the Mac. The board flashes its own SPI NOR
in about a minute and needs no console to do it. Nothing confirms success; step 3 boots
through SPI U-Boot either way, and the image is idempotent, so re-running this step is
harmless.

> Flashing SPI is the only hard-to-reverse step: a half-written SPI image outranks every
> other boot source, so the cable must not be disturbed while it writes. Recovery exists
> (hold RECOVER → Rockchip MaskROM `2207:330c` + `rkdeveloptool`, which needs a Linux host)
> but should not be needed.

*If the board gives no sign of running the flasher* (no network response, no boot
settle): power off, remove the eMMC module, retry — this removes the boot-order variable.
Reseat the module squarely afterwards; a half-seated module is harder to diagnose headless
than the problem it solves.

### 2. Prepare the seed drive

```bash
diskutil list
diskutil unmountDisk /dev/diskN
diskutil partitionDisk /dev/diskN 1 MBRFormat MS-DOS CIDATA 100%
R=/Volumes/CIDATA
cp ubuntu-26.04.1-preinstalled-server-arm64.img.xz user-data network-config meta-data "$R/"
diskutil info "$R" | grep -E 'File System|Volume Name'   # must read MS-DOS / FAT32, label CIDATA
```

`instance-id` in `meta-data` is what makes cloud-init re-run. Bump it to re-seed.

### 3. First boot from microSD

```bash
diskutil list
diskutil unmountDisk /dev/diskN
sudo dd if=ubuntu-26.04.1-preinstalled-server-arm64.img.xz of=/dev/rdiskN bs=4m status=progress; sync
```

Assemble: microSD in, USB-C drive in a **host** Type-C port, single C-to-C cable from the
**OTG port (the Type-C next to HDMI)** to the Mac.

This overwrites the SPI flasher card. That is fine — the firmware is written — and this
same microSD boot is the rescue system for the rest of the process and afterwards.

First boot takes about two minutes (filesystem resize, then cloud-install). There is no
password — the `admin` account is key-only.

```bash
ssh -i ~/Workspaces/renegade/id_renegade admin@renegade.local
```

If the name does not resolve: `dns-sd -G v4 renegade.local`, then `arp -a | grep 10.55.0`.

Before touching the eMMC:

```bash
cloud-init status --wait && uname -r
```

### 4. Install to eMMC

Stream the image from the seed drive directly to the eMMC (`/dev/mmcblk0`).
Because it is a clean image write, Ubuntu's cloud-init will automatically grow the
partition to the full eMMC capacity and resize the filesystem on first boot — no manual
`growpart` or filesystem resizing needed.

The board is booted from microSD, so **`mmcblk0` = eMMC** and **`mmcblk1` = microSD**.

```bash
lsblk -o NAME,SIZE,MOUNTPOINT,MODEL      # confirm mmcblk0 is the eMMC and mmcblk1 is the microSD
ls -d /media/*/CIDATA                    # verify seed drive is mounted
SEED=$(echo /media/*/CIDATA)
ls -l "$SEED"                            # should show the .img.xz and seed files
```

> **`of=/dev/mmcblk0`** — the *eMMC*, the whole disk. A wrong target destroys the
> system the board is currently running. Double-check `lsblk` before proceeding.

```bash
sudo xz -dc "$SEED/ubuntu-26.04.1-preinstalled-server-arm64.img.xz" \
  | sudo dd of=/dev/mmcblk0 bs=64M status=progress oflag=sync
sync
```

Power off the board (unplug the USB-C cable).
Remove the microSD card, **leave the seed drive plugged in**, and re-apply power.
The eMMC boots as a pristine image: cloud-init provisions it, expands the partition to full
eMMC capacity, and generates fresh SSH host keys (~2 minutes).

Once verified via SSH, the seed drive can be removed.

### 5. Verify

```bash
lsblk /dev/mmcblk0            # root on eMMC, grown to module size
df -h /
cloud-init status --wait
systemctl is-enabled ssh avahi-daemon usb-gadget
ip -br a
```

**Acceptance test:** enable System Settings → General → Sharing → **Internet Sharing →
Thunderbolt/USB-C**, confirm `ping -c3 1.1.1.1` and `sudo apt update`, then unplug the
cable, wait 10 s, replug — `ssh admin@renegade.local` answers again on its own.

Run `sudo apt update && sudo apt full-upgrade` over the cable, then move the board to
`eth0` for the LAN.

---

## If something fails

| Symptom | Action |
|---|---|
| Kernel panics / no console handoff from eMMC | Device-tree hand-off. Copy `/usr/lib/firmware/*/device-tree/rockchip/rk3399-roc-pc.dtb` to `/boot/dtb/rockchip/`, set `GRUB_DEVICE_TREE=/boot/dtb/rockchip/rk3399-roc-pc.dtb`, `update-grub`. |
| Gadget never enumerates on the Mac | Boot the microSD rescue copy. Check `dmesg \| grep -i dwc3` and `ls /sys/class/udc`. |
| No SSH but link is up | `systemctl status ssh avahi-daemon usb-gadget`; connect by `10.55.0.1` instead of the mDNS name. |
| 26.04 misbehaves on this board | Copy `ubuntu-24.04.5-preinstalled-server-arm64.img.xz` to the seed drive as well, then repeat steps 3–4 with it, and `sudo apt install linux-modules-extra-$(uname -r)` (24.04 splits drivers out; 26.04 does not). |
| Last resort image | Libre `ubuntu-22.04.3-preinstalled-base-arm64+arm64` — `root`/`root`, no cloud-init, `apt install ssh`. Past standard support. |
| Board does not boot at all | Hold RECOVER, plug in, look for `2207:330c` in `lsusb` from a Linux host → `rkdeveloptool`. |
| Reboot loop / shut-off during boot | Marginal power or USB-PD renegotiation ([#2846](https://hub.libre.computer/t/roc-rk3399-pc-renegade-elite-overview-resources-and-guides/2846)). Use dumb 5V 3A (15W) power or powered USB-C hub. |
| RAM or hardware instability suspected | Run the official [ROC-RK3399-PC Memory Test (#93)](https://hub.libre.computer/t/roc-rk3399-pc-renegade-elite-memory-test/93) image. |

### Deliberately deferred

SPI content read-back, a USB-ACM serial console function (the fallback when SSH doesn't
come up), the 3-pin debug UART (needs 1.5 Mbps — a CP2102 cable tops out at 1 Mbps),
gadget re-arm on reconnect, journald persistence.

## Sources & Official Documentation

Linked from the [ROC-RK3399-PC Help Tab](https://libre.computer/products/roc-rk3399-pc/#help):

- **Official Guides:**
  - [ROC-RK3399-PC Firmware (#151)](https://hub.libre.computer/t/roc-rk3399-pc-firmware/151) — SPI flash image and update procedure
  - [ROC-RK3399-PC Overview, Resources and Guides (#2846)](https://hub.libre.computer/t/roc-rk3399-pc-renegade-elite-overview-resources-and-guides/2846) — Power requirements (5.0V–5.5V, 15W) and LED controls
  - [Boot Media Detection Sequence (#92)](https://hub.libre.computer/t/roc-rk3399-pc-board-boot-media-detection-sequence/92) — BootROM order: SPI → eMMC → microSD → USB OTG
  - [USB Device Tree (#2087)](https://hub.libre.computer/t/roc-rk3399-pc-renegade-elite-usb-device-tree/2087) — Controller enumeration and port assignments
  - [ROC-RK3399-PC Memory Test (#93)](https://hub.libre.computer/t/roc-rk3399-pc-renegade-elite-memory-test/93) — Standalone RAM diagnostic
- **Hardware & Software References:**
  - [Interactive GPIO Pinout](https://gpio.hardware.libre.computer/?board=roc-rk3399-pc)
  - [Power Tree Architecture](https://power.hardware.libre.computer/?board=roc-rk3399-pc)
  - [U-Boot Features & Status](https://u-boot.software.libre.computer/features/?board=roc-rk3399-pc)
  - [ROC-RK3399-PC Schematic](https://drive.google.com/file/d/162C8mfrm1__Lm5sD4PtgNaOAYpAAxsHG/view?usp=sharing)
  - [Renegade Elite Hub Discussions](https://hub.libre.computer/tag/roc-rk3399-pc)
- **Firmware & OS Downloads:**
  - SPI Update Image: `https://boot.libre.computer/release/roc-rk3399-pc/roc-rk3399-pc-spiflash.img` (or `https://boot.libre.computer/ci/roc-rk3399-pc-spiflash`)
  - Ubuntu Releases: `https://cdimage.ubuntu.com/releases/`
  - [Firmware Update Images Thread (#3113)](https://hub.libre.computer/t/libre-computer-board-bios-firmware-update-images/3113)
  - [Ubuntu 22.04 LTS Images Thread (#20)](https://hub.libre.computer/t/ubuntu-22-04-jammy-lts-for-libre-computer-boards/20)
  - [Developer Boot Guide Thread (#4245)](https://hub.libre.computer/t/roc-rk3399-pc-renegade-elite-developer-boot-guide/4245)
