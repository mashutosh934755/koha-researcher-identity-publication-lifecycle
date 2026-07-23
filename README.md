# Koha-Based Researcher Identity and Publication Lifecycle Management System

A Koha extension for researcher onboarding, persistent researcher identity, scholarly identifier management, publication synchronization, Scopus–Web of Science deduplication, author disambiguation, public researcher profiles, email notifications, audit logging, and Active/Former lifecycle management.

## Status

Pilot implementation. Test on a non-production Koha instance before deployment.

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
- Scheduled synchronization and audit trail
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
→ Verification email
→ API synchronization
→ Metadata normalization
→ Scopus–WoS deduplication
→ Author disambiguation
→ Manual review when required
→ Public researcher profile enabled
→ Scheduled synchronization
→ Patron-expiry lifecycle
→ Former / Reactivated / Hidden / Restored / Deleted state
```

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

## Documentation

- [Installation](INSTALLATION.md)
- [Configuration](CONFIGURATION.md)
- [Security](SECURITY.md)
- [System workflow](docs/01-system-workflow.md)
- [Scopus–WoS deduplication](docs/02-deduplication.md)
- [Author disambiguation](docs/03-author-disambiguation.md)
- [Lifecycle management](docs/04-lifecycle.md)

## Security warning

Never commit production credentials, API keys, SMTP passwords, Koha configuration files, patron data, private researcher information, raw licensed API datasets, database dumps, or production logs.
