-- =====================================================================================================
-- (8 من 10) الربط المباشر مع شغلنا: النواقص، عروض الموردين (الوارد والقوايم)، أحسن خصم، الموقع،
--           التوصيل، التواصل مع العملاء، مفاتيح الأجهزة
--   البوت والموقع وأداة التواصل بيقروا ويكتبوا هنا على طول. مفيش تصدير ولا مزامنة من اللاب.
-- =====================================================================================================

-- -----------------------------------------------------------------------------------------------------
-- النواقص: بتتحسب لوحدها من الرصيد والبيع (بدل الملف اللي اللاب كان بيبعته)
-- -----------------------------------------------------------------------------------------------------
create table ph.item_stock_rules (
  item_id   bigint primary key references ph.items (id),
  min_units numeric(14, 2) check (min_units >= 0),   -- أقل من كده = ناقص
  max_units numeric(14, 2) check (max_units >= 0),   -- نطلب لحد كده
  check (max_units is null or min_units is null or max_units >= min_units)
);

-- اللي المالك قرره على صنف ناقص: الكمية، أو «أجّله لحد …»
create table ph.shortage_marks (
  item_id        bigint primary key references ph.items (id),
  order_packs    numeric(12, 2) check (order_packs > 0),
  deferred_until date,
  note           text check (char_length(note) <= 300),
  updated_at     timestamptz not null default now(),
  by_user        uuid default auth.uid()
);

-- -----------------------------------------------------------------------------------------------------
-- عروض الموردين: كل صنف وصل في وارد الواتس أو في قايمة مخزن، بالسعر والخصم لو مكتوبين
-- -----------------------------------------------------------------------------------------------------
create table ph.supplier_offers (
  id           bigint generated always as identity primary key,
  supplier_id  integer not null references ph.suppliers (id),
  rep_id       integer references ph.supplier_reps (id),
  item_id      bigint not null references ph.items (id),
  offered_at   timestamptz not null default now(),
  source       text not null check (source in ('whatsapp', 'list', 'manual')),
  price        numeric(12, 2) check (price > 0),
  discount_pct numeric(5, 2) check (discount_pct between 0 and 100),
  quota        text check (char_length(quota) <= 60),            -- «كوته 2»
  raw_text     text check (char_length(raw_text) <= 300),        -- السطر زي ما المورد كتبه
  match        text not null default 'sure' check (match in ('sure', 'review')),
  inbox_ref    text                                              -- رقم الرسالة في الوارد
);
create index on ph.supplier_offers (item_id, offered_at desc);
create index on ph.supplier_offers (supplier_id, offered_at desc);

-- -----------------------------------------------------------------------------------------------------
-- طلبات الموقع والتوصيل: الطلب بيستنى تأكيدك، ولما يتأكد بيتسجل بيع عادي بـ post_sale
-- -----------------------------------------------------------------------------------------------------
create table ph.online_orders (
  id            bigint generated always as identity primary key,
  client_uuid   uuid not null unique default gen_random_uuid(),   -- نفسه بيبقى client_uuid للبيع
  created_at    timestamptz not null default now(),
  customer_id   bigint references ph.customers (id),
  name          text not null check (char_length(name) between 2 and 80),
  phone         text not null check (phone ~ '^01[0-9]{9}$'),
  address       text not null check (char_length(address) between 5 and 300),
  notes         text check (char_length(notes) <= 500),
  items         jsonb not null check (jsonb_typeof(items) = 'array' and jsonb_array_length(items) between 1 and 50),
  total         numeric(12, 2) not null check (total >= 0),
  status        text not null default 'new' check (status in ('new', 'confirmed', 'out', 'delivered', 'cancelled')),
  sale_id       bigint references ph.sales (id),
  driver        uuid references ph.staff (user_id),
  delivery_fee  numeric(10, 2) not null default 0 check (delivery_fee >= 0),
  rx_paths      text[] not null default '{}' check (cardinality(rx_paths) <= 4)
);

