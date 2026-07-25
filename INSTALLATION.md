# Installation Guide

## 1. Use a test server first

Do not install directly on production. Prepare a Koha test instance, root or sudo access, a verified database backup, Koha file backup, SMTP credentials, and authorised API access.

## 2. Record the Koha environment

```text
Koha instance name
Koha version
Operating system
OPAC URL
Staff URL
Database name
OPAC template language
Staff template language
Plack status
Apache virtual-host configuration
Server time zone
```

Useful commands:

```bash
koha-list
sudo koha-plack --status INSTANCE
sudo koha-shell INSTANCE -c 'perl -I/usr/share/koha/lib -e "use C4::Context; print C4::Context->preference(q{Version}), qq{\n};"'
timedatectl
```

Replace `INSTANCE` with the real Koha instance name in every command.

## 3. Back up Koha

Create a timestamped backup directory so that database and file backups belong to the same deployment attempt.

```bash
STAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="/root/koha-researcher-backups/$STAMP"

sudo mkdir -p "$BACKUP_DIR"
sudo koha-dump INSTANCE

sudo tar -czf "$BACKUP_DIR/koha-researcher-files-before-install.tar.gz" \
  /usr/share/koha/opac/cgi-bin/opac \
  /usr/share/koha/intranet/cgi-bin/tools \
  /usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/en/modules \
  /usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/modules/tools \
  /usr/share/koha/bin \
  /etc/cron.d
```

Confirm that the backup files exist before continuing.

## 4. Prepare patron data

The following Koha patron information should be available:

```text
Full name
Official email
Card number
Employee or enrolment ID
Department
Designation
Patron category
Registration date
Expiry date
```

The integration uses Koha `borrowernumber` as the operational link. The researcher system creates a persistent `researcher_uuid` for scholarly identity.

## 5. Prepare patron categories

Identify the categories eligible for researcher onboarding, for example:

```text
Faculty
Research Scholar
Research Staff
Academic Staff
Library Professional with Publications
```

Normal circulation rules remain controlled by Koha.

## 6. Install the database schema

After reviewing the schema file, load it through the Koha instance database connection rather than placing a database password in the shell command or repository.

```bash
sudo koha-mysql INSTANCE < database/schema/researcher-system-schema.sql
```

Validate the expected tables after import:

```bash
sudo koha-mysql INSTANCE -e "
SHOW TABLES LIKE 'custom_profile_details';
SHOW TABLES LIKE 'researcher_identifiers';
SHOW TABLES LIKE 'researcher_publications_master';
SHOW TABLES LIKE 'researcher_publication_sources';
SHOW TABLES LIKE 'researcher_publication_links';
SHOW TABLES LIKE 'researcher_sync_jobs';
"
```

Never store a database password in this repository.

## 7. Install OPAC programs

```bash
sudo install -m 0755 \
  src/opac/cgi-bin/opac-researcher-search.pl \
  /usr/share/koha/opac/cgi-bin/opac/

sudo install -m 0755 \
  src/opac/cgi-bin/opac-researcher-profile.pl \
  /usr/share/koha/opac/cgi-bin/opac/
```

A photograph endpoint is optional and should not be installed when photographs are disabled.

## 8. Install OPAC templates

```bash
sudo install -m 0644 \
  src/opac/templates/opac-researcher-search.tt \
  /usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/en/modules/

sudo install -m 0644 \
  src/opac/templates/opac-researcher-profile.tt \
  /usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/en/modules/
```

Adjust the template-language path when the instance does not use `en`.

## 9. Install staff verification files

```bash
sudo install -m 0755 \
  src/intranet/cgi-bin/researcher-verification.pl \
  /usr/share/koha/intranet/cgi-bin/tools/

sudo install -m 0644 \
  src/intranet/templates/researcher-verification.tt \
  /usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/modules/tools/
```

The verification program must retain the background Scopus and Web of Science launch block. A deployment that copies an older verification file can silently remove immediate synchronization.

After installation, confirm the worker references:

```bash
sudo grep -nE \
  'bu-researcher-publication-sync\.pl|bu-rims-wos-auto-sync\.pl|fork\(|exec\(|system\(' \
  /usr/share/koha/intranet/cgi-bin/tools/researcher-verification.pl
```

## 10. Install maintenance scripts

Review each script before installation, then copy only the required workers.

