-- =====================================================================================================
-- نظام صيدلية عسكر — قاعدة البيانات (1 من 10): الأساس
-- =====================================================================================================
-- الحالة: تصميم مجرَّب على Postgres محلي بس. ماتطبقش على Supabase.
--
-- قواعد القاعدة كلها (الملفات من 01 لـ 10 بتلتزم بيها):
--   1) أي حركة مخزون أو فلوس = سطر في دفتر (stock_moves، money_moves، party_ledger). الدفتر مابيتعدلش ولا بيتمسح؛
--      الغلط بيتصلح بمستند عكسي (مرتجع أو تسوية).
--   2) الدفاتر مابيكتبش فيها غير دوال الترحيل (post_*) في عملية واحدة: يا كله يتسجل يا ولا حاجة.
--      لا الكاشير ولا البوت ولا الموقع بيكتبوا في دفتر مباشرة.
--   3) المستند بعد الترحيل (posted) مابيتعدلش.
--   4) الرصيد (stock_balances) بيتحدث مع كل حركة في نفس العملية، ومابيبقاش بالسالب إلا لو الإعداد سمح.
--   5) الكميات بالوحدة الصغيرة (qty_units)، والعرض «علب + وحدات» بـ pack_parts. السعر على التشغيلة (القديم بسعره).
--   6) RLS على كل جدول. anon مالوش غير دوال الموقع.
--   7) كل مستند له رقم مسلسل لكل نوع وفرع وسنة (S-2026-000123).
-- الرجوع: drop schema ph cascade;
-- =====================================================================================================

create schema if not exists ph;
create schema if not exists extensions;   -- نفس مكان الإضافات في Supabase
create extension if not exists pg_trgm with schema extensions;   -- البحث بأي جزء من الاسم وبالغلط البسيط

-- -----------------------------------------------------------------------------------------------------
-- الإعدادات (سطر واحد) والفروع
-- -----------------------------------------------------------------------------------------------------
create table ph.settings (
  id                   smallint primary key default 1 check (id = 1),
  pharmacy_name        text not null check (char_length(pharmacy_name) between 2 and 120),
  time_zone            text not null default 'Africa/Cairo',
  day_starts_at        smallint not null default 6 check (day_starts_at between 0 and 12), -- يوم الصيدلية من 6 الصبح لـ 6 الصبح
  allow_negative_stock boolean not null default false,  -- البيع قبل إدخال فاتورة الشرا (مش مستحب)
  near_expiry_days     integer not null default 90 check (near_expiry_days between 7 and 730),
  updated_at           timestamptz not null default now()
);

create table ph.branches (
  id      smallint generated always as identity primary key,
  name    text not null unique check (char_length(name) between 2 and 80),
  phone   text check (phone ~ '^[0-9]{8,15}$'),
  address text check (char_length(address) <= 300),
  active  boolean not null default true
);

-- يوم الصيدلية: بيع الساعة 1 بالليل بيتحسب على اليوم اللي قبله
create function ph.business_day(ts timestamptz default now()) returns date
language sql stable set search_path = '' as $$
  select coalesce(
    (select ((ts at time zone s.time_zone) - make_interval(hours => s.day_starts_at))::date from ph.settings s where s.id = 1),
    ((ts at time zone 'Africa/Cairo') - interval '6 hours')::date)
$$;

-- -----------------------------------------------------------------------------------------------------
-- الموظفين والأدوار
--   owner = كل حاجة · manager = كل حاجة غير الإعدادات والموظفين · pharmacist = بيع وشرا ومخزن وعملاء
--   cashier = بيع وتحصيل من العملاء · delivery = طلباته بس
-- -----------------------------------------------------------------------------------------------------
create table ph.staff (
  user_id            uuid primary key references auth.users (id),
  branch_id          smallint references ph.branches (id),
  name               text not null check (char_length(name) between 2 and 80),
  role               text not null check (role in ('owner', 'manager', 'pharmacist', 'cashier', 'delivery')),
  can_override_limit boolean not null default false,   -- يبيع آجل فوق حد العميل
  active             boolean not null default true,
  created_at         timestamptz not null default now()
);