-- -----------------------------------------------------------------------------------------------------
-- التواصل الأسبوعي مع العملاء (أداة التواصل جوه البرنامج). الإرسال دايمًا بإيدك من الواتس
-- -----------------------------------------------------------------------------------------------------
create table ph.outreach_cycles (
  id         bigint generated always as identity primary key,
  started_at timestamptz not null default now(),
  message    text check (char_length(message) <= 4000),
  image_path text
);
create table ph.outreach_log (
  cycle_id    bigint not null references ph.outreach_cycles (id),
  customer_id bigint not null references ph.customers (id),
  status      text not null check (status in ('sent', 'skip')),
  at          timestamptz not null default now(),
  primary key (cycle_id, customer_id)
);

-- مفاتيح الأجهزة (موبايل الواتس، جهاز الكاشير): بيتحفظ الـ sha256 بس، زي البوت دلوقتي
create table ph.device_keys (
  key_hash     text primary key check (key_hash ~ '^[0-9a-f]{64}$'),
  label        text not null check (char_length(label) between 1 and 80),
  kind         text not null check (kind in ('inbox', 'pos')),
  created_at   timestamptz not null default now(),
  last_used_at timestamptz
);

-- -----------------------------------------------------------------------------------------------------
-- Views للبوت والموقع
-- -----------------------------------------------------------------------------------------------------
-- الرصيد اللي يتباع منه: الأماكن اللي بتتحسب بس، ومن غير المنتهي
create view ph.v_onhand with (security_invoker = true) as
select sb.item_id, sum(sb.qty_units) as units
from ph.stock_balances sb
join ph.locations l on l.id = sb.location_id
join ph.batches b on b.id = sb.batch_id
where l.counts_as_stock and (b.expiry is null or b.expiry >= current_date)
group by sb.item_id;

-- البيع في آخر 30 يوم (بعد المرتجع)
create view ph.v_sales_30d with (security_invoker = true) as
select x.item_id, sum(x.units) as units
from (
  select sl.item_id, sl.qty_units as units
  from ph.sale_lines sl join ph.sales s on s.id = sl.sale_id
  where s.status = 'posted' and s.business_day > ph.business_day() - 30
  union all
  select rl.item_id, -rl.qty_units
  from ph.sale_return_lines rl join ph.sale_returns r on r.id = rl.return_id
  where r.business_day > ph.business_day() - 30
) x
group by x.item_id;

-- النواقص: الرصيد أقل من الحد الأدنى (أو أقل من بيع أسبوع لو مفيش حد متسجل).
-- بتشتغل بصلاحية صاحب القاعدة + شرط الدور، عشان البوت يشوف النواقص من غير ما يشوف فواتير البيع نفسها
create view ph.v_shortages as
select i.id as item_id, i.name_en, i.name_ar, i.pack_parts,
       coalesce(o.units, 0)                                   as onhand_units,
       coalesce(s.units, 0)                                   as sold_30d_units,
       coalesce(r.min_units, ceil(coalesce(s.units, 0) * 7 / 30.0)) as min_units,
       coalesce(m.order_packs,
                greatest(1, ceil((coalesce(r.max_units, coalesce(s.units, 0)) - coalesce(o.units, 0)) / i.pack_parts))) as order_packs,
       (m.order_packs is not null)                             as qty_by_owner,
       (select so.name from ph.purchase_order_lines pl
          join ph.purchase_orders po on po.id = pl.order_id
          join ph.suppliers so on so.id = po.supplier_id
         where pl.item_id = i.id and po.status = 'sent' and ph.business_day(po.sent_at) = ph.business_day()
         order by po.sent_at desc limit 1)                     as ordered_today_from
from ph.items i
left join ph.v_onhand o on o.item_id = i.id
left join ph.v_sales_30d s on s.item_id = i.id
left join ph.item_stock_rules r on r.item_id = i.id
left join ph.shortage_marks m on m.item_id = i.id
where i.active and i.track_stock
  and ph.has_role(array['owner', 'manager', 'pharmacist', 'cashier', 'bot'])
  and (m.deferred_until is null or m.deferred_until < current_date)
  and coalesce(o.units, 0) < coalesce(r.min_units, ceil(coalesce(s.units, 0) * 7 / 30.0))
  and coalesce(r.min_units, ceil(coalesce(s.units, 0) * 7 / 30.0)) > 0;