```bash
sudo install -m 0755 scripts/maintenance/*.pl /usr/share/koha/bin/
```

Expected production workers can include:

```text
bu-researcher-publication-sync.pl
bu-rims-wos-auto-sync.pl
bu-crossref-publication-sync.pl
```

Validate every installed Perl worker:

```bash
export PERL5LIB=/usr/share/koha/lib

for file in \
  /usr/share/koha/bin/bu-researcher-publication-sync.pl \
  /usr/share/koha/bin/bu-rims-wos-auto-sync.pl \
  /usr/share/koha/bin/bu-crossref-publication-sync.pl
do
  [[ -f "$file" ]] && sudo koha-shell INSTANCE -c "perl -c '$file'"
done
```

## 11. Configure APIs and mail

```bash
sudo mkdir -p /etc/koha/researcher-system
sudo cp config/researcher-system.example.conf \
  /etc/koha/researcher-system/researcher-system.conf
sudo chown root:INSTANCE-koha \
  /etc/koha/researcher-system/researcher-system.conf
sudo chmod 0640 \
  /etc/koha/researcher-system/researcher-system.conf
```

Confirm the actual Koha group name before using the `chown` command. Use mode `0600` instead when only root should read the file.

Enter real credentials only in the local protected file.

## 12. Install cron jobs safely

Do not blindly copy cron templates into production. Review and replace all placeholders first:

```bash
grep -RniE 'INSTANCE|CHANGEME|example|/path/to' scripts/cron config
```

Each cron entry should:

- run as the Koha instance user;
- set `KOHA_CONF` and `PERL5LIB` explicitly;
- use `flock` to prevent overlapping runs;
- write to a protected instance log;
- use schedules appropriate for API quotas.

Example Crossref metadata-enrichment cron:

```cron
35 3 * * * INSTANCE-koha flock -n /var/lock/koha/INSTANCE/crossref-publication-sync.lock env KOHA_CONF=/etc/koha/sites/INSTANCE/koha-conf.xml PERL5LIB=/usr/share/koha/lib /usr/share/koha/bin/bu-crossref-publication-sync.pl --apply >> /var/log/koha/INSTANCE/crossref-publication-sync.log 2>&1
```

After replacing `INSTANCE`, install reviewed cron files and validate them:

```bash
sudo install -m 0644 scripts/cron/REVIEWED_FILE \
  /etc/cron.d/REVIEWED_FILE
sudo systemctl restart cron
sudo systemctl is-active cron
sudo grep -Rni 'bu-.*sync' /etc/cron.d
```

## 13. Validate repository Perl files

```bash
export PERL5LIB=/usr/share/koha/lib

find src scripts -name '*.pl' -print0 |
while IFS= read -r -d '' file; do
    perl -I/usr/share/koha/lib -c "$file"
done
```

## 14. Restart Koha services

```bash
sudo koha-plack --restart INSTANCE
sudo systemctl reload apache2
```

Check service and HTTP status after restart.

## 15. Test the complete workflow

```text
Create or locate a patron
Send patron activation email
Create researcher profile
Generate researcher UUID
Add ORCID, Scopus ID and WoS ResearcherID
Register name variants and affiliations
Verify identifiers against official source profiles
Verify the researcher profile
Confirm verification email
Confirm immediate background Scopus synchronization
Confirm immediate/background Web of Science synchronization
Normalize DOI, title and journal metadata
Merge Scopus–WoS duplicates
Run author disambiguation
Review uncertain records
Enable public profile
Run Crossref DOI metadata verification
Confirm Crossref changes source rows only
Test scheduled synchronization and retry jobs
Test Active/Former lifecycle
Test Hide and Restore
Verify audit logs
```

Useful validation queries:

```bash
sudo koha-mysql INSTANCE -e "
SELECT source_name, job_type, job_status, COUNT(*) AS jobs,
       MAX(started_at) AS latest_job
FROM researcher_sync_jobs
GROUP BY source_name, job_type, job_status
ORDER BY latest_job DESC;
"
```

Validate the public profile with an HTTP request and confirm that no private data is exposed.

## 16. Production release checklist

```text
Backup verified
Secret scan passed
Schema verified
CGI and worker syntax passed
Verification-trigger worker references confirmed
API tests passed
Email delivery passed
Cron placeholders removed
Cron overlap protection enabled
Role permissions reviewed
HTTPS verified
Data privacy review completed
Rollback tested
```
