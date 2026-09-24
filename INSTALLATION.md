# Installation Guide

## 1. Test server first

Use a non-production Koha instance. Confirm root/sudo access, backups, and authorised API access before enabling external-source synchronization.

## 2. Clone and inspect

```bash
git clone https://github.com/mashutosh934755/koha-researcher-identity-publication-lifecycle.git
cd koha-researcher-identity-publication-lifecycle
```

Review `database/schema/researcher-system-schema.sql`, `install/install.sh`, `scripts/cron/`, and `config/*.example`.

## 3. Install

```bash
sudo RIMS_INSTITUTION_NAME="Example University"      SCOPUS_AFFILIATION_ID="YOUR_SCOPUS_AFFILIATION_ID"      CROSSREF_MAILTO="library@example.edu"      ./install/install.sh <koha-instance>
```

Optional public-profile base URL can be supplied as `RIMS_PUBLIC_PROFILE_BASE_URL`.

The installer loads the structure-only schema, installs staff/OPAC files and workers, renders the Koha-instance/institution defaults, installs cron definitions, and writes only example credential files. Files replaced on the host are backed up first under `/root/koha-rims-backup-<timestamp>`.

## 4. Configure protected runtime credentials

Create/edit:

```text
/etc/koha/sites/<instance>/research-api.env
```

using `config/research-api.env.example`, then set restrictive permissions (`chmod 600`). Optional AI query configuration uses:

```text
/etc/koha/sites/<instance>/gemini-expert-discovery.conf
```

Never commit active credential files.

## 5. Verify

```bash
sudo ./install/verify.sh <koha-instance>
```

The verifier checks expected files, Koha-environment Perl syntax for key components, selected database objects and obvious hard-coded-secret patterns. Live external API behaviour still requires configured credentials/network access.

## 6. Roll back replaced files

```bash
sudo ./install/rollback.sh /root/koha-rims-backup-YYYYMMDD-HHMMSS
```

Database objects are intentionally not dropped automatically during rollback.

## 7. Current readiness boundary

The source is production-derived and sanitized, but the generic installer still requires a clean third-party Koha integration test before the repository should be called universally production-ready.
