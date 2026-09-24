#!/usr/bin/env bash
set -Eeuo pipefail

echo "[BU-WOS-PUBLICATION-SYNC] Started: $(date '+%F %T')"

cd /tmp

exec /usr/bin/python3 \
    /usr/share/koha/bin/bu-wos-publication-sync.py
