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
SSH_PUBLIC_KEY="$(printf '%s' '__SSH_PUBLIC_KEY_B64__' | base64 -d)"
WIFI_SSID="$(printf '%s' '__WIFI_SSID_B64__' | base64 -d)"
WIFI_PASSWORD="$(printf '%s' '__WIFI_PASSWORD_B64__' | base64 -d)"

cat >/usr/local/sbin/greylock-direct-network <<'EOF'
#!/bin/sh
set -eu
ip link set eth0 up
ip address replace 192.168.137.2/24 dev eth0
EOF
chmod 0755 /usr/local/sbin/greylock-direct-network

cat >/etc/systemd/system/greylock-direct-network.service <<'EOF'
[Unit]
Description=Greylock Radio direct Ethernet address
After=NetworkManager.service systemd-networkd.service
Before=ssh.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/greylock-direct-network
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

install -d -m 0755 /etc/NetworkManager/dispatcher.d
cat >/etc/NetworkManager/dispatcher.d/90-greylock-direct <<'EOF'
#!/bin/sh
if [ "${1:-}" = "eth0" ] && { [ "${2:-}" = "up" ] || [ "${2:-}" = "dhcp4-change" ]; }; then
  /usr/local/sbin/greylock-direct-network
fi
EOF
chmod 0755 /etc/NetworkManager/dispatcher.d/90-greylock-direct

/usr/local/sbin/greylock-direct-network
systemctl daemon-reload
systemctl enable --now greylock-direct-network.service
if command -v rfkill >/dev/null 2>&1; then
  rfkill unblock wifi || true
fi

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
  /usr/lib/raspberrypi-sys-mods/imager_custom set_wlan -p "${WIFI_SSID}" "${WIFI_PASSWORD}" US
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

sed -i '/# BEGIN GREYLOCK HEADLESS/,/# END GREYLOCK HEADLESS/d' "${BOOT_ROOT}/config.txt"
sed -i '/# BEGIN GREYLOCK TFT/,/# END GREYLOCK TFT/d' "${BOOT_ROOT}/config.txt"
cat >>"${BOOT_ROOT}/config.txt" <<'EOF'

# BEGIN GREYLOCK TFT
[all]
dtparam=spi=on
dtparam=i2c_arm=on
enable_uart=1
dtoverlay=tft35a:rotate=90
hdmi_force_hotplug=1
hdmi_group=2
hdmi_mode=1
hdmi_mode=87
hdmi_cvt=480 320 60 6 0 0 0
hdmi_drive=2
gpu_mem=64
disable_splash=1
# END GREYLOCK TFT
EOF

rm -rf "${BUNDLE}"
rm -f "${BOOT_ROOT}/firstrun.sh"
sed -i 's| systemd.run=.*$||' "${BOOT_ROOT}/cmdline.txt"
sync
echo "=== Greylock Radio installation complete ==="
exit 0
