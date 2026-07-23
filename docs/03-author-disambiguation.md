# Author Disambiguation

## Purpose

A publication retrieved by name is not automatically assumed to belong to the researcher. The system evaluates multiple evidence types.

## Evidence weights

| Evidence | Maximum score |
|---|---:|
| Verified source identifier | 55 |
| Name variant | 20 |
| Affiliation | 15 |
| Timeline | 10 |
| Total | 100 |

## Identifier evidence

A matching verified Scopus Author ID or Web of Science ResearcherID is the strongest evidence.

## Name evidence

Normalize punctuation, case, commas and initials. Registered variants such as the following can be treated as equivalent when supported by stronger evidence:

```text
Subaveerapandiyan A
A Subaveerapandiyan
A. Subaveerapandiyan
Subaveerapandiyan, A.
A, Subaveerapandiyan
```

A common surname or initial alone is not enough for automatic confirmation.

## Affiliation evidence

Compare publication-level author affiliation with verified affiliation history using organisation name, aliases, department, email domain or persistent organisation identifiers where available.

## Timeline evidence

Compare publication date with affiliation start/end dates. A publication before the current affiliation may still belong to the researcher, but it should not automatically be classified as a current-institution publication.

## Decisions

| Evidence / score | Decision |
|---|---|
| Verified source identifier | Auto-confirm |
| Score >= 80 | Auto-confirm |
| Score 50–79 | Manual review |
| Score below 50 | Review or probable rejection |
| Conflicting verified identifier | Identity conflict |

## Manual review

The reviewer should see author name, registered variants, source author ID, verified identifiers, DOI, title, year, affiliation, score breakdown and source links.

Manual confirmations and rejections must not be overwritten by later automated jobs.
