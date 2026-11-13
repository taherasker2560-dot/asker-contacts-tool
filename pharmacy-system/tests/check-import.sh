#!/usr/bin/env bash
# بيجرب النقل من فارمافلاي على تاريخ تجريبي (2018–2026) في قاعدة Postgres مؤقتة. مابيلمسش Supabase.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-import.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PGURL="${PGURL:-postgresql:///postgres}"
DB="ph_import_$$"
psql "$PGURL" -qX -v ON_ERROR_STOP=1 -c "create database $DB"
trap 'psql "$PGURL" -qX -c "drop database if exists $DB" >/dev/null' EXIT
URL="${PGURL%/*}/$DB"
psql "$PGURL" -qX -c "do \$\$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
end \$\$"
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/stubs.sql
for f in db/[0-9][0-9]-*.sql; do psql "$URL" -qX -v ON_ERROR_STOP=1 -f "$f"; done
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/import-sample.sql
[ "${KEEP:-}" = 1 ] && { echo "DB: $URL"; trap - EXIT; }
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/import-checks.sql >/dev/null   # النتايج بتطلع كـ NOTICE
echo "IMPORT OK"
