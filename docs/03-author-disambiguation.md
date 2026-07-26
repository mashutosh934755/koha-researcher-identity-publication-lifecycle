# Author Disambiguation

## What author disambiguation means

Author disambiguation is the process of deciding whether a publication really belongs to a particular researcher.

This is necessary because the same person's name may appear in many forms, while different people may also have the same or very similar names.

For example, all of the following may refer to the same person:

```text
Subaveerapandiyan A
A Subaveerapandiyan
A. Subaveerapandiyan
Subaveerapandiyan, A.
A, Subaveerapandiyan
```

However, a name match alone is not enough to prove that the publication belongs to that researcher.

## Two separate tasks

The system treats these as two different tasks:

```text
1. Fetch candidate publication records
2. Decide whether each record belongs to the researcher
```

A record may be found through an API search, but it must still be checked before it is confirmed.

## How publication data can be fetched

Publication records may be retrieved through:

```text
Scopus Author ID
Web of Science ResearcherID
ORCID
DOI
Author-name search
Affiliation search
```

The safest method is to use a verified source identifier. Name-based searching is used only when stronger identifiers are unavailable.

## ORCID is helpful but not mandatory

A researcher does not need an ORCID record for the system to work.

If ORCID is unavailable, publications may still be retrieved through a verified Scopus Author ID or Web of Science ResearcherID.

### Scopus example

```text
Researcher: Subaveerapandiyan A
Scopus Author ID: 57221391744
```

The system can request publications directly for that Scopus Author ID:

```text
Verified Scopus Author ID
→ Scopus API
→ Publications linked to that author profile
```

This is safer than searching only by name.

A librarian should still review the source profile before verification because Scopus can sometimes split one real researcher into more than one author profile. The reviewer should compare the name, affiliation, subject area, co-authors and known publications.

### Web of Science example

```text
Web of Science ResearcherID: AEK-5815-2022
```

The system can retrieve publications linked to the verified Web of Science profile:

```text
Verified Web of Science ResearcherID
→ Web of Science API
→ Publications linked to that researcher profile
```

## What happens when no persistent identifier is available

A researcher may have no ORCID, no verified Scopus Author ID and no Web of Science ResearcherID.

In that situation, the system searches for candidate records using the researcher's name and known affiliations. These records must not be treated as confirmed automatically.

The system should compare several types of evidence.

## Name evidence

Names are normalized before comparison. The system may ignore differences in:

```text
Capital letters
Punctuation
Commas
Periods
Spacing
Initial order
```

For example:

```text
Ashutosh Mishra
A Mishra
Ashutosh K Mishra
Mishra, Ashutosh
A. K. Mishra
```

A complete and distinctive name is useful evidence. A common surname and initial, such as `A Mishra`, is weak evidence because it may match many people.

## Affiliation evidence

The system compares the affiliation in the publication record with the researcher's verified affiliation history.

Possible matching evidence includes:

```text
Institution name
Institution aliases
Department
City and country
Official email domain
ROR or another organisation identifier
```

For example, these may refer to the same organisation:

```text
Bennett University
Bennett Univ
Department of Library, Bennett University
Bennett University, Greater Noida
```

An affiliation match increases confidence, but it is not sufficient by itself.

## Timeline evidence

The publication date is compared with the researcher's affiliation start and end dates.

Example:

```text
Researcher joined Bennett University: 2025
Publication year: 2026
Publication affiliation: Bennett University
```

This supports classification as a current-institution publication.

A publication from 2021 with a different institution may still belong to the same researcher, but it should not be counted as a Bennett University publication.

The system must therefore keep these two decisions separate:

```text
Does this publication belong to the researcher?
Was it produced during the current institutional affiliation?
```

## DOI and publication matching

When a Scopus record and a Web of Science record have the same normalized DOI, they are very likely to describe the same publication.

When DOI is missing, the system can compare:

```text
Normalized title
Publication year
Journal or ISSN
Author list
Affiliation
```

Uncertain matches should be sent to manual review rather than merged automatically.

## Co-author evidence

A candidate publication is more likely to belong to the researcher when it includes co-authors who already appear in confirmed publications.

Co-author matching is supporting evidence only. It must not be used as the only proof because different researchers may work with the same people.

## Subject-area evidence

The system may compare the candidate publication with the researcher's verified research areas.

For example, a researcher known for:

