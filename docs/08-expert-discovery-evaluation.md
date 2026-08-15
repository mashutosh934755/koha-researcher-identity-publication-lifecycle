# Expert Discovery Evaluation Protocol

The pilot interface demonstrates feasibility. A Q1-level research claim about ranking effectiveness requires a reproducible evaluation beyond screenshots or anecdotal examples.

## 1. Query set

Construct a representative set of research information needs across multiple disciplines and query forms, for example:

- short research topics;
- natural-language research questions;
- methodology queries;
- technology/tool queries;
- bibliometric/research-support needs.

A future study can begin with 50-100 queries and expand as the researcher population grows.

## 2. Relevance ground truth

Ask independent domain experts, librarians, or research administrators to judge which institutional researchers are relevant to each query. Preserve graded relevance where possible (for example: highly relevant, relevant, partially relevant, not relevant).

## 3. Baselines

Compare the evidence-grounded approach against simpler baselines:

1. keyword-only research-interest matching;
2. department-only matching;
3. publication-volume ranking;
4. proposed multi-evidence ranking.

Where an AI-assisted query interpretation layer is used, also compare direct local matching against semantic expansion + local evidence ranking.

## 4. Ranking metrics

Recommended metrics include:

- Precision@k
- Recall@k
- Mean Reciprocal Rank (MRR)
- nDCG@k for graded relevance

Report the query set, candidate pool, relevance-judging process, tie handling, and exact ranking configuration.

## 5. Latency and resilience

Measure separately:

- query interpretation time;
- local evidence retrieval time;
- ranking time;
- total response time;
- fallback response time when an external semantic service is unavailable.

Use median and tail latency (for example P95) rather than reporting only a single best-case timing.

## 6. Explainability/user evaluation

A user study can assess:

- perceived relevance;
- explanation usefulness;
- transparency;
- trust in the recommendation;
- ease of finding the right researcher;
- intention to contact/use the recommended expert.

Use a documented Likert scale and report participant roles and sample size.

## 7. Data quality analysis

Expert ranking depends on profile evidence quality. Audit:

- missing research interests;
- stale interests;
- overly broad keywords;
- missing OECD fields;
- incorrect department/school values;
- lifecycle status errors;
- missing or incorrectly linked publications.

## 8. Responsible interpretation

The system recommends potentially relevant research contacts; it does not measure researcher quality. Ranking outputs should not be repurposed as automatic performance, hiring, promotion, or disciplinary scores.
