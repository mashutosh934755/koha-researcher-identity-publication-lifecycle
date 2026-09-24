#!/usr/bin/env bash
set -euo pipefail

INSTANCE="${KOHA_INSTANCE:-INSTANCE}"
export KOHA_INSTANCE="$INSTANCE"
export KOHA_CONF="/etc/koha/sites/$INSTANCE/koha-conf.xml"
export PERL5LIB="/usr/share/koha/lib"

exec /usr/bin/python3 /usr/share/koha/bin/bu-wos-publication-sync.py "$@"
