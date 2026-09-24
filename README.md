# Koha-Based Researcher Identity, Publication Lifecycle and Expert Discovery System

A Koha extension and pilot implementation for researcher onboarding, persistent researcher identity, scholarly identifier management, publication synchronization, Scopus/Web of Science deduplication, author disambiguation, public researcher profiles, lifecycle management, and evidence-grounded expert discovery.

## Repository status

This repository now includes a **sanitized production-derived implementation tree** in addition to architecture/research documentation. The public source includes the database structure, staff and OPAC CGI programs/templates, synchronization workers, onboarding/lifecycle helpers, cron templates, protected-configuration examples, and install/verify/rollback scripts.

It is **not yet claimed as universally one-command production-ready**: the generic package still needs a clean third-party Koha-instance integration test. Always test on a non-production Koha instance first.

Start with [Installable reference release](install/README.md), [Installation](INSTALLATION.md), and [Project readiness](PROJECT-READINESS.md).

## Included implementation

```text
database/schema/researcher-system-schema.sql
config/research-api.env.example
config/gemini-expert-discovery.conf.example
install/install.sh
install/verify.sh
install/rollback.sh
src/intranet/cgi-bin/
src/intranet/templates/
src/opac/cgi-bin/
src/opac/templates/
scripts/maintenance/
scripts/onboarding/
scripts/cron/
```

The release intentionally excludes credentials, production data, raw licensed API payloads, internal addresses, production backup tables, and protected configuration. See [Source provenance](SOURCE-PROVENANCE.md).

## Production-hardening controls reflected in source

- authoritative verified + primary + active source identifiers;
- identifier-change quarantine for old Scopus/WoS links;
- guarded Scopus current-set reconciliation;
- evidence-derived disambiguation scores without artificial score inflation;
- duplicate unresolved-review protection;
- distinct confirmed master-publication counting;
- confirmed same-source Scopus/WoS visibility;
- Crossref DOI/bibliographic provenance/enrichment on confirmed publications;
- source-faithful author-name caching with extraction provenance;
- lifecycle preservation across active, former, hidden, restored and rejoined states.

See [Production hardening guide](docs/11-production-hardening-and-reproducible-deployment.md) and [Post-hardening validation](docs/12-post-hardening-validation-2026-09.md).

## Main capabilities

- Koha patron-linked onboarding and persistent researcher UUID
- ORCID, Scopus Author ID and Web of Science ResearcherID registry
- name variants and multi-period affiliation history
- staff verification and publication-intelligence interfaces
- public researcher directory/profile/photo/query endpoints
- research interests, keywords and OECD classification support
- Scopus, Web of Science, ORCID and Crossref integration paths
- source-to-master deduplication and author disambiguation
- source-specific citation/provenance storage
- scheduled synchronization, retry, audit and lifecycle processing
- Active, Former, Hidden, Restored and rejoining/reactivation flows
- optional AI-assisted query interpretation with local evidence-grounded discovery

## Safe installation summary

```bash
git clone https://github.com/mashutosh934755/koha-researcher-identity-publication-lifecycle.git
cd koha-researcher-identity-publication-lifecycle

sudo RIMS_INSTITUTION_NAME="Example University"      SCOPUS_AFFILIATION_ID="YOUR_SCOPUS_AFFILIATION_ID"      CROSSREF_MAILTO="library@example.edu"      ./install/install.sh <koha-instance>

sudo ./install/verify.sh <koha-instance>
```

The installer backs up files it replaces under `/root/koha-rims-backup-<timestamp>`.

## Security

Never commit real API keys, SMTP passwords, Koha configuration files, patron/private researcher data, raw licensed Scopus/WoS datasets, database dumps, logs containing private data, or internal network addresses.

## Research and evaluation note

The pilot audit demonstrates technical feasibility and implementation behaviour. It does not by itself establish expert-ranking effectiveness; the documented judged relevance protocol remains the next research evaluation step.
