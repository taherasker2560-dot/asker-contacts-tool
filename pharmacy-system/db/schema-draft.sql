-- =====================================================================================================
-- نظام صيدلية عسكر — مسودة قاعدة البيانات (schema اسمها ph)
-- =====================================================================================================
-- الحالة: مسودة تصميم بس. ماتتطبقتش على Supabase.
--   التطبيق محتاج: موافقة المالك + تجربة على نسخة منفصلة (Supabase branch) + خطة رجوع.
-- ليه schema منفصلة: جداول البوت الحالية (ar_*) بتفضل زي ما هي ومحدش بيكتب فيها من هنا.
--   المرحلة الأولى بتقرا منها بـ views (الملف phase1-views.sql).
-- الكميات: كل الكميات بتتسجل بالوحدة الصغيرة (الشريط/الأمبول/الكيس) في qty_units،
--   وبتتعرض «علب + وحدات» بـ pack_parts، زي ar_stock (packs/units/parts) دلوقتي.
-- الأصناف: id الصنف = نفس رقم الصنف في فارمافلاي، عشان الربط يفضل سهل لحد ما (ولو) نستغنى عنه.
-- الرجوع (لو اتطبقت): drop schema ph cascade;
-- =====================================================================================================

create schema if not exists ph;

-- -----------------------------------------------------------------------------------------------------
-- 0) الموظفين والصلاحيات
-- -----------------------------------------------------------------------------------------------------
create table ph.staff (
  user_id    uuid primary key references auth.users (id),
  name       text not null check (char_length(name) between 2 and 80),
  role       text not null check (role in ('owner', 'pharmacist', 'assistant', 'delivery')),
  active     boolean not null default true,
  created_at timestamptz not null default now()
);
comment on table ph.staff is 'مين بيستخدم البرنامج ودوره. owner = كل حاجة، pharmacist = بيع ومخزون ونواقص وعملاء، assistant = بيع وبحث رصيد، delivery = طلباته بس.';

create function ph.my_role() returns text
language sql stable security definer set search_path = '' as $$
  select s.role from ph.staff s where s.user_id = auth.uid() and s.active
$$;

create function ph.has_role(roles text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(ph.my_role() = any (roles), false)
$$;

-- -----------------------------------------------------------------------------------------------------
-- 1) الأصناف
-- -----------------------------------------------------------------------------------------------------
create table ph.generics (
  gkey        text primary key,                       -- نفس gkey في ar_store_generic
  ingredients text not null check (char_length(ingredients) between 2 and 400),
  form        text
);
comment on table ph.generics is 'المادة الفعالة + الشكل. أصناف نفس المجموعة = بدايل لبعض.';

create table ph.items (
  id            bigint primary key,                   -- رقم الصنف في فارمافلاي
  name_en       text not null check (char_length(name_en) between 2 and 250),
  name_ar       text check (char_length(name_ar) <= 250),
  spoken_name   text check (char_length(spoken_name) <= 120),   -- إزاي الموبايل ينطقه (زي ar_names.spoken_name)
  form          text,                                 -- tab, cap, syrup, inj, cream ...
  strength      text,
  pack_parts    integer not null default 1 check (pack_parts between 1 and 10000), -- وحدات في العلبة
  category      text,                                 -- نفس تصنيفات الموقع (ar_store_items.cat)
  gkey          text references ph.generics (gkey),
  needs_rx      boolean not null default false,       -- محتاج روشتة
  is_controlled boolean not null default false,       -- جدول: بيتسجل في دفتر خاص
  is_fridge     boolean not null default false,       -- تلاجة
  public_price  numeric(12, 2) check (public_price > 0),          -- سعر العلبة للجمهور
  is_active     boolean not null default true,
  source        text not null default 'pharmafly' check (source in ('pharmafly', 'ph')),
  updated_at    timestamptz not null default now()
);
create index on ph.items (gkey);
create index on ph.items (category);

create table ph.item_barcodes (
  barcode text primary key check (barcode ~ '^[0-9A-Za-z-]{4,40}$'),
  item_id bigint not null references ph.items (id)
);

