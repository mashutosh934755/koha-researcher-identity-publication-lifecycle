# Configuration Guide

Copy `config/researcher-system.example.conf` to a protected server location and enter local values there.

```bash
sudo mkdir -p /etc/koha/researcher-system
sudo cp config/researcher-system.example.conf \
  /etc/koha/researcher-system/researcher-system.conf
sudo chmod 600 /etc/koha/researcher-system/researcher-system.conf
```

## General settings

- Institution display name
- Public OPAC base URL
- Staff interface base URL
- Time zone
- Eligible researcher patron categories
- Public visibility rules
- Active/Former lifecycle rules

## API settings

### ORCID

Configure the public API base URL and authorised credentials where required.

### Scopus

Configure the Elsevier API base URL, API key and institutional token where licensed.

### Web of Science

Configure the approved Starter or other authorised API endpoint and API key.

### Crossref

Configure the REST API endpoint and a contact email for polite-pool requests.

## Email settings

Configure:

```text
SMTP host
SMTP port
SMTP username
SMTP password
Encryption
Sender name
Sender address
Reply-to address
```

Use a secure password or app password. Do not commit the real configuration file.

## Deduplication defaults

```text
Exact normalized DOI match: enabled
Title + year + journal/ISSN match: enabled
Manual-review threshold: 60
Automatic-merge threshold: 85
```

## Disambiguation defaults

```text
Identifier weight: 55
Name weight: 20
Affiliation weight: 15
Timeline weight: 10
Auto-confirm threshold: 80
Manual-review minimum: 50
```

## Lifecycle defaults

```text
Use Koha patron expiry: enabled
Former profiles remain public: enabled
Former researcher synchronization: disabled
```
