# Project Readiness and Repository Completeness

## Current classification

This repository currently serves as a **pilot architecture and implementation-documentation repository**.

A person can understand the intended system, workflow, configuration, security model, deduplication logic, author-disambiguation logic, lifecycle rules, and installation sequence from the documentation.

A person cannot reproduce the complete working application from documentation alone unless all implementation files listed below are also present and tested.

## Required release structure

A reproducible release should contain at least:

```text
.
├── README.md
├── BEGINNER-BUILD-GUIDE.md
├── INSTALLATION.md
├── CONFIGURATION.md
├── SECURITY.md
├── PROJECT-READINESS.md
├── database/
│   └── schema/
│       └── researcher-system-schema.sql
├── config/
│   └── researcher-system.example.conf
├── src/
│   ├── intranet/
│   │   ├── cgi-bin/
│   │   │   └── researcher-verification.pl
│   │   └── templates/
│   │       └── researcher-verification.tt
│   └── opac/
│       ├── cgi-bin/
│       │   ├── opac-researcher-search.pl
│       │   └── opac-researcher-profile.pl
│       └── templates/
│           ├── opac-researcher-search.tt
│           └── opac-researcher-profile.tt
├── scripts/
│   ├── maintenance/
│   │   ├── bu-researcher-publication-sync.pl
│   │   ├── bu-rims-wos-auto-sync.pl
│   │   └── bu-crossref-publication-sync.pl
│   └── cron/
│       ├── researcher-scopus.example
│       ├── researcher-wos.example
│       └── researcher-crossref.example
├── docs/
│   ├── 01-system-workflow.md
│   ├── 02-deduplication.md
│   ├── 03-author-disambiguation.md
│   ├── 04-lifecycle.md
│   ├── database-dictionary.md
│   ├── api-behaviour.md
│   ├── email-events.md
│   ├── permissions.md
│   ├── testing.md
│   ├── troubleshooting.md
│   └── rollback.md
└── tests/
    ├── syntax/
    ├── database/
    ├── integration/
    └── fixtures/
```

## Files verified during the documentation audit

The documentation audit confirmed the presence of:

```text
README.md
INSTALLATION.md
CONFIGURATION.md
SECURITY.md
config/researcher-system.example.conf
docs/01-system-workflow.md
docs/02-deduplication.md
docs/03-author-disambiguation.md
docs/04-lifecycle.md
```

## Critical implementation gap found

At the time of this audit, the expected database schema path was not available:

```text
database/schema/researcher-system-schema.sql
```

The expected staff verification source path was also not available:

```text
src/intranet/cgi-bin/researcher-verification.pl
```

Therefore the repository should not yet be advertised as a complete one-command or clone-and-install application.

## Definition of complete

The project should be marked reproducible only after all of the following are true:

```text
[ ] Database schema is included and creates every required table/index/constraint
[ ] Staff CGI and template are included
[ ] OPAC CGI files and templates are included
[ ] Scopus worker is included
[ ] Web of Science worker is included
[ ] Crossref worker is included
[ ] Example cron files are included
[ ] No production secret or private data is included
[ ] Every Perl file passes syntax validation
[ ] Database migration is tested on a clean Koha test instance
[ ] Verification-trigger synchronization is tested
[ ] Scheduled retry is tested
[ ] Deduplication is tested with DOI and non-DOI cases
[ ] Manual decisions survive later sync jobs
[ ] Public-profile privacy is tested
[ ] Former/reactivation/hide/restore lifecycle is tested
[ ] Rollback procedure is tested
[ ] A tagged release records compatible Koha and operating-system versions
```

## Release recommendation

Until the implementation files are published and tested, use wording such as:

```text
Pilot implementation documentation and reference architecture.
Not yet a complete distributable installer.
```

After the complete source tree and tests are added, publish a versioned release such as `v0.1.0-pilot`, include release notes, and record the exact Koha version used for validation.

## Security requirement before publishing source

Before uploading code copied from a production server, remove or replace:

- API keys and tokens;
- SMTP usernames and passwords;
- internal URLs and private IP addresses;
- patron or researcher personal data;
- database credentials;
- raw licensed Scopus or Web of Science responses;
- production logs and diagnostic reports;
- institution-specific secrets or identifiers that are not approved for publication.

Run a secret scan and manually review every diff before merging.
