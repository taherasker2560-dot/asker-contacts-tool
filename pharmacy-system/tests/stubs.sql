-- بديل صغير لـ Supabase عشان نجرب المسودة على Postgres محلي (مش على قاعدة الصيدلية).
-- auth.users و auth.uid() و role authenticated، وجداول ar_* بالأعمدة اللي الـ views بتقراها بس.
create role authenticated nologin;
create schema auth;
create table auth.users (id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant usage on schema auth to authenticated;
grant execute on function auth.uid() to authenticated;

create table public.ar_store_items (id bigint primary key, name text not null, status text not null, price numeric,
  cat text, needs_rx boolean not null default false, arabic_name text);
create table public.ar_store_arabic (item_id bigint primary key, arabic_name text not null);
create table public.ar_store_generic (item_id bigint primary key, form text not null, ingredients text not null, gkey text not null);
create table public.ar_stock (item_id bigint primary key, name text not null, arabic_name text, price numeric,
  packs numeric not null default 0, units numeric not null default 0, parts integer, exp_near date,
  other jsonb not null default '[]', data_at text);
create table public.ar_shortages (id uuid primary key default gen_random_uuid(), name_key text unique not null,
  product_name text not null, is_active boolean not null default true, suggested_qty numeric, order_qty numeric);
create table public.ar_names (name_key text primary key, english_name text not null, arabic_name text not null);
create table public.ar_orders (id uuid primary key default gen_random_uuid(), name_key text not null, product_name text not null,
  supplier text, ordered_at timestamptz not null default now());
create table public.ar_supplier_lists (id bigint primary key, supplier text not null, list_date date not null);
create table public.ar_supplier_items (id bigint primary key, list_id bigint not null references public.ar_supplier_lists (id),
  supplier text not null, item_id bigint, price numeric, discount_pct numeric, match_status text not null, review text not null default 'pending');
create table public.ar_inbox (id uuid primary key default gen_random_uuid(), received_at timestamptz not null default now(), hidden_at timestamptz);
create table public.ar_store_orders (id bigint primary key, status text not null default 'new');
create table public.ar_documents (id uuid primary key default gen_random_uuid(), status text not null default 'new');
create table public.ar_sync_log (id bigint primary key, at timestamptz not null default now(), status text not null, dry_run boolean not null);
