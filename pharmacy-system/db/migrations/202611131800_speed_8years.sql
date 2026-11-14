-- 202611131800_speed_8years
-- المطلوب (المالك 2026-11-13): كل شاشة أقل من ثانية على حجم 8 سنين (876 ألف فاتورة، 2 مليون حركة مخزون).
-- السبب (اتقاس وإنت المالك على قاعدة 8 سنين):
--   (1) البيع اليومي (v_sales_daily) بيحسب التكلفة لكل الـ 8 سنين حتى لو الشاشة عايزة 15 يوم: ملخص المبيعات 4.3 ث،
--       شهر بشهر 1.4، اللوحة 1.4. ← تكلفة كل يوم خلص محفوظة في ph.sales_day_cost (الفواتير المرحّلة مابتتعدلش)،
--       والنهارده وأي يوم اتغير بيتحسب من الدفاتر على طول. الحفظ معاه عدد الفواتير وإجماليها: لو فاتورة متأخرة
--       دخلت على يوم قديم (البيع والنت قاطع) العدد مش هيطابق، فاليوم ده بيتحسب من الأول. الأرقام نفسها ماتتغيرش.
--   (2) فحص القاعدة (health_check) 14 ث: استعلام لكل فاتورة. ← بقى تجميع واحد لكل جدول (نفس الفحوص ونفس الكلام)،
--       وآخر نتيجة بتتحفظ (ph.health_runs) عشان الإعدادات واللوحة وملخص الصبح يعرضوها على طول، والفحص الكامل
--       بيتعمل في الخلفية (ph.health_run).
--   (3) أعمار المديونيات 12–17 ث: «النهارده» بيتحسب لكل سطر، وآخر تحصيل لكل عميل من غير فهرس. ← مرة واحدة + فهرس.
--   (4) الراكد 1 ث: آخر بيع لكل صنف من كل سطور البيع. ← الأصناف اللي اتباعت في الفترة بتتشال الأول، وآخر بيع للباقي بس.
--   (5) القاعدة كانت فاكرة القراية من الهارد بطيئة (random_page_cost = 4، إعداد الهاردات القديمة) فبتقرا جداول كاملة
--       بدل الفهرس، والـ JIT بيضيّع لحد نص ثانية في تجميع الاستعلام. ← random_page_cost = 1.1 و jit = off للقاعدة دي بس.
--       (بيشتغلوا مع الاتصالات الجديدة: بعد التحديث PostgREST بيتعمله restart.)
--   (6) آخر الفواتير في اللوحة: فهرس على وقت الفاتورة.
-- الرجوع:
--   view ph.v_sales_daily ← التعريف اللي في 202611131600_speed.sql. الدوال ph.health_check و ph.rep_dues_aging
--   و ph.rep_dead_stock و ph.morning_brief ← تعريفاتهم في db/12-health.sql و 202611131000_reports.sql.
--   drop function ph.health_run(), ph.health_last(), ph.warm_sales_cache(); drop table ph.health_runs, ph.sales_day_cost;
--   drop index ph.sales_posted_at_idx, ph.payments_customer_at_idx;
--   alter database <القاعدة> reset random_page_cost; alter database <القاعدة> reset jit;

-- ---------------------------------------------------------------------------------------------- (5) إعدادات القاعدة
do $$
begin
  execute format('alter database %I set random_page_cost = 1.1', current_database());
  execute format('alter database %I set jit = off', current_database());
exception when insufficient_privilege then
  raise notice 'random_page_cost و jit ماتغيروش (محتاج صاحب القاعدة). الباقي اتطبق.';
end $$;
set local random_page_cost = 1.1;
set local jit = off;

-- ---------------------------------------------------------------------------------------------- (1) البيع اليومي
create table ph.sales_day_cost (
  business_day date primary key,
  invoices     bigint not null,      -- عدد الفواتير المرحّلة وقت الحساب
  total        numeric not null,     -- وإجماليها: لو اتغيروا، المحفوظ مابيتاخدش
  cost         numeric not null,
  at           timestamptz not null default now()
);
alter table ph.sales_day_cost enable row level security;
create policy staff_read on ph.sales_day_cost for select to authenticated
  using ((select ph.has_role(array['owner', 'manager', 'pharmacist', 'cashier'])));