-- -----------------------------------------------------------------------------------------------------
-- 2) الموردين (لازم قبل المخزون عشان مخازن الانتظار)
-- -----------------------------------------------------------------------------------------------------
create table ph.suppliers (
  id     integer generated always as identity primary key,
  code   text unique check (code ~ '^[A-Z0-9_]{2,20}$'),   -- NEWCITY, REDA, ELFATH, AMG, PHARMA, IBNSINA
  name   text not null unique check (char_length(name) between 2 and 80),
  kind   text not null check (kind in ('warehouse', 'company')),   -- مخزن / شركة توزيع
  pf_ref     text unique,                 -- رقم المورد في فارمافلاي
  balance_pf numeric(12, 2),              -- رصيده في فارمافلاي (قراية بس من اللاب، المرحلة ١)
  balance_at timestamptz,
  active boolean not null default true
);

create table ph.supplier_reps (
  id          integer generated always as identity primary key,
  supplier_id integer not null references ph.suppliers (id),
  chat_name   text not null unique check (char_length(chat_name) between 2 and 80), -- زي ar_suppliers.name: «مخزن ... (اسم)»
  phone       text check (phone ~ '^[0-9]{8,15}$'),
  shift       text not null default 'any' check (shift in ('day', 'night', 'any')),
  active      boolean not null default true
);
comment on table ph.supplier_reps is 'المناديب. الوارد التلقائي بيتعرف على الشات من chat_name (نفس قاعدة البوت: كل الكلمات موجودة في عنوان الإشعار).';

create table ph.supplier_item_names (
  supplier_id   integer not null references ph.suppliers (id),
  name_norm     text not null,
  supplier_name text not null,
  item_id       bigint not null references ph.items (id),
  first_seen    date not null default current_date,
  last_seen     date not null default current_date,
  primary key (supplier_id, name_norm)
);
comment on table ph.supplier_item_names is 'اسم الصنف عند المورد ← صنفنا (= ar_supplier_aliases).';

-- -----------------------------------------------------------------------------------------------------
-- 3) المخزون: أماكن + تشغيلات + دفتر حركة. الرصيد = مجموع الحركة.
-- -----------------------------------------------------------------------------------------------------
create table ph.locations (
  id              smallint generated always as identity primary key,
  name            text not null unique check (char_length(name) between 2 and 80),
  kind            text not null check (kind in ('main', 'waiting', 'returns', 'damaged')),
  supplier_id     integer references ph.suppliers (id),     -- لمخازن الانتظار (ابن سينا، فارما)
  counts_as_stock boolean not null default true,            -- قرار المالك: مخزن الانتظار يتحسب ولا لأ
  check (kind <> 'waiting' or supplier_id is not null)
);

create table ph.batches (
  id               bigint generated always as identity primary key,
  item_id          bigint not null references ph.items (id),
  expiry           date,
  unit_cost        numeric(12, 4) check (unit_cost >= 0),       -- تكلفة الوحدة الصغيرة بعد الخصم والبونص
  public_price     numeric(12, 2) check (public_price > 0),     -- سعر العلبة وقت الشرا
  purchase_line_id bigint,                                      -- سطر فاتورة الشرا (بيتربط تحت)
  created_at       timestamptz not null default now()
);
create index on ph.batches (item_id, expiry);

create table ph.stock_moves (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  item_id     bigint not null references ph.items (id),
  batch_id    bigint references ph.batches (id),
  location_id smallint not null references ph.locations (id),
  qty_units   numeric(12, 2) not null check (qty_units <> 0),   -- موجب = دخل، سالب = خرج
  kind        text not null check (kind in ('purchase', 'sale', 'sale_return', 'purchase_return',
                                            'transfer', 'adjust', 'expired', 'count')),
  ref_type    text,                                             -- sales / purchase_invoices / ...
  ref_id      bigint,
  by_user     uuid default auth.uid(),
  note        text check (char_length(note) <= 300)
);
create index on ph.stock_moves (item_id, location_id);
create index on ph.stock_moves (at);
comment on table ph.stock_moves is 'دفتر الحركة: مفيش تعديل رصيد من غير سطر هنا. الرصيد والجرد والتقارير بتتحسب منه.';

create view ph.v_stock with (security_invoker = true) as
select m.item_id,
       m.location_id,
       m.batch_id,
       b.expiry,
       sum(m.qty_units)                                     as qty_units,
       floor(sum(m.qty_units) / i.pack_parts)               as packs,
       sum(m.qty_units) - floor(sum(m.qty_units) / i.pack_parts) * i.pack_parts as units
