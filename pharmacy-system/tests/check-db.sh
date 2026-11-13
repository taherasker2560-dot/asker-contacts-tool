#!/usr/bin/env bash
# بيجرب قاعدة البيانات على Postgres محلي في قاعدة مؤقتة وبيمسحها في الآخر. مابيلمسش Supabase.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-db.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PGURL="${PGURL:-postgresql:///postgres}"
DB="ph_test_$$"
psql "$PGURL" -qX -v ON_ERROR_STOP=1 -c "create database $DB"
trap 'psql "$PGURL" -qX -c "drop database if exists $DB" >/dev/null' EXIT
URL="${PGURL%/*}/$DB"
# roles بتاعة Supabase (مرة واحدة على السيرفر)
psql "$PGURL" -qX -c "do \$\$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
end \$\$"
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/stubs.sql
for f in db/[0-9][0-9]-*.sql; do
  psql "$URL" -qX -v ON_ERROR_STOP=1 -f "$f"
done
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/checks.sql >/dev/null   # النتايج بتطلع كـ NOTICE
echo "DB OK"
