# Expert Evidence and Ranking Principles

## Design objective

Expert ranking should prioritize topical relevance and verified institutional evidence. A large publication count must not make a researcher the top recommendation when the research topic is weakly aligned.

## Evidence hierarchy

A practical evidence hierarchy is:

1. Direct declared research-interest / keyword match
2. Related semantic concept match
3. Fields of Science and Technology (OECD) alignment
4. Department / disciplinary alignment
5. Verified and current institutional status
6. Linked scholarly-output evidence

Persistent scholarly identifiers support identity verification and provenance. They should not be converted directly into expertise points merely because an identifier exists.

## Conceptual score

The pilot can be described using a generic evidence function:

```text
ExpertScore(researcher, query) =
    w1 * direct_topic_evidence
  + w2 * semantic_evidence
  + w3 * OECD_alignment
  + w4 * disciplinary_alignment
  + w5 * lifecycle_and_verification_evidence
  + w6 * scholarly_output_support
```

The exact deployed weights must be documented from the implementation before they are reported as experimental facts. Documentation should distinguish **implemented weights** from **proposed/evaluation weights**.

## Why publication volume receives limited influence

Publication volume is not synonymous with expertise in the user's topic. It is supporting scholarly evidence only. The ranking should therefore prevent a high-output researcher with weak topic alignment from outranking a lower-output researcher with a strong verified topic match solely because of publication count.

## Explainable result

The result interface should provide both ranking and evidence. Example:

```text
Why this expert?
- Direct research-interest match: Digital Repositories
- Disciplinary alignment: Library and Information Science
- Linked scholarly outputs available
- Current verified researcher
```

## Evidence provenance

For reproducibility, the ranking layer should be able to identify which normalized profile field or scholarly relationship supported each explanation. Recommended provenance metadata include researcher identifier, evidence field, normalized evidence value, evidence source, lifecycle/verification state, and evidence refresh timestamp.

## Local evidence representation

A pre-built local evidence representation or index can decouple public matching from repeated runtime profile retrieval. It should contain only the fields required for public discovery and must exclude private patron data, credentials, licensed raw API responses, and other restricted information.

## Failure behaviour

If optional external semantic interpretation is unavailable, direct local keyword/evidence matching should remain available. This graceful degradation is preferable to allowing the entire expert discovery service to fail because an external AI service is unavailable.
