# Installable reference release

This directory installs the sanitized implementation extracted from the validated Koha deployment. It does **not** ship credentials or production data.

## Prerequisites
- Debian/Ubuntu Koha package installation with a working instance.
- MariaDB/MySQL used by Koha.
- Root/sudo access.
- Perl dependencies already required by the included Koha scripts; Python 3 for the WoS helper.
- Licensed API access where applicable (Scopus / Web of Science). Crossref can be used with a contact mailto.

## Install
```bash
sudo RIMS_INSTITUTION_NAME="Example University" \
     SCOPUS_AFFILIATION_ID="YOUR_ID" \
     CROSSREF_MAILTO="library@example.edu" \
     ./install/install.sh <koha-instance>
```

Then copy/edit the generated config examples under `/etc/koha/sites/<instance>/`, keep them mode `600`, and run:
```bash
sudo ./install/verify.sh <koha-instance>
```

`install.sh` backs up replaced files under `/root/koha-rims-backup-<timestamp>` before modifying them. `rollback.sh` restores those files. Database objects are not automatically dropped during rollback.

## Scope of validation
The release contains production-derived application source that was syntax-checked on its source deployment. The generic installer itself still needs a clean Koha-instance integration test before the project should be described as universally one-command installable.
