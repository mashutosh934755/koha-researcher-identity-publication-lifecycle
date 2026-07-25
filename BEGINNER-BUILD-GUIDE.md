# Beginner Build Guide

> This guide explains the complete build sequence in simple language. It does **not** replace the actual application source code, database schema, templates, workers, or cron files. Confirm the repository-completeness checklist before attempting installation.

## 1. What you are building

This project extends Koha so that a normal patron can also have a verified researcher identity. The system stores ORCID, Scopus Author ID, Web of Science ResearcherID, name variants, affiliations, publications, source records, review decisions, synchronization jobs, and public-profile status.

The main rule is:

```text
Koha patron = operational library account
Researcher UUID = persistent scholarly identity
borrowernumber = link between both systems
```

## 2. Skills and access required

A beginner should have help from a Koha/Linux administrator for the first deployment. You need:

- a non-production Koha test instance;
- sudo or root access;
- access to the Koha database through `koha-mysql`;
- permission to edit Koha CGI and template directories;
- authorised Scopus and Web of Science API access;
- SMTP credentials for system email;
- HTTPS URLs for OPAC and staff interfaces;
- a verified backup and rollback plan.

Do not start on production.

## 3. Confirm that the repository is complete

Before running any install command, confirm that these files exist:

```text
database/schema/researcher-system-schema.sql
config/researcher-system.example.conf
src/intranet/cgi-bin/researcher-verification.pl
src/intranet/templates/researcher-verification.tt
src/opac/cgi-bin/opac-researcher-search.pl
src/opac/cgi-bin/opac-researcher-profile.pl
src/opac/templates/opac-researcher-search.tt
src/opac/templates/opac-researcher-profile.tt
scripts/maintenance/bu-researcher-publication-sync.pl
scripts/maintenance/bu-rims-wos-auto-sync.pl
scripts/maintenance/bu-crossref-publication-sync.pl
scripts/cron/
```

Run from the cloned repository:

```bash
required=(
  database/schema/researcher-system-schema.sql
  config/researcher-system.example.conf
  src/intranet/cgi-bin/researcher-verification.pl
  src/intranet/templates/researcher-verification.tt
  src/opac/cgi-bin/opac-researcher-search.pl
  src/opac/cgi-bin/opac-researcher-profile.pl
  src/opac/templates/opac-researcher-search.tt
  src/opac/templates/opac-researcher-profile.tt
  scripts/maintenance/bu-researcher-publication-sync.pl
  scripts/maintenance/bu-rims-wos-auto-sync.pl
  scripts/maintenance/bu-crossref-publication-sync.pl
)

missing=0
for file in "${required[@]}"; do
  if [[ -f "$file" ]]; then
    printf 'OK      %s\n' "$file"
  else
    printf 'MISSING %s\n' "$file"
    missing=1
  fi
done

exit "$missing"
```

Stop if any required file is missing. Documentation alone cannot create the working system.

## 4. Record the Koha environment

Replace `INSTANCE` with the real Koha instance name.

```bash
koha-list
sudo koha-plack --status INSTANCE
sudo koha-shell INSTANCE -c 'perl -I/usr/share/koha/lib -e "use C4::Context; print C4::Context->preference(q{Version}), qq{\n};"'
timedatectl
```

Record:

```text
Koha instance name
Koha version
Operating system
OPAC URL
Staff URL
Database name
Template language
Plack status
Server time zone
```

## 5. Create backups

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/root/koha-researcher-backups/$STAMP"

sudo mkdir -p "$BACKUP_DIR"
sudo koha-dump INSTANCE

sudo tar -czf "$BACKUP_DIR/koha-researcher-files-before-install.tar.gz" \
  /usr/share/koha/opac/cgi-bin/opac \
  /usr/share/koha/intranet/cgi-bin/tools \
  /usr/share/koha/opac/htdocs/opac-tmpl \
  /usr/share/koha/intranet/htdocs/intranet-tmpl \
  /usr/share/koha/bin \
  /etc/cron.d

sudo ls -lh "$BACKUP_DIR"
```

Do not continue until backup files are visible.

## 6. Install and validate the database schema

Review the SQL file first:

```bash
less database/schema/researcher-system-schema.sql
```

Install it through the Koha database connection:

```bash
sudo koha-mysql INSTANCE < database/schema/researcher-system-schema.sql
```

Confirm the main tables:

```bash
sudo koha-mysql INSTANCE -e "
SHOW TABLES LIKE 'custom_profile_details';
SHOW TABLES LIKE 'researcher_identifiers';
SHOW TABLES LIKE 'researcher_affiliations';
SHOW TABLES LIKE 'researcher_publications_master';
SHOW TABLES LIKE 'researcher_publication_sources';
SHOW TABLES LIKE 'researcher_publication_links';
SHOW TABLES LIKE 'researcher_sync_jobs';
"
```

## 7. Install staff and OPAC files

Adjust `en` when the Koha instance uses another template language.

```bash
sudo install -m 0755 \
  src/intranet/cgi-bin/researcher-verification.pl \
  /usr/share/koha/intranet/cgi-bin/tools/

sudo install -m 0644 \
  src/intranet/templates/researcher-verification.tt \
  /usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/modules/tools/