revoke all on ph.sales_day_cost from public, anon, authenticated;
grant select on ph.sales_day_cost to authenticated;

-- بيحسب الأيام اللي خلصت ولسه مش محفوظة (أو اتغيرت). أي حد بيقرا البيع يقدر يناديها: بتكتب حساب من الدفاتر بس
create function ph.warm_sales_cache() returns integer
language plpgsql volatile security definer set search_path = '' as $$
declare n integer;
begin
  if auth.uid() is not null then perform ph.require_role(array['owner', 'manager', 'pharmacist', 'cashier']); end if;
  with d as (
    select x.business_day, count(*) as invoices, sum(x.total) as total
    from ph.sales x where x.status = 'posted' and x.business_day < ph.business_day() group by 1
  ), need as (
    select d.* from d left join ph.sales_day_cost k on k.business_day = d.business_day
    where k.business_day is null or k.invoices <> d.invoices or k.total <> d.total
  )
  insert into ph.sales_day_cost as k (business_day, invoices, total, cost)
  select n.business_day, n.invoices, n.total,
         coalesce((select sum(round(l.qty_units * coalesce(l.unit_cost, 0), 2))
                   from ph.sales x join ph.sale_lines l on l.sale_id = x.id
                   where x.status = 'posted' and x.business_day = n.business_day), 0)
  from need n
  on conflict (business_day) do update set invoices = excluded.invoices, total = excluded.total, cost = excluded.cost, at = now();
  get diagnostics n = row_count;
  return n;
end $$;
revoke all on function ph.warm_sales_cache() from public, anon;
grant execute on function ph.warm_sales_cache() to authenticated;

-- نفس الأعمدة والأرقام. البيع من الفهرس، والتكلفة من المحفوظ لو مطابق، وإلا من سطور اليوم ده بس
create or replace view ph.v_sales_daily with (security_invoker = true) as
with s as (
  select x.business_day, count(*) as invoices, sum(x.total) as total, sum(x.paid) as paid, sum(x.on_credit) as on_credit
  from ph.sales x where x.status = 'posted' group by x.business_day
)
select s.business_day, s.invoices, s.total, s.paid, s.on_credit,
       coalesce(r.returns, 0)                                                        as returns,
       s.total - coalesce(r.returns, 0)                                              as net_sales,
       coalesce(c.cost, 0) - coalesce(rc.returns_cost, 0)                            as net_cost,
       (s.total - coalesce(r.returns, 0)) - (coalesce(c.cost, 0) - coalesce(rc.returns_cost, 0)) as gross_profit
from s
left join ph.sales_day_cost k on k.business_day = s.business_day and k.invoices = s.invoices and k.total = s.total
cross join lateral (
  select coalesce(k.cost, (select sum(round(l.qty_units * coalesce(l.unit_cost, 0), 2))
                           from ph.sales x join ph.sale_lines l on l.sale_id = x.id
                           where x.status = 'posted' and x.business_day = s.business_day)) as cost) c
left join lateral (
  select sum(x.total) as returns from ph.sale_returns x where x.business_day = s.business_day) r on true
left join lateral (
  select sum(round(rl.qty_units * coalesce(sl.unit_cost, b.unit_cost, 0), 2)) as returns_cost
  from ph.sale_returns x join ph.sale_return_lines rl on rl.return_id = x.id
  join ph.batches b on b.id = rl.batch_id left join ph.sale_lines sl on sl.id = rl.sale_line_id
  where x.business_day = s.business_day) rc on true;

-- ---------------------------------------------------------------------------------------------- (2) فحص القاعدة
-- نفس الفحوص العشرة بنفس الترتيب والكلام، بس كل فحص تجميع واحد بدل استعلام لكل فاتورة
create or replace function ph.health_check() returns table (check_name text, ok boolean, detail text)
language plpgsql stable security definer set search_path = '' set work_mem = '64MB' set jit = off as $$
declare
  n     bigint;
  n5    bigint;
  v_txt text;
