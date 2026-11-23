# ROC-RK3399-PC — Ubuntu 26.04 LTS on eMMC via USB Wi-Fi

Clean-slate process for installing **Ubuntu 26.04.1 LTS Server** onto the **ROC-RK3399-PC** ("Renegade Elite") eMMC module using a USB Wi-Fi adapter and SSH (`ubuntu@renegade.local`).

---

## Distilled Findings (Lessons Learned)

1. **SPI Firmware is Done:** SPI NOR already holds current UEFI U-Boot, which natively boots generic Ubuntu `arm64` preinstalled server images (`7.0.0-generic` kernel + full `linux-firmware`). Do not re-flash SPI.
2. **Wall Power Required:** Board + USB peripherals draw up to 15W. Laptop USB-C ports brown out; always power via a dumb **5V/3A wall adapter** into the **Type-C port next to HDMI**.
3. **Removable eMMC Eliminates Boot Collisions:** A partial eMMC write previously blocked microSD boots due to GRUB UUID collisions and UEFI boot priority (`mmc0` vs `mmc1`). Booting microSD **with the eMMC removed** guarantees a clean boot every time, and the RK3399 eMMC socket can be bound once in Linux (or flashed after hot-seating / rebinding `sdhci-arasan`).
   - *Safer alternative to hot-plugging:* Boot **24.04.5** on microSD with eMMC **installed**? No — Ubuntu 24.04/26.04 Server images **omit `wpasupplicant`**, so offline `.deb` packages for **26.04** are staged on `CIDATA/debs/`. Booting **26.04.1** on microSD with eMMC **removed** avoids UUID collision, then we hot-seat eMMC + rebind `fe330000.mmc` to flash it cleanly.
4. **Offline Wi-Fi Bootstrap Trap:** Generic Ubuntu 26.04 Server omits `wpasupplicant` and `avahi-daemon` from the base image! Without `wpasupplicant`, Netplan Wi-Fi silently fails offline. Our `CIDATA/debs/` folder bundles `wpasupplicant` + `avahi-daemon` (8 arm64 `.deb`s, SHA-256 verified) and `user-data` installs them via `dpkg -i` on first boot before `netplan apply`.
5. **User Account:** Ubuntu reserves the `admin` group name, causing `useradd admin` to fail silently. Always use `ubuntu` (with `- default`).
6. **GRUB Timeout:** Without `GRUB_TIMEOUT=2` and `GRUB_RECORDFAIL_TIMEOUT=2`, an interrupted boot leaves GRUB stuck indefinitely at the menu screen.

---

## Prerequisites Ready in `~/Workspaces/renegade/`

- `ubuntu-26.04.1-preinstalled-server-arm64.img.xz` (verified)
- `id_renegade` / `id_renegade.pub` (SSH keypair)
- `debs/` — offline `wpasupplicant` + `avahi-daemon` arm64 `.deb` packages for Ubuntu 26.04
- `user-data`, `network-config` (local, gitignored — templated in `network-config.example`), `meta-data` (`renegade-wifi-1`)

---

## Step-by-Step Clean-Slate Process

### Step 1 — Prepare `CIDATA` USB-C Flash Drive (Mac)
Format the USB-C flash drive as MBR FAT32 named `CIDATA` and copy the OS image, offline `.deb`s, and cloud-init seed files:

```bash
cd ~/Workspaces/renegade
diskutil list                              # identify USB-C flash drive (/dev/diskN)
diskutil unmountDisk /dev/diskN
diskutil partitionDisk /dev/diskN 1 MBRFormat MS-DOS CIDATA 100%
cp -R ubuntu-26.04.1-preinstalled-server-arm64.img.xz debs user-data network-config meta-data /Volumes/CIDATA/
diskutil eject /dev/diskN
```

### Step 2 — Flash Ubuntu 26.04.1 to microSD (Mac)

```bash
cd ~/Workspaces/renegade
diskutil list                              # identify microSD card (/dev/diskN)
diskutil unmountDisk /dev/diskN
xz -dc ubuntu-26.04.1-preinstalled-server-arm64.img.xz | sudo dd of=/dev/rdiskN bs=4m status=progress; sync
diskutil eject /dev/diskN
```

### Step 3 — Boot microSD Without eMMC (Board)
1. **Remove the eMMC module** from the board (prevents UUID/UEFI collision with the partial eMMC write).
2. Insert:
   - **microSD card**
   - **`CIDATA` USB-C drive** into the **outer Type-C host port** (away from HDMI)
   - **USB Wi-Fi adapter** into a USB-A port
3. Plug **5V/3A wall power** into the **Type-C port next to HDMI**.
4. Wait ~2–3 minutes (boots → installs `wpasupplicant` & `avahi-daemon` from `CIDATA/debs` → auto-reboots → joins Wi-Fi).
5. Verify SSH from Mac:
   ```bash
   ssh -i ~/Workspaces/renegade/id_renegade ubuntu@renegade.local
   ```

### Step 4 — Attach & Flash eMMC (Over SSH)
1. Carefully **snap the eMMC module onto its socket** (Libre Computer confirms RK3399 eMMC is hot-pluggable via driver bind/rebind), then probe it:
   ```bash
   echo fe330000.mmc | sudo tee /sys/bus/platform/drivers/sdhci-arasan/unbind 2>/dev/null || true
   echo fe330000.mmc | sudo tee /sys/bus/platform/drivers/sdhci-arasan/bind
   lsblk -o NAME,SIZE,MOUNTPOINT
   ```
   *(Confirm `/dev/mmcblk0` appears as the ~59 GB eMMC and `/dev/mmcblk1` is `/`.)*
2. Stream the clean 26.04.1 image to `/dev/mmcblk0` (**without** `oflag=sync` so it completes in ~1 min, followed by `sync`):
   ```bash
   sudo mkdir -p /mnt/cidata
   sudo mount -o ro $(blkid -L CIDATA) /mnt/cidata
   xz -dc /mnt/cidata/ubuntu-26.04.1-preinstalled-server-arm64.img.xz \
     | sudo dd of=/dev/mmcblk0 bs=16M status=progress && sync
   sudo partprobe /dev/mmcblk0
   sudo poweroff
   ```

### Step 5 — Boot eMMC Standalone & Verify
1. Unplug wall power.
2. **Remove the microSD card** (keep as rescue).
3. **Leave `CIDATA` USB-C drive and USB Wi-Fi adapter plugged in.**
4. Plug wall power back in and wait ~2–3 minutes (cloud-init expands eMMC to full 59 GB, installs offline `wpasupplicant` + `avahi-daemon`, regenerates SSH host keys, reboots onto Wi-Fi).
5. SSH in and verify:
   ```bash
   ssh-keygen -R renegade.local
   ssh -i ~/Workspaces/renegade/id_renegade ubuntu@renegade.local
   lsblk /dev/mmcblk0 && df -h / && ip -br a
   ```
6. Remove the `CIDATA` USB-C drive.