from ph.stock_moves m
join ph.items i on i.id = m.item_id
left join ph.batches b on b.id = m.batch_id
group by m.item_id, m.location_id, m.batch_id, b.expiry, i.pack_parts
having sum(m.qty_units) <> 0;

create table ph.stock_counts (
  id         bigint generated always as identity primary key,
  started_at timestamptz not null default now(),
  closed_at  timestamptz,
  scope      text,                        -- رف / تصنيف / الكل
  by_user    uuid default auth.uid()
);
create table ph.stock_count_lines (
  count_id      bigint not null references ph.stock_counts (id),
  item_id       bigint not null references ph.items (id),
  location_id   smallint not null references ph.locations (id),
  system_units  numeric(12, 2) not null,
  counted_units numeric(12, 2) not null check (counted_units >= 0),
  primary key (count_id, item_id, location_id)
);

-- -----------------------------------------------------------------------------------------------------
-- 4) النواقص والطلبيات وقوايم الأسعار
-- -----------------------------------------------------------------------------------------------------
create table ph.shortages (
  item_id       bigint primary key references ph.items (id),
  status        text not null default 'active' check (status in ('active', 'deferred', 'off')),
  min_units     numeric(12, 2) check (min_units >= 0),     -- أقل رصيد قبل ما يبقى ناقص
  suggested_qty numeric(12, 2) check (suggested_qty >= 0), -- اقتراح الحقيبة (زي ar_shortages.suggested_qty)
  order_qty     numeric(12, 2) check (order_qty > 0),      -- اللي المالك كتبه، بيكسب
  since         timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create table ph.price_lists (
  id          bigint generated always as identity primary key,
  supplier_id integer not null references ph.suppliers (id),
  list_date   date not null,
  received_at timestamptz not null default now(),
  source_file text,
  rows_count  integer
);
create table ph.price_list_lines (
  id            bigint generated always as identity primary key,
  list_id       bigint not null references ph.price_lists (id),
  item_id       bigint references ph.items (id),
  supplier_name text not null,
  price         numeric(12, 2),
  discount_pct  numeric(5, 2) check (discount_pct between 0 and 100),
  match_status  text not null check (match_status in ('strong', 'good', 'weak', 'none')),
  review        text not null default 'pending' check (review in ('pending', 'accepted', 'rejected', 'not_stocked'))
);
create index on ph.price_list_lines (item_id);

create table ph.purchase_orders (
  id           bigint generated always as identity primary key,
  supplier_id  integer not null references ph.suppliers (id),
  rep_id       integer references ph.supplier_reps (id),
  created_at   timestamptz not null default now(),
  sent_at      timestamptz,                -- لما المالك يدوس «علّمها اتطلب» (هو اللي بيبعت من الواتس)
  status       text not null default 'draft' check (status in ('draft', 'sent', 'partial', 'received', 'cancelled')),
  message_text text check (char_length(message_text) <= 20000),
  by_user      uuid default auth.uid()
);
create table ph.purchase_order_lines (
  order_id     bigint not null references ph.purchase_orders (id),
  item_id      bigint not null references ph.items (id),
  qty_packs    numeric(12, 2) not null check (qty_packs > 0),
  expected_pct numeric(5, 2),              -- الخصم المتوقع وقت الطلب
  primary key (order_id, item_id)
);

-- -----------------------------------------------------------------------------------------------------
-- 5) حسابات الموردين: فواتير شرا، مرتجعات/إشعارات، تحصيل
-- -----------------------------------------------------------------------------------------------------
create table ph.purchase_invoices (
  id           bigint generated always as identity primary key,
  supplier_id  integer not null references ph.suppliers (id),
  doc_no       text check (char_length(doc_no) <= 60),
  invoice_date date not null,
  document_id  uuid,                       -- صورة الفاتورة في ar_documents
  order_id     bigint references ph.purchase_orders (id),
  total        numeric(12, 2) not null default 0 check (total >= 0),   -- المطلوب دفعه
  status       text not null default 'draft' check (status in ('draft', 'reviewed', 'entered_pharmafly', 'posted')),
  created_at   timestamptz not null default now(),
  by_user      uuid default auth.uid(),
  unique (supplier_id, doc_no)
);
comment on column ph.purchase_invoices.status is 'draft = اتقرت من الصورة، reviewed = المالك راجعها، entered_pharmafly = اتدخلت في فارمافلاي، posted = نزلت مخزون عندنا (المرحلة ٣).';

