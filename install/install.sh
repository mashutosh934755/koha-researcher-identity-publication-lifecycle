#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${1:-}"
if [[ -z "$INSTANCE" ]]; then
  echo "Usage: sudo ./install/install.sh <koha-instance>" >&2
  exit 2
fi
if [[ $EUID -ne 0 ]]; then
  echo "Run as root." >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="/root/koha-rims-backup-$STAMP"
KOHA_CONF="/etc/koha/sites/$INSTANCE/koha-conf.xml"
[[ -f "$KOHA_CONF" ]] || { echo "Missing $KOHA_CONF" >&2; exit 1; }

INTRA_CGI="/usr/share/koha/intranet/cgi-bin/tools"
INTRA_TT="/usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/modules/tools"
OPAC_CGI="/usr/share/koha/opac/cgi-bin/opac"
OPAC_TT="/usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/en/modules"
BIN="/usr/share/koha/bin"
CRON="/etc/cron.d"

mkdir -p "$BACKUP"
backup_if_exists(){ local f="$1"; [[ -e "$f" ]] && { mkdir -p "$BACKUP$(dirname "$f")"; cp -a "$f" "$BACKUP$f"; }; }
install_file(){ local src="$1" dst="$2" mode="$3"; backup_if_exists "$dst"; install -D -m "$mode" "$src" "$dst"; }
render(){ sed -e "s/INSTANCE/$INSTANCE/g" \
  -e "s/Example University/${RIMS_INSTITUTION_NAME:-Example University}/g" \
  -e "s#SCOPUS_AFFILIATION_ID=#SCOPUS_AFFILIATION_ID=${SCOPUS_AFFILIATION_ID:-}#g" \
  -e "s#RIMS_PUBLIC_PROFILE_BASE_URL=#RIMS_PUBLIC_PROFILE_BASE_URL=${RIMS_PUBLIC_PROFILE_BASE_URL:-}#g" \
  -e "s/library@example.edu/${CROSSREF_MAILTO:-library@example.edu}/g" "$1"; }
install_rendered(){ local src="$1" dst="$2" mode="$3" tmp; tmp="$(mktemp)"; render "$src" > "$tmp"; install_file "$tmp" "$dst" "$mode"; rm -f "$tmp"; }

echo "Backup: $BACKUP"

# Database schema (structure only; no production data)
koha-mysql "$INSTANCE" < "$ROOT/database/schema/researcher-system-schema.sql"

# Staff UI
install_rendered "$ROOT/src/intranet/cgi-bin/researcher-verification.pl" "$INTRA_CGI/researcher-verification.pl" 0755
install_rendered "$ROOT/src/intranet/cgi-bin/researcher-publication-intelligence.pl" "$INTRA_CGI/researcher-publication-intelligence.pl" 0755
install_rendered "$ROOT/src/intranet/templates/researcher-verification.tt" "$INTRA_TT/researcher-verification.tt" 0644
install_rendered "$ROOT/src/intranet/templates/researcher-publication-intelligence.tt" "$INTRA_TT/researcher-publication-intelligence.tt" 0644

# OPAC
for f in opac-researcher-profile.pl opac-researcher-search.pl opac-researcher-photo.pl opac-researcher-ai-query.pl; do
  install_rendered "$ROOT/src/opac/cgi-bin/$f" "$OPAC_CGI/$f" 0755
done
for f in opac-researcher-profile.tt opac-researcher-search.tt; do
  install_rendered "$ROOT/src/opac/templates/$f" "$OPAC_TT/$f" 0644
done

# Workers
for f in "$ROOT"/scripts/maintenance/*; do
  [[ -f "$f" ]] || continue
  install_rendered "$f" "$BIN/$(basename "$f")" 0755
done
install_rendered "$ROOT/scripts/onboarding/researcher_onboarding.pl" "$BIN/cronjobs/researcher_onboarding.pl" 0755

# Runtime config examples only; never overwrite real credentials.
if [[ ! -f "/etc/koha/sites/$INSTANCE/research-api.env" ]]; then
  install -m 0600 "$ROOT/config/research-api.env.example" "/etc/koha/sites/$INSTANCE/research-api.env.example"
fi
if [[ ! -f "/etc/koha/sites/$INSTANCE/gemini-expert-discovery.conf" ]]; then
  install -m 0600 "$ROOT/config/gemini-expert-discovery.conf.example" "/etc/koha/sites/$INSTANCE/gemini-expert-discovery.conf.example"
fi

# Cron templates rendered for this instance.
for f in "$ROOT"/scripts/cron/*.example; do
  name="$(basename "$f" .example)"
  tmp="$(mktemp)"; render "$f" > "$tmp"; install_file "$tmp" "$CRON/$name" 0644; rm -f "$tmp"
done

systemctl reload cron 2>/dev/null || systemctl reload crond 2>/dev/null || true

echo "Installed. Backup retained at $BACKUP"
echo "Now configure /etc/koha/sites/$INSTANCE/research-api.env, optional AI config, then run install/verify.sh $INSTANCE"
