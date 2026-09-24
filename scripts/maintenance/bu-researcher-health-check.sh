#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${1:-${KOHA_INSTANCE:-INSTANCE}}"
KOHA_CONF="/etc/koha/sites/$INSTANCE/koha-conf.xml"
[[ -f "$KOHA_CONF" ]] || { echo "Missing $KOHA_CONF" >&2; exit 1; }

export KOHA_CONF
export PERL5LIB=/usr/share/koha/lib

echo "== Koha RIMS health check =="
echo "Instance: $INSTANCE"

for f in  /usr/share/koha/bin/bu-researcher-publication-sync.pl  /usr/share/koha/bin/bu-rims-wos-auto-sync.pl  /usr/share/koha/bin/bu-crossref-publication-sync.pl  /usr/share/koha/bin/bu-official-api-author-names-sync.pl  /usr/share/koha/bin/bu-researcher-disambiguation-score.pl  /usr/share/koha/bin/bu-researcher-expiry-lifecycle.pl
do
  if [[ -f "$f" ]]; then
    koha-shell "$INSTANCE" -c "perl -c '$f'" >/dev/null
    echo "OK $f"
  else
    echo "MISSING $f"
  fi
done

koha-mysql "$INSTANCE" -NBe "
SELECT CONCAT('verified_public_profiles=',COUNT(*))
FROM custom_profile_details
WHERE verification_status='verified'
  AND public_visibility=1;

SELECT CONCAT('confirmed_publication_links=',COUNT(*))
FROM researcher_publication_links
WHERE system_decision='confirmed'
  AND review_status IN ('confirmed','auto_confirmed','manually_confirmed');

SELECT CONCAT('unique_confirmed_publications=',COUNT(DISTINCT publication_id))
FROM researcher_publication_links
WHERE system_decision='confirmed'
  AND review_status IN ('confirmed','auto_confirmed','manually_confirmed');
"

echo "Health check complete."