begin
  -- من البرنامج: المالك والمدير بس. من اتصال مباشر بالقاعدة (سكريبتات اللاب): مسموح
  if auth.uid() is not null then perform ph.require_role(array['owner', 'manager']); end if;

  -- 1) رصيد كل تشغيلة = مجموع دفتر الحركة
  select count(*) into n from (
    select m.item_id from (select item_id, location_id, batch_id, sum(qty_units) q from ph.stock_moves group by 1, 2, 3) m
    full join ph.stock_balances b using (item_id, location_id, batch_id)
    where coalesce(m.q, 0) <> coalesce(b.qty_units, 0)) d;
  return query select 'الرصيد = دفتر الحركة', n = 0, n || ' تشغيلة مختلفة';

  -- 2) مفيش رصيد بالسالب (إلا لو الإعداد سامح)
  select count(*) into n from ph.stock_balances where qty_units < 0;
  return query select 'مفيش رصيد بالسالب',
    n = 0 or coalesce((select allow_negative_stock from ph.settings where id = 1), false), n || ' تشغيلة بالسالب';

  -- 3) حساب كل عميل ومورد = مجموع دفتره
  select count(*) into n from (
    select l.party_id from (select party_type, party_id, sum(amount) a from ph.party_ledger group by 1, 2) l
    full join ph.party_balances b using (party_type, party_id)
    where coalesce(l.a, 0) <> coalesce(b.balance, 0)) d;
  return query select 'الحسابات = دفتر الحسابات', n = 0, n || ' حساب مختلف';

  -- 4) و 5) في لفّة واحدة على فواتير البيع
  select count(*) filter (where s.subtotal <> coalesce(l.st, 0)
                             or s.total <> s.subtotal - s.discount
                             or s.paid + s.on_credit <> s.total
                             or s.paid <> coalesce(p.a, 0)),
         count(*) filter (where coalesce(l.q, 0) <> -coalesce(m.q, 0))
  into n, n5
  from ph.sales s
  left join (select sale_id, sum(line_total) as st, sum(qty_units) as q from ph.sale_lines group by 1) l on l.sale_id = s.id
  left join (select sale_id, sum(amount) as a from ph.sale_payments group by 1) p on p.sale_id = s.id
  left join (select doc_id, sum(qty_units) as q from ph.stock_moves where doc_type = 'sale' group by 1) m on m.doc_id = s.id
  where s.status = 'posted';
  -- 4) كل فاتورة بيع: الإجمالي = السطور − الخصم، والمدفوع + الآجل = الإجمالي، والدفع = المدفوع
  return query select 'حساب فواتير البيع مظبوط', n = 0, n || ' فاتورة';
  -- 5) كل سطر بيع ليه حركة مخزون بنفس الكمية
  return query select 'البيع طلّع من المخزون نفس الكمية', n5 = 0, n5 || ' فاتورة';

  -- 6) كل فاتورة شرا: الإجمالي = تكلفة السطور
  select count(*) into n from ph.purchase_invoices i
  left join (select invoice_id, sum(cost_total) as c from ph.purchase_invoice_lines group by 1) l on l.invoice_id = i.id
  where i.status = 'posted' and i.total <> coalesce(l.c, 0);
  return query select 'حساب فواتير الشرا مظبوط', n = 0, n || ' فاتورة';

  -- 7) أرقام المستندات مسلسلة من غير فراغات ولا تكرار (لكل نوع وسنة). الرقم فريد في كل جدول، فبيتعد في جدوله
  select string_agg(k || ' ناقص ' || gap, '، ') into v_txt from (
    select k, max(mx) - sum(c) as gap from (
      select split_part(no, '-', 1) || '-' || split_part(no, '-', 2) as k, max(split_part(no, '-', 3)::integer) as mx, count(*) as c
      from (select no from ph.sales union all select no from ph.sale_returns union all select no from ph.purchase_invoices
            union all select no from ph.purchase_returns union all select no from ph.payments union all select no from ph.expenses
            union all select no from ph.stock_adjustments union all select no from ph.transfers union all select no from ph.stock_counts) x
      where no ~ '^[A-Z]+-[0-9]{4}-[0-9]+$'
      group by 1) t
    group by k) g
  where gap <> 0;
  return query select 'الأرقام مسلسلة', v_txt is null, coalesce(v_txt, '');

  -- 8) مفيش بيع من تشغيلة منتهية (بعد البرنامج ما اشتغل، مش تاريخ فارمافلاي)
  select count(*) into n from ph.sale_lines l join ph.sales s on s.id = l.sale_id join ph.batches b on b.id = l.batch_id
  where s.source = 'ph' and b.expiry is not null and b.expiry < s.business_day;
  return query select 'مفيش بيع منتهي', n = 0, n || ' سطر';

  -- 9) وضع النقل مقفول
  return query select 'وضع النقل مقفول', not coalesce((select import_mode from ph.settings where id = 1), false), '';

  -- 10) مفيش وردية مفتوحة من أكتر من يوم (تنبيه)
  select count(*) into n from ph.shifts where status = 'open' and opened_at < now() - interval '24 hours';
  return query select 'الورديات اتقفلت', n = 0, n || ' وردية مفتوحة من أكتر من يوم';
