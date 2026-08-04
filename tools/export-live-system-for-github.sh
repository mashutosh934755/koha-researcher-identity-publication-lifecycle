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
EXPORT_USER="${SUDO_USER:-root}"
ROOT="/home/${EXPORT_USER}/koha-researcher-github-export-$STAMP"
ARCHIVE="${ROOT}.tar.gz"
KOHA_CONF="/etc/koha/sites/$INSTANCE/koha-conf.xml"

[[ -f "$KOHA_CONF" ]] || {
  echo "Missing $KOHA_CONF"
  exit 1
}

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
  local src="$1"
  local dst="$2"

  if [[ -f "$src" ]]; then
    install -m 0644 "$src" "$dst"
    echo "COPIED $src"
  else
    echo "MISSING $src" | tee -a "$ROOT/evidence/missing-files.txt"
  fi
}

copy_file "/usr/share/koha/opac/cgi-bin/opac/opac-researcher-search.pl" \
  "$ROOT/src/opac/cgi-bin/opac-researcher-search.pl"
copy_file "/usr/share/koha/opac/cgi-bin/opac/opac-researcher-profile.pl" \
  "$ROOT/src/opac/cgi-bin/opac-researcher-profile.pl"
copy_file "/usr/share/koha/opac/cgi-bin/opac/opac-researcher-photo.pl" \
  "$ROOT/src/opac/cgi-bin/opac-researcher-photo.pl"
copy_file "/usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/en/modules/opac-researcher-search.tt" \
  "$ROOT/src/opac/templates/opac-researcher-search.tt"
copy_file "/usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/en/modules/opac-researcher-profile.tt" \
  "$ROOT/src/opac/templates/opac-researcher-profile.tt"
copy_file "/usr/share/koha/intranet/cgi-bin/tools/researcher-verification.pl" \
  "$ROOT/src/intranet/cgi-bin/researcher-verification.pl"
copy_file "/usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/modules/tools/researcher-verification.tt" \
  "$ROOT/src/intranet/templates/researcher-verification.tt"

for src in \
  "/usr/share/koha/bin/cronjobs/researcher_onboarding.pl" \
  "/usr/share/koha/bin/bu-researcher-publication-sync.pl" \
  "/usr/share/koha/bin/bu-researcher-disambiguation-score.pl" \
  "/usr/share/koha/bin/bu-researcher-expiry-lifecycle.pl" \
  "/usr/share/koha/bin/bu-wos-publication-sync.py" \
  "/usr/share/koha/bin/bu-run-wos-publication-sync.sh"
do
  if [[ -f "$src" ]]; then
    install -m 0644 "$src" "$ROOT/scripts/maintenance/$(basename "$src")"
    echo "COPIED $src"
  fi
done

shopt -s nullglob
for src in /etc/cron.d/*researcher* /etc/cron.d/*publication* /etc/cron.d/*wos*; do
  install -m 0644 "$src" "$ROOT/scripts/cron/$(basename "$src")"
  echo "COPIED $src"
done
shopt -u nullglob

TABLES="$(
  sudo koha-mysql "$INSTANCE" -N -e "
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND (
        table_name = 'custom_profile_details'
        OR table_name LIKE 'researcher_%'
      )
    ORDER BY table_name;
  "
)"

if [[ -n "$TABLES" ]]; then
  {
    echo "SET NAMES utf8mb4;"
    echo "SET FOREIGN_KEY_CHECKS=0;"

    while IFS= read -r table; do
      [[ -n "$table" ]] || continue

      sudo koha-mysql "$INSTANCE" -N -e \
        "SHOW CREATE TABLE \`$table\`;" |
        cut -f2- |
        sed 's/$/;/'
    done <<< "$TABLES"

    echo "SET FOREIGN_KEY_CHECKS=1;"
  } > "$ROOT/database/schema/researcher-system-schema.sql"
fi

# Replace deployment-specific instance and private IPv4 values.
find "$ROOT" -type f \
  \( -name '*.pl' -o -name '*.py' -o -name '*.sh' -o -name '*.tt' -o -name '*.sql' \) \
  -print0 |
while IFS= read -r -d '' file; do
  sed -i \
    -e "s/${INSTANCE}/INSTANCE/g" \
    -e 's#10\.[0-9]\+\.[0-9]\+\.[0-9]\+#SERVER_IP#g' \
    "$file"
done

# High-confidence secret scan. Variable names such as api_key and safe
# environment lookups are intentionally allowed; only credential-like values
# and private-key material cause the exporter to stop.
SECRET_REPORT="$ROOT/evidence/secret-scan.txt"
: > "$SECRET_REPORT"

scan_pattern() {
  local pattern="$1"

  grep -RInE \
    --exclude='secret-scan.txt' \
    --exclude='SHA256SUMS' \
    "$pattern" \
    "$ROOT" >> "$SECRET_REPORT" 2>/dev/null || true
}

scan_pattern 'BEGIN (RSA|OPENSSH|EC|DSA) PRIVATE KEY'
scan_pattern 'Authorization:[[:space:]]*(Bearer|Basic)[[:space:]]+[A-Za-z0-9._~+/-]{16,}'
scan_pattern 'sk-[A-Za-z0-9_-]{20,}'
scan_pattern 'sk-proj-[A-Za-z0-9_-]{20,}'
scan_pattern 'AIza[0-9A-Za-z_-]{30,}'
scan_pattern 'gh[pousr]_[A-Za-z0-9]{30,}'
scan_pattern 'github_pat_[A-Za-z0-9_]{20,}'
scan_pattern 'AKIA[0-9A-Z]{16}'
scan_pattern '-----BEGIN [A-Z ]*PRIVATE KEY-----'

if [[ -s "$SECRET_REPORT" ]]; then
  echo "High-confidence secret matches found. Review: $SECRET_REPORT"
  exit 2
fi

# Record potentially sensitive literals for manual review without failing.
REVIEW_REPORT="$ROOT/evidence/manual-review.txt"
: > "$REVIEW_REPORT"
grep -RInE \
  --exclude='manual-review.txt' \
  --exclude='secret-scan.txt' \
  --exclude='SHA256SUMS' \
  '(api[_-]?key|client_secret|access_token|smtp_password|password|passwd|email|cardnumber|borrowernumber|employee_id)' \
  "$ROOT" >> "$REVIEW_REPORT" 2>/dev/null || true

find "$ROOT" -type f -exec sha256sum {} + \
  > "$ROOT/evidence/SHA256SUMS"

find "$ROOT" -type f -printf '%P\n' | sort \
  > "$ROOT/evidence/file-list.txt"

tar -czf "$ARCHIVE" \
  -C "$(dirname "$ROOT")" \
  "$(basename "$ROOT")"

chown -R "$EXPORT_USER:$EXPORT_USER" "$ROOT" "$ARCHIVE" 2>/dev/null || true
chmod 640 "$ARCHIVE"

echo "EXPORT_OK"
echo "Directory: $ROOT"
echo "Archive:   $ARCHIVE"
echo "Manual review: $REVIEW_REPORT"
