# Koha-Based Researcher Identity and Publication Lifecycle Management System

A Koha extension for researcher onboarding, persistent researcher identity, scholarly identifier management, publication synchronization, Scopus–Web of Science deduplication, author disambiguation, public researcher profiles, email notifications, audit logging, and Active/Former lifecycle management.

## Read this first

This repository currently contains the **pilot architecture and implementation documentation**. It explains the intended workflow and production-pilot behaviour, but it should not be treated as a complete clone-and-install release until the database schema, CGI programs, templates, synchronization workers, cron files, and tests listed in [Project readiness](PROJECT-READINESS.md) are present.

For a simple start-to-finish explanation, read the [Beginner Build Guide](BEGINNER-BUILD-GUIDE.md).

## Status

Pilot implementation documentation and reference architecture. Test only on a non-production Koha instance. Do not deploy from documentation alone when required implementation files are missing.

## Main capabilities

- Koha patron-linked researcher onboarding
- Persistent researcher UUID
- ORCID, Scopus Author ID, and Web of Science ResearcherID
- Name variants and affiliation history
- Library verification dashboard
- Public researcher directory and profile without mandatory photograph
- Scopus, Web of Science, ORCID, and Crossref integration
- DOI and metadata normalization
- Scopus–WoS publication deduplication
- Author disambiguation with automated scoring and manual review
- Source-specific citation counts
- Verification-triggered synchronization
- Scheduled retry and metadata-enrichment jobs
- Synchronization audit trail
- Active, Former, Hidden, Restored, and Deleted researcher lifecycle

## Start-to-end workflow

```text
New user arrives
→ Existing patron search
→ Koha patron creation
→ Borrowernumber generated
→ Expiry date assigned
→ Patron activation email
→ Researcher eligibility check
→ Researcher profile created
→ Researcher UUID generated
→ ORCID / Scopus / WoS identifiers added
→ Name variants registered
→ Affiliation history registered
→ Library verification
→ Verification status becomes verified
→ Public visibility and synchronization enabled for active researchers
→ Verification email
→ Immediate background Scopus synchronization
→ Immediate/background Web of Science synchronization
→ Metadata normalization
→ Scopus–WoS deduplication
→ Author disambiguation
→ Manual review when required
→ Public researcher profile enabled
→ Scheduled Scopus/WoS retry synchronization
→ Daily Crossref DOI metadata verification
→ Patron-expiry lifecycle
→ Former / Reactivated / Hidden / Restored / Deleted state
```

## Verified synchronization behaviour

The production pilot currently uses two layers of automation.

### Verification trigger

When library staff verify an active researcher, the staff verification program:

1. sets `verification_status = 'verified'`;
2. enables public visibility and synchronization for an active researcher;
3. launches the Scopus publication worker as a background process;
4. launches or queues the Web of Science synchronization process;
5. records synchronization activity in the RIMS audit tables and log files.

The scheduled jobs remain a retry and refresh mechanism. They are not the only synchronization path.

### Crossref enrichment

Crossref does not discover researchers and does not create researcher-publication links. It verifies and enriches DOI-bearing records already present in the publication master.

```text
Scopus / Web of Science publication
→ DOI normalized
→ Crossref DOI lookup
→ DOI, title and year validation
→ Crossref source metadata inserted or updated
```

The Crossref worker changes `CROSSREF_SOURCE_ROWS_ONLY`; it does not replace Scopus or Web of Science as the source of researcher authorship.

## Publication deduplication

The unique-publication total is not calculated by adding Scopus and Web of Science totals.

```text
Unique publications = deduplicated master publication records
```

Matching order:

1. Exact normalized DOI match
2. Normalized title + year + ISSN/journal match
3. Fuzzy metadata comparison
4. Manual review for uncertain matches

One publication can retain several source records:

```text
One master publication
├── Scopus source
├── Web of Science source
├── Crossref source
└── ORCID source
```

Source totals may overlap. For example, a profile can have 23 unique publications, 21 Scopus links, 14 Web of Science links, and 14 Crossref-verified DOI records without those source totals being added together.

## Author disambiguation

| Evidence | Maximum score |
|---|---:|
| Verified source identifier | 55 |
| Name variant match | 20 |
| Affiliation match | 15 |
| Timeline match | 10 |
| Total | 100 |

Decision rules:

| Evidence / score | Decision |
|---|---|
| Verified author identifier | Auto-confirm |
| Total score >= 80 | Auto-confirm |
| Score 50–79 | Manual review |
| Score below 50 | Needs review or rejection |
| Manual decision already exists | Preserve the manual decision |

## Operational safety

- Never enter an unverified Scopus Author ID or Web of Science ResearcherID.
- Verify identifiers against the source profile before approving the researcher.
- Use cache-first retrieval where configured and respect licensed API limits.
- Use `flock` for scheduled workers to prevent overlapping jobs.
- Back up files and the Koha database before changing production code.
- Run Perl syntax checks before restarting Koha services.
- Treat retracted, corrected, missing, or low-similarity Crossref records as review items rather than silently approving them.

## Documentation order for a new user

1. [Beginner Build Guide](BEGINNER-BUILD-GUIDE.md)
2. [Project readiness and required files](PROJECT-READINESS.md)
3. [Installation](INSTALLATION.md)
4. [Configuration](CONFIGURATION.md)
5. [Security](SECURITY.md)
6. [System workflow](docs/01-system-workflow.md)
7. [Scopus–WoS deduplication](docs/02-deduplication.md)
8. [Author disambiguation](docs/03-author-disambiguation.md)
9. [Lifecycle management](docs/04-lifecycle.md)

## Security warning

Never commit production credentials, API keys, SMTP passwords, Koha configuration files, patron data, private researcher information, raw licensed API datasets, database dumps, production logs, or diagnostic reports containing sensitive data.
