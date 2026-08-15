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
- Name variants and multi-period affiliation history
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
- No-dues/separation transition without deleting scholarly history
- Rejoining/reactivation using the same persistent researcher identity
- Evidence-grounded expert discovery from a research topic or question
- Optional AI-assisted query interpretation and concept expansion
- Deterministic/local researcher-evidence matching
- Explainable `Why this expert?` recommendations
- Structured directory filters for known-item/faceted researcher discovery

## Two public discovery modes

### 1. Researcher directory

Use this when the user already knows a person, department, school, researcher type, or employment status. The directory supports structured browsing and filtering, including Current and Former researcher views.

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

The expert discovery layer can use verified profile evidence such as declared research interests and keywords, Fields of Science and Technology (OECD) classifications, department/school context, verified current status, linked scholarly outputs, and persistent identifiers as identity/provenance anchors. Publication volume is supporting evidence, not a substitute for topical expertise.

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

## From author-disambiguation gaps to institutional operationalization

The framework is positioned as an implementable institutional response to several recurring problems in researcher-identity and author-name-disambiguation research. It does **not** claim to solve every disambiguation problem.

The main operational responses include:

- ORCID is not treated as sufficient in isolation; it is combined with Scopus Author ID, Web of Science ResearcherID, Koha-linked institutional identity, registered name variants, affiliation history and timeline evidence;
- author ambiguity is handled through weighted identifier, name, affiliation and temporal evidence;
- DOI/title/name/affiliation/document-type normalization reduces metadata inconsistency;
- DOI-first and metadata-assisted deduplication consolidates duplicate source records into master publications;
- library-mediated review is preserved for ambiguous cases instead of forcing opaque automated decisions;
- publication ownership is separated from institutional-affiliation-period attribution;
- Current/Former/rejoining lifecycle rules preserve one persistent researcher identity across multiple employment periods;
- verified identity and publication provenance provide the foundation for explainable expert discovery.

See [From Author-Disambiguation Gaps to Institutional Operationalization](docs/09-gap-to-operationalization.md) for the detailed gap-to-response matrix and scholarly positioning.

## No-dues, separation and rejoining

A no-dues/separation event changes lifecycle state; it does **not** delete the researcher or their publications.

```text
Active researcher
-> no-dues / separation
-> close current affiliation period
-> Former researcher
-> preserve UUID + identifiers + publications + audit history
```

If the same faculty member later rejoins, the system searches for and reuses the existing persistent researcher identity instead of creating a duplicate profile:

```text
Former researcher
-> rejoining detected
-> existing identity verified
-> preserve old affiliation history
-> open new current affiliation period
-> reactivate profile and synchronization
-> incremental publication refresh
-> eligible for current expert discovery again
```

This allows one researcher identity to represent multiple institutional affiliation periods while preserving provenance. See [Lifecycle management](docs/04-lifecycle.md) for the detailed rules.

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
-> No-dues / separation -> Former while scholarly history is preserved
-> Rejoining -> same identity reactivated with a new affiliation period
-> Hidden / Restored / Deleted administrative states as applicable
```

## Publication deduplication

The unique-publication total is not calculated by adding Scopus and Web of Science totals. Unique publications are represented by deduplicated master publication records. Matching proceeds from exact normalized DOI, to normalized title/year/ISSN or journal evidence, to fuzzy comparison, with manual review for uncertain cases.

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
13. [Gap-to-operationalization framework](docs/09-gap-to-operationalization.md)

## Security warning

Never commit production credentials, API keys, SMTP passwords, Koha configuration files, patron data, private researcher information, raw licensed API datasets, database dumps, production logs, internal server addresses, or diagnostic reports containing sensitive data.