end $$;

-- آخر نتيجة فحص (الإعدادات واللوحة وملخص الصبح بيعرضوها على طول)
create table ph.health_runs (
  id      bigint generated always as identity primary key,
  at      timestamptz not null default now(),
  by_user uuid default auth.uid(),
  ms      integer not null,
  bad     integer not null,
  rows    jsonb not null
);
alter table ph.health_runs enable row level security;   -- مفيش سياسات: بيتقري من الدالتين بس
revoke all on ph.health_runs from public, anon, authenticated;

-- الفحص الكامل + حفظه (+ تكلفة الأيام اللي خلصت). نفس صلاحية health_check
create function ph.health_run() returns table (check_name text, ok boolean, detail text, checked_at timestamptz)
language plpgsql volatile security definer set search_path = '' as $$
declare
  t0   timestamptz := clock_timestamp();
  v    jsonb;
  v_at timestamptz;
begin
  if auth.uid() is not null then perform ph.require_role(array['owner', 'manager']); end if;
  perform ph.warm_sales_cache();
  -- الترتيب (n) بيتخزن جوه كل عنصر عشان القراية بعدين من غير with ordinality
  select jsonb_agg(jsonb_build_object('n', h.n, 'check_name', h.check_name, 'ok', h.ok, 'detail', h.detail) order by h.n) into v
  from ph.health_check() with ordinality as h(check_name, ok, detail, n);
  insert into ph.health_runs (at, ms, bad, rows)
  values (clock_timestamp(), extract(epoch from clock_timestamp() - t0) * 1000,
          (select count(*) from jsonb_array_elements(v) e where not (e ->> 'ok')::boolean), v)
  returning at into v_at;
  delete from ph.health_runs where at < now() - interval '30 days';
  return query select r.check_name, r.ok, r.detail, v_at
               from jsonb_to_recordset(v) as r(n bigint, check_name text, ok boolean, detail text) order by r.n;
end $$;

