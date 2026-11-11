#!/usr/bin/env bash
# بيجرب مسودة القاعدة على Postgres محلي في قاعدة مؤقتة وبيمسحها في الآخر.
# مابيلمسش Supabase. الاستخدام: PGURL=postgres://user@localhost/postgres bash pharmacy-system/tests/check-db.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PGURL="${PGURL:-postgres://postgres@localhost/postgres}"
DB="ph_draft_test_$$"
psql "$PGURL" -qX -v ON_ERROR_STOP=1 -c "create database $DB"
trap 'psql "$PGURL" -qX -c "drop database if exists $DB" >/dev/null' EXIT
URL="${PGURL%/*}/$DB"
# role authenticated بتتعمل مرة واحدة على السيرفر كله
psql "$PGURL" -qX -c "do \$\$ begin if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if; end \$\$"
sed '/^create role authenticated/d' tests/stubs.sql | psql "$URL" -qX -v ON_ERROR_STOP=1
psql "$URL" -qX -v ON_ERROR_STOP=1 -f db/schema-draft.sql
psql "$URL" -qX -v ON_ERROR_STOP=1 -f db/phase1-views.sql
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/checks.sql
echo "DB OK"
