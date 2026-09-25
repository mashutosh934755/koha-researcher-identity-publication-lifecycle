# Koha-Based Researcher Identity, Publication Lifecycle and Expert Discovery System

A Koha extension and pilot implementation for researcher onboarding, persistent researcher identity, scholarly identifier management, publication synchronization, Scopus/Web of Science deduplication, author disambiguation, public researcher profiles, lifecycle management, and evidence-grounded expert discovery.

## Repository status

This repository includes a **sanitized production-derived implementation tree** in addition to architecture/research documentation. The public source includes the database structure, staff and OPAC CGI programs/templates, synchronization workers, onboarding/lifecycle helpers, cron templates, protected-configuration examples, and install/verify/rollback scripts.

It is **not yet claimed as universally one-command production-ready**: the generic package still needs a clean third-party Koha-instance integration test. Always test on a non-production Koha instance first.

Start with [Installable reference release](install/README.md), [Installation](INSTALLATION.md), and [Project readiness](PROJECT-READINESS.md).

## Expert Discovery V4.2 architecture

The current pilot Expert Discovery design separates **query understanding** from **expert ranking**:

```text
Research question
-> direct local match for short topic queries
   OR optional DeepSeek query interpretation for natural-language questions
-> verified local Koha researcher evidence
-> evidence-grounded scoring
-> current/verified filtering
-> ranked expert cards with explanation and profile photo
```

The external AI service is used only to interpret a research question into structured concepts. It does **not** select researchers, invent staff identities, or independently determine expertise.

Current deployed ranking principles:

- literal exact profile phrase match receives stronger priority than a near-equivalent match;
- lightweight singular/plural equivalents such as `Digital Library` / `Digital Libraries` are treated as near-equivalent, but not identical;
- direct declared research areas/interests remain the strongest topical evidence;
- semantic, OECD and department/domain evidence are secondary;
- current + verified institutional status is explicit evidence;
- publication/output count is supporting evidence and a final equal-relevance tie-break, not a topical relevance booster;
- multiple relevant experts may be returned; the current UI displays the top five above the relevance threshold;
- Expert Discovery cards use the same public researcher-photo endpoint as the directory, with initials as fallback.

The production pilot uses a DB-backed local expert index refreshed by a systemd timer. The public repository includes sanitized operational examples and documentation, but the exact live production index/data are intentionally excluded.

## Included implementation

```text
database/schema/researcher-system-schema.sql
config/research-api.env.example
config/deepseek-expert-discovery.conf.example
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
scripts/systemd/
```

The release intentionally excludes credentials, production data, raw licensed API payloads, internal addresses, production backup tables, generated production expert-index JSON, patron photos, and protected configuration. See [Source provenance](SOURCE-PROVENANCE.md).

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
- lifecycle preservation across active, former, hidden, restored and rejoined states;
- evidence-grounded Expert Discovery with external-AI query interpretation separated from local researcher ranking.

See [Production hardening guide](docs/11-production-hardening-and-reproducible-deployment.md), [Post-hardening validation](docs/12-post-hardening-validation-2026-09.md), and [Expert Discovery V4.2 validation note](docs/13-expert-discovery-v4-2-2026-09-25.md).

## Main capabilities

- Koha patron-linked onboarding and persistent researcher UUID
- ORCID, Scopus Author ID and Web of Science ResearcherID registry
- name variants and multi-period affiliation history
- staff verification and publication-intelligence interfaces
- public researcher directory/profile/photo/query endpoints
- structured research areas plus legacy research interests/keywords and OECD classification support
- Scopus, Web of Science, ORCID and Crossref integration paths
- source-to-master deduplication and author disambiguation
- source-specific citation/provenance storage
- scheduled synchronization, retry, audit and lifecycle processing
- Active, Former, Hidden, Restored and rejoining/reactivation flows
- optional DeepSeek-assisted natural-language query interpretation with local evidence-grounded discovery
- DB-backed Expert Discovery index with periodic refresh
- explainable multi-expert ranking and profile-photo cards

## Safe installation summary

```bash
git clone https://github.com/mashutosh934755/koha-researcher-identity-publication-lifecycle.git
cd koha-researcher-identity-publication-lifecycle

sudo RIMS_INSTITUTION_NAME="Example University" \
     SCOPUS_AFFILIATION_ID="YOUR_SCOPUS_AFFILIATION_ID" \
     CROSSREF_MAILTO="library@example.edu" \
     ./install/install.sh <koha-instance>

sudo ./install/verify.sh <koha-instance>
```

The installer backs up files it replaces under `/root/koha-rims-backup-<timestamp>`.

## Security

Never commit real API keys, SMTP passwords, Koha configuration files, patron/private researcher data, researcher photos, raw licensed Scopus/WoS datasets, database dumps, generated production expert-index JSON, logs containing private data, or internal network addresses.

DeepSeek credentials must remain in a protected server-side configuration file. They must never be embedded in JavaScript, public JSON, templates, shell-history arguments, or repository source.

## Research and evaluation note

The pilot audit demonstrates technical feasibility and implementation behaviour. It does not by itself establish expert-ranking effectiveness; a judged relevance protocol remains necessary for formal evaluation. The current V4.2 implementation should be evaluated with a benchmark set covering exact topic queries, singular/plural variants, natural-language questions, multi-expert topics, weak/no-match topics, and lifecycle cases.