create table ph.purchase_invoice_lines (
  id           bigint generated always as identity primary key,
  invoice_id   bigint not null references ph.purchase_invoices (id),
  item_id      bigint not null references ph.items (id),
  qty_packs    numeric(12, 2) not null check (qty_packs > 0),
  bonus_packs  numeric(12, 2) not null default 0 check (bonus_packs >= 0),
  public_price numeric(12, 2) not null check (public_price > 0),
  cost_total   numeric(12, 2) not null check (cost_total >= 0),
  expiry       date,
  -- الخصم الفعلي بعد البونص (نفس معادلة مستشار الطلبيات):
  -- 1 − التكلفة ÷ (سعر الجمهور × (العدد + البونص))
  real_discount numeric(7, 4) generated always as
    (1 - cost_total / nullif(public_price * (qty_packs + bonus_packs), 0)) stored
);
create index on ph.purchase_invoice_lines (item_id);

alter table ph.batches
  add constraint batches_purchase_line_fk foreign key (purchase_line_id) references ph.purchase_invoice_lines (id);

create table ph.purchase_returns (
  id             bigint generated always as identity primary key,
  supplier_id    integer not null references ph.suppliers (id),
  created_at     timestamptz not null default now(),
  reason         text not null check (reason in ('expiry', 'damaged', 'wrong_item', 'overstock', 'other')),
  status         text not null default 'draft' check (status in ('draft', 'sent', 'credited', 'refused')),
  credit_note_no text check (char_length(credit_note_no) <= 60),   -- رقم الإشعار
  document_id    uuid,
  total          numeric(12, 2) not null default 0 check (total >= 0)
);
create table ph.purchase_return_lines (
  return_id bigint not null references ph.purchase_returns (id),
  item_id   bigint not null references ph.items (id),
  batch_id  bigint references ph.batches (id),
  qty_units numeric(12, 2) not null check (qty_units > 0),
  value     numeric(12, 2) check (value >= 0),
  primary key (return_id, item_id)
);

create table ph.supplier_payments (
  id          bigint generated always as identity primary key,
  supplier_id integer not null references ph.suppliers (id),
  paid_on     date not null default current_date,
  amount      numeric(12, 2) not null check (amount > 0),
  method      text not null check (method in ('cash', 'transfer', 'cheque', 'wallet')),
  receipt_no  text check (char_length(receipt_no) <= 60),   -- إيصال التحصيل
  document_id uuid,
  by_user     uuid default auth.uid()
);

create view ph.v_supplier_balance with (security_invoker = true) as
select s.id as supplier_id,
       s.name,
       coalesce(i.total, 0)                                         as invoices,
       coalesce(r.total, 0)                                         as returns,
       coalesce(p.total, 0)                                         as payments,
       coalesce(i.total, 0) - coalesce(r.total, 0) - coalesce(p.total, 0) as balance
from ph.suppliers s
left join (select supplier_id, sum(total) total from ph.purchase_invoices group by 1) i on i.supplier_id = s.id
left join (select supplier_id, sum(total) total from ph.purchase_returns where status = 'credited' group by 1) r on r.supplier_id = s.id
left join (select supplier_id, sum(amount) total from ph.supplier_payments group by 1) p on p.supplier_id = s.id;