```text
Library and Information Science
Scholarly Communication
Bibliometrics
Open Access
```

is more likely to match a publication in those areas than an unrelated publication in cardiac surgery or astrophysics.

Subject similarity is useful supporting evidence, but it must not override a conflicting verified identifier.

## Email evidence

Some source records contain an author email address. A match with the researcher's verified institutional email is strong evidence.

Email addresses used for internal verification must not automatically be shown on the public profile.

## Matching the same author across Scopus and Web of Science

Consider the following two records.

### Scopus record

```text
Name: A Subaveerapandiyan
Scopus Author ID: 57221391744
Affiliation: Bennett University
Title: XYZ
DOI: 10.1234/example
```

### Web of Science record

```text
Name: Subaveerapandiyan A
Web of Science ResearcherID: AEK-5815-2022
Affiliation: Bennett Univ
Title: XYZ
DOI: 10.1234/example
```

The system compares:

```text
DOI
Normalized title
Publication year
Affiliation
Registered name variants
Verified source identifiers
```

When the evidence agrees, both source records are linked to one master publication:

```text
One master publication
├── Scopus source record
└── Web of Science source record
```

The publication is counted once, not twice.

## Primary evidence score

The current primary scoring model is:

| Evidence | Maximum score |
|---|---:|
| Verified source identifier | 55 |
| Name variant | 20 |
| Affiliation | 15 |
| Timeline | 10 |
| Total | 100 |

### Example with a verified identifier

```text
Verified source identifier: 55
Name match:                20
Affiliation match:         15
Timeline match:            10
Total:                    100
Decision: Auto-confirm
```

### Important limitation of this model

Without a verified source identifier, the maximum possible score is:

```text
Name 20 + Affiliation 15 + Timeline 10 = 45
```

This means that a candidate without a verified identifier cannot reach the current manual-review threshold of 50.

That behaviour is deliberately conservative, but it also means every identifier-free case requires manual review or a separate secondary scoring model.

## Recommended decision logic

The safest practical workflow is:

```text
Verified Scopus or Web of Science identifier matches
→ Auto-confirm, unless conflicting evidence exists

No verified identifier
→ Use secondary metadata evidence
→ Send uncertain cases to manual review
```

Possible secondary evidence may include:

| Evidence | Suggested role |
|---|---|
| Exact DOI from an institutional CV or trusted local record | Strong evidence |
| Verified institutional email match | Strong evidence |
| Full-name or registered name-variant match | Supporting evidence |
| Current or historical affiliation match | Supporting evidence |
| Publication timeline match | Supporting evidence |
| Repeated co-author network | Supporting evidence |
| Subject-area similarity | Supporting evidence |
| Journal or department consistency | Supporting evidence |

Any secondary score must be normalized and tested against real examples before production use.

## Decision table

| Evidence or result | Decision |
|---|---|
| Verified source identifier with no conflict | Auto-confirm |
| Primary score 80 or above | Auto-confirm |
| Primary score 50–79 | Manual review |
| Primary score below 50 | Manual review, unresolved or probable rejection |
| Conflicting verified identifier | Identity conflict |
| Exact DOI but uncertain author identity | Manual review |
| Manual decision already exists | Preserve the manual decision |

## Safe end-to-end workflow

```text
Researcher profile created
↓
ORCID available?
├── Yes → Verify ORCID
└── No
     ↓
Scopus Author ID available?
├── Yes → Verify the Scopus profile
└── No
     ↓
Web of Science ResearcherID available?
├── Yes → Verify the Web of Science profile
└── No
     ↓
Search by name and affiliation
     ↓
Create candidate publication records
     ↓
Compare DOI, email, co-authors, subject, affiliation and timeline
     ↓
Manual librarian review
     ↓
Confirm, reject or leave unresolved
```

## Manual review screen

The reviewer should be able to see:

```text
Researcher name
Registered name variants
Source author name
Source author identifier
Verified identifiers
DOI
Publication title
Publication year
Journal
Affiliation
Email evidence when permitted
Co-author evidence
Subject-area evidence
Timeline evidence
Score breakdown
Source links
Previous manual decision
```

The reviewer should be able to choose:

```text
Confirm
Reject
Keep unresolved
Mark identity conflict
```

Manual confirmations and rejections must never be overwritten by later automated jobs.

## Core rule

> A name can be used to find candidate publications, but a name alone must not be used to confirm author identity.