-- آخر فحص محفوظ (فاضي لو لسه ماحصلش)
create function ph.health_last() returns table (check_name text, ok boolean, detail text, checked_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is not null then perform ph.require_role(array['owner', 'manager']); end if;
  return query
  select r.check_name, r.ok, r.detail, h.at
  from (select * from ph.health_runs order by at desc limit 1) h
  cross join lateral jsonb_to_recordset(h.rows) as r(n bigint, check_name text, ok boolean, detail text)
  order by r.n;
end $$;
revoke all on function ph.health_run(), ph.health_last() from public, anon;
grant execute on function ph.health_run(), ph.health_last() to authenticated;

-- ملخص الصبح: نفس الملخص، والفحص من آخر نتيجة لو من أقل من يوم (وإلا بيفحص دلوقتي زي الأول)
create or replace function ph.morning_brief() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_day   date := ph.business_day() - 1;
  y       jsonb;
  lw      jsonb;
  v_top   jsonb;
  v_bad   integer;
begin
  perform ph.require_role(array['owner', 'manager', 'bot']);
  y  := ph.rep_sales_block(v_day, v_day);
  lw := ph.rep_sales_block(v_day - 7, v_day - 7);
  select coalesce(jsonb_agg(t order by t.v desc), '[]') into v_top from (
    select coalesce(i.name_ar, i.name_en) as name, sum(l.line_total) as v, round(sum(l.qty_units) / i.pack_parts, 1) as packs
    from ph.sale_lines l join ph.sales s on s.id = l.sale_id join ph.items i on i.id = l.item_id
    where s.status = 'posted' and s.business_day = v_day group by i.id, i.name_ar, i.name_en, i.pack_parts
    order by 2 desc limit 3) t;
  begin   -- الفحص للمالك والمدير بس؛ يوزر البوت مايشوفش تفاصيله
    if auth.uid() is not null then perform ph.require_role(array['owner', 'manager']); end if;
    select h.bad into v_bad from ph.health_runs h where h.at > now() - interval '1 day' order by h.at desc limit 1;
    if not found then select count(*) into v_bad from ph.health_check() h where not h.ok; end if;
  exception when others then v_bad := null;
  end;
  return jsonb_build_object(
    'day', v_day,
    'yesterday', y,
    'same_day_last_week', lw,
    'change_pct', round(100 * ((y ->> 'net_sales')::numeric - (lw ->> 'net_sales')::numeric) / nullif((lw ->> 'net_sales')::numeric, 0), 1),
    'top_items', v_top,
    'shortages', (select count(*) from ph.v_shortages where ordered_today_from is null),
    'expiring_30d', (select count(*) from ph.v_expiring where level in ('expired', 'red')),
    'expiry_risk_value', (select coalesce(round(sum(at_risk_value)), 0) from ph.v_expiry_risk),
    'refills_due', (select count(*) from ph.v_refills_due),
    'customers_over_limit', (select count(*) from ph.v_customer_dues where over_limit),
    'customers_due', (select coalesce(sum(balance), 0) from ph.party_balances where party_type = 'customer' and balance > 0),
    'late_order_lines', (select count(*) from ph.purchase_orders po join ph.purchase_order_lines pl on pl.order_id = po.id
                          where po.status = 'sent' and po.sent_at < now() - interval '24 hours' and po.sent_at > now() - interval '7 days'
                            and not exists (select 1 from ph.purchase_invoice_lines l join ph.purchase_invoices pi on pi.id = l.invoice_id
                                            where pi.status = 'posted' and pi.supplier_id = po.supplier_id and l.item_id = pl.item_id
                                              and (pi.order_id = po.id or pi.invoice_date >= ph.business_day(po.sent_at)))),
    'open_shifts_old', (select count(*) from ph.shifts where status = 'open' and opened_at < now() - interval '18 hours'),
    'open_notes', (select count(*) from ph.trial_notes where status = 'open'),
    'health_failures', v_bad);
end $$;

-- ---------------------------------------------------------------------------------------------- (3) أعمار المديونيات
create index if not exists payments_customer_at_idx on ph.payments (party_id, at) where kind = 'from_customer';

create or replace function ph.rep_dues_aging()
returns table (customer_id bigint, name text, phone text, balance numeric, credit_limit numeric, over_limit boolean,
               last_payment timestamptz, oldest_unpaid date, age_days integer, b_0_30 numeric, b_31_60 numeric, b_61_90 numeric, b_90p numeric)
language plpgsql stable security definer set search_path = '' as $$
declare v_today date := ph.business_day();
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with bal as (select pb.party_id, pb.balance from ph.party_balances pb where pb.party_type = 'customer' and pb.balance > 0),
  ch as (   -- المديونية من الأحدث للأقدم لحد ما توصل للرصيد
    select l.party_id, l.business_day, l.amount,
           sum(l.amount) over (partition by l.party_id order by l.at desc, l.id desc) as run
    from ph.party_ledger l join bal on bal.party_id = l.party_id
    where l.party_type = 'customer' and l.amount > 0
  ), alloc as (
    select ch.party_id, ch.business_day, greatest(0, least(ch.amount, bal.balance - (ch.run - ch.amount))) as part
    from ch join bal on bal.party_id = ch.party_id where ch.run - ch.amount < bal.balance
  ), ag as (
    select a.party_id, min(a.business_day) as oldest,
           sum(a.part) filter (where v_today - a.business_day <= 30) as b1,
           sum(a.part) filter (where v_today - a.business_day between 31 and 60) as b2,
           sum(a.part) filter (where v_today - a.business_day between 61 and 90) as b3,
           sum(a.part) filter (where v_today - a.business_day > 90) as b4
    from alloc a group by 1
  )
  select c.id, c.name, c.phone, bal.balance, c.credit_limit, bal.balance > c.credit_limit,
         (select max(p.at) from ph.payments p where p.kind = 'from_customer' and p.party_id = c.id),
         ag.oldest, v_today - ag.oldest,
         coalesce(ag.b1, 0), coalesce(ag.b2, 0), coalesce(ag.b3, 0), coalesce(ag.b4, 0)
  from bal join ph.customers c on c.id = bal.party_id left join ag on ag.party_id = bal.party_id
  order by 9 desc nulls last, 4 desc;
end $$;

-- ---------------------------------------------------------------------------------------------- (4) الراكد
create or replace function ph.rep_dead_stock(p_days integer default 90)
returns table (item_id bigint, name_en text, name_ar text, pack_parts integer, onhand_units numeric, cost_value numeric,
               sale_value numeric, last_sold date, days_since integer, nearest_expiry date)
language plpgsql stable security definer set search_path = '' as $$
declare
  v_today date := ph.business_day();
  v_cut   date := ph.business_day() - greatest(coalesce(p_days, 90), 7);
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with st as (
    select v.item_id, sum(v.qty_units) as u, sum(v.cost_value) as c, sum(v.qty_units * coalesce(v.public_price, 0)) as pv,
           min(v.expiry) filter (where v.expiry >= current_date) as ne
    from ph.v_stock v where v.qty_units > 0 and v.counts_as_stock group by 1
  ), recent as (   -- اتباع بعد الحد = مش راكد
    select distinct l.item_id from ph.sales x join ph.sale_lines l on l.sale_id = x.id
    where x.status = 'posted' and x.business_day > v_cut
  ), dead as materialized (
    select st.* from st where not exists (select 1 from recent r where r.item_id = st.item_id)
  )
  select i.id, i.name_en, i.name_ar, i.pack_parts, d.u, round(d.c, 2), round(d.pv / i.pack_parts, 2), ls.d,
         (v_today - ls.d), d.ne
  from dead d join ph.items i on i.id = d.item_id
  left join lateral (select max(x.business_day) as d from ph.sale_lines l join ph.sales x on x.id = l.sale_id
                     where l.item_id = d.item_id and x.status = 'posted') ls on true
  order by 6 desc nulls last;
end $$;

-- ---------------------------------------------------------------------------------------------- (6) آخر الفواتير
create index if not exists sales_posted_at_idx on ph.sales (at) where status = 'posted';

-- أول حساب لتكلفة الأيام اللي فاتت (على 8 سنين: ثواني)
select ph.warm_sales_cache();
analyze ph.sales_day_cost; analyze ph.payments; analyze ph.sales;
-- فحص أول مرة متحفوظ عشان اللوحة والإعدادات يشتغلوا فورًا بعد التحديث (بياخد ثواني مرة واحدة)
select count(*) from ph.health_run();
