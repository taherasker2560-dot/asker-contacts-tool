#!/usr/bin/env bash
# النسخة الاحتياطية بترجع فعلًا؟ يوم الشغل التجريبي (checks.sql) ← pg_dump ← pg_restore في قاعدة تانية ← الفحص الذاتي والأعداد.
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
new_db ph_backup
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/checks.sql >/dev/null 2>&1
DUMP=$(mktemp); R="${DB}_r"; RURL="${PGURL%/*}/$R"
trap 'rm -f "$DUMP"; psql "$PGURL" -qX -c "drop database if exists $DB" -c "drop database if exists $R" >/dev/null' EXIT
pg_dump -Fc -Z 6 -f "$DUMP" "$URL"
psql "$PGURL" -qX -c "create database $R"
pg_restore --no-owner --exit-on-error -d "$RURL" "$DUMP"
q="select (select count(*) from ph.sales) || '|' || (select count(*) from ph.stock_moves) || '|' || (select count(*) from ph.party_ledger) || '|' || (select sum(qty_units) from ph.stock_balances)"
A=$(psql "$URL" -qXAt -c "$q"); B=$(psql "$RURL" -qXAt -c "$q")
BAD=$(psql "$RURL" -qXAt -c "select count(*) from ph.health_check() where not ok")
echo "  الأصل $A · النسخة $B · قواعد فشلت $BAD · حجم النسخة $(du -h "$DUMP" | cut -f1)"
[ "$A" = "$B" ] && [ "$BAD" = 0 ] && echo "RESTORE OK" || { echo "RESTORE FAILED"; exit 1; }
