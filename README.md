# Koha-Based Researcher Identity, Publication Lifecycle and Expert Discovery System

A Koha extension and pilot reference architecture for researcher onboarding, persistent researcher identity, scholarly identifier management, publication synchronization, Scopus-Web of Science deduplication, author disambiguation, public researcher profiles, lifecycle management, and **evidence-grounded explainable expert discovery**.

## Read this first

This repository currently contains the **pilot architecture and implementation documentation**. It explains the intended workflow and production-pilot behaviour, but it should not be treated as a complete clone-and-install release until the database schema, CGI programs, templates, synchronization workers, expert-discovery implementation files, cron files, and tests listed in [Project readiness](PROJECT-READINESS.md) are present.

For a simple start-to-finish explanation, read the [Beginner Build Guide](BEGINNER-BUILD-GUIDE.md).

## Status

Pilot implementation documentation and reference architecture. Test only on a non-production Koha instance. Do not deploy from documentation alone when required implementation files are missing.

## Main capabilities

- Koha patron-linked researcher onboarding
- Persistent researcher UUID
- ORCID, Scopus Author ID, and Web of Science ResearcherID
- Name variants and affiliation history
- Library verification dashboard
- Public researcher directory and researcher profiles
- Research interests / keywords and disciplinary evidence
- Fields of Science and Technology (OECD) classification support
- Scopus, Web of Science, ORCID, and Crossref integration
- DOI and metadata normalization
- Scopus-WoS publication deduplication
- Author disambiguation with automated scoring and manual review
- Source-specific citation counts
- Verification-triggered synchronization
- Scheduled retry and metadata-enrichment jobs
- Synchronization audit trail
- Active, Former, Hidden, Restored, and Deleted researcher lifecycle
- Evidence-grounded expert discovery from a research topic or question
- Optional AI-assisted query interpretation and concept expansion
- Deterministic/local researcher-evidence matching
- Explainable `Why this expert?` recommendations
- Structured directory filters for known-item/faceted researcher discovery

## Two public discovery modes

The public layer intentionally separates two different information needs.

### 1. Researcher directory

Use this when the user already knows a person, department, school, researcher type, or employment status. The directory supports structured browsing and filtering.

### 2. Expert discovery

Use this when the user knows the **research problem but not the right person**.

```text
Topic Need
-> Profile Data
-> Evidence
-> AI-Assisted Query Match (optional)
-> Evidence-Grounded Ranking
-> Explainable Result
-> Connect to Researcher Profile
```

The expert discovery layer can use verified profile evidence such as:

- declared research interests and keywords;
- Fields of Science and Technology (OECD) classifications;
- department, school and disciplinary affiliation;
- verified and Current/Former researcher status;
- linked scholarly-output evidence;
- persistent identifiers as identity/provenance anchors.

Publication volume is supporting evidence, not a substitute for topical expertise.

## Responsible AI boundary

The language-model or semantic component, when configured, is used for **query interpretation and concept expansion**. It is not treated as the authority that decides who is an expert.

```text
Natural-language research question
-> query normalization / semantic concepts
-> locally maintained verified researcher evidence
-> deterministic evidence matching and ranking
-> human-readable explanation
```

Direct keyword matching can operate without an external semantic service. This provides a local fallback and reduces dependency on external AI availability.

## Explainability

A recommendation should expose the evidence behind the ranking instead of presenting a score as self-justifying. Example explanation categories include:

- direct research-interest match;
- related/semantic expertise match;
- OECD or disciplinary alignment;
- department/domain alignment;
- current verified researcher status;
- linked scholarly-output evidence.

The interface concept is summarized as **Why this expert?**

## Start-to-end researcher and publication workflow

```text
New user arrives
-> Existing patron search
-> Koha patron creation
-> Borrowernumber generated
-> Expiry date assigned
-> Researcher eligibility check
-> Researcher profile created
-> Researcher UUID generated
-> ORCID / Scopus / WoS identifiers added
-> Name variants registered
-> Affiliation history registered
-> Research interests / disciplinary evidence maintained
-> Library verification
-> Verification status becomes verified
-> Public visibility and synchronization enabled for active researchers
-> Scopus / Web of Science synchronization
-> Metadata normalization
-> Scopus-WoS deduplication
-> Author disambiguation
-> Manual review when required
-> Public researcher profile enabled
-> Researcher evidence available to directory / expert discovery
-> Scheduled synchronization and metadata enrichment
-> Patron-expiry lifecycle
-> Former / Reactivated / Hidden / Restored / Deleted state
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

One master publication can retain several source records: Scopus, Web of Science, Crossref and ORCID.

## Author disambiguation

| Evidence | Maximum score |
|---|---:|
| Verified source identifier | 55 |
| Name variant match | 20 |
| Affiliation match | 15 |
| Timeline match | 10 |
| Total | 100 |

Decision rules preserve manual librarian decisions and route ambiguous cases to review.

## Expert-discovery evaluation roadmap

The pilot demonstrates technical feasibility. Stronger research evaluation should use a larger set of research questions with expert-judged relevance and report measures such as Precision@k, Recall@k, Mean Reciprocal Rank (MRR), and nDCG. Recommended baselines include keyword-only matching, department-only matching, publication-volume ranking, and the proposed evidence-grounded approach. Latency and resilience should also be compared for direct local matching and AI-assisted query interpretation.

## Documentation order

1. [Beginner Build Guide](BEGINNER-BUILD-GUIDE.md)
2. [Project readiness and required files](PROJECT-READINESS.md)
3. [Installation](INSTALLATION.md)
4. [Configuration](CONFIGURATION.md)
5. [Security](SECURITY.md)
6. [System workflow](docs/01-system-workflow.md)
7. [Scopus-WoS deduplication](docs/02-deduplication.md)
8. [Author disambiguation](docs/03-author-disambiguation.md)
9. [Lifecycle management](docs/04-lifecycle.md)
10. [Expert discovery](docs/06-expert-discovery.md)
11. [Expert evidence and ranking](docs/07-expert-evidence-ranking.md)
12. [Expert discovery evaluation protocol](docs/08-expert-discovery-evaluation.md)

## Security warning

Never commit production credentials, API keys, SMTP passwords, Koha configuration files, patron data, private researcher information, raw licensed API datasets, database dumps, production logs, internal server addresses, or diagnostic reports containing sensitive data.
