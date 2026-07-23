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

When the Koha patron expiry date is earlier than the current date, the lifecycle job marks the researcher Former.

```text
employment_status = former
public_visibility = 1
sync_enabled = 0
relieving_date = patron expiry date
```

Existing publications and verified identity remain preserved.

## Reactivation

When the patron expiry is extended to a valid date:

```text
employment_status = active
public_visibility = 1
sync_enabled = 1
relieving_date = NULL
```

The existing researcher UUID, identifiers and publications are reused.

## Hide

```text
public_visibility = 0
sync_enabled = 0
profile_status = hidden
```

Hide does not delete the patron, publications or audit history and does not change Active/Former employment state.

## Restore

Restore must check the current patron expiry date:

- Valid expiry: restore as Active and sync-enabled.
- Expired patron: restore as Former with synchronization disabled.

## Permanent researcher-domain deletion

Only an authorised administrator should perform deletion after confirmation, reason capture and backup/export where required. Researcher tables may be cleaned, but the Koha `borrowers` record is preserved unless a separate authorised patron action is taken.

## Important distinction

```text
Patron expiry ≠ publication deletion
Former status ≠ researcher deletion
Hide ≠ deletion
Researcher deletion ≠ automatic patron deletion
```
