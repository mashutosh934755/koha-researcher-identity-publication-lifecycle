#!/usr/bin/env bash
set -Eeuo pipefail

# Read-only exporter for a Koha researcher-identity implementation.
# Run this on the Koha server as root/sudo. It copies source files and
# database STRUCTURE only. It does not export patron data, API responses,
# passwords, logs, photographs, or production records.

INSTANCE="${1:-}"
if [[ -z "$INSTANCE" ]]; then
  echo "Usage: sudo $0 <koha-instance>"
  exit 1
fi

STAMP="$(date +%Y%m%d_%H%M%S)"
ROOT="/home/${SUDO_USER:-root}/koha-researcher-github-export-$STAMP"
ARCHIVE="${ROOT}.tar.gz"
KOHA_CONF="/etc/koha/sites/$INSTANCE/koha-conf.xml"

[[ -f "$KOHA_CONF" ]] || { echo "Missing $KOHA_CONF"; exit 1; }

mkdir -p \
  "$ROOT/src/opac/cgi-bin" \
  "$ROOT/src/opac/templates" \
  "$ROOT/src/intranet/cgi-bin" \
  "$ROOT/src/intranet/templates" \
  "$ROOT/scripts/maintenance" \
  "$ROOT/scripts/cron" \
  "$ROOT/database/schema" \
  "$ROOT/evidence"

copy_file() {
  local src="$1" dst="$2"
  if [[ -f "$src" ]]; then
    install -m 0644 "$src" "$dst"
    echo "COPIED $src"
  else
    echo "MISSING $src" | tee -a "$ROOT/evidence/missing-files.txt"
  fi
}

copy_file /usr/share/koha/opac/cgi-bin/opac/opac-researcher-search.pl \
  "$ROOT/src/opac/cgi-bin/opac-researcher-search.pl"
copy_file /usr/share/koha/opac/cgi-bin/opac/opac-researcher-profile.pl \
  "$ROOT/src/opac/cgi-bin/opac-researcher-profile.pl"
copy_file /usr/share/koha/opac/cgi-bin/opac/opac-researcher-photo.pl \
  "$ROOT/src/opac/cgi-bin/opac-researcher-photo.pl"
copy_file /usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/en/modules/opac-researcher-search.tt \
  "$ROOT/src/opac/templates/opac-researcher-search.tt"
copy_file /usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/en/modules/opac-researcher-profile.tt \
  "$ROOT/src/opac/templates/opac-researcher-profile.tt"
copy_file /usr/share/koha/intranet/cgi-bin/tools/researcher-verification.pl \
  "$ROOT/src/intranet/cgi-bin/researcher-verification.pl"
copy_file /usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/modules/tools/researcher-verification.tt \
  "$ROOT/src/intranet/templates/researcher-verification.tt"

for src in \
  /usr/share/koha/bin/cronjobs/researcher_onboarding.pl \
  /usr/share/koha/bin/bu-researcher-publication-sync.pl \
  /usr/share/koha/bin/bu-researcher-disambiguation-score.pl \
  /usr/share/koha/bin/bu-researcher-expiry-lifecycle.pl \
  /usr/share/koha/bin/bu-wos-publication-sync.py \
  /usr/share/koha/bin/bu-run-wos-publication-sync.sh
 do
  [[ -f "$src" ]] && install -m 0644 "$src" "$ROOT/scripts/maintenance/$(basename "$src")"
 done

for src in /etc/cron.d/*researcher* /etc/cron.d/*publication* /etc/cron.d/*wos*; do
  [[ -f "$src" ]] && install -m 0644 "$src" "$ROOT/scripts/cron/$(basename "$src")"
done

# Obtain DB name without printing credentials.
DB_NAME="$(sudo koha-mysql "$INSTANCE" -N -e 'SELECT DATABASE();')"
TABLES="$(sudo koha-mysql "$INSTANCE" -N -e "
SELECT table_name
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND (table_name = 'custom_profile_details' OR table_name LIKE 'researcher_%')
ORDER BY table_name;")"

if [[ -n "$TABLES" ]]; then
  # koha-mysql does not expose the password. Export each CREATE TABLE using SQL.
  {
    echo "SET NAMES utf8mb4;"
    echo "SET FOREIGN_KEY_CHECKS=0;"
    while IFS= read -r table; do
      [[ -n "$table" ]] || continue
      sudo koha-mysql "$INSTANCE" -N -e "SHOW CREATE TABLE \`$table\`;" |
        cut -f2- | sed 's/$/;/'
    done <<< "$TABLES"
    echo "SET FOREIGN_KEY_CHECKS=1;"
  } > "$ROOT/database/schema/researcher-system-schema.sql"
fi

# Remove deployment-specific names and paths while retaining logic.
find "$ROOT" -type f \( -name '*.pl' -o -name '*.py' -o -name '*.sh' -o -name '*.tt' -o -name '*.sql' \) -print0 |
while IFS= read -r -d '' file; do
  sed -i \
    -e "s/$INSTANCE/INSTANCE/g" \
    -e 's#10\.[0-9]\+\.[0-9]\+\.[0-9]\+#SERVER_IP#g' \
    -e 's#/var/log/koha/INSTANCE#/var/log/koha/INSTANCE#g' \
    "$file"
done

# Fail if likely secrets or personal data remain.
PATTERN='(api[_-]?key|client_secret|access_token|smtp_password|password)[[:space:]]*[:=][[:space:]]*[^[:space:]"'"']+|BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|@[A-Za-z0-9.-]+\.(com|org|in)'
if grep -RInE --exclude='export-report.txt' "$PATTERN" "$ROOT" > "$ROOT/evidence/secret-scan.txt"; then
  echo "Potential secret/personal-data matches found. Review: $ROOT/evidence/secret-scan.txt"
  exit 2
fi

find "$ROOT" -type f -exec sha256sum {} + > "$ROOT/evidence/SHA256SUMS"
find "$ROOT" -type f -printf '%P\n' | sort > "$ROOT/evidence/file-list.txt"

tar -czf "$ARCHIVE" -C "$(dirname "$ROOT")" "$(basename "$ROOT")"
chown -R "${SUDO_USER:-root}:${SUDO_USER:-root}" "$ROOT" "$ARCHIVE" 2>/dev/null || true
chmod 640 "$ARCHIVE"

echo "EXPORT_OK"
echo "Directory: $ROOT"
echo "Archive:   $ARCHIVE"
