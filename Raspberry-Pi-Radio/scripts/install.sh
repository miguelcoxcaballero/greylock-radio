#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this installer with sudo: sudo ./scripts/install.sh"
  exit 1
fi

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_ROOT=/opt/greylock-radio
STATE_ROOT=/var/lib/greylock-radio
MEDIA_ROOT=/srv/greylock-radio/media
CONFIG_ROOT=/etc/greylock-radio
SERVICE_USER=greylock-radio

echo "Installing system packages..."
apt-get -o Acquire::Retries=5 update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  python3 mpv alsa-utils avahi-daemon ca-certificates

if ! id "${SERVICE_USER}" >/dev/null 2>&1; then
  useradd --system --create-home --home-dir "${STATE_ROOT}" \
    --shell /usr/sbin/nologin "${SERVICE_USER}"
fi
usermod -a -G audio "${SERVICE_USER}"

install -d -m 0755 "${APP_ROOT}/app" "${APP_ROOT}/scripts"
install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 0750 "${STATE_ROOT}"
install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 2775 "${MEDIA_ROOT}"
install -d -o "${SERVICE_USER}" -g "${SERVICE_USER}" -m 2775 \
  "${MEDIA_ROOT}/music" "${MEDIA_ROOT}/announcements"
install -d -o root -g "${SERVICE_USER}" -m 0770 "${CONFIG_ROOT}"

if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  usermod -a -G "${SERVICE_USER}" "${SUDO_USER}"
fi

cp -a "${SOURCE_DIR}/app/." "${APP_ROOT}/app/"
cp -a "${SOURCE_DIR}/scripts/." "${APP_ROOT}/scripts/"
chmod 0755 "${APP_ROOT}/scripts/"*.sh

if [[ ! -f "${CONFIG_ROOT}/config.json" ]]; then
  install -o root -g "${SERVICE_USER}" -m 0660 \
    "${SOURCE_DIR}/config/config.example.json" "${CONFIG_ROOT}/config.json"
fi

install -m 0644 "${SOURCE_DIR}/systemd/greylock-radio.service" \
  /etc/systemd/system/greylock-radio.service

chown -R root:root "${APP_ROOT}"
systemctl daemon-reload
systemctl enable --now greylock-radio.service

IP_ADDRESS="$(hostname -I 2>/dev/null | awk '{print $1}')"
LOCAL_NAME="$(hostname).local"
echo
echo "Greylock Radio is installed and running."
echo "Open: http://${LOCAL_NAME}:8080"
if [[ -n "${IP_ADDRESS}" ]]; then
  echo "Or:   http://${IP_ADDRESS}:8080"
fi
echo "Music:        ${MEDIA_ROOT}/music"
echo "Announcements:${MEDIA_ROOT}/announcements"
echo "Configuration:${CONFIG_ROOT}/config.json"
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  echo "Log out and back in once before copying audio into the media folders."
fi