-- -----------------------------------------------------------------------------------------------------
-- 6) العملاء (من أداة التواصل + الموقع + الكاشير)
-- -----------------------------------------------------------------------------------------------------
create table ph.customers (
  id           bigint generated always as identity primary key,
  name         text not null check (char_length(name) between 1 and 80),
  phone        text unique check (phone ~ '^[0-9]{8,15}$'),   -- نفس normPhone في أداة التواصل: 2010xxxxxxxx
  area         text check (char_length(area) <= 80),
  address      text check (char_length(address) <= 300),
  outreach_day smallint check (outreach_day between 0 and 6), -- مجموعة اليوم: 0 = السبت … 6 = الجمعة
  whatsapp_ok  boolean not null default true,                 -- لو قال «ماتبعتليش» تبقى false
  source       text not null default 'csv' check (source in ('csv', 'store', 'counter', 'phone', 'pharmafly')),
  pf_ref       text unique,                                   -- رقم العميل في فارمافلاي (لو له حساب هناك)
  credit_limit numeric(12, 2) check (credit_limit >= 0),      -- حد العميل: أقصى مبلغ يفضل عليه
  balance_pf   numeric(12, 2),                                -- اللي عليه في فارمافلاي (قراية بس، المرحلة ١)
  balance_at   timestamptz,
  notes        text check (char_length(notes) <= 500),
  created_at   timestamptz not null default now()
);

create table ph.customer_meds (
  customer_id bigint not null references ph.customers (id),
  item_id     bigint not null references ph.items (id),
  every_days  integer not null check (every_days between 1 and 365),   -- العلبة بتخلص كل كام يوم
  last_bought date,
  active      boolean not null default true,
  primary key (customer_id, item_id)
);
comment on table ph.customer_meds is 'الأدوية المزمنة: تذكير «علبتك قربت تخلص» برسالة جاهزة والمالك يبعتها بنفسه.';

create view ph.v_refills_due with (security_invoker = true) as
select m.customer_id, m.item_id, m.last_bought, m.last_bought + m.every_days as due_on
from ph.customer_meds m
where m.active and m.last_bought is not null and m.last_bought + m.every_days <= current_date + 3;

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

create table ph.prescriptions (
  id          bigint generated always as identity primary key,
  customer_id bigint references ph.customers (id),
  received_at timestamptz not null default now(),
  file_path   text not null,                 -- bucket خاص
  doctor      text check (char_length(doctor) <= 80),
  note        text check (char_length(note) <= 500)
);

create table ph.customer_credit (
  id          bigint generated always as identity primary key,
  customer_id bigint not null references ph.customers (id),
  at          timestamptz not null default now(),
  amount      numeric(12, 2) not null check (amount <> 0),   -- موجب = عليه، سالب = دفع
  sale_id     bigint,
  note        text check (char_length(note) <= 300),
  by_user     uuid default auth.uid()
);
comment on table ph.customer_credit is 'دفتر الآجل عندنا (المرحلة ٣، لما الكاشير يبقى بتاعنا). قبلها الرصيد بييجي من فارمافلاي في customers.balance_pf.';

-- «اللي عليهم فلوس وحد كل عميل» (شاشة العملاء في البوت): الأكبر الأول، واللي عدّى حده متعلّم
create view ph.v_customer_dues with (security_invoker = true) as
select c.id, c.name, c.phone, c.credit_limit,
       c.balance_pf as balance,
       c.balance_at,
       (c.credit_limit is not null and c.balance_pf > c.credit_limit) as over_limit
from ph.customers c
where c.balance_pf > 0;

-- -----------------------------------------------------------------------------------------------------
-- 7) المبيعات
--   المرحلة ١ و٢: ملخص يومي جاي من فارمافلاي (daily_sales) للتقارير والاقتراحات.
--   المرحلة ٣ (بقرار): الكاشير بتاعنا بيكتب في sales و sale_lines وبيعمل حركة مخزون.
-- -----------------------------------------------------------------------------------------------------
create table ph.daily_sales (
  day       date not null,
  item_id   bigint not null references ph.items (id),
  qty_units numeric(12, 2) not null,
  value     numeric(12, 2) not null,
  primary key (day, item_id)
);

create table ph.shifts (
  id           bigint generated always as identity primary key,
  opened_by    uuid not null default auth.uid(),
  opened_at    timestamptz not null default now(),
  closed_at    timestamptz,
  opening_cash numeric(12, 2) not null default 0,
  counted_cash numeric(12, 2),
  note         text check (char_length(note) <= 300)
);

