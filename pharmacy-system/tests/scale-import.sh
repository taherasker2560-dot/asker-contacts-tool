#!/usr/bin/env bash
# قياس سرعة النقل على حجم شبه 8 سنين شغل (داتا متولّدة، مش داتا الصيدلية).
# الاستخدام: DAYS=2920 SALES_PER_DAY=300 PGURL=postgresql:///postgres bash pharmacy-system/tests/scale-import.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
DAYS="${DAYS:-2920}"; SPD="${SALES_PER_DAY:-300}"
new_db ph_scale
psql "$URL" -qX -v ON_ERROR_STOP=1 -v days="$DAYS" -v spd="$SPD" <<'SQL'
insert into ph.settings (pharmacy_name) values ('قياس');
insert into ph.branches (name) values ('الفرع');
insert into ph.cash_accounts (branch_id, name, kind) values (1, 'درج', 'drawer');
insert into ph.payment_methods values ('cash', 'كاش', 1), ('credit', 'آجل', null);
insert into stage.locations values ('S1', 'الرئيسي', 'main', null, true, true);
insert into stage.suppliers select 'V' || g, 'مورد ' || g, 'warehouse', null from generate_series(1, 10) g;
insert into stage.customers select 'C' || g, 'عميل ' || g, array['010' || lpad(g::text, 8, '0')], 1000, '2018-01-01' from generate_series(1, 2000) g;
insert into stage.items (code, name_en, pack_parts, public_price, category)
  select g, 'ITEM ' || g, (array[1, 1, 3, 2])[1 + g % 4], 10 + g % 200, 'cat' || g % 20 from generate_series(1, 5000) g;
insert into stage.purchases select 'P' || d || '-' || k, null, 'V' || (1 + k % 10), 'D' || d || '-' || k,
  ('2018-01-01'::date + d) + time '10:00', 'S1', false, 0 from generate_series(0, :days - 1) d, generate_series(1, 5) k;
insert into stage.purchase_lines
  select 'P' || d || '-' || k, l, i.code, null, 10, 1, i.public_price, round(10 * i.public_price * 0.75, 2), '2018-01-01'::date + d + 700
  from generate_series(0, :days - 1) d, generate_series(1, 5) k, generate_series(1, 20) l, stage.items i
  where i.code = 1 + ((d * 97 + k * 31 + l * 7) % 5000);
insert into stage.sales select 'T' || d || '-' || n, (d * :spd + n)::text, ('2018-01-01'::date + d) + time '09:00' + (n * interval '1 minute') * (17.0 * 60 / :spd),
  'S1', case when n % 5 = 0 then 'C' || (1 + (d * 7 + n) % 2000) end, 'sale', null, 0,
  case when n % 5 = 0 then 0 else 1000000 end
  from generate_series(0, :days - 1) d, generate_series(1, :spd) n;
insert into stage.sale_lines
  select 'T' || d || '-' || n, l, i.code, null, 1, null, round(i.public_price / i.pack_parts, 2)
  from generate_series(0, :days - 1) d, generate_series(1, :spd) n, generate_series(1, 2) l, stage.items i
  where i.code = 1 + ((d * 13 + n * 17 + l * 101) % 5000);
insert into stage.payments select 'Y' || d || '-' || n, null, ('2018-01-01'::date + d) + time '12:00', 'from_customer',
  'C' || (1 + (d * 3 + n) % 2000), 20 from generate_series(0, :days - 1) d, generate_series(1, 30) n;
select (select count(*) from stage.sales) sales, (select count(*) from stage.sale_lines) sale_lines,
       (select count(*) from stage.purchase_lines) purchase_lines, (select count(*) from stage.payments) payments;
\timing on
select ph.import_history('scale test') - 'issues' as summary;
\timing off
select pg_size_pretty(pg_database_size(current_database())) as db_size;
SQL
