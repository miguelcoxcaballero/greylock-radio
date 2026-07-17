#!/usr/bin/env bash
set -euo pipefail

xset -dpms
xset s off
xset s noblank
openbox-session &

BROWSER="$(command -v chromium || command -v chromium-browser || true)"
if [[ -z "${BROWSER}" ]]; then
  echo "Chromium is not installed."
  exit 1
fi

exec "${BROWSER}" \
  --kiosk \
  --noerrdialogs \
  --disable-infobars \
  --disable-gpu \
  --disable-dev-shm-usage \
  --disable-session-crashed-bubble \
  --renderer-process-limit=2 \
  --check-for-update-interval=31536000 \
  --user-data-dir=/var/lib/greylock-radio/chromium \
  http://127.0.0.1:8080
