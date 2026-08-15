# From Author-Disambiguation Gaps to Institutional Operationalization

## Purpose

This note explains how the Koha-based framework provides an implementable institutional response to several recurring problems in researcher identity and author-name disambiguation research. The intended scholarly wording is **addresses**, **operationalizes**, or **provides an institutional response to** the identified gaps; the project does not claim to solve every author-disambiguation problem.

## Gap-to-response mapping

| Identified challenge | Framework response | Interpretation |
|---|---|---|
| ORCID alone can be incomplete or unevenly adopted | ORCID is combined with Scopus Author ID, Web of Science ResearcherID, Koha-linked institutional identity, name variants, affiliation history and timeline evidence | Strongly addressed |
| Author name ambiguity | Weighted identifier, name-variant, affiliation and temporal evidence | Directly addressed |
| Metadata inconsistency | DOI, title, author-name, affiliation and document-type normalization | Directly addressed |
| Duplicate publications | DOI-first plus metadata-assisted deduplication into master publication records | Directly addressed |
| Cross-platform interoperability | ORCID, Scopus, Web of Science and Crossref integrations around a Koha-based identity layer | Strongly addressed |
| Opaque automation | Evidence scoring plus librarian-mediated review for ambiguous cases | Directly addressed |
| Lack of institutionally governed framework | Library-governed Koha implementation with verification, lifecycle rules and auditability | Directly addressed |
| Affiliation uncertainty | Multi-period affiliation history and timeline consistency | Strongly addressed |
| Confusion between author ownership and institutional attribution | Publication ownership and institutional-affiliation-period attribution are treated as separate decisions | Strong additional contribution |
| Researcher departure causes identity fragmentation | Current/Former lifecycle preserves researcher UUID, identifiers and publication history | Strongly addressed |
| Rejoining may create duplicate local identities | Existing persistent researcher identity is reactivated and a new affiliation period is opened | Strongly addressed |
| Multilingual/culturally diverse name forms | Name variants provide partial support | Partially addressed; dedicated multilingual evaluation remains future work |
| Large South-Asia-specific empirical validation | Pilot implementation provides an operational base | Not yet fully demonstrated; larger evaluation is future work |

## Evidence model for author disambiguation

The current documented primary scoring model is:

| Evidence | Maximum score |
|---|---:|
| Verified persistent/source identifier | 55 |
| Registered name-variant match | 20 |
| Affiliation-history match | 15 |
| Publication-affiliation timeline consistency | 10 |
| **Total** | **100** |

Decision rules:

- 80 or above: auto-confirm if there is no conflicting evidence;
- 50-79: librarian-mediated review;
- below 50: unresolved/review-required;
- without a verified persistent identifier, the primary score is capped below the auto-confirm threshold, so human review remains mandatory.

The principle is therefore not `ORCID = identity proof`, but rather:

```text
Persistent identifiers
+ registered name evidence
+ institutional affiliation history
+ temporal consistency
+ librarian verification where ambiguous
= trusted researcher-publication relationship
```

## Author ownership versus institutional provenance

The framework separates two questions that are often conflated:

1. **Does this publication belong to this researcher?**
2. **Was this publication produced during this researcher's relevant institutional affiliation period?**

A publication may correctly belong to a researcher while being attributable to a previous institution or an earlier affiliation period. The system therefore treats publication ownership and institutional output attribution as distinct decisions. This helps prevent a current institution from automatically claiming all historical works of a newly joined researcher.

## Current, Former and rejoining lifecycle

A no-dues or separation event is treated as a lifecycle transition rather than identity deletion:

```text
Current
-> separation/no-dues
-> close active affiliation interval
-> Former
-> preserve UUID, identifiers, validated publications and audit history
```

If the same researcher later rejoins:

```text
Former
-> rejoining detected
-> existing identity verified
-> new affiliation interval opened
-> profile returns to Current
-> synchronization re-enabled
-> historical publication links remain intact
```

This prevents duplicate institutional researcher identities and preserves scholarly provenance across multiple employment periods.

## Extension from disambiguation to expert discovery

The expert-discovery layer is deliberately built on verified identity and publication evidence. Its logic is:

```text
Verified researcher identity
-> validated publications
-> verified institutional timeline
-> research interests / disciplinary evidence
-> question-to-expert matching
-> explainable 'Why this expert?' result
```

AI or semantic processing may assist with query interpretation, but it is not the authority that determines expert status. Ranking is grounded in local verified researcher evidence.

## Scholarly positioning

A defensible manuscript claim is:

> Earlier author-disambiguation research identifies the need for interoperable, institutionally grounded, metadata-aware and identifier-supported approaches to researcher identification. The present Koha-based framework operationalizes several of these requirements through multi-source persistent identifiers, institutional identity evidence, affiliation timelines, metadata normalization, publication deduplication, evidence-based author matching, librarian-mediated verification, lifecycle preservation and explainable expert discovery.

Avoid the stronger claim that the framework **solves all gaps** in author-name disambiguation. Multilingual transliteration, large-scale multi-institutional validation, benchmark comparison and broader user studies remain future work.

## Research progression

The intended research storyline is:

```text
Gap identification
-> institutional framework design
-> implementation
-> verified identity and publication provenance
-> lifecycle governance
-> evidence-grounded expertise discovery
```

This moves the research contribution from bibliometric observation toward an operational, library-governed institutional system.
