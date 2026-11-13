-- =====================================================================================================
-- (11) النقل من فارمافلاي: البرنامج يبدأ «كأنه شغال من 2018»
-- =====================================================================================================
-- الفكرة:
--   1) نسخة فارمافلاي (الملف المضغوط) بتترجع على SQL Server، وكل جداولها بتتنسخ زي ما هي لـ schema pf_raw (import/).
--   2) ملف الربط (import/pharmafly-to-stage.sql) بيحوّل pf_raw لشكل موحّد هنا اسمه stage. ده الجزء الوحيد اللي
--      مربوط بشكل جداول فارمافلاي، وبيتكتب بعد ما نشوف الجداول الحقيقية.
--   3) ph.import_history() بتنقل stage ← ph بتواريخ وأرقام فارمافلاي الأصلية: كل فاتورة بيع وشرا ومرتجع وتحصيل
--      وتسوية من أول يوم. كارت الصنف وكشف حساب العميل والتقارير بيرجعوا لـ 2018.
--   4) في الآخر بتطابق الرصيد لكل تشغيلة وحساب كل عميل ومورد مع فارمافلاي النهارده. أي فرق بيتسجل «تسوية نقل»
--      ويظهر في ph.import_issues، مش بيتخبى.
--   5) بتلاقي كمان مشاكل التاريخ: بيع من غير رصيد، بيع منتهي، عملاء عدّوا حدهم، وتذاكر ممسوحة (أرقام ناقصة).
-- بتتنادى من اتصال مباشر بالقاعدة (مالك القاعدة) على قاعدة لسه فاضية. مش متاحة للبرنامج ولا للموظفين.
-- الكميات: stage بالوحدة الصغيرة (qty_units) للبيع والتسويات والرصيد، وبالعلبة (packs) لفواتير الشرا زي الورق.
-- الوقت: stage بتوقيت الصيدلية من غير منطقة (زي فارمافلاي)، والتحويل لتوقيت القاهرة هنا.
-- =====================================================================================================

create schema if not exists stage;

create table stage.locations (
  code            text primary key,
  name            text not null,
  kind            text not null default 'main' check (kind in ('main', 'waiting', 'returns', 'damaged')),
  supplier_code   text,                  -- لمخازن الانتظار
  counts_as_stock boolean not null default true,
  is_default_sale boolean not null default false
);
create table stage.suppliers (
  code  text primary key,
  name  text not null,
  kind  text not null default 'warehouse' check (kind in ('warehouse', 'company')),
  phone text
);
create table stage.customers (
  code         text primary key,
  name         text not null,
  phones       text[] not null default '{}',
  credit_limit numeric,
  area         text,
  address      text,
  created_at   timestamp
);
create table stage.items (
  code          bigint primary key,      -- رقم الصنف في فارمافلاي = رقمه عندنا
  name_en       text not null,
  name_ar       text,
  pack_parts    integer not null default 1,
  public_price  numeric,
  category      text,
  manufacturer  text,
  gkey          text,
  needs_rx      boolean not null default false,
  is_controlled boolean not null default false,
  is_fridge     boolean not null default false,
  active        boolean not null default true,
  barcodes      text[] not null default '{}'
);
create table stage.batches (
  batch_key    text primary key,
  item_code    bigint not null,
  expiry       date,
  public_price numeric,                  -- سعر العلبة على التشغيلة
  unit_cost    numeric                   -- تكلفة الوحدة الصغيرة
);
create table stage.purchases (
  doc_key         text primary key,
  legacy_no       text,
  supplier_code   text not null,
  supplier_doc_no text,
  at              timestamp not null,
  location_code   text not null,
  is_return       boolean not null default false,
  paid            numeric not null default 0
);
create table stage.purchase_lines (
  doc_key      text not null,
  line_no      integer not null,
  item_code    bigint not null,
  batch_key    text,                     -- فاضي = تشغيلة جديدة للسطر ده
  packs        numeric not null,
  bonus_packs  numeric not null default 0,
  public_price numeric,
  cost_total   numeric not null,
  expiry       date,
  primary key (doc_key, line_no)
);
create table stage.sales (
  doc_key       text primary key,
  legacy_no     text,                    -- رقم التذكرة
  at            timestamp not null,
  location_code text not null,
  customer_code text,
  kind          text not null default 'sale' check (kind in ('sale', 'return')),
  ref_doc_key   text,                    -- المرتجع: فاتورة البيع الأصلية لو معروفة
  discount      numeric not null default 0,
  paid          numeric not null default 0   -- البيع: اللي اتدفع. المرتجع: اللي رجع كاش. الباقي على حساب العميل
);
create table stage.sale_lines (
  doc_key    text not null,
  line_no    integer not null,
  item_code  bigint not null,
  batch_key  text,
  qty_units  numeric not null,
  unit_price numeric,
  line_total numeric not null,
  primary key (doc_key, line_no)
);
create table stage.payments (
  doc_key    text primary key,
  legacy_no  text,
  at         timestamp not null,
  kind       text not null check (kind in ('from_customer', 'to_customer', 'to_supplier')),
  party_code text not null,
  amount     numeric not null
);
create table stage.adjustments (            -- جرد، تالف، تحويل (سطرين: − من مكان و+ لمكان)
  doc_key       text not null,
  line_no       integer not null,
  legacy_no     text,
  at            timestamp not null,
  location_code text not null,
  item_code     bigint not null,
  batch_key     text,
  qty_units     numeric not null,
  reason        text not null default 'other' check (reason in ('damaged', 'expired', 'count', 'transfer', 'other')),
  primary key (doc_key, line_no)
);
-- فارمافلاي النهارده: للمطابقة بس
create table stage.current_stock (
  location_code text not null,
  item_code     bigint not null,
  batch_key     text,
  qty_units     numeric not null
);
create table stage.current_balances (
  party_type text not null check (party_type in ('customer', 'supplier')),
  party_code text not null,
  balance    numeric not null
);

