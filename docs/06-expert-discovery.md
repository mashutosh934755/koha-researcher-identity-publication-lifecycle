# Evidence-Grounded Expert Discovery

## Purpose

The expert discovery layer addresses a different problem from a conventional researcher directory. A directory assumes that the user already knows a researcher name, department, school, or other structured attribute. Expert discovery begins with a research need: the user knows the topic, question, methodology, technology, subject area, or bibliometric problem but may not know the right institutional person to approach.

The current pilot workflow is:

```text
Research need
-> direct local topic matching for concise queries
   OR optional DeepSeek query interpretation for natural-language questions
-> verified local researcher evidence
-> evidence-grounded ranking
-> explanation
-> researcher profile
```

## Evidence sources

The discovery layer should operate only on fields intentionally exposed for research information and discovery. Candidate evidence includes:

- verified researcher identity;
- Current / Former lifecycle status;
- structured Research Areas & Expertise;
- legacy research interests and keywords as backward-compatible fallback;
- Fields of Science and Technology (OECD) classifications;
- department, school and disciplinary affiliation;
- linked verified scholarly outputs;
- ORCID, Scopus Author ID and Web of Science ResearcherID as identity/provenance anchors.

Persistent identifiers establish identity and provenance. They do not by themselves prove topical expertise.

## Local evidence index

The deployed pilot uses a DB-backed public discovery index generated from Koha-side verified profile data. The index is intended to contain only public discovery fields required by the ranker.

The generated production index is not committed to the public repository. It may contain institution-specific profile content and should be rebuilt locally.

A periodic systemd timer can refresh the index so newly verified profiles, research areas, lifecycle changes and publication counts become available to Expert Discovery without manual regeneration.

## Query processing

Two query paths are supported.

### Direct topic/keyword path

A concise query such as `Open Access`, `Digital Library`, `Bibliometrics` or `Research Metrics` can be matched directly against local profile evidence. This avoids unnecessary external-AI latency for short subject-style searches.

### Natural-language question path

A longer research question can optionally be passed through DeepSeek as a **query-understanding component**. The service extracts structured concepts such as:

- primary topic;
- research domain;
- keywords;
- methodologies;
- related concepts;
- context;
- query intent.

The returned concepts are then matched against verified local Koha evidence.

The external semantic component does **not** select the expert.

```text
Question
-> DeepSeek concept interpretation
-> verified local Koha researcher evidence
-> deterministic evidence scoring
-> ranking
-> explanation
```

If the external AI service is unavailable, local evidence matching remains available as a fallback.

## V4.2 matching behaviour

The deployed V4.2 pilot applies these principles:

1. Literal exact profile phrase match has the strongest direct-match priority.
2. Lightweight singular/plural equivalents are treated as near-equivalent but not literal exact matches.
3. Direct declared Research Areas / Research Interests remain stronger than AI-expanded semantic concepts.
4. OECD and department/domain matches provide secondary evidence.
5. Current and verified institutional state is explicit evidence.
6. Publication/output volume does not increase topical relevance; it is supporting evidence and can be used only as an equal-relevance tie-break.
7. Multiple researchers may be returned for one topic. The current result interface displays up to five current researchers above the relevance threshold.

Example:

```text
Query: Digital Library

Profile A: Digital Library     -> literal exact match
Profile B: Digital Libraries  -> singular/plural near-equivalent
Profile C: Digital Libraries  -> singular/plural near-equivalent

A ranks above B/C on topical match.
If B and C have equal relevance, linked-output volume may break the tie.
```

## Profile-photo behaviour

Expert result cards use the same public researcher-photo endpoint as the researcher directory:

```text
/cgi-bin/koha/opac-researcher-photo.pl?id=<borrowernumber>
```

If a usable profile photo is not available, initials should remain visible as fallback. Production researcher images themselves are not included in the public repository.

## Explainability

Every recommendation should be inspectable. A `Why this expert?` explanation may expose:

- direct research-interest / research-area match;
- related semantic concept match;
- OECD/disciplinary alignment;
- department/domain alignment;
- linked scholarly-output evidence;
- verified current institutional status.

The score is not intended to be self-justifying. The matched local evidence is the primary explanation.

## Directory versus expert discovery

| Mode | User starts with | Main operation | Output |
|---|---|---|---|
| Researcher directory | Known person/attribute | Browse and filter | Matching profiles |
| Expert discovery | Research need/question | Evidence matching and ranking | Ranked profiles with reasons |

## Lifecycle rule

Current and Former status must remain visible as lifecycle evidence. Former researchers may remain discoverable for historical continuity, but an active support/contact use case should not silently treat Former status as equivalent to Current status.

## Responsible use

The expert discovery result is research-support decision assistance. It must not be used as an automated employment, promotion, performance, disciplinary, funding, or other high-impact personnel decision system.

Research interests and profile evidence should be maintained and reviewable because stale or incomplete profile data can affect ranking quality.

## Ranganathan-inspired service principle

The prototype presentation describes the service goal as connecting every research question with an appropriate expert and reducing the user's time in locating trusted support. This is an application-oriented design principle inspired by user-centred library service; it is not presented as a replacement or alteration of Ranganathan's historical Five Laws.
