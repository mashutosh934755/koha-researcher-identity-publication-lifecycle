# Production Hardening and Reproducible Koha Deployment Guide

This guide documents the production-hardening controls validated in September 2026 for the Koha-based Researcher Identity and Publication Lifecycle system. It is intended for institutions that want to reproduce the same architecture on their own Koha deployment without copying private credentials, institution-specific identifiers, licensed raw API data, or private patron information.

## Important scope

The repository is a reference architecture and reproducibility guide. Adapt paths, Koha instance name, language, API entitlements, and institutional policies before deployment.

Never commit API keys, SMTP passwords, Koha database credentials, patron-private data, raw licensed Scopus/Web of Science datasets, internal IP addresses, private DNS names, or production logs containing secrets.

Use a non-production Koha instance first.

## 1. Target architecture

The hardened system separates four kinds of truth:

1. Researcher identity — persistent researcher UUID and authoritative verified identifiers.
2. Researcher-publication ownership — confirmed researcher-to-publication relationships.
3. Source provenance — Scopus, Web of Science and Crossref evidence attached to a deduplicated master publication.
4. Institutional lifecycle — Current, Former, Hidden, Restored and Deleted states without destroying scholarly history.

```text
Koha patron
-> persistent researcher identity
-> verified primary identifiers
-> source synchronization
-> source-specific raw/provenance records
-> master-publication deduplication
-> author disambiguation
-> source visibility rules
-> public profile / directory / expert discovery
```

## 2. Authoritative identifier rule

Do not treat a denormalized public-profile field as the source of truth for scholarly identifiers. Use an identifier registry such as `researcher_identifiers` and require `verification_status=verified`, `is_primary=1`, and `is_active=1` for the identifier used in production synchronization and automatic disambiguation.

When an identifier is changed, do not silently keep old source-bound publication relationships as confirmed. Quarantine old source-bound links for review, invalidate old source-specific identity cache/name variants, preserve master publications and provenance, and write an audit event.

## 3. Source-specific visibility model

Recommended rule:

```text
Overall Publications = distinct master publications with at least one confirmed researcher-publication link
Scopus count/badge    = distinct master publications with a confirmed Scopus researcher-publication link
WoS count/badge       = distinct master publications with a confirmed WoS researcher-publication link
Crossref count/badge  = confirmed master publications that contain Crossref provenance
```

Crossref is normally DOI/bibliographic enrichment and does not need a dedicated researcher-author link in the same way Scopus and WoS do.

Example confirmed Scopus/WoS visibility condition:

```sql
AND EXISTS (
    SELECT 1
    FROM researcher_publication_links rpl_source
    WHERE rpl_source.publication_id = rpm.id
      AND rpl_source.borrowernumber = ?
      AND rpl_source.source_name = rps.source_name
      AND rpl_source.source_name IN ('scopus','wos')
      AND rpl_source.system_decision = 'confirmed'
      AND rpl_source.review_status IN ('confirmed','auto_confirmed')
)
```

For Crossref provenance of an already-confirmed publication, `rps.source_name = 'crossref'` can be allowed without requiring a separate Crossref researcher link.

## 4. Scopus current-set reconciliation

A production sync should not simply add/update records forever. It should reconcile the currently returned Scopus set against existing confirmed Scopus links.

Safe behavior:

1. fetch the complete Scopus result set for the authoritative verified primary Scopus Author ID;
2. process and deduplicate every returned record;
3. reconcile only when the API result is complete;
4. quarantine previously confirmed Scopus links that are absent from the complete current set;
5. do not delete the master publication or source provenance;
6. log the retirement/quarantine decision.

Do not reconcile on a partial or failed API response.

## 5. Author-disambiguation scoring

| Evidence | Maximum |
|---|---:|
| Verified authoritative source identifier | 55 |
| Registered name-variant evidence | 20 |
| Affiliation evidence | 15 |
| Timeline consistency | 10 |
| Total | 100 |

Operational rules: `>=80` auto-confirm only without conflict; `50-79` librarian/manual review; `<50` unresolved/review-required.

Hardening rules: use only verified+primary+active identifier evidence; do not artificially inflate scores to 100; preserve manual decisions; prevent duplicate unresolved-case creation; identifier-free cases must not auto-confirm merely from weak supporting evidence.

## 6. Source-faithful author names

Store source-native author names separately from local normalized names. Recommended cache fields include `borrowernumber`, `source_name`, `source_author_id`, `display_name`, `published_name`, `extraction_method`, and `last_fetched_at`.

For Scopus, retain the official display representation and indexed/published form. For Web of Science, first attempt current authoritative ResearcherID-bound evidence. When that evidence has not propagated to the article record, a controlled fallback may use an already-confirmed WoS publication source record plus an unambiguous local identity/name match. Record the extraction method.

## 7. Recommended production job order

The exact times may be changed for local API quotas and maintenance windows. The validated ordering was:

```text
02:20  Scopus/main publication synchronization
02:35  Web of Science publication synchronization
03:10  Official Scopus/WoS author-name synchronization
03:35  Crossref DOI metadata enrichment
03:40  Disambiguation scoring/review refresh

Hourly:
:17 and :47  WoS incremental/automatic synchronization

Frequent lifecycle job:
patron-expiry/current-former lifecycle reconciliation
```

Use `flock` for jobs that must not overlap.

### Example cron: main publication sync