create function ph.my_role() returns text
language sql stable security definer set search_path = '' as $$
  select s.role from ph.staff s where s.user_id = auth.uid() and s.active
$$;

create function ph.has_role(roles text[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce(ph.my_role() = any (roles), false)
$$;

create function ph.require_role(roles text[]) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not ph.has_role(roles) then
    raise exception 'مش مسموح: دورك (%) مايقدرش يعمل كده', coalesce(ph.my_role(), 'مش موظف') using errcode = '42501';
  end if;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- ترقيم المستندات: نوع-سنة-مسلسل لكل فرع، من غير تكرار حتى مع كاشيرين في نفس اللحظة
-- -----------------------------------------------------------------------------------------------------
create table ph.doc_counters (
  doc_type  text not null,
  branch_id smallint not null references ph.branches (id),
  year      smallint not null,
  last_no   integer not null default 0,
  primary key (doc_type, branch_id, year)
);

create function ph.next_doc_no(p_type text, p_branch smallint, p_day date default null) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_year smallint := extract(year from coalesce(p_day, ph.business_day()));
  v_no   integer;
begin
  insert into ph.doc_counters as c (doc_type, branch_id, year, last_no)
  values (p_type, p_branch, v_year, 1)
  on conflict (doc_type, branch_id, year) do update set last_no = c.last_no + 1
  returning c.last_no into v_no;
  return p_type || '-' || v_year || '-' || lpad(v_no::text, 6, '0');
end $$;

-- -----------------------------------------------------------------------------------------------------
-- المرفقات: صور الفواتير والإيصالات والروشتات (الملف نفسه في bucket خاص)
-- -----------------------------------------------------------------------------------------------------
create table ph.attachments (
  id          bigint generated always as identity primary key,
  file_path   text not null unique check (char_length(file_path) between 3 and 300),
  kind        text not null check (kind in ('image', 'pdf', 'sheet')),
  source      text not null default 'upload' check (source in ('upload', 'whatsapp', 'store')),
  doc_type    text,                        -- purchase_invoice / payment / expense / prescription ...
  doc_id      bigint,
  note        text check (char_length(note) <= 500),
  received_at timestamptz not null default now(),
  by_user     uuid default auth.uid()
);
create index on ph.attachments (doc_type, doc_id);

-- -----------------------------------------------------------------------------------------------------
-- سجل التعديلات + حماية الدفاتر والمستندات المرحّلة
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

-- الدفاتر: مفيش تعديل ولا مسح أبدًا
create function ph.forbid_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'الدفتر % مابيتعدلش ولا بيتمسح: اعمل مستند عكسي (مرتجع أو تسوية)', tg_table_name using errcode = '55000';
end $$;

-- رأس المستند: بعد الترحيل مابيتعدلش ولا بيتمسح
create function ph.forbid_posted_header() returns trigger
language plpgsql set search_path = '' as $$
begin
  if old.status = 'posted' then
    raise exception 'المستند % اترحّل: مابيتعدلش. اعمل مستند عكسي', coalesce(old.no, old.id::text) using errcode = '55000';
  end if;
  return coalesce(new, old);
end $$;

-- سطور المستند: بتتقفل مع الرأس. tg_argv[0] = جدول الرأس، tg_argv[1] = عمود الربط
create function ph.forbid_posted_lines() returns trigger
language plpgsql set search_path = '' as $$
declare
  v_id     bigint := (to_jsonb(coalesce(new, old)) ->> tg_argv[1])::bigint;
  v_status text;
begin
  execute format('select status from ph.%I where id = $1', tg_argv[0]) into v_status using v_id;
  if v_status = 'posted' then
    raise exception 'سطور مستند مرحّل مابتتعدلش (%)', tg_table_name using errcode = '55000';
  end if;
  return coalesce(new, old);
end $$;