-- أحسن خصم لكل صنف: آخر عرض من كل مورد (وارد أو قايمة في آخر 30 يوم) أو آخر فاتورة شرا فعلية، والأحدث بيكسب.
-- نفس فكرة v_shortages: البوت يشوف نسبة الخصم بس، مش الفواتير
create view ph.v_best_offer as
with seen as (
  select o.item_id, o.supplier_id, o.discount_pct, o.offered_at as at, o.source
  from ph.supplier_offers o
  where o.discount_pct is not null and o.match = 'sure' and o.offered_at > now() - interval '30 days'
  union all
  select l.item_id, pi.supplier_id, round(l.real_discount * 100, 2), pi.posted_at, 'purchase'
  from ph.purchase_invoice_lines l join ph.purchase_invoices pi on pi.id = l.invoice_id
  where pi.status = 'posted' and l.real_discount is not null
),
latest as (
  select distinct on (item_id, supplier_id) item_id, supplier_id, discount_pct, at, source
  from seen order by item_id, supplier_id, at desc
),
ranked as (
  select l.*, row_number() over (partition by item_id order by discount_pct desc, at desc) as rnk,
         count(*) over (partition by item_id) as suppliers_count
  from latest l
)
select b.item_id, b.supplier_id as best_supplier_id, b.discount_pct as best_pct, b.source as best_source, b.at as best_at,
       s2.supplier_id as second_supplier_id, s2.discount_pct as second_pct,
       b.discount_pct - coalesce(s2.discount_pct, b.discount_pct) as gap_pct, b.suppliers_count
from ranked b left join ranked s2 on s2.item_id = b.item_id and s2.rnk = 2
where b.rnk = 1 and ph.has_role(array['owner', 'manager', 'pharmacist', 'bot']);

-- -----------------------------------------------------------------------------------------------------
-- الموقع: كتالوج من غير كميات ولا تكلفة (متاح / تحت الطلب)، وطلب جديد. دول بس اللي anon يقدر يناديهم
-- -----------------------------------------------------------------------------------------------------
create function ph.store_catalog(q text default null, max_rows integer default 60)
returns table (id bigint, name_en text, name_ar text, price numeric, available boolean, needs_rx boolean, category text)
language sql stable security definer set search_path = '' as $$
  select i.id, i.name_en, i.name_ar, i.public_price, coalesce(o.units, 0) > 0, i.needs_rx or i.is_controlled, c.code
  from ph.items i
  left join ph.v_onhand o on o.item_id = i.id
  left join ph.categories c on c.id = i.category_id
  where i.active and i.public_price is not null and not i.is_controlled
    and (q is null or i.name_en ilike '%' || btrim(q) || '%' or i.name_ar ilike '%' || btrim(q) || '%')
  order by (coalesce(o.units, 0) > 0) desc, i.name_en
  limit least(greatest(coalesce(max_rows, 60), 1), 200)
$$;

create function ph.store_place_order(p jsonb) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_items jsonb := '[]';
  l       jsonb;
  it      ph.items;
  v_qty   integer;
  v_total numeric := 0;
  v_id    bigint;
begin
  if jsonb_typeof(p -> 'items') <> 'array' or jsonb_array_length(p -> 'items') not between 1 and 50 then
    raise exception 'الطلب لازم يبقى فيه من 1 لـ 50 صنف';
  end if;
  for l in select * from jsonb_array_elements(p -> 'items') loop
    select * into it from ph.items where id = (l ->> 'id')::bigint and active and not is_controlled and public_price is not null;
    if not found then raise exception 'صنف مش متاح على الموقع: %', l ->> 'id'; end if;
    v_qty := (l ->> 'qty')::integer;
    if v_qty is null or v_qty not between 1 and 20 then raise exception 'كمية غلط'; end if;
    -- السعر من القاعدة، مش من المتصفح
    v_items := v_items || jsonb_build_object('item_id', it.id, 'name', it.name_en, 'packs', v_qty, 'price', it.public_price);
    v_total := v_total + v_qty * it.public_price;
  end loop;
  insert into ph.online_orders (name, phone, address, notes, items, total)
  values (btrim(p ->> 'name'), p ->> 'phone', btrim(p ->> 'address'), p ->> 'notes', v_items, v_total)
  returning id into v_id;
  return v_id;
end $$;
