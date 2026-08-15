# Evidence-Grounded Expert Discovery

## Purpose

The expert discovery layer addresses a different problem from a conventional researcher directory. A directory assumes that the user already knows a researcher name, department, school, or other structured attribute. Expert discovery begins with a research need: the user knows the topic, question, methodology, technology, subject area, or bibliometric problem but may not know the right institutional person to approach.

The pilot workflow is:

```text
Topic Need
-> Profile Data
-> Evidence
-> AI-Assisted Match (optional query interpretation)
-> Evidence-Grounded Ranking
-> Connect to Researcher Profile
```

## Evidence sources

The discovery layer should operate only on fields that are intentionally exposed for research information and discovery. Candidate evidence includes:

- verified researcher identity;
- Current / Former lifecycle status;
- research interests and keywords;
- Fields of Science and Technology (OECD) classifications;
- department, school and disciplinary affiliation;
- linked verified scholarly outputs;
- ORCID, Scopus Author ID and Web of Science ResearcherID as identity/provenance anchors.

Persistent identifiers establish identity and provenance. They do not by themselves prove topical expertise.

## Query processing

Two query paths are supported conceptually.

### Direct topic/keyword path

A concise topic such as `Open Access`, `Digital Repositories`, or `Research Metrics` can be normalized and matched directly against the local researcher evidence representation.

### Natural-language question path

A longer research question can optionally be passed through a semantic interpretation layer that extracts or expands concepts. The resulting concepts are then matched against verified local evidence.

The semantic component does **not** independently select the expert.

```text
Question
-> semantic interpretation / concept expansion
-> verified local researcher evidence
-> ranking
-> explanation
```

## Explainability

Every recommendation should be inspectable. A `Why this expert?` explanation may expose:

- direct research-interest match;
- related semantic concept match;
- OECD/disciplinary alignment;
- department/domain alignment;
- linked scholarly-output evidence;
- verified current institutional status.

The score is not intended to be self-justifying. The evidence is the primary explanation.

## Directory versus expert discovery

| Mode | User starts with | Main operation | Output |
|---|---|---|---|
| Researcher directory | Known person/attribute | Browse and filter | Matching profiles |
| Expert discovery | Research need/question | Evidence matching and ranking | Ranked profiles with reasons |

## Lifecycle rule

Current and Former status must remain visible as lifecycle evidence. Former researchers may remain discoverable for historical continuity, but an active support/contact use case should not silently treat Former status as equivalent to Current status.

## Responsible use

The expert discovery result is research-support decision assistance. It must not be used as an automated employment, promotion, performance, or disciplinary decision system. Research interests and profile evidence should be maintained and reviewable because stale or incomplete profile data can affect ranking quality.

## Ranganathan-inspired service principle

The prototype presentation describes the service goal as connecting every research question with an appropriate expert and reducing the user's time in locating trusted support. This is an application-oriented design principle inspired by user-centred library service; it is not presented as a replacement or alteration of Ranganathan's historical Five Laws.
