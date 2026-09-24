# Project Readiness and Repository Completeness

## Current classification

This repository now contains a **sanitized production-derived implementation release plus research/architecture documentation**.

Previously missing core implementation categories are now present: structure-only database schema, staff CGI/templates, OPAC CGI/templates, Scopus/WoS/Crossref workers, source-name synchronization, disambiguation, onboarding/lifecycle/rejoin helpers, cron templates, and install/verify/rollback scripts.

## What has been validated

- Core production Perl components passed syntax validation in the source Koha environment during collection.
- Public package was sanitized to remove institution-specific names, internal IPs, production identifiers, backup tables and SQL `DEFINER` clauses.
- No production data or real API credentials are included.
- Installer/verification/rollback and shell helpers pass shell syntax checks in the preparation environment.
- WoS Python helper passes Python compilation in the preparation environment.
- Schema is structure-only and excludes timestamped backup tables.

## Remaining validation before universal install-ready status

```text
[ ] Fresh-clone install on a separate clean Koha test instance
[ ] Schema/view/constraint validation on that clean database
[ ] All included Perl CGI/workers checked with koha-shell after rendering
[ ] Test Scopus/WoS live API behaviour within licence terms
[ ] Crossref enrichment/source visibility end-to-end validation
[ ] Onboarding, verification, hide/restore, former/reactivation and rejoin tests
[ ] OPAC privacy/permissions validation
[ ] Cron and overlap-protection validation
[ ] Backup and rollback test on disposable instance
[ ] Record exact compatible Koha/OS versions and tag a release
```

Current wording:

> Sanitized implementation/reference release derived from a validated pilot deployment. Static packaging checks completed; clean-instance integration validation still required.