-- -----------------------------------------------------------------------------------------------------
-- سجل النقل والمشاكل اللي اتلاقت
-- -----------------------------------------------------------------------------------------------------
create table ph.import_runs (
  id          bigint generated always as identity primary key,
  source      text,                        -- اسم الملف المضغوط ونسخة فارمافلاي
  started_at  timestamptz not null default now(),
  finished_at timestamptz,
  summary     jsonb
);
create table ph.import_issues (
  id      bigint generated always as identity primary key,
  run_id  bigint not null references ph.import_runs (id),
  kind    text not null check (kind in ('sold_without_stock', 'sold_expired', 'over_limit', 'missing_numbers',
                                        'stock_reconciled', 'balance_reconciled', 'skipped_line', 'credit_without_customer',
                                        'duplicate_phone', 'duplicate_supplier_doc', 'duplicate_barcode')),
  at      timestamptz,
  item_id bigint,
  party   text,
  ref     text,
  detail  jsonb
);
create index on ph.import_issues (run_id, kind);

-- الأرصدة من الدفاتر من الأول (بعد النقل)
create function ph.rebuild_balances() returns void
language plpgsql set search_path = '' as $$
begin
  if not ph.importing() then raise exception 'rebuild_balances بتشتغل جوه النقل بس'; end if;
  delete from ph.stock_balances;
  insert into ph.stock_balances (item_id, location_id, batch_id, qty_units)
  select m.item_id, m.location_id, m.batch_id, sum(m.qty_units) from ph.stock_moves m group by 1, 2, 3 having sum(m.qty_units) <> 0;
  delete from ph.party_balances;
  insert into ph.party_balances (party_type, party_id, balance)
  select l.party_type, l.party_id, sum(l.amount) from ph.party_ledger l group by 1, 2;
end $$;

-- =====================================================================================================
-- ph.import_history: النقل كله في عملية واحدة. لو أي حاجة وقعت، مفيش حاجة بتتسجل
-- =====================================================================================================
create function ph.import_history(p_source text default null, p_cutover timestamptz default now()) returns jsonb
language plpgsql set search_path = '' as $$
declare
  v_run     bigint;
  v_branch  smallint;
  v_tz      text;
  v_start   smallint;
  v_adj     bigint;
  v_summary jsonb;
