#!/usr/bin/env bash
set -euo pipefail
BACKUP="${1:-}"
[[ -d "$BACKUP" ]] || { echo "Usage: sudo ./install/rollback.sh /root/koha-rims-backup-<stamp>" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "Run as root." >&2; exit 2; }
cd "$BACKUP"
find . -type f -print0 | while IFS= read -r -d '' f; do
  dst="/${f#./}"
  install -D -m "$(stat -c %a "$f")" "$f" "$dst"
done
echo "Files restored from $BACKUP. Database schema changes are intentionally not dropped automatically."
