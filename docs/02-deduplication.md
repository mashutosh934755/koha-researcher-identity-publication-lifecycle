# Scopus–Web of Science Publication Deduplication

## Objective

The same publication may appear in Scopus and Web of Science. It must be displayed and counted once while preserving each source record.

## Normalization

Normalize DOI by lowercasing, trimming spaces, removing `doi:` and DOI URL prefixes, and removing trailing punctuation.

Normalize titles by decoding entities, lowercasing, normalizing ampersands, removing punctuation and repeated spaces, and applying Unicode normalization.

Normalize journals using ISSN/eISSN where available, then normalized journal title and publisher.

## Matching hierarchy

### 1. Exact DOI

An exact normalized DOI match is the highest-confidence duplicate signal.

### 2. Strong metadata match

When DOI is missing, compare:

```text
Exact normalized title
Same publication year
Same ISSN or normalized journal
Same first author or strongly similar author list
```

### 3. Probable fuzzy match

Compare title similarity, year, journal, ISSN and author similarity. Do not merge uncertain records automatically.

### 4. Manual review

The reviewer can merge, keep separate or leave unresolved.

## Storage model

```text
One master publication
├── Scopus source record
├── Web of Science source record
├── Crossref source record
└── ORCID source record
```

## Citation counts

Do not add source citation counts together. Preserve and display them separately:

```text
Scopus citations: 25
Web of Science times cited: 19
```

## Unique-publication calculation

```text
Unique publications = count of deduplicated master publications linked to the researcher
```

Example:

```text
Scopus records: 78
WoS records: 46
Matched overlap: 45
WoS-only: 1
Unique publications: 79
```
