# Expert Evidence and Ranking Principles

## Design objective

Expert ranking should prioritize topical relevance and verified institutional evidence. A large publication count must not make a researcher the top recommendation when the research topic is weakly aligned.

## Evidence hierarchy

The current deployed hierarchy is:

1. Literal exact declared research-area / research-interest phrase match
2. Singular/plural near-equivalent direct phrase match
3. Other direct declared research-area / research-interest match
4. Related semantic concept match
5. Fields of Science and Technology (OECD) alignment
6. Department / disciplinary alignment
7. Verified and current institutional status
8. Linked scholarly-output evidence as explanation and equal-relevance tie-break only

Persistent scholarly identifiers support identity verification and provenance. They should not be converted directly into expertise points merely because an identifier exists.

## Deployed V4.2 relevance model

The deployed pilot no longer adds publication volume to topical relevance.

Conceptually:

```text
Relevance(researcher, query) =
    direct_topic_evidence
  + semantic_evidence
  + OECD_alignment
  + disciplinary_alignment
  + lifecycle_and_verification_evidence
```

Linked scholarly-output volume remains visible as supporting evidence. When two researchers have equal relevance, output count may be used as the final tie-break.

This distinction matters because publication productivity and topical relevance are different constructs.

## Direct phrase precision

Direct declared profile evidence receives the strongest priority.

The V4.2 pilot distinguishes:

```text
Digital Library    vs Digital Library     -> literal exact
Digital Libraries  vs Digital Library     -> singular/plural near-equivalent
Digital Repository vs Digital Library     -> ordinary similarity/semantic path
```

Literal exact matching is intentionally stronger than singular/plural equivalence. This prevents a high-output researcher with only a near-equivalent phrase from outranking a lower-output researcher whose declared expertise exactly matches the user's query.

## Why publication volume is not part of relevance

Publication volume is not synonymous with expertise in the user's topic. It can be useful evidence that a profile has linked scholarly activity, but it should not override stronger topical evidence.

The deployed rule is:

```text
topical relevance first
-> lifecycle / verification evidence
-> publication count only if relevance is equal
```

## Multi-expert behaviour

Expert Discovery is not restricted to one result.

The current interface:

- considers all verified eligible researcher profiles;
- ranks current researchers by evidence score;
- applies a minimum relevance threshold;
- displays up to the top five current researchers;
- uses publication count only as the final tie-break when relevance scores are equal.

For larger institutional deployments, the same principle can be extended with server-side candidate retrieval and pagination rather than loading every full profile client-side.

## Explainable result

The result interface should provide both ranking and evidence. Example:

```text
Why this expert?
- Direct research-interest match: Digital Library
- Related semantic evidence: Institutional Repository
- Current verified researcher
- 12 linked research outputs available as scholarly evidence
```

The linked-output statement explains available evidence; it is not itself the reason the researcher was judged topically relevant.

## Evidence provenance

For reproducibility, the ranking layer should be able to identify which normalized profile field or scholarly relationship supported each explanation.

Recommended provenance metadata include:

- researcher identifier;
- evidence field;
- original evidence value;
- normalized evidence value;
- evidence source;
- lifecycle/verification state;
- evidence refresh timestamp;
- query-processing source (direct local or AI-assisted interpretation).

## Local evidence representation

A pre-built local evidence representation or index can decouple public matching from repeated runtime profile retrieval. It should contain only fields required for public discovery and must exclude private patron data, credentials, licensed raw API responses, internal network details and other restricted information.

Structured `researcher_research_areas` should be preferred where available. Legacy multiline `research_interests` may remain as a backward-compatible fallback.

## Failure behaviour

If optional external semantic interpretation is unavailable, direct local keyword/evidence matching should remain available.

External AI must not be allowed to:

- invent staff identities;
- select a researcher without local evidence;
- override lifecycle/verification state;
- turn publication count into unsupported topical expertise.

Graceful local fallback is preferable to allowing the entire Expert Discovery service to fail because an external AI service is unavailable.

## Evaluation note

Implemented ranking behaviour and research-evaluation metrics should be documented separately.

A formal evaluation should include judged queries covering:

- literal exact matches;
- singular/plural variants;
- natural-language questions;
- multiple genuinely relevant experts;
- weak/no-match cases;
- current versus former lifecycle cases;
- stale/incomplete profile evidence;
- AI-service unavailable fallback behaviour.