create table ph.sales (
  id          bigint generated always as identity primary key,
  at          timestamptz not null default now(),
  shift_id    bigint references ph.shifts (id),
  customer_id bigint references ph.customers (id),
  channel     text not null default 'counter' check (channel in ('counter', 'phone', 'store', 'delivery')),
  status      text not null default 'done' check (status in ('done', 'returned', 'cancelled')),
  subtotal    numeric(12, 2) not null default 0,
  discount    numeric(12, 2) not null default 0 check (discount >= 0),
  total       numeric(12, 2) generated always as (subtotal - discount) stored,
  source      text not null default 'ph' check (source in ('ph', 'pharmafly')),
  external_id text,                                     -- رقم الفاتورة في فارمافلاي وقت التشغيل جنب بعض
  by_user     uuid default auth.uid()
);
create index on ph.sales (at);

create table ph.sale_lines (
  id         bigint generated always as identity primary key,
  sale_id    bigint not null references ph.sales (id),
  item_id    bigint not null references ph.items (id),
  batch_id   bigint references ph.batches (id),
  qty_units  numeric(12, 2) not null check (qty_units > 0),
  unit_price numeric(12, 4) not null check (unit_price >= 0),   -- سعر الوحدة الصغيرة
  line_total numeric(12, 2) not null check (line_total >= 0)
);

create table ph.sale_payments (
  sale_id bigint not null references ph.sales (id),
  method  text not null check (method in ('cash', 'card', 'wallet', 'instapay', 'credit')),
  amount  numeric(12, 2) not null check (amount > 0),
  primary key (sale_id, method)
);

alter table ph.customer_credit
  add constraint customer_credit_sale_fk foreign key (sale_id) references ph.sales (id);

-- -----------------------------------------------------------------------------------------------------
-- 8) الموقع والتوصيل (طلبات الموقع نفسها في ar_store_orders زي ما هي)
-- -----------------------------------------------------------------------------------------------------
create table ph.deliveries (
  id             bigint generated always as identity primary key,
  sale_id        bigint references ph.sales (id),
  store_order_id bigint,                              -- ar_store_orders.id
  customer_id    bigint references ph.customers (id),
  address        text not null check (char_length(address) between 5 and 300),
  driver         uuid references ph.staff (user_id),
  fee            numeric(12, 2) not null default 0 check (fee >= 0),
  status         text not null default 'new' check (status in ('new', 'out', 'delivered', 'failed')),
  created_at     timestamptz not null default now(),
  delivered_at   timestamptz,
  check (sale_id is not null or store_order_id is not null)
);

-- -----------------------------------------------------------------------------------------------------
-- 9) المصروفات وقفل اليوم (صور الإيصالات في ar_documents زي ما هي)
-- -----------------------------------------------------------------------------------------------------
create table ph.expenses (
  id          bigint generated always as identity primary key,
  spent_on    date not null default current_date,
  category    text not null check (category in ('rent', 'electricity', 'water', 'internet', 'salary', 'delivery', 'other')),
  amount      numeric(12, 2) not null check (amount > 0),
  document_id uuid,
  note        text check (char_length(note) <= 300),
  by_user     uuid default auth.uid()
);

create table ph.cash_days (
  day               date primary key,                   -- يوم الصيدلية: من 6 الصبح لـ 6 الصبح (زي مستشار الطلبيات)
  sales_cash        numeric(12, 2),
  sales_other       numeric(12, 2),
  expenses          numeric(12, 2),
  supplier_payments numeric(12, 2),
  counted_cash      numeric(12, 2),
  closed_by         uuid default auth.uid(),
  closed_at         timestamptz
);

-- -----------------------------------------------------------------------------------------------------
-- 10) سجل التعديلات (مين غيّر إيه وإمتى)
-- -----------------------------------------------------------------------------------------------------
create table ph.audit_log (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  by_user    uuid default auth.uid(),
  table_name text not null,
  action     text not null check (action in ('INSERT', 'UPDATE', 'DELETE')),
  row_data   jsonb,
  old_data   jsonb
);

create function ph.audit() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into ph.audit_log (table_name, action, row_data, old_data)
  values (tg_table_name, tg_op,
          case when tg_op <> 'DELETE' then to_jsonb(new) end,
          case when tg_op <> 'INSERT' then to_jsonb(old) end);
  return coalesce(new, old);
end $$;

