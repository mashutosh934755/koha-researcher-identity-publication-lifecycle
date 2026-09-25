# Project Readiness and Repository Completeness

## Current classification

This repository contains a **sanitized production-derived implementation release plus research/architecture documentation**.

Core implementation categories present include: structure-only database schema, staff CGI/templates, OPAC CGI/templates, Scopus/WoS/Crossref workers, source-name synchronization, disambiguation, onboarding/lifecycle/rejoin helpers, cron templates, protected configuration examples, and install/verify/rollback scripts.

The 2026-09-25 Expert Discovery V4.2 update additionally documents and reflects:

- DeepSeek-based natural-language query interpretation;
- local evidence-grounded researcher ranking;
- structured Research Areas as preferred expertise evidence with legacy fallback;
- exact-phrase versus singular/plural near-equivalent ranking;
- publication count removed from topical relevance and retained only as supporting evidence / equal-score tie-break;
- DB-backed expert-index refresh through systemd examples;
- Expert Discovery profile-photo integration.

## What has been validated in the pilot environment

- Core production Perl components passed syntax validation in the source Koha environment during collection.
- Public package was sanitized to remove institution-specific names, internal IPs, production identifiers, backup tables and SQL `DEFINER` clauses.
- No production data or real API credentials are included.
- Installer/verification/rollback and shell helpers pass shell syntax checks in the preparation environment.
- WoS Python helper passes Python compilation in the preparation environment.
- Schema is structure-only and excludes timestamped backup tables.
- Natural-language Expert Discovery query interpretation was validated with a server-side DeepSeek configuration.
- Direct local topic matching was validated independently of external AI.
- Multiple relevant researchers were returned for a shared topic.
- Literal exact expertise phrases ranked above singular/plural near-equivalents in the tested case.
- Publication count was removed from topical relevance scoring and retained as supporting evidence / final equal-score tie-break.
- Researcher profile photos were successfully loaded in Expert Discovery through the same public photo endpoint used by the directory.

## Remaining validation before universal install-ready status

```text
[ ] Fresh-clone install on a separate clean Koha test instance
[ ] Schema/view/constraint validation on that clean database
[ ] All included Perl CGI/workers checked with koha-shell after rendering
[ ] DeepSeek CGI checked after INSTANCE placeholder rendering
[ ] Test Scopus/WoS live API behaviour within licence terms
[ ] Crossref enrichment/source visibility end-to-end validation
[ ] Onboarding, verification, hide/restore, former/reactivation and rejoin tests
[ ] OPAC privacy/permissions validation
[ ] Expert-index builder sanitized and packaged as a generic installable script
[ ] Expert-index service/timer path validated on a clean install
[ ] Expert Discovery JavaScript source synchronized into the sanitized repository
[ ] Missing-photo initials fallback verified in a clean generic installation
[ ] Cron and overlap-protection validation
[ ] Backup and rollback test on disposable instance
[ ] Record exact compatible Koha/OS versions and tag a release
```

Current wording:

> Sanitized implementation/reference release derived from a validated pilot deployment. Expert Discovery V4.2 architecture and key backend behaviour are documented; exact production-generated index data and remaining client-side source packaging are intentionally excluded pending clean-instance sanitization and validation.
