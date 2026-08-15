# Researcher Lifecycle Management

## Active researcher

A verified researcher with a valid Koha patron expiry date remains active and eligible for synchronization.

```text
employment_status = active
public_visibility = 1
sync_enabled = 1
relieving_date = NULL
```

## Former researcher

When the institutional patron/employment lifecycle indicates that the researcher has left, the lifecycle process marks the researcher Former.

```text
employment_status = former
public_visibility = 1
sync_enabled = 0
relieving_date = recorded affiliation end date
```

Existing publications, persistent researcher identity, verified identifiers, name variants, affiliation history, audit history, and researcher-publication links remain preserved. The former profile can therefore remain available as a historical institutional research record while current-only discovery can exclude it.

## No-dues / separation handling

A no-dues or separation event is treated as a **lifecycle transition, not a deletion event**. The system should close the current affiliation period and transition the researcher to Former while preserving the same researcher UUID and scholarly record.

```text
No-dues / separation completed
-> close current affiliation period
-> record relieving / affiliation end date
-> employment_status = former
-> sync_enabled = 0
-> preserve researcher UUID
-> preserve ORCID / Scopus / WoS identifiers
-> preserve publications and source provenance
-> preserve audit history
```

This prevents historical publications from disappearing merely because a person leaves the institution.

## Rejoining after no-dues / separation

If the same faculty member or researcher later rejoins, the system must first search for the existing researcher identity rather than creating a new researcher profile. Matching should use the persistent researcher UUID and verified scholarly identifiers where available, with institutional identity evidence and librarian review for ambiguous cases.

When the existing identity is confirmed:

```text
Rejoining event
-> locate existing researcher identity
-> preserve researcher UUID
-> preserve historical affiliation period
-> create a new current affiliation period
-> update current department / designation where required
-> employment_status = active
-> relieving_date = NULL for the current affiliation
-> public_visibility = 1
-> sync_enabled = 1
-> reuse verified scholarly identifiers
-> reuse master publications and researcher-publication links
-> run incremental synchronization for new outputs
-> write reactivation event to audit history
```

The earlier affiliation must not be overwritten. A researcher may therefore have multiple affiliation periods, for example:

```text
Affiliation period 1: joined -> separated / no-dues
Affiliation period 2: rejoined -> present
```

Public profile and expert discovery should use the **current active affiliation** for current-person recommendations while retaining historical affiliation periods for provenance and publication interpretation.

## Reactivation

When a previously Former researcher becomes institutionally active again, the existing researcher identity is reactivated rather than duplicated.

```text
employment_status = active
public_visibility = 1
sync_enabled = 1
relieving_date = NULL
```

The existing researcher UUID, identifiers, publications, manual decisions, and audit history are reused. New publication synchronization is incremental and does not recreate already deduplicated master publications.

## Expert-discovery lifecycle rule

Lifecycle state affects recommendation eligibility:

- Current, verified researchers can participate in current expert discovery.
- Former researchers remain available in the historical researcher directory when public visibility is enabled.
- Former researchers should not normally be presented as currently available institutional experts unless a specific historical search mode is requested.
- A rejoined researcher becomes eligible for current expert discovery again after reactivation and verification of the new current affiliation.

## Hide

```text
public_visibility = 0
sync_enabled = 0
profile_status = hidden
```

Hide does not delete the patron, publications or audit history and does not change Active/Former employment state.

## Restore

Restore must check the current institutional lifecycle state:

- Valid/current affiliation: restore as Active and sync-enabled.
- Ended affiliation: restore as Former with synchronization disabled.

## Permanent researcher-domain deletion

Only an authorised administrator should perform deletion after confirmation, reason capture and backup/export where required. Researcher tables may be cleaned, but the Koha `borrowers` record is preserved unless a separate authorised patron action is taken.

## Important distinction

```text
No-dues / separation != publication deletion
Former status != researcher deletion
Rejoining != creation of a second researcher identity
Hide != deletion
Researcher deletion != automatic patron deletion
```
