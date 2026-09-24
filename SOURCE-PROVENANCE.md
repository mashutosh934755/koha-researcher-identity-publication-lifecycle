# Source provenance

This release was prepared from a production Koha pilot implementation and sanitized before publication.

Removed from the public tree:
- production credentials and protected configuration files;
- patron/researcher data and API payloads;
- private/internal network addresses;
- deployment-specific institution names and identifiers;
- production backup tables and SQL DEFINER clauses;
- collector audit artifacts.

The included schema is structure-only. No production data is included.

Institution-specific values are rendered at install time from environment variables or protected local configuration.
