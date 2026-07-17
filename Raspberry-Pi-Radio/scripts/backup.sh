#!/usr/bin/env bash
set -euo pipefail

DESTINATION="${1:-$HOME}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="${DESTINATION%/}/greylock-radio-backup-${STAMP}.tar.gz"

tar -czf "${ARCHIVE}" \
  /etc/greylock-radio/config.json \
  /srv/greylock-radio/media

echo "Backup created: ${ARCHIVE}"