```cron
20 2 * * * KOHAUSER KOHA_CONF=/etc/koha/sites/INSTANCE/koha-conf.xml PERL5LIB=/usr/share/koha/lib /usr/bin/perl /usr/share/koha/bin/bu-researcher-publication-sync.pl INSTANCE >> /var/log/koha/INSTANCE/researcher-publication-sync.log 2>&1
```

### Example cron: official author-name sync

```cron
10 3 * * * KOHAUSER flock -n /var/lock/koha/INSTANCE/official-api-author-names-sync.lock env KOHA_CONF=/etc/koha/sites/INSTANCE/koha-conf.xml PERL5LIB=/usr/share/koha/lib /usr/bin/perl /usr/share/koha/bin/bu-official-api-author-names-sync.pl --instance=INSTANCE --all >> /var/log/koha/INSTANCE/official-api-author-names-sync.log 2>&1
```

### Example cron: Crossref enrichment

```cron
35 3 * * * KOHAUSER flock -n /var/lock/koha/INSTANCE/crossref-publication-sync.lock env KOHA_CONF=/etc/koha/sites/INSTANCE/koha-conf.xml PERL5LIB=/usr/share/koha/lib /usr/share/koha/bin/bu-crossref-publication-sync.pl --apply >> /var/log/koha/INSTANCE/crossref-publication-sync.log 2>&1
```

### Example cron: disambiguation refresh

```cron
40 3 * * * KOHAUSER KOHA_CONF=/etc/koha/sites/INSTANCE/koha-conf.xml PERL5LIB=/usr/share/koha/lib /usr/bin/perl /usr/share/koha/bin/bu-researcher-disambiguation-score.pl >> /var/log/koha/INSTANCE/researcher-disambiguation.log 2>&1
```

Replace `INSTANCE` and `KOHAUSER` with the local Koha instance and service user.

## 8. Safe install workflow

Always use:

```text
backup -> copy to temporary file -> patch -> syntax check -> install -> production syntax check -> database/UI assertions
```

Koha Perl syntax checks must run inside the Koha environment:

```bash
sudo koha-shell INSTANCE -c "perl -c '/usr/share/koha/opac/cgi-bin/opac/opac-researcher-profile.pl'"
```

Do not rely on plain root `perl -c` for Koha CGI scripts because Koha modules/environment may be unavailable outside `koha-shell`.

## 9. Public-count validation queries

Overall confirmed unique publications:

```sql
SELECT COUNT(DISTINCT publication_id)
FROM researcher_publication_links
WHERE borrowernumber = ?
  AND system_decision = 'confirmed'
  AND review_status IN ('confirmed','auto_confirmed');
```

Confirmed Scopus coverage:

```sql
SELECT COUNT(DISTINCT publication_id)
FROM researcher_publication_links
WHERE borrowernumber = ?
  AND source_name = 'scopus'
  AND system_decision = 'confirmed'
  AND review_status IN ('confirmed','auto_confirmed');
```

Confirmed WoS coverage:

```sql
SELECT COUNT(DISTINCT publication_id)
FROM researcher_publication_links
WHERE borrowernumber = ?
  AND source_name = 'wos'
  AND system_decision = 'confirmed'
  AND review_status IN ('confirmed','auto_confirmed');
```

Crossref provenance over confirmed publications:

```sql
SELECT COUNT(DISTINCT rpl.publication_id)
FROM researcher_publication_links rpl
WHERE rpl.borrowernumber = ?
  AND rpl.system_decision = 'confirmed'
  AND rpl.review_status IN ('confirmed','auto_confirmed')
  AND EXISTS (
      SELECT 1
      FROM researcher_publication_sources rps
      WHERE rps.publication_id = rpl.publication_id
        AND rps.source_name = 'crossref'
  );
```

## 10. Lifecycle behavior

```text
Current + valid patron membership
-> public/sync eligibility subject to policy

membership/affiliation expiry
-> Former
-> synchronization disabled
-> relieving/end date recorded
-> identifiers/publications/provenance preserved

Hide
-> public visibility off
-> synchronization off
-> employment state unchanged

Restore
-> re-evaluate current/former state from authoritative lifecycle evidence

Delete
-> authorized removal of researcher-domain records
-> do not silently delete the Koha patron account
-> audit the operation
```

Rejoining must reuse the same persistent researcher identity after verification and open a new affiliation period.

## 11. Failure modes to test before production

- stale or changed Scopus/WoS identifier;
- API timeout or partial result;
- duplicate DOI across sources;
- same publication present in Scopus and WoS;
- publication disappears from current Scopus set but remains valid in WoS;
- Crossref provenance exists without a dedicated Crossref researcher link;
- public count/badge leakage from stale source rows;
- duplicate disambiguation-case creation;
- manual decision persistence across automated jobs;
- new/changed author display names;
- Current -> Former -> Current lifecycle;
- Hide/Restore behavior;
- cron overlap and lock behavior.

## 12. Post-install verification

```bash
sudo systemctl is-active cron
sudo grep -RniE 'researcher|wos|crossref|author-name|disambiguation' /etc/cron.d
```

Check recent logs and compare database counts with the public UI.

## 13. What this guide deliberately does not publish

This guide does not publish real API keys or credentials, private Koha patron data, institution-specific production IDs, raw licensed Scopus/WoS payloads, internal hostnames or IP addresses, or private audit logs. Those values must remain local to each institution.