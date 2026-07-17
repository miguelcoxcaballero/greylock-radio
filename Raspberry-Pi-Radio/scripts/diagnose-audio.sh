#!/usr/bin/env bash
set -euo pipefail

echo "=== Playback devices (ALSA) ==="
aplay -l || true
echo
echo "=== Capture devices (ALSA) ==="
arecord -l || true
echo
echo "=== mpv audio outputs ==="
mpv --no-config --audio-device=help 2>&1 || true
echo
echo "Current radio configuration:"
if [[ -r /etc/greylock-radio/config.json ]]; then
  cat /etc/greylock-radio/config.json
else
  echo "/etc/greylock-radio/config.json is not readable."
fi

if [[ "${1:-}" == "--test-live" ]]; then
  echo
  echo "Testing the configured default microphone and output. Press Ctrl+C to stop."
  arecord -q -D default -f S16_LE -r 48000 -c 1 -t raw | \
    aplay -q -D default -f S16_LE -r 48000 -c 1 -t raw
fi
