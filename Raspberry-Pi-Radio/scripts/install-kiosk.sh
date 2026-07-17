#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this installer with sudo: sudo ./scripts/install-kiosk.sh"
  exit 1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! systemctl cat greylock-radio.service >/dev/null 2>&1; then
  echo "Install the radio first with: sudo ./scripts/install.sh"
  exit 1
fi

echo "Installing the optional local screen..."
apt-get -o Acquire::Retries=5 update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  xserver-xorg xserver-xorg-video-fbdev x11-xserver-utils xinit openbox chromium

usermod -a -G audio,video,render,input greylock-radio
install -m 0755 "${SOURCE_DIR}/scripts/kiosk-session.sh" \
  /opt/greylock-radio/scripts/kiosk-session.sh
install -m 0644 "${SOURCE_DIR}/systemd/greylock-radio-kiosk.service" \
  /etc/systemd/system/greylock-radio-kiosk.service

systemctl daemon-reload
systemctl set-default graphical.target
systemctl enable --now greylock-radio-kiosk.service

echo "Kiosk mode is installed. The radio screen will open after reboot."
