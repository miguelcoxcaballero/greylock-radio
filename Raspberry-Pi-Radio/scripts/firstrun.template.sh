#!/bin/bash
set -euo pipefail

BOOT_ROOT=/boot/firmware
if [[ ! -d "${BOOT_ROOT}" ]]; then
  BOOT_ROOT=/boot
fi
LOG_FILE="${BOOT_ROOT}/greylock-firstboot.log"
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "=== Greylock Radio first boot: $(date -Is) ==="

HOSTNAME_VALUE=greylock-radio
ADMIN_USER=radio
PASSWORD_HASH="$(printf '%s' '__PASSWORD_HASH_B64__' | base64 -d)"
WIFI_SSID="$(printf '%s' '__WIFI_SSID_B64__' | base64 -d)"
WIFI_PASSWORD="$(printf '%s' '__WIFI_PASSWORD_B64__' | base64 -d)"
SSH_PUBLIC_KEY="$(printf '%s' '__SSH_PUBLIC_KEY_B64__' | base64 -d)"

if [[ -x /usr/lib/raspberrypi-sys-mods/imager_custom ]]; then
  /usr/lib/raspberrypi-sys-mods/imager_custom set_hostname "${HOSTNAME_VALUE}"
else
  CURRENT_HOSTNAME="$(tr -d ' \t\n\r' </etc/hostname)"
  echo "${HOSTNAME_VALUE}" >/etc/hostname
  sed -i "s/127.0.1.1.*${CURRENT_HOSTNAME}/127.0.1.1\t${HOSTNAME_VALUE}/" /etc/hosts
fi

if id "${ADMIN_USER}" >/dev/null 2>&1; then
  echo "${ADMIN_USER}:${PASSWORD_HASH}" | chpasswd -e
elif [[ -x /usr/lib/userconf-pi/userconf ]]; then
  /usr/lib/userconf-pi/userconf "${ADMIN_USER}" "${PASSWORD_HASH}"
else
  useradd -m -s /bin/bash -G adm,audio,cdrom,dialout,gpio,i2c,input,netdev,plugdev,render,spi,sudo,video "${ADMIN_USER}"
  echo "${ADMIN_USER}:${PASSWORD_HASH}" | chpasswd -e
fi
usermod -a -G adm,audio,cdrom,dialout,gpio,i2c,input,netdev,plugdev,render,spi,sudo,video "${ADMIN_USER}"
echo "${ADMIN_USER} ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/010_greylock-radio
chmod 0440 /etc/sudoers.d/010_greylock-radio

ADMIN_HOME="$(getent passwd "${ADMIN_USER}" | cut -d: -f6)"
if [[ -z "${ADMIN_HOME}" ]]; then
  echo "Could not determine the home directory for ${ADMIN_USER}."
  exit 1
fi
install -d -o "${ADMIN_USER}" -g "${ADMIN_USER}" -m 0700 "${ADMIN_HOME}/.ssh"
printf '%s\n' "${SSH_PUBLIC_KEY}" >"${ADMIN_HOME}/.ssh/authorized_keys"
chown "${ADMIN_USER}:${ADMIN_USER}" "${ADMIN_HOME}/.ssh/authorized_keys"
chmod 0600 "${ADMIN_HOME}/.ssh/authorized_keys"

if [[ -x /usr/lib/raspberrypi-sys-mods/imager_custom ]]; then
  /usr/lib/raspberrypi-sys-mods/imager_custom enable_ssh -p
  /usr/lib/raspberrypi-sys-mods/imager_custom set_timezone America/New_York
  /usr/lib/raspberrypi-sys-mods/imager_custom set_keymap us
  if [[ -n "${WIFI_SSID}" ]]; then
    /usr/lib/raspberrypi-sys-mods/imager_custom set_wlan -p "${WIFI_SSID}" "${WIFI_PASSWORD}" US
  fi
else
  systemctl enable ssh
fi
systemctl enable --now ssh

export DEBIAN_FRONTEND=noninteractive
apt-get -o Acquire::Retries=10 update

BUNDLE="${BOOT_ROOT}/greylock-radio"
if [[ ! -d "${BUNDLE}" ]]; then
  echo "Missing installation bundle: ${BUNDLE}"
  exit 1
fi

SUDO_USER="${ADMIN_USER}" bash "${BUNDLE}/scripts/install.sh"
SUDO_USER="${ADMIN_USER}" bash "${BUNDLE}/scripts/install-kiosk.sh"

install -d -m 0755 /etc/X11/xorg.conf.d
cat >/etc/X11/xorg.conf.d/99-greylock-tft.conf <<'EOF'
Section "Device"
  Identifier "Greylock TFT"
  Driver "fbdev"
  Option "fbdev" "/dev/fb1"
EndSection

Section "InputClass"
  Identifier "Greylock TFT touch calibration"
  MatchProduct "ADS7846 Touchscreen"
  Option "Calibration" "3936 227 268 3880"
  Option "SwapAxes" "1"
EndSection
EOF

cat >/etc/X11/Xwrapper.config <<'EOF'
allowed_users=anybody
needs_root_rights=yes
EOF

systemctl enable greylock-radio.service greylock-radio-kiosk.service
systemctl set-default graphical.target

rm -rf "${BUNDLE}"
rm -f "${BOOT_ROOT}/firstrun.sh"
sed -i 's| systemd.run=.*$||' "${BOOT_ROOT}/cmdline.txt"
sync
echo "=== Greylock Radio installation complete ==="
exit 0
