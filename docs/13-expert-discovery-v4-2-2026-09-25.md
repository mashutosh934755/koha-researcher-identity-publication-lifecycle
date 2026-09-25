# Expert Discovery V4.2 Validation Note — 2026-09-25

## Scope

This note records the behaviour validated in the Bennett University pilot before sanitization/generalization for the public repository.

The production deployment itself is not reproduced here. Credentials, internal addresses, researcher photos, generated production index JSON and institution-specific private data are excluded.

## Validated query behaviour

### Direct topic query

A concise topic query such as:

```text
Digital Library
```

is handled through local profile evidence without requiring external semantic interpretation when a strong local match exists.

The tested pilot returned multiple current verified experts rather than forcing a single result.

### Exact versus plural-equivalent ranking

The deployed V4.2 ranking distinguishes literal exact phrases from singular/plural near-equivalents.

Observed test pattern:

```text
Query: Digital Library

Researcher A profile evidence: Digital Library
Researcher B profile evidence: Digital Libraries
Researcher C profile evidence: Digital Libraries
```

The literal exact profile phrase ranked above the plural-equivalent profiles.

When the plural-equivalent researchers had equal relevance, linked-output volume was used only as the final tie-break.

## Publication-count rule

Earlier pilot scoring allowed publication volume to contribute a small number of relevance points.

V4.2 changes this rule:

```text
Publication count is NOT part of topical relevance.
```

Publication/output volume remains:

- visible scholarly evidence;
- useful for explanation;
- available as a final tie-break when topical relevance is equal.

This prevents productivity volume from overriding a stronger topic match.

## Natural-language query path

A natural-language research question is optionally interpreted by DeepSeek.

The AI component is constrained to query understanding. It returns structured concepts used by the local ranker.

The local Koha evidence remains authoritative for:

- researcher identity;
- lifecycle state;
- verification state;
- research areas/interests;
- OECD/domain evidence;
- publication linkage;
- final ranking.

The external model is not allowed to invent or independently select institutional experts.

## Research-area source precedence

The public researcher directory and Expert Discovery pipeline were aligned so that structured `researcher_research_areas` values are preferred where available.

Legacy multiline `custom_profile_details.research_interests` remains a backward-compatible fallback for profiles that have not yet been migrated to structured research areas.

## DB-backed index

The pilot Expert Discovery V4 path uses a locally generated DB-backed index rather than repeatedly scraping or reconstructing every researcher card at query time.

The index is periodically refreshed by a systemd timer.

The public repository intentionally does not include generated production index JSON.

## Profile-photo integration

Expert result cards use the same public photo endpoint as the researcher directory:

```text
/cgi-bin/koha/opac-researcher-photo.pl?id=<borrowernumber>
```

The tested pilot confirmed successful image responses for current researcher profiles and displayed those images in Expert Discovery result cards.

Initials remain the intended fallback when a usable image is unavailable.

## Scale note

The current browser renderer displays up to five current researchers above the relevance threshold.

For a larger institutional deployment containing thousands of profiles, candidate retrieval should move toward a compact/server-side retrieval layer with pagination while preserving the same evidence hierarchy and explainability rules.

## Remaining research evaluation

This validation confirms implementation behaviour, not ranking effectiveness across all research domains.

A formal evaluation should use judged query sets and measures such as precision at k, recall, nDCG/MRR where appropriate, agreement between domain judges, and error analysis for:

- exact topic matches;
- semantic natural-language questions;
- interdisciplinary queries;
- multiple relevant experts;
- no-match cases;
- stale profile evidence;
- current/former lifecycle differences;
- external AI unavailable fallback.