sudo install -m 0755 \
  src/opac/cgi-bin/opac-researcher-search.pl \
  src/opac/cgi-bin/opac-researcher-profile.pl \
  /usr/share/koha/opac/cgi-bin/opac/

sudo install -m 0644 \
  src/opac/templates/opac-researcher-search.tt \
  src/opac/templates/opac-researcher-profile.tt \
  /usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/en/modules/
```

## 8. Install synchronization workers

```bash
sudo install -m 0755 \
  scripts/maintenance/bu-researcher-publication-sync.pl \
  scripts/maintenance/bu-rims-wos-auto-sync.pl \
  scripts/maintenance/bu-crossref-publication-sync.pl \
  /usr/share/koha/bin/
```

Validate Perl syntax:

```bash
for file in \
  /usr/share/koha/intranet/cgi-bin/tools/researcher-verification.pl \
  /usr/share/koha/opac/cgi-bin/opac/opac-researcher-search.pl \
  /usr/share/koha/opac/cgi-bin/opac/opac-researcher-profile.pl \
  /usr/share/koha/bin/bu-researcher-publication-sync.pl \
  /usr/share/koha/bin/bu-rims-wos-auto-sync.pl \
  /usr/share/koha/bin/bu-crossref-publication-sync.pl
do
  sudo koha-shell INSTANCE -c "perl -c '$file'" || exit 1
done
```

## 9. Configure APIs and email

```bash
sudo mkdir -p /etc/koha/researcher-system
sudo cp config/researcher-system.example.conf \
  /etc/koha/researcher-system/researcher-system.conf
sudo chmod 0600 \
  /etc/koha/researcher-system/researcher-system.conf
sudoedit /etc/koha/researcher-system/researcher-system.conf
```

Enter credentials only in this protected server file. Never commit the real file.

Test each API separately before enabling automatic jobs. A failed API test should not be treated as successful synchronization.

## 10. Confirm the verification trigger

The verification action should set the researcher to verified, enable synchronization for active researchers, and start or queue the source workers.

```bash
sudo grep -nE \
  'verification_status|sync_enabled|bu-researcher-publication-sync\.pl|bu-rims-wos-auto-sync\.pl|fork\(|exec\(|system\(' \
  /usr/share/koha/intranet/cgi-bin/tools/researcher-verification.pl
```

The output must show both the verification update and worker-launch code. If it only shows verification fields, immediate synchronization is not installed.

## 11. Install reviewed cron jobs

Never copy cron templates without replacing placeholders. First inspect them:

```bash
grep -RniE 'INSTANCE|CHANGEME|example|/path/to' scripts/cron config
```

Each cron should:

- run as the Koha instance user;
- set `KOHA_CONF` and `PERL5LIB`;
- use `flock` to avoid overlapping runs;
- write to a protected log;
- respect API quotas.

Install only reviewed files:

```bash
sudo install -m 0644 scripts/cron/REVIEWED_FILE \
  /etc/cron.d/REVIEWED_FILE
sudo systemctl restart cron
sudo systemctl is-active cron
```

## 12. Restart services

```bash
sudo koha-plack --restart INSTANCE
sudo systemctl reload apache2
sudo koha-plack --status INSTANCE
```

## 13. Test one researcher from beginning to end

Use a test patron and test identifiers.

```text
1. Search for an existing patron.
2. Create the patron only when no match exists.
3. Create the researcher profile.
4. Add ORCID, Scopus Author ID and WoS ResearcherID.
5. Register name variants and affiliation dates.
6. Verify identifiers against the official source profiles.
7. Click Verify.
8. Confirm verification email.
9. Confirm immediate Scopus job.
10. Confirm immediate/background WoS job.
11. Confirm publications are normalized.
12. Confirm Scopus–WoS duplicates merge into one master record.
13. Confirm Crossref enriches DOI-bearing source rows only.
14. Confirm uncertain author matches enter manual review.
15. Confirm public profile hides private patron data.
16. Test Former, Reactivated, Hidden and Restored states.
```

Check synchronization jobs:

```bash
sudo koha-mysql INSTANCE -e "
SELECT source_name, job_type, job_status, COUNT(*) AS jobs,
       MAX(started_at) AS latest_job
FROM researcher_sync_jobs
GROUP BY source_name, job_type, job_status
ORDER BY latest_job DESC;
"
```

## 14. Understand the publication count

Do not add Scopus, Web of Science and Crossref totals.

```text
Unique publications = deduplicated master publications linked to the researcher
```

One master publication can retain several source rows.

## 15. Production approval checklist

Move to production only when all items pass:

```text
Repository-completeness check passed
Database and file backups verified
Rollback tested
Schema tables verified
All Perl syntax checks passed
Verification trigger confirmed
API authentication tests passed
Email delivery and resend tested
Cron placeholders removed
Cron overlap protection enabled
Audit logs verified
Public privacy review passed
Licensed-data review passed
HTTPS verified
One complete researcher test passed
Former/Reactivate/Hide/Restore tests passed
```

## 16. Troubleshooting order

When something fails, check in this order:

```text
File exists
File permission
Perl syntax
Koha instance name
KOHA_CONF / PERL5LIB
Database table and column
API credential and quota
Worker log
researcher_sync_jobs row
Plack/Apache restart
Public-profile privacy
```

Never solve a failure by exposing credentials, disabling authentication, or publishing private logs.
