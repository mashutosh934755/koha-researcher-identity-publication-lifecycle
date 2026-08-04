# Source-code release process

This repository must not receive a raw production audit archive. Production audits can contain patron data, internal hostnames, licensed API responses, logs, credentials, and operational details.

## 1. Export the implementation safely

On the Koha server, clone or download this repository and run:

```bash
sudo bash tools/export-live-system-for-github.sh INSTANCE
```

Replace `INSTANCE` with the local Koha instance name.

The exporter collects only:

- OPAC researcher CGI programs
- OPAC Template Toolkit files
- staff verification CGI and template
- onboarding, publication, disambiguation, lifecycle and WoS workers when present
- researcher-related cron definitions
- database `CREATE TABLE` statements only
- file hashes and an inventory

It does not intentionally export:

- patron rows
- researcher production records
- email addresses
- photographs
- API keys or tokens
- Koha passwords
- SMTP credentials
- raw Scopus/WoS/Crossref responses
- logs
- database data dumps

## 2. Review the export

The script stops when its basic secret scan detects likely credentials or personal email addresses. Review all exported files manually before publication.

Required checks:

```bash
EXPORT_DIR=/path/to/koha-researcher-github-export-TIMESTAMP

grep -RInE 'Bennett|bulibrary|10\.[0-9]+\.[0-9]+\.[0-9]+|@bennett|api[_-]?key|client_secret|access_token|password' "$EXPORT_DIR" || true

grep -RInE '^INSERT INTO|^REPLACE INTO' "$EXPORT_DIR/database/schema" || true
```

The schema directory must contain structure only. No `INSERT INTO` or `REPLACE INTO` statements should be present.

## 3. Upload the reviewed export

After review, copy the exported directories into the matching repository paths:

```text
src/
scripts/
database/schema/
```

Do not overwrite documentation without reviewing the diff.

## 4. Validate before merge

Run Perl syntax checks in a Koha test environment:

```bash
export PERL5LIB=/usr/share/koha/lib
find src scripts -type f -name '*.pl' -print0 |
while IFS= read -r -d '' file; do
  perl -I/usr/share/koha/lib -c "$file"
done
```

Validate Python and shell workers where present:

```bash
find scripts -type f -name '*.py' -exec python3 -m py_compile {} \;
find scripts -type f -name '*.sh' -exec bash -n {} \;
```

Then verify:

- database schema applies to a fresh Koha test database;
- the staff researcher-verification page loads;
- the OPAC directory and profile pages load;
- no API secret is committed;
- no production identity or publication data is committed;
- cron files use placeholders rather than a production instance name;
- hide, restore, delete, active and former lifecycle tests pass.

## 5. Public-release rule

The repository is currently public. Only sanitized, redistributable source code should be committed. Licensed API datasets and institution-specific secrets must remain outside GitHub.
