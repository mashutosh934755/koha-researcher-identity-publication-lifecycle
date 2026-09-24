#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${1:-${KOHA_INSTANCE:-INSTANCE}}"

echo "=================================================="
echo " BU RESEARCHER INTELLIGENCE HEALTH CHECK"
echo "=================================================="
echo "Date: $(date)"
echo

echo "===== FILES ====="

for FILE in \
/usr/share/koha/opac/cgi-bin/opac/opac-researcher-search.pl \
/usr/share/koha/opac/cgi-bin/opac/opac-researcher-profile.pl \
/usr/share/koha/opac/cgi-bin/opac/opac-custom-profile.pl \
/usr/share/koha/intranet/cgi-bin/tools/researcher-verification.pl \
/usr/share/koha/intranet/cgi-bin/tools/researcher-publication-intelligence.pl \
/usr/share/koha/bin/bu-researcher-publication-sync.pl \
/usr/share/koha/bin/bu-researcher-disambiguation-score.pl \
/usr/share/koha/bin/bu-researcher-exit-watch.pl
do
    if [[ -f "$FILE" ]]; then
        echo "OK: $FILE"
    else
        echo "MISSING: $FILE"
    fi
done

echo
echo "===== DATABASE SUMMARY ====="

sudo koha-mysql "$INSTANCE" -e "
SELECT
    COUNT(*) AS total_profiles,
    SUM(verification_status='verified')
        AS verified_profiles,
    SUM(employment_status='active')
        AS active_profiles,
    SUM(employment_status='former')
        AS former_profiles
FROM custom_profile_details;

SELECT
    COUNT(*) AS unique_publications
FROM researcher_publications_master;

SELECT
    source_name,
    COUNT(*) AS source_records
FROM researcher_publication_sources
GROUP BY source_name;

SELECT
    system_decision,
    review_status,
    COUNT(*) AS total
FROM researcher_publication_links
GROUP BY system_decision, review_status;

SELECT
    job_status,
    COUNT(*) AS jobs
FROM researcher_sync_jobs
GROUP BY job_status;
"

echo
echo "===== CRON ====="

sudo cat \
/etc/cron.d/bu-researcher-publication-sync \
/etc/cron.d/bu-researcher-disambiguation \
/etc/cron.d/bu-researcher-exit-watch \
2>/dev/null || true

echo
echo "===== SERVICE ====="

sudo systemctl is-active apache2

echo
echo "===== PROFILE HTTP ====="

curl -sS \
    --max-time 30 \
    -o /dev/null \
    -w 'Public profile HTTP: %{http_code}\n' \
    "http://127.0.0.1:8081/cgi-bin/koha/opac-researcher-profile.pl?id=52"

echo
echo "===== EXTERNAL STATUS ====="

echo "Scopus: locally synchronised"
echo "WoS: awaiting API quota availability"
echo "ORCID OAuth: awaiting ORCID client credentials"
echo "HR/No-dues: manual dashboard action + automated candidate detection"

echo
echo "=================================================="
echo " HEALTH CHECK COMPLETE"
echo "=================================================="
