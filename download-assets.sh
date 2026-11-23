#!/usr/bin/env bash
#
# Download and verify large binary assets for ROC-RK3399-PC Renegade Elite setup.
# The Ubuntu LTS image (1.3 GB) exceeds GitHub's 100 MB single-file repository limit,
# so this script fetches it directly from the official Canonical release mirror.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

UBUNTU_IMG="ubuntu-26.04.1-preinstalled-server-arm64.img.xz"
UBUNTU_URL="https://cdimage.ubuntu.com/releases/26.04.1/release/${UBUNTU_IMG}"

SPI_IMG="roc-rk3399-pc-spiflash.img"
SPI_URL="https://boot.libre.computer/release/roc-rk3399-pc/${SPI_IMG}"

echo "==> Checking assets..."

if [ ! -f "${SPI_IMG}" ]; then
  echo "==> Downloading SPI flash image (${SPI_IMG})..."
  curl -f -LO --retry 3 "${SPI_URL}"
else
  echo "==> SPI flash image (${SPI_IMG}) already present."
fi

if [ ! -f "${UBUNTU_IMG}" ]; then
  echo "==> Downloading Ubuntu LTS image (${UBUNTU_IMG}, ~1.3 GB)..."
  curl -f -LO -C - --retry 3 "${UBUNTU_URL}"
else
  echo "==> Ubuntu LTS image (${UBUNTU_IMG}) already present."
fi

mkdir -p debs
echo "==> Downloading offline Ubuntu 26.04 arm64 Wi-Fi & mDNS packages (debs/)..."
PORTS_URL="http://ports.ubuntu.com/ubuntu-ports/pool/main"
DEBS=(
  "libn/libnl3/libnl-genl-3-200_3.12.0-2_arm64.deb"
  "p/pcsc-lite/libpcsclite1_2.4.1-1_arm64.deb"
  "w/wpa/wpasupplicant_2.11-0ubuntu5_arm64.deb"
  "a/avahi/avahi-daemon_0.8-18ubuntu1_arm64.deb"
  "a/avahi/libavahi-common-data_0.8-18ubuntu1_arm64.deb"
  "a/avahi/libavahi-common3_0.8-18ubuntu1_arm64.deb"
  "a/avahi/libavahi-core7_0.8-18ubuntu1_arm64.deb"
  "libd/libdaemon/libdaemon0_0.14-7.1ubuntu5_arm64.deb"
)
for rel in "${DEBS[@]}"; do
  f="debs/$(basename "${rel}")"
  [ -f "${f}" ] || curl -f -L -o "${f}" --retry 3 "${PORTS_URL}/${rel}"
done

echo "==> Verifying SHA-256 checksums..."
if command -v shasum >/dev/null 2>&1; then
  shasum -a 256 -c SHA256SUMS
elif command -v sha256sum >/dev/null 2>&1; then
  sha256sum -c SHA256SUMS
else
  echo "Warning: neither shasum nor sha256sum found. Skipping verification."
fi

echo "==> All assets ready!"