-- الجداول اللي فيها فلوس أو رصيد بيتسجل عليها كل تعديل
create trigger audit_purchase_invoices after insert or update or delete on ph.purchase_invoices for each row execute function ph.audit();
create trigger audit_supplier_payments after insert or update or delete on ph.supplier_payments for each row execute function ph.audit();
create trigger audit_stock_moves       after insert or update or delete on ph.stock_moves       for each row execute function ph.audit();
create trigger audit_sales             after insert or update or delete on ph.sales             for each row execute function ph.audit();
create trigger audit_customer_credit   after insert or update or delete on ph.customer_credit   for each row execute function ph.audit();
create trigger audit_expenses          after insert or update or delete on ph.expenses          for each row execute function ph.audit();
create trigger audit_staff             after insert or update or delete on ph.staff             for each row execute function ph.audit();

-- -----------------------------------------------------------------------------------------------------
-- 11) الأمان (RLS): كل جدول مقفول، والمالك بيشوف كل حاجة، والباقي حسب دوره
-- -----------------------------------------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'ph' loop
    execute format('alter table ph.%I enable row level security', t.tablename);
    execute format('create policy owner_all on ph.%I for all to authenticated using (ph.has_role(array[''owner''])) with check (ph.has_role(array[''owner'']))', t.tablename);
  end loop;
end $$;

-- الصيدلي والمساعد: يشوفوا الأصناف والرصيد والنواقص
create policy staff_read on ph.items        for select to authenticated using (ph.has_role(array['pharmacist', 'assistant']));
create policy staff_read on ph.item_barcodes for select to authenticated using (ph.has_role(array['pharmacist', 'assistant']));
create policy staff_read on ph.generics     for select to authenticated using (ph.has_role(array['pharmacist', 'assistant']));
create policy staff_read on ph.locations    for select to authenticated using (ph.has_role(array['pharmacist', 'assistant']));
create policy staff_read on ph.batches      for select to authenticated using (ph.has_role(array['pharmacist', 'assistant']));
create policy staff_read on ph.stock_moves  for select to authenticated using (ph.has_role(array['pharmacist', 'assistant']));
create policy staff_read on ph.shortages    for select to authenticated using (ph.has_role(array['pharmacist', 'assistant']));
-- الصيدلي: يضيف ناقص، ويتعامل مع العملاء والروشتات
create policy pharmacist_add on ph.shortages     for insert to authenticated with check (ph.has_role(array['pharmacist']));
create policy pharmacist_rw  on ph.customers     for all    to authenticated using (ph.has_role(array['pharmacist'])) with check (ph.has_role(array['pharmacist']));
create policy pharmacist_rw  on ph.customer_meds for all    to authenticated using (ph.has_role(array['pharmacist'])) with check (ph.has_role(array['pharmacist']));
create policy pharmacist_rw  on ph.prescriptions for all    to authenticated using (ph.has_role(array['pharmacist'])) with check (ph.has_role(array['pharmacist']));
-- الكاشير (المرحلة ٣): الصيدلي والمساعد بيبيعوا، ومحدش غير المالك بيعدّل فاتورة قديمة
create policy sell_insert on ph.sales         for insert to authenticated with check (ph.has_role(array['pharmacist', 'assistant']));
create policy sell_insert on ph.sale_lines    for insert to authenticated with check (ph.has_role(array['pharmacist', 'assistant']));
create policy sell_insert on ph.sale_payments for insert to authenticated with check (ph.has_role(array['pharmacist', 'assistant']));
-- التوصيل: طلباته بس
create policy driver_own on ph.deliveries for select to authenticated using (driver = auth.uid());
create policy driver_upd on ph.deliveries for update to authenticated using (driver = auth.uid()) with check (driver = auth.uid());
-- كل واحد يشوف سطره في staff
create policy self_read on ph.staff for select to authenticated using (user_id = auth.uid());

-- الصلاحيات العادية لحساب مسجل دخول بس (anon مالوش أي حاجة). الـ RLS فوق هي اللي بتحدد الصفوف.
-- في Supabase لازم كمان نضيف ph في «Exposed schemas» عشان الصفحة تقدر تقراها.
grant usage on schema ph to authenticated;
grant select, insert, update, delete on all tables in schema ph to authenticated;
grant usage, select on all sequences in schema ph to authenticated;
revoke execute on function ph.audit() from public;
grant execute on function ph.my_role(), ph.has_role(text[]) to authenticated;
