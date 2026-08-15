# Empirical Pilot Audit — 15 August 2026

This document records an **aggregate, anonymized, read-only audit snapshot** of the deployed pilot. No production credentials, internal server addresses, patron-private data, API keys, or licensed raw metadata are included here.

The audit used read-only SQL queries, schema inspection, JSON validation, checksum comparison, and local HTTP timing. No `INSERT`, `UPDATE`, `DELETE`, `ALTER`, or file-modification operation was executed.

## Researcher identity snapshot

| Indicator | Audited result |
|---|---:|
| Verified researcher profiles | 6 |
| Active researchers | 4 |
| Former researchers | 2 |
| Publicly visible verified profiles | 5 of 6 (83.33%) |
| Hidden verified profiles | 1 of 6 (16.67%) |
| ORCID coverage | 4 of 6 (66.67%) |
| Scopus Author ID coverage | 4 of 6 (66.67%) |
| Web of Science ResearcherID coverage | 4 of 6 (66.67%) |

The pilot therefore demonstrates multi-identifier support, but it also shows why a single persistent identifier cannot be assumed to be universally available.

## Publication and provenance snapshot

| Indicator | Audited result |
|---|---:|
| Source-specific publication records | 423 |
| Master publication entities | 151 |
| Researcher-publication links | 230 |
| `review_status=auto_confirmed` | 152 |
| `review_status=confirmed` | 78 |
| Match-score band 80–100 | 188 |
| Match-score band 50–79 | 42 |
| Recorded disambiguation-case rows | 4,385 |

The 423 source records and 151 master entities demonstrate the separation between source-level provenance and consolidated publication entities. The difference between those counts should **not** be interpreted as a validated duplicate count without record-level duplicate adjudication.

All 230 researcher-publication links in this snapshot had a final `system_decision=confirmed`. The disambiguation-case table stores candidate/evidence rows, so its 4,385 rows are an audit-trail volume and are not equivalent to 4,385 unresolved author identities.

## Expert-discovery evidence index

| Indicator | Audited result |
|---|---:|
| Public indexed researcher profiles | 5 |
| Active indexed profiles | 4 |
| Former indexed profiles | 1 |
| Profiles with declared research interests | 2 of 5 |
| Total indexed research-interest terms | 26 |
| Profiles with OECD evidence | 4 of 5 |
| Total indexed OECD classifications | 8 |
| Indexed publication-count evidence | 230 linked outputs |
| Profiles with profile photo | 2 of 5 |

The private and browser-served expert-index JSON copies were byte-identical by SHA-256 checksum, and the JSON passed syntax validation.

### Deployed expert-ranking emphasis

The deployed precision scorer gives the strongest weight to direct topic/research-interest evidence:

- direct research-interest/topic evidence: maximum 55 points;
- semantic interest expansion: maximum 15 points;
- OECD-field alignment: maximum 10 points;
- smaller bounded contributions from department/domain context, verified current status, and publication support.

This reflects the design principle that publication volume is supporting evidence rather than a substitute for topical expertise.

## Retrieval performance

Five local HTTP measurements were recorded for each endpoint class:

| Measurement | Mean | Median |
|---|---:|---:|
| Complete researcher directory page | 2.087 s | 2.089 s |
| Local expert-index JSON | 3.37 ms | 3.07 ms |

The millisecond-level JSON result supports the use of a pre-built local evidence index for the fast retrieval path. These measurements do **not** represent end-to-end semantic query latency or expert-ranking relevance effectiveness.

## Lifecycle and rejoining snapshot

The researcher-person model contained four verified `current` and two verified `former` identities. The dedicated rejoin-candidate table contained zero active candidates at audit time. The affiliation-history table contained two verified current affiliation rows and no historical rows in this snapshot.

Accordingly, rejoining is documented as an **implemented and schema-validated workflow**, not as an empirically observed rejoining event in this particular audit snapshot. Longitudinal validation across real separation/rejoining episodes remains future work.

## Interpretation for research reporting

The audit supports the following cautious claims:

1. verified researcher identities, persistent identifiers, publication provenance, master-publication consolidation, researcher-publication linking, lifecycle state and expert-discovery evidence are implemented as distinct data structures;
2. the pilot provides an operational response to several recurring author-disambiguation and institutional-provenance gaps;
3. local expert-evidence retrieval is fast enough to justify the pre-built JSON evidence-index architecture;
4. ranking effectiveness is **not yet established** by this audit and still requires expert-judged queries with measures such as Precision@k, Recall@k, MRR and nDCG;
5. expert-discovery quality depends on profile completeness: only two of five public indexed profiles contained declared research-interest evidence in this snapshot.

These aggregate values are intended for reproducibility documentation and pilot research reporting, not for institutional performance benchmarking.
