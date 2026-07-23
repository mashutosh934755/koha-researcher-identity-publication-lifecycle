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
```

Useful commands:

```bash
koha-list
sudo koha-plack --status INSTANCE
sudo koha-shell INSTANCE -c 'perl -I/usr/share/koha/lib -e "use C4::Context; print C4::Context->preference(q{Version}), qq{\n};"'
```

## 3. Back up Koha

```bash
sudo koha-dump INSTANCE

sudo tar -czf /root/koha-researcher-files-before-install.tar.gz \
  /usr/share/koha/opac/cgi-bin/opac \
  /usr/share/koha/intranet/cgi-bin/tools \
  /usr/share/koha/opac/htdocs/opac-tmpl/bootstrap/en/modules \
  /usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/modules/tools \
  /usr/share/koha/bin \
  /etc/cron.d
```

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

After the schema file is added to this repository:

```bash
mysql KOHA_DATABASE < database/schema/researcher-system-schema.sql
```

Use credentials from the local Koha configuration. Never store a database password in this repository.

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

## 9. Install staff verification files

```bash
sudo install -m 0755 \
  src/intranet/cgi-bin/researcher-verification.pl \
  /usr/share/koha/intranet/cgi-bin/tools/

sudo install -m 0644 \
  src/intranet/templates/researcher-verification.tt \
  /usr/share/koha/intranet/htdocs/intranet-tmpl/prog/en/modules/tools/
```

## 10. Install maintenance scripts

```bash
sudo install -m 0755 scripts/maintenance/*.pl /usr/share/koha/bin/
```

## 11. Configure APIs and mail

```bash
sudo mkdir -p /etc/koha/researcher-system
sudo cp config/researcher-system.example.conf \
  /etc/koha/researcher-system/researcher-system.conf
sudo chmod 600 /etc/koha/researcher-system/researcher-system.conf
```

Enter real credentials only in the local protected file.

## 12. Install cron jobs

Review instance names and schedules before copying:

```bash
sudo cp scripts/cron/* /etc/cron.d/
sudo chmod 0644 /etc/cron.d/researcher*
sudo systemctl restart cron
```

## 13. Validate Perl

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

## 15. Test the complete workflow

```text
Create or locate a patron
Send patron activation email
Create researcher profile
Generate researcher UUID
Add ORCID, Scopus ID and WoS ResearcherID
Register name variants and affiliations
Verify profile
Send verification email
Synchronize publications
Normalize DOI, title and journal metadata
Merge Scopus–WoS duplicates
Run author disambiguation
Review uncertain records
Enable public profile
Test scheduled synchronization
Test Active/Former lifecycle
Test Hide and Restore
Verify audit logs
```

## 16. Production release checklist

```text
Backup verified
Secret scan passed
Schema verified
CGI syntax passed
API tests passed
Email delivery passed
Role permissions reviewed
HTTPS verified
Data privacy review completed
Rollback tested
```
