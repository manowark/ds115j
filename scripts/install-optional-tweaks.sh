#!/bin/sh
# install-optional-tweaks.sh — deploy optional tweaks to DS115j
# Usage: run on helper, targets NAS via SSH
#        ./install-optional-tweaks.sh [wol|sysctl|usb|all]
#
# These are OPTIONAL — the base system works without them.
# Each tweak can be installed/removed independently.

set -e

NAS_IP="${NAS_IP:-192.168.68.233}"
NAS_USER="${NAS_USER:-root}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/../config"

usage() {
  echo "Usage: $0 [wol|sysctl|usb|all]"
  echo ""
  echo "  wol    — Wake-on-LAN (requires: ethtool)"
  echo "  sysctl — BBR + TCP buffer tuning"
  echo "  usb    — USB auto-mount (udev rule)"
  echo "  all    — install everything"
  exit 1
}

[ $# -eq 0 ] && usage

deploy() {
  local src="$1" dst="$2"
  scp -q "$src" "${NAS_USER}@${NAS_IP}:${dst}"
}

run() {
  ssh "${NAS_USER}@${NAS_IP}" "$@"
}

install_wol() {
  echo "[wol] Installing Wake-on-LAN..."
  # Ensure ethtool is installed
  run "DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends ethtool >/dev/null 2>&1"
  # Deploy systemd oneshot service (reliable, runs after network.target)
  deploy "${CONFIG_DIR}/wol.service" /etc/systemd/system/wol.service
  run "systemctl daemon-reload && systemctl enable wol.service >/dev/null 2>&1"
  # Deploy udev rule as early attempt (harmless)
  deploy "${CONFIG_DIR}/70-wol-eth0.rules" /etc/udev/rules.d/70-wol-eth0.rules
  # Enable now
  run "ethtool -s eth0 wol g"
  echo "[wol] Done. WoL enabled: $(run "ethtool eth0 2>/dev/null | grep Wake-on")"
}

install_sysctl() {
  echo "[sysctl] Installing BBR + TCP tuning..."
  deploy "${CONFIG_DIR}/99-ds115j-network.conf" /etc/sysctl.d/99-ds115j-network.conf
  run "sysctl --system >/dev/null 2>&1"
  echo "[sysctl] Done. congestion_control=$(run "sysctl -n net.ipv4.tcp_congestion_control")"
}

install_usb() {
  echo "[usb] Installing USB auto-mount..."
  deploy "${CONFIG_DIR}/usb-automount.sh" /usr/local/sbin/usb-automount.sh
  run "chmod +x /usr/local/sbin/usb-automount.sh"
  deploy "${CONFIG_DIR}/99-usb-automount.rules" /etc/udev/rules.d/99-usb-automount.rules
  run "udevadm control --reload-rules 2>/dev/null || true"
  echo "[usb] Done. USB drives will auto-mount to /mnt/usb-<device>"
}

for arg in "$@"; do
  case "$arg" in
    wol)    install_wol ;;
    sysctl) install_sysctl ;;
    usb)    install_usb ;;
    all)    install_wol; install_sysctl; install_usb ;;
    *)      usage ;;
  esac
done

echo ""
echo "All requested tweaks installed."
