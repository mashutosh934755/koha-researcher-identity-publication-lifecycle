#!/usr/bin/env bash
set -euo pipefail
INSTANCE="${1:-}"
[[ -n "$INSTANCE" ]] || { echo "Usage: ./install/verify.sh <koha-instance>" >&2; exit 2; }
KOHA_CONF="/etc/koha/sites/$INSTANCE/koha-conf.xml"
[[ -f "$KOHA_CONF" ]] || { echo "Missing $KOHA_CONF" >&2; exit 1; }

FILES=(
/usr/share/koha/intranet/cgi-bin/tools/researcher-verification.pl
/usr/share/koha/intranet/cgi-bin/tools/researcher-publication-intelligence.pl
/usr/share/koha/opac/cgi-bin/opac/opac-researcher-profile.pl
/usr/share/koha/opac/cgi-bin/opac/opac-researcher-search.pl
/usr/share/koha/opac/cgi-bin/opac/opac-researcher-photo.pl
/usr/share/koha/opac/cgi-bin/opac/opac-researcher-ai-query.pl
/usr/share/koha/bin/bu-researcher-publication-sync.pl
/usr/share/koha/bin/bu-rims-wos-auto-sync.pl
/usr/share/koha/bin/bu-researcher-disambiguation-score.pl
/usr/share/koha/bin/bu-researcher-expiry-lifecycle.pl
)
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { echo "MISSING $f"; exit 1; }
  [[ "$f" == *.pl ]] && koha-shell "$INSTANCE" -c "perl -c '$f'" >/dev/null
  echo "OK $f"
done

koha-mysql "$INSTANCE" -NBe "SHOW TABLES LIKE 'researcher_identifiers'; SHOW TABLES LIKE 'researcher_publications_master'; SHOW TABLES LIKE 'researcher_publication_links';" | sed 's/^/DB OK /'
grep -RniE '(sk-[A-Za-z0-9_-]{20,}|AIza[0-9A-Za-z_-]{20,}|bearer[[:space:]]+[A-Za-z0-9._-]{20,})'   /usr/share/koha/bin/bu-*research* /usr/share/koha/opac/cgi-bin/opac/opac-researcher-* 2>/dev/null && {
    echo "Potential hard-coded secret found" >&2; exit 1;
  } || true

echo "Verification completed. API/network functionality still requires configured credentials and live-source testing."
