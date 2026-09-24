# Post-Hardening Validation — September 2026

This document records the key production-hardening controls validated after the original 15 August 2026 pilot audit. It is not a replacement for the August baseline snapshot; it documents subsequent corrective controls and regression checks.

## Why a second validation phase was required

Deeper operational testing exposed realistic research-information failure modes: stale public identifiers, source-author IDs changing over time, stale source links, source-link counts being mistaken for unique-publication counts, score inflation, duplicate review rows, source jobs overwriting later scores, Crossref being incorrectly treated like an author-bound source, and source-native author-name representations being lost.

## Validated controls

### Authoritative identifier gate

Production synchronization and disambiguation now use identifiers that are verified, primary, and active in the authoritative identifier registry. Denormalized public-profile values are not accepted as the authoritative synchronization key.

### Identifier-change lifecycle

When a verified Scopus or WoS identifier changes, old identifier-bound links are quarantined for review, old source-specific identity cache/name variants are invalidated, master publication records and provenance are preserved, and the change can be audited.

### Evidence-derived disambiguation score

The primary score remains 55 identifier + 20 name + 15 affiliation + 10 timeline. Automatic processing no longer inflates an evidence-derived score to 100 solely because an identifier exists. Duplicate unresolved case creation is also prevented.

### Current-set reconciliation

Scopus synchronization includes a conservative current-set reconciliation step. It retires/quarantines absent source links only after a complete successful set has been processed. A partial or failed API response does not trigger destructive reconciliation.

### Source visibility semantics

```text
Overall Publications = confirmed unique master publications
Scopus              = confirmed Scopus researcher links
WoS                 = confirmed WoS researcher links
Crossref            = Crossref provenance on confirmed publications
```

This prevents stale Scopus provenance from displaying a Scopus badge while allowing a publication to remain public if it is still validly linked through another source such as WoS.

### Crossref provenance behavior

Crossref is treated as DOI/bibliographic enrichment. It is not forced to have a dedicated researcher-author link. Crossref visibility is derived from provenance attached to an already-confirmed researcher publication.

### Source-faithful author names

The production name cache preserves source-native name evidence. Scopus stores an official display representation and the indexed/published form. WoS first uses current authoritative ResearcherID-bound evidence and can use a controlled confirmed-publication fallback when identifier propagation is incomplete. The extraction method is recorded.

## Validated scheduling order

```text
02:20  main/Scopus publication sync
02:35  WoS publication sync
03:10  official Scopus/WoS author-name sync
03:35  Crossref enrichment
03:40  disambiguation refresh

17,47 * * * *  WoS automatic/incremental synchronization
```

A frequent lifecycle reconciliation job separately maintains Current/Former state from patron/affiliation validity.

## Regression example: one master publication, multiple sources

A validated profile can have one unique publication with one confirmed Scopus link, one confirmed WoS link and one Crossref provenance record. The public profile must show one publication, not two or three.

A second validated scenario demonstrated that a publication may remain part of the overall publication set through WoS even after its Scopus relationship is quarantined. In that case the publication remains visible, the WoS badge remains visible, and the stale Scopus badge disappears.

## Reproducibility

See [Production Hardening and Reproducible Koha Deployment Guide](11-production-hardening-and-reproducible-deployment.md) for implementation rules, cron examples, validation SQL and safe deployment commands.

## Interpretation

The September hardening phase strengthens the claim that the system is provenance-aware and lifecycle-aware. It should not be interpreted as a formal accuracy benchmark for expert ranking or universal author disambiguation. Large-scale labelled evaluation and multi-institutional validation remain future work.