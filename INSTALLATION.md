# Installation Guide

## 1. Test server first

Use a non-production Koha instance. Confirm root/sudo access, backups, and authorised API access before enabling external-source synchronization.

## 2. Clone and inspect

```bash
git clone https://github.com/mashutosh934755/koha-researcher-identity-publication-lifecycle.git
cd koha-researcher-identity-publication-lifecycle
```

Review `database/schema/researcher-system-schema.sql`, `install/install.sh`, `scripts/cron/`, `scripts/systemd/`, and `config/*.example`.

## 3. Install

```bash
sudo RIMS_INSTITUTION_NAME="Example University" \
     SCOPUS_AFFILIATION_ID="YOUR_SCOPUS_AFFILIATION_ID" \
     CROSSREF_MAILTO="library@example.edu" \
     ./install/install.sh <koha-instance>
```

Optional public-profile base URL can be supplied as `RIMS_PUBLIC_PROFILE_BASE_URL`.

The installer loads the structure-only schema, installs staff/OPAC files and workers, renders the Koha-instance/institution defaults, installs cron definitions, and writes only example credential files. Files replaced on the host are backed up first under `/root/koha-rims-backup-<timestamp>`.

## 4. Configure protected runtime credentials

Create/edit:

```text
/etc/koha/sites/<instance>/research-api.env
```

using `config/research-api.env.example`, then set restrictive permissions.

### Optional DeepSeek query understanding

The current Expert Discovery pilot uses DeepSeek only for natural-language query interpretation. Final expert ranking remains local and evidence-grounded.

Copy:

```text
config/deepseek-expert-discovery.conf.example
```

to:

```text
/etc/koha/sites/<instance>/deepseek-expert-discovery.conf
```

Set the real key only on the server. Never commit it.

Recommended ownership/permissions depend on the Koha deployment, but the file must be readable by the Koha runtime and not world-readable.

## 5. Expert Discovery index refresh

The production pilot uses a DB-backed local expert index. The generated production JSON must not be committed.

Sanitized systemd examples are provided:

```text
scripts/systemd/koha-expert-index.service
scripts/systemd/koha-expert-index.timer
```

Before enabling them, install and review the local sanitized index-builder implementation at the path referenced by the service. Confirm that it exports only public discovery fields.

Example enablement after local validation:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now koha-expert-index.timer
systemctl list-timers --all koha-expert-index.timer
```

## 6. Verify

```bash
sudo ./install/verify.sh <koha-instance>
```

The verifier checks expected files, Koha-environment Perl syntax for key components, selected database objects and obvious hard-coded-secret patterns. Live external API behaviour still requires configured credentials/network access.

For Expert Discovery, additionally verify:

```text
- direct short-topic query works without external AI
- natural-language query returns structured concepts
- local verified profile evidence determines ranking
- exact phrase ranks above singular/plural near-equivalent
- publication count does not increase topical relevance
- profile photos load through the public researcher-photo endpoint
- missing photos fall back safely to initials
- timer refreshes the local expert index
```

## 7. Roll back replaced files

```bash
sudo ./install/rollback.sh /root/koha-rims-backup-YYYYMMDD-HHMMSS
```

Database objects are intentionally not dropped automatically during rollback.

## 8. Current readiness boundary

The source is production-derived and sanitized, but the generic installer still requires a clean third-party Koha integration test before the repository should be called universally production-ready.

The V4.2 Expert Discovery update documents the deployed ranking/query architecture. Exact generated production index content and production credentials remain intentionally excluded.
