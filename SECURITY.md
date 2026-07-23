# Security and Privacy

## Never commit

- Koha database passwords
- API keys, access tokens or client secrets
- SMTP credentials
- `koha-conf.xml`
- Patron names, emails, mobile numbers or addresses
- Employee or enrolment identifiers
- Researcher photographs
- Production database dumps
- Raw licensed Scopus or Web of Science datasets
- Production logs, cookies, sessions or CSRF tokens
- Private server IPs and internal URLs where disclosure is not authorised

## Required controls

- Staff authentication
- Role-based permissions
- CSRF protection
- Parameterised SQL
- Input validation
- Output escaping
- HTTPS
- Restricted configuration permissions
- Audit logging
- Backup before destructive actions
- Expiring email-verification links
- API rate-limit handling

## Public-profile privacy

The public profile should not expose private email, personal mobile number, residential address, password data, staff notes, raw API responses, or internal identifiers.

## Licensed data

Scopus and Web of Science data may be subject to subscription and redistribution restrictions. Publish only metadata and metrics permitted under the organisation's agreements.

## Incident response

If a secret is committed:

1. Revoke or rotate it immediately.
2. Remove it from the current files.
3. Rewrite Git history when required.
4. Review access logs.
5. Document the incident and corrective action.
