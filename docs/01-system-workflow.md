# Complete System Workflow

## 1. First-time user arrival

Library staff verify institutional eligibility and collect the user's name, official email, employee or enrolment identifier, department, designation, category, joining date and expected expiry date.

## 2. Existing patron search

Search Koha by employee/enrolment identifier, official email, mobile number, card number and full name. Reuse and update an existing record instead of creating a duplicate.

## 3. Patron creation

Create the Koha patron with category, branch, registration date, expiry date, username and communication preference. Koha generates the operational `borrowernumber`.

## 4. Patron activation email

Send membership details, card number, category, expiry date, OPAC URL, username and a secure password-setup/reset link. A mail failure must not roll back patron creation; it should be logged and available for resend.

## 5. Researcher eligibility

Only eligible patron categories proceed to researcher onboarding. Non-research users remain normal Koha patrons.

## 6. Researcher profile

Create `custom_profile_details` with pending verification, hidden public visibility and disabled synchronization. Generate a persistent `researcher_uuid`.

## 7. Researcher onboarding email

Ask the researcher to provide or review preferred publication name, ORCID, Scopus Author ID, Web of Science ResearcherID, name variants, affiliation history and research interests.

## 8. Identity completion

Store core profile data, external identifiers, verified name variants and current/previous affiliations. No photograph is required.

## 9. Verification

The library verifier checks the patron link, official email, identifiers, identifier conflicts, names, affiliations and employment state. Verified profiles become public and sync-enabled.

## 10. API synchronization

Create source-specific sync jobs for ORCID, Scopus, Web of Science and Crossref. Preserve raw responses according to licence and privacy policy, then normalize DOI, title, journal, dates, names and identifiers.

## 11. Publication deduplication

Create one master publication for the same work and preserve multiple source links. Use DOI first, then strong metadata matching, then fuzzy comparison and manual review.

## 12. Author disambiguation

Evaluate identifier, name, affiliation and timeline evidence. Auto-confirm strong matches and send uncertain cases to manual review. Preserve manual decisions during later automated jobs.

## 13. Public profile

Display verified identity, identifiers, affiliations, unique publications, source badges, source-specific citations and last synchronization time. Do not expose sensitive patron information.

## 14. Scheduled operation

Cron jobs synchronize active verified researchers, score publication links, recalculate metrics and record audit events.

## 15. Employment lifecycle

Koha patron expiry controls Active/Former state. Former profiles can remain public while synchronization is disabled. Extending the patron expiry reactivates the existing researcher identity and publications.

## 16. Administrative lifecycle

Hide temporarily removes public visibility without changing employment state. Restore recalculates Active/Former state from patron expiry. Permanent researcher-domain deletion preserves the Koha patron unless a separate authorised patron action is taken.
