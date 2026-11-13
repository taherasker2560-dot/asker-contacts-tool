#!/usr/bin/env bash
# كاشيرين بيبيعوا آخر علبة في نفس اللحظة: واحد بس لازم ينجح، والرصيد مايبقاش بالسالب.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-concurrency.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PGURL="${PGURL:-postgresql:///postgres}"
DB="ph_race_$$"
psql "$PGURL" -qX -v ON_ERROR_STOP=1 -c "create database $DB"
trap 'psql "$PGURL" -qX -c "drop database if exists $DB" >/dev/null' EXIT
URL="${PGURL%/*}/$DB"
psql "$PGURL" -qX -c "do \$\$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
end \$\$"
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/stubs.sql
for f in db/[0-9][0-9]-*.sql; do psql "$URL" -qX -v ON_ERROR_STOP=1 -f "$f"; done
psql "$URL" -qX -v ON_ERROR_STOP=1 <<'SQL' >/dev/null
insert into ph.settings (pharmacy_name) values ('تجربة');
insert into ph.branches (name) values ('الفرع');
insert into auth.users values ('00000000-0000-0000-0000-0000000000a1');
insert into ph.staff (user_id, branch_id, name, role) values ('00000000-0000-0000-0000-0000000000a1', 1, 'المالك', 'owner');
insert into ph.locations (branch_id, name, kind, is_default_sale) values (1, 'الرئيسي', 'main', true);
insert into ph.cash_accounts (branch_id, name, kind) values (1, 'درج', 'drawer');
insert into ph.payment_methods values ('cash', 'كاش', 1), ('credit', 'آجل', null);
insert into ph.items (id, name_en, pack_parts, public_price) values (1, 'LAST BOX', 1, 10);
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false);
select ph.post_opening_stock(1::smallint, '[{"item_id":1,"packs":1}]');
SQL

sale() {  # $1 = رقم الفاتورة على الجهاز، $2 = يستنى قد إيه وهو ماسك العلبة
  psql "$URL" -qX -At 2>&1 <<SQL
set role authenticated;
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000a1', false) \g /dev/null
begin;
select ph.post_sale('{"client_uuid":"$1","lines":[{"item_id":1,"packs":1}],"payments":[{"method":"cash","amount":10}]}') ->> 'no';
select pg_sleep($2) \g /dev/null
commit;
SQL
}
TA=$(mktemp); TB=$(mktemp)
sale 00000000-0000-0000-0000-00000000aaaa 2 > "$TA" &
sleep 0.5
sale 00000000-0000-0000-0000-00000000bbbb 0 > "$TB" || true
wait
A=$(cat "$TA"); B=$(cat "$TB"); rm -f "$TA" "$TB"
echo "الكاشير الأول: $A"
echo "الكاشير التاني: $B"
LEFT=$(psql "$URL" -qXAt -c "select qty_units from ph.stock_balances where item_id = 1")
SALES=$(psql "$URL" -qXAt -c "select count(*) from ph.sales")
echo "الرصيد بعدهم: $LEFT · الفواتير: $SALES"
[[ "$A" == S-* && "$B" == *"الرصيد مايكفيش"* && "$LEFT" == "0.00" && "$SALES" == "1" ]] && echo "RACE OK" || { echo "RACE FAILED"; exit 1; }