begin
  -- ---------------------------------------------------------------- شروط
  if exists (select 1 from ph.items) or exists (select 1 from ph.stock_moves) or exists (select 1 from ph.party_ledger)
     or exists (select 1 from ph.sales) then
    raise exception 'القاعدة فيها داتا: النقل بيتعمل على قاعدة فاضية بس (drop schema ph cascade وابدأ من الأول)';
  end if;
  if (select count(*) from ph.branches) <> 1 then raise exception 'النقل محتاج فرع واحد متسجل'; end if;
  if not exists (select 1 from ph.payment_methods where code = 'cash') then raise exception 'سجّل طرق الدفع الأول'; end if;
  select id into v_branch from ph.branches;
  select time_zone, day_starts_at into v_tz, v_start from ph.settings where id = 1;
  if v_tz is null then raise exception 'سجّل إعدادات الصيدلية الأول'; end if;

  insert into ph.import_runs (source) values (p_source) returning id into v_run;
  update ph.settings set import_mode = true where id = 1;
  perform set_config('ph.importing', 'on', true);
  -- الأرصدة بتتحسب مرة واحدة في الآخر: تريجرات تحديث الرصيد بتقف لحد آخر العملية (والقفل على الدفاتر شغال زي ما هو)
  alter table ph.stock_moves disable trigger stock_moves_apply;
  alter table ph.party_ledger disable trigger party_ledger_apply;

  -- ---------------------------------------------------------------- 1) البيانات الأساسية
  insert into ph.categories (code, name_ar)
  select distinct 'pf_' || substr(md5(btrim(category)), 1, 12), left(btrim(category), 80)
  from stage.items where char_length(btrim(coalesce(category, ''))) >= 2;

  insert into ph.manufacturers (name)
  select distinct left(btrim(manufacturer), 120) from stage.items where char_length(btrim(coalesce(manufacturer, ''))) >= 2;

  insert into ph.generics (gkey, ingredients)
  select distinct left(gkey, 200), left(gkey, 400) from stage.items where char_length(coalesce(gkey, '')) >= 2;

  insert into ph.suppliers (name, kind, phone, legacy_id)
  select case when count(*) over (partition by btrim(s.name)) > 1 then left(btrim(s.name), 60) || ' (' || s.code || ')'
              else left(btrim(s.name), 80) end,
         s.kind, ph.norm_phone(s.phone), s.code
  from stage.suppliers s;

  insert into ph.locations (branch_id, name, kind, supplier_id, counts_as_stock, is_default_sale, legacy_id)
  select v_branch,
         case when count(*) over (partition by btrim(l.name)) > 1 then left(btrim(l.name), 60) || ' (' || l.code || ')'
              else left(btrim(l.name), 80) end,
         case when l.kind = 'waiting' and s.id is null then 'main' else l.kind end, s.id, l.counts_as_stock, l.is_default_sale, l.code
  from stage.locations l left join ph.suppliers s on s.legacy_id = l.supplier_code;

  insert into ph.items (id, name_en, name_ar, pack_parts, public_price, category_id, manufacturer_id, gkey,
                        needs_rx, is_controlled, is_fridge, active)
  select i.code,
         case when char_length(btrim(i.name_en)) >= 2 then left(btrim(i.name_en), 250) else 'ITEM ' || i.code end,
         left(nullif(btrim(i.name_ar), ''), 250),
         greatest(1, least(coalesce(i.pack_parts, 1), 10000)),
         case when i.public_price > 0 then round(i.public_price, 2) end,
         c.id, m.id, case when char_length(coalesce(i.gkey, '')) >= 2 then left(i.gkey, 200) end,
         i.needs_rx, i.is_controlled, i.is_fridge, i.active
  from stage.items i
  left join ph.categories c on c.code = 'pf_' || substr(md5(btrim(i.category)), 1, 12)
  left join ph.manufacturers m on m.name = left(btrim(i.manufacturer), 120);
  -- الأصناف الجديدة بعد النقل تبدأ بعد أكبر رقم
  perform setval(pg_get_serial_sequence('ph.items', 'id'), greatest(1000000, (select max(id) + 1 from ph.items)), false);

  -- الباركود: بتاع الشركة + ستيكر فارمافلاي (100000 + رقم الصنف)، عشان الستيكرات اللي على العلب تفضل شغالة
  with codes as (
    select distinct btrim(b) as barcode, i.code as item_id, 1 as pri from stage.items i, unnest(i.barcodes) b
    union
    select (100000 + i.code)::text, i.code, 2 from stage.items i
  ), ranked as (
    select c.*, count(*) over (partition by barcode) as n_items,
           row_number() over (partition by barcode order by pri, item_id) as rn
    from codes c where barcode ~ '^[0-9A-Za-z-]{4,40}$'
  ), ins as (
    insert into ph.item_barcodes (barcode, item_id) select barcode, item_id from ranked where rn = 1 returning 1
  )
  insert into ph.import_issues (run_id, kind, item_id, ref, detail)
  select v_run, 'duplicate_barcode', item_id, barcode, jsonb_build_object('items', n_items) from ranked where rn = 1 and n_items > 1;

  -- العملاء: أول رقم سليم هو الأساسي، والباقي «أرقام تانية». الرقم المكرر بيروح لأول عميل بس
  with c as (
    select s.*, array(select p from (select ph.norm_phone(x) as p, o from unnest(s.phones) with ordinality u(x, o)) q
                      where p is not null order by o) as ok
    from stage.customers s
  ), r as (
    select c.*, c.ok[1] as p1, row_number() over (partition by c.ok[1] order by c.created_at nulls last, c.code) as rn from c
  ), ins as (
    insert into ph.customers (name, phone, other_phones, area, address, credit_limit, source, legacy_id, created_at)
    select left(coalesce(nullif(btrim(name), ''), 'عميل ' || code), 80),
           case when rn = 1 then p1 end,
           case when rn = 1 then coalesce(ok[2:], '{}') else ok end,
           left(area, 80), left(address, 300), greatest(0, coalesce(credit_limit, 0)), 'import', code,
           coalesce(created_at at time zone v_tz, now())
    from r returning 1
  )
  insert into ph.import_issues (run_id, kind, party, ref)
  select v_run, 'duplicate_phone', code, p1 from r where rn > 1 and p1 is not null;

  -- ---------------------------------------------------------------- 2) التشغيلات
  insert into ph.batches (item_id, expiry, public_price, unit_cost, source, legacy_key)
  select b.item_code, b.expiry, case when b.public_price > 0 then round(b.public_price, 2) end,
         case when b.unit_cost >= 0 then round(b.unit_cost, 4) end, 'import', b.batch_key
  from stage.batches b join ph.items i on i.id = b.item_code;
  -- سطر شرا من غير تشغيلة معروفة = تشغيلة جديدة للسطر
  insert into ph.batches (item_id, expiry, public_price, unit_cost, source, legacy_key)
  select l.item_code, l.expiry,
         case when coalesce(nullif(l.public_price, 0), i.public_price) > 0 then round(coalesce(nullif(l.public_price, 0), i.public_price), 2) end,
         case when l.packs + l.bonus_packs > 0 and l.cost_total >= 0
              then round(l.cost_total / ((l.packs + l.bonus_packs) * i.pack_parts), 4) end,
         'import', 'P:' || l.doc_key || '#' || l.line_no
  from stage.purchase_lines l
  join stage.purchases p on p.doc_key = l.doc_key and not p.is_return
  join ph.items i on i.id = l.item_code
  where not exists (select 1 from ph.batches b where b.legacy_key = l.batch_key and b.item_id = l.item_code);
  -- البيع والتسويات والمرتجعات اللي تشغيلتها مش معروفة: تشغيلة «من غير تشغيلة» لكل صنف
  insert into ph.batches (item_id, public_price, unit_cost, source, legacy_key)
  select i.id, i.public_price,
         (select b.unit_cost from ph.batches b where b.item_id = i.id and b.unit_cost is not null order by b.id desc limit 1),
         'unbatched', 'U:' || i.id
  from ph.items i
  where i.id in (
    select x.item_code from (
      select item_code, batch_key from stage.sale_lines
      union all select item_code, batch_key from stage.adjustments
      union all select item_code, batch_key from stage.current_stock
      union all select l.item_code, l.batch_key from stage.purchase_lines l join stage.purchases p on p.doc_key = l.doc_key and p.is_return
    ) x
    where not exists (select 1 from ph.batches b where b.legacy_key = x.batch_key and b.item_id = x.item_code));

  -- ---------------------------------------------------------------- 3) فواتير الشرا والمرتجع للمورد
  create temp table t_pur on commit drop as
  select nextval(pg_get_serial_sequence(case when p.is_return then 'ph.purchase_returns' else 'ph.purchase_invoices' end, 'id')) as id,
         p.*, (p.at at time zone v_tz) as ts, (p.at - make_interval(hours => v_start))::date as bday, s.id as supplier_id, l.id as location_id
  from stage.purchases p
  join ph.suppliers s on s.legacy_id = p.supplier_code
  join ph.locations l on l.legacy_id = p.location_code;

  -- تنبيه: رقم الفاتورة ورقم المرتجع من عدّادين مختلفين، فـ doc_id لوحده مش كفاية: دايمًا معاه is_return
  create temp table t_pl on commit drop as
  select p.id as doc_id, p.is_return, p.ts, p.bday, p.location_id, p.supplier_id, l.doc_key, l.line_no, l.item_code,
         l.packs, greatest(l.bonus_packs, 0) as bonus_packs, l.cost_total, l.expiry, i.pack_parts,
         coalesce(b1.id, case when p.is_return then bu.id else bp.id end) as batch_id,
         coalesce(nullif(l.public_price, 0), coalesce(b1.public_price, bp.public_price), i.public_price) as price
  from stage.purchase_lines l
  join pg_temp.t_pur p on p.doc_key = l.doc_key
  join ph.items i on i.id = l.item_code
  left join ph.batches b1 on b1.legacy_key = l.batch_key and b1.item_id = l.item_code
  left join ph.batches bp on bp.legacy_key = 'P:' || l.doc_key || '#' || l.line_no
  left join ph.batches bu on bu.legacy_key = 'U:' || l.item_code
  where l.packs > 0 and l.cost_total >= 0 and (p.is_return or coalesce(nullif(l.public_price, 0), b1.public_price, bp.public_price, i.public_price) > 0);

  insert into ph.purchase_invoices (id, no, supplier_id, supplier_doc_no, invoice_date, location_id, status, total, paid_amount,
                                    created_at, posted_at, source, legacy_no)
  overriding system value
  select p.id,
         'PI-' || extract(year from p.bday)::int || '-' || lpad((row_number() over (partition by extract(year from p.bday) order by p.ts, p.doc_key))::text, 6, '0'),
         p.supplier_id,
         case when count(*) over (partition by p.supplier_id, nullif(btrim(p.supplier_doc_no), '')) = 1 then nullif(btrim(p.supplier_doc_no), '') end,
         p.bday, p.location_id, 'posted', coalesce(t.total, 0), greatest(0, least(p.paid, coalesce(t.total, 0))),
         p.ts, p.ts, 'pharmafly', coalesce(p.legacy_no, p.doc_key)
  from pg_temp.t_pur p
  left join (select doc_id, sum(cost_total) as total from pg_temp.t_pl where not is_return group by 1) t on t.doc_id = p.id
  where not p.is_return;
  insert into ph.import_issues (run_id, kind, party, ref)
  select v_run, 'duplicate_supplier_doc', s.name, p.supplier_doc_no
  from pg_temp.t_pur p join ph.suppliers s on s.id = p.supplier_id
  where not p.is_return and nullif(btrim(p.supplier_doc_no), '') is not null
  group by s.name, p.supplier_doc_no having count(*) > 1;

  insert into ph.purchase_invoice_lines (invoice_id, item_id, packs, bonus_packs, public_price, cost_total, expiry, batch_id)
  select doc_id, item_code, packs, bonus_packs, round(price, 2), round(cost_total, 2), expiry, batch_id
  from pg_temp.t_pl where not is_return;
  insert into ph.stock_moves (at, business_day, item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
  select ts, bday, item_code, batch_id, location_id, (packs + bonus_packs) * pack_parts,
         round(cost_total / ((packs + bonus_packs) * pack_parts), 4), 'purchase', doc_id
  from pg_temp.t_pl where not is_return;

  insert into ph.purchase_returns (id, no, supplier_id, location_id, reason, status, total, created_at, posted_at, source, legacy_no)
  overriding system value
  select p.id,
         'PR-' || extract(year from p.bday)::int || '-' || lpad((row_number() over (partition by extract(year from p.bday) order by p.ts, p.doc_key))::text, 6, '0'),
         p.supplier_id, p.location_id, 'other', 'posted', coalesce(t.total, 0), p.ts, p.ts, 'pharmafly', coalesce(p.legacy_no, p.doc_key)
  from pg_temp.t_pur p
  left join (select doc_id, sum(cost_total) as total from pg_temp.t_pl where is_return group by 1) t on t.doc_id = p.id
  where p.is_return;
  insert into ph.purchase_return_lines (return_id, batch_id, qty_units, value)
  select doc_id, batch_id, sum(packs * pack_parts), round(sum(cost_total), 2) from pg_temp.t_pl where is_return group by doc_id, batch_id;
  insert into ph.stock_moves (at, business_day, item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
  select ts, bday, item_code, batch_id, location_id, -sum(packs * pack_parts), null, 'purchase_return', doc_id
  from pg_temp.t_pl where is_return group by ts, bday, item_code, batch_id, location_id, doc_id;

  insert into ph.party_ledger (at, business_day, party_type, party_id, amount, doc_type, doc_id)
  select p.ts, p.bday, 'supplier', p.supplier_id, x.amount, x.doc_type, p.id
  from pg_temp.t_pur p
  join lateral (
    select i.total as amount, 'purchase' as doc_type from ph.purchase_invoices i where i.id = p.id and not p.is_return
    union all select -i.paid_amount, 'payment' from ph.purchase_invoices i where i.id = p.id and not p.is_return
    union all select -r.total, 'purchase_return' from ph.purchase_returns r where r.id = p.id and p.is_return
  ) x on x.amount <> 0;

  -- ---------------------------------------------------------------- 4) فواتير البيع والمرتجعات
  create temp table t_sale on commit drop as
  select nextval(pg_get_serial_sequence(case when s.kind = 'sale' then 'ph.sales' else 'ph.sale_returns' end, 'id')) as id,
         s.*, (s.at at time zone v_tz) as ts, (s.at - make_interval(hours => v_start))::date as bday, l.id as location_id, c.id as customer_id
  from stage.sales s
  join ph.locations l on l.legacy_id = s.location_code
  left join ph.customers c on c.legacy_id = s.customer_code;

  -- تنبيه: نفس الكلام هنا: doc_id دايمًا معاه kind
  create temp table t_sl on commit drop as
  select t.id as doc_id, t.kind, t.ts, t.bday, t.location_id, l.doc_key, l.line_no, l.item_code, l.qty_units,
         round(coalesce(l.unit_price, l.line_total / l.qty_units), 4) as unit_price, round(l.line_total, 2) as line_total,
         coalesce(b1.id, bu.id) as batch_id, coalesce(b1.unit_cost, bu.unit_cost) as unit_cost
  from stage.sale_lines l
  join pg_temp.t_sale t on t.doc_key = l.doc_key
  join ph.items i on i.id = l.item_code
  left join ph.batches b1 on b1.legacy_key = l.batch_key and b1.item_id = l.item_code
  left join ph.batches bu on bu.legacy_key = 'U:' || l.item_code
  where l.qty_units > 0 and l.line_total >= 0;

  -- إجمالي كل فاتورة مرة واحدة (رقم البيع ورقم المرتجع من عدّادين مختلفين: لازم النوع كمان)
  create temp table t_tot on commit drop as
  select doc_id, kind, sum(line_total) as st from pg_temp.t_sl group by doc_id, kind;
  -- cash = اللي اتدفع في البيع، أو اللي رجع كاش في المرتجع. من غير عميل = كله كاش
  create temp table t_head on commit drop as
  select x.*, x.st - x.d as tot,
         case when x.customer_id is null then x.st - x.d else least(greatest(x.paid, 0), x.st - x.d) end as cash
  from (select t.*, coalesce(tt.st, 0) as st, least(greatest(t.discount, 0), coalesce(tt.st, 0)) as d
        from pg_temp.t_sale t left join pg_temp.t_tot tt on tt.doc_id = t.id and tt.kind = t.kind) x;
  insert into ph.import_issues (run_id, kind, at, ref, detail)
  select v_run, 'credit_without_customer', ts, coalesce(legacy_no, doc_key), jsonb_build_object('total', tot, 'paid', paid)
  from pg_temp.t_head where kind = 'sale' and customer_id is null and paid < tot;

  insert into ph.sales (id, no, branch_id, location_id, at, business_day, customer_id, channel, status, subtotal, discount, total,
                        paid, on_credit, client_uuid, posted_at, source, legacy_no)
  overriding system value
  select id,
         'S-' || extract(year from bday)::int || '-' || lpad((row_number() over (partition by extract(year from bday) order by ts, doc_key))::text, 6, '0'),
         v_branch, location_id, ts, bday, customer_id, 'counter', 'posted', st, d, tot, cash, tot - cash,
         md5('pf-sale-' || doc_key)::uuid, ts, 'pharmafly', coalesce(legacy_no, doc_key)
  from pg_temp.t_head where kind = 'sale';
  insert into ph.sale_lines (sale_id, item_id, batch_id, qty_units, unit_price, line_total, unit_cost)
  select doc_id, item_code, batch_id, qty_units, unit_price, line_total, unit_cost from pg_temp.t_sl where kind = 'sale';
  insert into ph.sale_payments (sale_id, method, account_id, amount)
  select id, 'cash', null, cash from pg_temp.t_head where kind = 'sale' and cash > 0;

  insert into ph.sale_returns (id, no, sale_id, location_id, customer_id, refund, total, at, business_day, client_uuid, source, legacy_no)
  overriding system value
  select h.id,
         'SR-' || extract(year from h.bday)::int || '-' || lpad((row_number() over (partition by extract(year from h.bday) order by h.ts, h.doc_key))::text, 6, '0'),
         o.id, h.location_id, h.customer_id, case when h.customer_id is not null and h.tot - h.cash > 0 then 'credit' else 'cash' end,
         h.tot, h.ts, h.bday, md5('pf-return-' || h.doc_key)::uuid, 'pharmafly', coalesce(h.legacy_no, h.doc_key)
  from pg_temp.t_head h left join pg_temp.t_sale o on o.doc_key = h.ref_doc_key and o.kind = 'sale'
  where h.kind = 'return';
  insert into ph.sale_return_lines (return_id, item_id, batch_id, qty_units, value)
  select doc_id, item_code, batch_id, qty_units, line_total from pg_temp.t_sl where kind = 'return';

  insert into ph.stock_moves (at, business_day, item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
  select ts, bday, item_code, batch_id, location_id, case when kind = 'sale' then -qty_units else qty_units end, unit_cost,
         case when kind = 'sale' then 'sale' else 'sale_return' end, doc_id
  from pg_temp.t_sl;
  insert into ph.party_ledger (at, business_day, party_type, party_id, amount, doc_type, doc_id)
  select ts, bday, 'customer', customer_id, case when kind = 'sale' then tot - cash else -(tot - cash) end,
         case when kind = 'sale' then 'sale' else 'sale_return' end, id
  from pg_temp.t_head where customer_id is not null and tot - cash > 0;

  -- ---------------------------------------------------------------- 5) التحصيل والسداد
  insert into ph.payments (no, kind, party_id, amount, account_id, at, client_uuid, source, legacy_no)
  select case x.kind when 'from_customer' then 'RC' when 'to_customer' then 'RF' else 'PY' end || '-' || extract(year from x.bday)::int || '-' ||
           lpad((row_number() over (partition by x.kind, extract(year from x.bday) order by x.ts, x.doc_key))::text, 6, '0'),
         x.kind, x.party_id, round(x.amount, 2), null, x.ts, md5('pf-pay-' || x.doc_key)::uuid, 'pharmafly', coalesce(x.legacy_no, x.doc_key)
  from (
    select p.*, (p.at at time zone v_tz) as ts, (p.at - make_interval(hours => v_start))::date as bday, coalesce(c.id, s.id::bigint) as party_id
    from stage.payments p
    left join ph.customers c on p.kind in ('from_customer', 'to_customer') and c.legacy_id = p.party_code
    left join ph.suppliers s on p.kind = 'to_supplier' and s.legacy_id = p.party_code
  ) x
  where x.party_id is not null and x.amount > 0;
  insert into ph.party_ledger (at, business_day, party_type, party_id, amount, doc_type, doc_id)
  select p.at, ph.business_day(p.at), case when p.kind = 'to_supplier' then 'supplier' else 'customer' end, p.party_id,
         case when p.kind = 'to_customer' then p.amount else -p.amount end, 'payment', p.id
  from ph.payments p where p.source = 'pharmafly';

  -- ---------------------------------------------------------------- 6) التسويات (جرد، تالف، تحويل)
  create temp table t_adj on commit drop as
  select nextval(pg_get_serial_sequence('ph.stock_adjustments', 'id')) as id, d.*,
         (d.at at time zone v_tz) as ts, (d.at - make_interval(hours => v_start))::date as bday
  from (select doc_key, min(at) as at, min(legacy_no) as legacy_no, min(reason) as reason,
               case when count(distinct location_code) = 1 then min(location_code) end as location_code
        from stage.adjustments group by doc_key) d;
  insert into ph.stock_adjustments (id, no, location_id, reason, at, source, legacy_no)
  overriding system value
  select a.id, 'ADJ-' || extract(year from a.bday)::int || '-' ||
               lpad((row_number() over (partition by extract(year from a.bday) order by a.ts, a.doc_key))::text, 6, '0'),
         l.id, a.reason, a.ts, 'pharmafly', coalesce(a.legacy_no, a.doc_key)
  from pg_temp.t_adj a left join ph.locations l on l.legacy_id = a.location_code;
  insert into ph.stock_moves (at, business_day, item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
  select a.ts, a.bday, s.item_code, coalesce(b1.id, bu.id), l.id, s.qty_units, coalesce(b1.unit_cost, bu.unit_cost), 'adjust', a.id
  from stage.adjustments s
  join pg_temp.t_adj a on a.doc_key = s.doc_key
  join ph.locations l on l.legacy_id = s.location_code
  join ph.items i on i.id = s.item_code
  left join ph.batches b1 on b1.legacy_key = s.batch_key and b1.item_id = s.item_code
  left join ph.batches bu on bu.legacy_key = 'U:' || s.item_code
  where s.qty_units <> 0;

  -- ---------------------------------------------------------------- 7) الترقيم يكمّل بعد آخر رقم
  insert into ph.doc_counters (doc_type, branch_id, year, last_no)
  select split_part(no, '-', 1), v_branch, split_part(no, '-', 2)::smallint, max(split_part(no, '-', 3)::integer)
  from (select no from ph.sales union all select no from ph.sale_returns union all select no from ph.purchase_invoices
        union all select no from ph.purchase_returns union all select no from ph.payments union all select no from ph.stock_adjustments) x
  where no is not null group by 1, 3;

  -- ---------------------------------------------------------------- 8) مشاكل التاريخ (بنعرضها، مش بنصلحها)
  -- بيع من غير رصيد: كل مرة رصيد الصنف في المكان بقى بالسالب بسبب بيع
  insert into ph.import_issues (run_id, kind, at, item_id, detail)
  select v_run, 'sold_without_stock', min(at), item_id, jsonb_build_object('times', count(*), 'location_id', location_id)
  from (
    select m.*, sum(m.qty_units) over w as bal, sum(m.qty_units) over w - m.qty_units as prev
    from ph.stock_moves m window w as (partition by m.item_id, m.location_id order by m.at, m.id)
  ) x
  where doc_type = 'sale' and bal < 0 and prev >= 0
  group by item_id, location_id;
  -- بيع من تشغيلة منتهية
  insert into ph.import_issues (run_id, kind, at, item_id, detail)
  select v_run, 'sold_expired', min(s.at), sl.item_id, jsonb_build_object('times', count(*), 'units', sum(sl.qty_units))
  from ph.sale_lines sl join ph.sales s on s.id = sl.sale_id join ph.batches b on b.id = sl.batch_id
  where b.expiry is not null and b.expiry < s.business_day
  group by sl.item_id;
  -- عملاء عدّوا حدّهم (بالحد الحالي)
  insert into ph.import_issues (run_id, kind, at, party, detail)
  select v_run, 'over_limit', min(x.at), c.name,
         jsonb_build_object('times', count(*), 'limit', c.credit_limit, 'max_balance', max(x.bal))
  from (select l.*, sum(l.amount) over (partition by l.party_id order by l.at, l.id) as bal
        from ph.party_ledger l where l.party_type = 'customer') x
  join ph.customers c on c.id = x.party_id
  where c.credit_limit > 0 and x.bal > c.credit_limit and x.doc_type = 'sale'
  group by c.id, c.name, c.credit_limit;
  -- أرقام تذاكر ناقصة (اتمسحت من فارمافلاي)
  insert into ph.import_issues (run_id, kind, ref, detail)
  select v_run, 'missing_numbers', 'tickets',
         jsonb_build_object('missing', sum(nxt - v - 1), 'gaps', count(*),
                            'first', (array_agg((v + 1) || case when nxt - v > 2 then '..' || (nxt - 1) else '' end order by v))[1:10])
  from (select v, lead(v) over (order by v) as nxt
        from (select legacy_no::bigint as v from ph.sales where source = 'pharmafly' and legacy_no ~ '^[0-9]{1,15}$'
              union select legacy_no::bigint from ph.sale_returns where source = 'pharmafly' and legacy_no ~ '^[0-9]{1,15}$'
              union select legacy_no::bigint from ph.payments where source = 'pharmafly' and legacy_no ~ '^[0-9]{1,15}$') n) g
  where nxt - v > 1
  having count(*) > 0;

  -- ---------------------------------------------------------------- 9) المطابقة مع فارمافلاي النهارده
  perform ph.rebuild_balances();
  if exists (select 1 from stage.current_stock) then
    create temp table t_target on commit drop as
    select l.id as location_id, c.item_code as item_id, coalesce(b1.id, bu.id) as batch_id, sum(c.qty_units) as qty
    from stage.current_stock c
    join ph.locations l on l.legacy_id = c.location_code
    join ph.items i on i.id = c.item_code
    left join ph.batches b1 on b1.legacy_key = c.batch_key and b1.item_id = c.item_code
    left join ph.batches bu on bu.legacy_key = 'U:' || c.item_code
    group by 1, 2, 3;
    create temp table t_diff on commit drop as
    select coalesce(t.item_id, b.item_id) as item_id, coalesce(t.location_id, b.location_id) as location_id,
           coalesce(t.batch_id, b.batch_id) as batch_id, coalesce(t.qty, 0) - coalesce(b.qty_units, 0) as diff
    from pg_temp.t_target t
    full join ph.stock_balances b on b.item_id = t.item_id and b.location_id = t.location_id and b.batch_id = t.batch_id
    where coalesce(t.qty, 0) <> coalesce(b.qty_units, 0);
    if exists (select 1 from pg_temp.t_diff) then
      insert into ph.stock_adjustments (no, reason, at, note, source)
      values (ph.next_doc_no('ADJ', v_branch, ph.business_day(p_cutover)), 'reconcile', p_cutover,
              'تسوية النقل: الرصيد = رصيد فارمافلاي وقت النسخة', 'pharmafly')
      returning id into v_adj;
      insert into ph.stock_moves (at, business_day, item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
      select p_cutover, ph.business_day(p_cutover), d.item_id, d.batch_id, d.location_id, d.diff, b.unit_cost, 'adjust', v_adj
      from pg_temp.t_diff d join ph.batches b on b.id = d.batch_id;
      -- الفرق على مستوى الصنف بس هو اللي يهم (توزيع التشغيلات جوه نفس الصنف مش فرق)
      insert into ph.import_issues (run_id, kind, at, item_id, detail)
      select v_run, 'stock_reconciled', p_cutover, d.item_id,
             jsonb_build_object('diff_units', sum(d.diff),
                                'pharmafly_units', (select coalesce(sum(t.qty), 0) from pg_temp.t_target t where t.item_id = d.item_id),
                                'history_units', (select coalesce(sum(b.qty_units), 0) from ph.stock_balances b where b.item_id = d.item_id))
      from pg_temp.t_diff d group by d.item_id having sum(d.diff) <> 0;
    end if;
  end if;
  if exists (select 1 from stage.current_balances) then
    create temp table t_pdiff on commit drop as
    select coalesce(x.party_type, b.party_type) as party_type, coalesce(x.party_id, b.party_id) as party_id,
           coalesce(x.target, 0) - coalesce(b.balance, 0) as diff, coalesce(x.target, 0) as target, coalesce(b.balance, 0) as history
    from (select cb.party_type, coalesce(c.id, s.id::bigint) as party_id, sum(cb.balance) as target
          from stage.current_balances cb
          left join ph.customers c on cb.party_type = 'customer' and c.legacy_id = cb.party_code
          left join ph.suppliers s on cb.party_type = 'supplier' and s.legacy_id = cb.party_code
          group by 1, 2) x
    full join ph.party_balances b on b.party_type = x.party_type and b.party_id = x.party_id
    where coalesce(x.target, 0) <> coalesce(b.balance, 0) and coalesce(x.party_id, b.party_id) is not null;
    insert into ph.party_ledger (at, business_day, party_type, party_id, amount, doc_type, doc_id, note)
    select p_cutover, ph.business_day(p_cutover), party_type, party_id, diff, 'adjust', v_run, 'تسوية النقل من فارمافلاي'
    from pg_temp.t_pdiff;
    insert into ph.import_issues (run_id, kind, at, party, detail)
    select v_run, 'balance_reconciled', p_cutover,
           coalesce((select c.name from ph.customers c where d.party_type = 'customer' and c.id = d.party_id),
                    (select s.name from ph.suppliers s where d.party_type = 'supplier' and s.id = d.party_id)),
           jsonb_build_object('party_type', d.party_type, 'diff', d.diff, 'pharmafly', d.target, 'history', d.history)
    from pg_temp.t_pdiff d;
  end if;
  perform ph.rebuild_balances();

  -- ---------------------------------------------------------------- 10) الملخص
  select jsonb_build_object(
    'items', (select count(*) from ph.items),
    'customers', (select count(*) from ph.customers),
    'suppliers', (select count(*) from ph.suppliers),
    'sales', (select count(*) from ph.sales),
    'sale_returns', (select count(*) from ph.sale_returns),
    'purchases', (select count(*) from ph.purchase_invoices),
    'purchase_returns', (select count(*) from ph.purchase_returns),
    'payments', (select count(*) from ph.payments),
    'adjustments', (select count(*) from ph.stock_adjustments),
    'stock_moves', (select count(*) from ph.stock_moves),
    'first_day', (select min(business_day) from ph.stock_moves),
    'last_day', (select max(business_day) from ph.sales),
    'skipped', jsonb_build_object(
       'sales', (select count(*) from stage.sales) - (select count(*) from pg_temp.t_sale),
       'sale_lines', (select count(*) from stage.sale_lines) - (select count(*) from pg_temp.t_sl),
       'purchases', (select count(*) from stage.purchases) - (select count(*) from pg_temp.t_pur),
       'purchase_lines', (select count(*) from stage.purchase_lines) - (select count(*) from pg_temp.t_pl),
       'payments', (select count(*) from stage.payments) - (select count(*) from ph.payments)),
    'issues', coalesce((select jsonb_object_agg(kind, n) from (select kind, count(*) as n from ph.import_issues where run_id = v_run group by kind) k), '{}')
  ) into v_summary;

  alter table ph.stock_moves enable trigger stock_moves_apply;
  alter table ph.party_ledger enable trigger party_ledger_apply;
  update ph.import_runs set finished_at = now(), summary = v_summary where id = v_run;
  update ph.settings set import_mode = false where id = 1;
  perform set_config('ph.importing', 'off', true);
  return v_summary;
end $$;

-- النقل من اتصال مباشر بالقاعدة بس (مالك القاعدة)، مش من البرنامج
revoke all on function ph.import_history(text, timestamptz), ph.rebuild_balances() from public, anon, authenticated;
alter table ph.import_runs enable row level security;
alter table ph.import_issues enable row level security;
create policy managers_read on ph.import_runs for select to authenticated using (ph.has_role(array['owner', 'manager']));
create policy managers_read on ph.import_issues for select to authenticated using (ph.has_role(array['owner', 'manager']));
grant select on ph.import_runs, ph.import_issues to authenticated;
revoke all on all tables in schema stage from public, anon, authenticated;
