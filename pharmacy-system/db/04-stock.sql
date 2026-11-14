-- =====================================================================================================
-- (4 من 10) المخزن: الأماكن، التشغيلات، دفتر الحركة، الرصيد، رصيد أول المدة، التحويل، الجرد
-- =====================================================================================================

create table ph.locations (
  id              smallint generated always as identity primary key,
  branch_id       smallint not null references ph.branches (id),
  name            text not null check (char_length(name) between 2 and 80),
  kind            text not null check (kind in ('main', 'waiting', 'returns', 'damaged')),
  supplier_id     integer references ph.suppliers (id),     -- مخزن الانتظار تبع مورد (ابن سينا، فارما)
  counts_as_stock boolean not null default true,            -- قرار المالك: مخزن الانتظار يتحسب في الرصيد ولا لأ
  is_default_sale boolean not null default false,           -- البيع بيطلع منه لو الكاشير ماحددش
  legacy_id       text unique,                              -- المخزن في فارمافلاي (StoreID)
  unique (branch_id, name),
  check (kind <> 'waiting' or supplier_id is not null)
);

-- التشغيلة: صلاحية + سعر الجمهور اللي عليها + تكلفة الوحدة. كل سطر فاتورة شرا = تشغيلة
create table ph.batches (
  id           bigint generated always as identity primary key,
  item_id      bigint not null references ph.items (id),
  expiry       date,
  public_price numeric(12, 2) check (public_price > 0),     -- سعر العلبة على التشغيلة دي
  unit_cost    numeric(14, 4) check (unit_cost >= 0),       -- تكلفة الوحدة الصغيرة بعد الخصم والبونص
  source       text not null check (source in ('opening', 'purchase', 'unbatched', 'import')),
  legacy_key   text unique,                                 -- التشغيلة في فارمافلاي (للنقل بس)
  created_at   timestamptz not null default now(),
  unique (id, item_id)                                      -- عشان الحركة ماتتسجلش على تشغيلة صنف تاني
);
create index on ph.batches (item_id, expiry);

-- دفتر الحركة: موجب = دخل، سالب = خرج. مابيتعدلش
create table ph.stock_moves (
  id           bigint generated always as identity primary key,
  at           timestamptz not null default now(),
  business_day date not null default ph.business_day(),
  item_id      bigint not null,
  batch_id     bigint not null,
  location_id  smallint not null references ph.locations (id),
  qty_units    numeric(14, 2) not null check (qty_units <> 0),
  unit_cost    numeric(14, 4),
  doc_type     text not null check (doc_type in ('opening', 'purchase', 'purchase_return', 'sale', 'sale_return',
                                                 'transfer', 'count', 'adjust')),
  doc_id       bigint not null,
  by_user      uuid default auth.uid(),
  foreign key (batch_id, item_id) references ph.batches (id, item_id)
);
create index on ph.stock_moves (item_id, at);
create index on ph.stock_moves (doc_type, doc_id);
create index on ph.stock_moves (business_day);

-- الرصيد الحالي لكل صنف × مكان × تشغيلة (بيتحدث مع كل حركة)
create table ph.stock_balances (
  item_id     bigint not null references ph.items (id),
  location_id smallint not null references ph.locations (id),
  batch_id    bigint not null references ph.batches (id),
  qty_units   numeric(14, 2) not null default 0,
  updated_at  timestamptz not null default now(),
  primary key (item_id, location_id, batch_id)
);
create index stock_balances_positive on ph.stock_balances (item_id, location_id) where qty_units > 0;

create function ph.apply_stock_move() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_qty   numeric;
  v_allow boolean;
begin
  if ph.importing() then return new; end if;   -- النقل: الأرصدة بتتحسب مرة واحدة في الآخر
  insert into ph.stock_balances as b (item_id, location_id, batch_id, qty_units, updated_at)
  values (new.item_id, new.location_id, new.batch_id, new.qty_units, now())
  on conflict (item_id, location_id, batch_id)
  do update set qty_units = b.qty_units + excluded.qty_units, updated_at = now()
  returning b.qty_units into v_qty;
  if v_qty < 0 then
    select s.allow_negative_stock into v_allow from ph.settings s where s.id = 1;
    if not coalesce(v_allow, false) then
      raise exception 'الرصيد مايكفيش: % (ناقص % وحدة)', (select i.name_en from ph.items i where i.id = new.item_id), -v_qty
        using errcode = '23514';
    end if;
  end if;
  return new;
end $$;
create trigger stock_moves_apply after insert on ph.stock_moves for each row execute function ph.apply_stock_move();
create trigger stock_moves_locked before update or delete on ph.stock_moves for each row execute function ph.forbid_change();

-- اختيار التشغيلات للبيع أو التحويل: الأقرب صلاحية الأول (FEFO)، والمنتهي مابيتباعش.
-- بتقفل صفوف الرصيد لحد آخر العملية، فكاشيرين مايبيعوش نفس العلبة.
create function ph.pick_batches(p_item bigint, p_location smallint, p_units numeric)
returns table (batch_id bigint, qty_units numeric, public_price numeric, unit_cost numeric)
language plpgsql security definer set search_path = '' as $$
#variable_conflict use_column
declare
  r      record;
  v_left numeric := p_units;
  v_take numeric;
  v_allow boolean;
  v_batch ph.batches;
begin
  for r in
    select sb.batch_id as b_id, sb.qty_units as avail, bt.public_price as b_price, bt.unit_cost as b_cost
    from ph.stock_balances sb
    join ph.batches bt on bt.id = sb.batch_id
    where sb.item_id = p_item and sb.location_id = p_location and sb.qty_units > 0
      and (bt.expiry is null or bt.expiry >= current_date)
    order by bt.expiry nulls last, bt.id
    for update of sb
  loop
    exit when v_left <= 0;
    v_take := least(v_left, r.avail);
    batch_id := r.b_id; qty_units := v_take; public_price := r.b_price; unit_cost := r.b_cost;
    return next;
    v_left := v_left - v_take;
  end loop;

  if v_left > 0 then
    select s.allow_negative_stock into v_allow from ph.settings s where s.id = 1;
    if not coalesce(v_allow, false) then
      raise exception 'الرصيد مايكفيش: % (ناقص % وحدة)', (select i.name_en from ph.items i where i.id = p_item), v_left
        using errcode = '23514';
    end if;
    -- مسموح بالسالب: الباقي على آخر تشغيلة، أو تشغيلة «من غير فاتورة» لحد ما الفاتورة تتدخل
    select * into v_batch from ph.batches b where b.item_id = p_item order by b.id desc limit 1;
    if not found then
      insert into ph.batches (item_id, public_price, source)
      values (p_item, (select i.public_price from ph.items i where i.id = p_item), 'unbatched')
      returning * into v_batch;
    end if;
    batch_id := v_batch.id; qty_units := v_left; public_price := v_batch.public_price; unit_cost := v_batch.unit_cost;
    return next;
  end if;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- رصيد أول المدة (النقل من فارمافلاي): [{item_id, packs, units, expiry, public_price, unit_cost}]
-- -----------------------------------------------------------------------------------------------------
create table ph.stock_openings (
  id          bigint generated always as identity primary key,
  location_id smallint not null references ph.locations (id),
  rows_count  integer not null,
  note        text,
  at          timestamptz not null default now(),
  by_user     uuid default auth.uid()
);

create function ph.post_opening_stock(p_location smallint, p_rows jsonb, p_note text default null) returns bigint
language plpgsql security definer set search_path = '' as $$
declare
  v_id    bigint;
  r       jsonb;
  v_item  ph.items;
  v_batch bigint;
  v_units numeric;
begin
  perform ph.require_role(array['owner']);
  insert into ph.stock_openings (location_id, rows_count, note)
  values (p_location, jsonb_array_length(p_rows), p_note) returning id into v_id;
  for r in select * from jsonb_array_elements(p_rows) loop
    select * into strict v_item from ph.items where id = (r ->> 'item_id')::bigint;
    v_units := coalesce((r ->> 'packs')::numeric, 0) * v_item.pack_parts + coalesce((r ->> 'units')::numeric, 0);
    continue when v_units <= 0;
    insert into ph.batches (item_id, expiry, public_price, unit_cost, source)
    values (v_item.id, (r ->> 'expiry')::date, coalesce((r ->> 'public_price')::numeric, v_item.public_price),
            (r ->> 'unit_cost')::numeric, 'opening')
    returning id into v_batch;
    insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
    values (v_item.id, v_batch, p_location, v_units, (r ->> 'unit_cost')::numeric, 'opening', v_id);
  end loop;
  return v_id;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- التحويل بين الأماكن (مثلًا من مخزن الانتظار للرئيسي)
-- -----------------------------------------------------------------------------------------------------
create table ph.transfers (
  id            bigint generated always as identity primary key,
  no            text unique,
  from_location smallint not null references ph.locations (id),
  to_location   smallint not null references ph.locations (id),
  status        text not null default 'draft' check (status in ('draft', 'posted')),
  note          text check (char_length(note) <= 300),
  created_at    timestamptz not null default now(),
  posted_at     timestamptz,
  by_user       uuid default auth.uid(),
  check (from_location <> to_location)
);
create table ph.transfer_lines (
  transfer_id bigint not null references ph.transfers (id),
  item_id     bigint not null references ph.items (id),
  qty_units   numeric(14, 2) not null check (qty_units > 0),
  primary key (transfer_id, item_id)
);
create trigger transfers_locked before update or delete on ph.transfers for each row execute function ph.forbid_posted_header();
create trigger transfer_lines_locked before insert or update or delete on ph.transfer_lines
  for each row execute function ph.forbid_posted_lines('transfers', 'transfer_id');

create function ph.post_transfer(p_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare
  t ph.transfers;
  l ph.transfer_lines;
  b record;
  v_branch smallint;
begin
  perform ph.require_role(array['owner', 'manager', 'pharmacist']);
  select * into strict t from ph.transfers where id = p_id for update;
  if t.status <> 'draft' then raise exception 'التحويل ده اترحّل قبل كده'; end if;
  for l in select * from ph.transfer_lines where transfer_id = p_id loop
    for b in select * from ph.pick_batches(l.item_id, t.from_location, l.qty_units) loop
      insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
      values (l.item_id, b.batch_id, t.from_location, -b.qty_units, b.unit_cost, 'transfer', p_id),
             (l.item_id, b.batch_id, t.to_location, b.qty_units, b.unit_cost, 'transfer', p_id);
    end loop;
  end loop;
  select branch_id into v_branch from ph.locations where id = t.from_location;
  update ph.transfers set status = 'posted', posted_at = now(), no = ph.next_doc_no('TR', v_branch) where id = p_id
  returning no into t.no;
  return t.no;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- الجرد: بتعدّ، والترحيل بيسجل الفرق حركة «count» على كل تشغيلة
-- -----------------------------------------------------------------------------------------------------
create table ph.stock_counts (
  id          bigint generated always as identity primary key,
  no          text unique,
  location_id smallint not null references ph.locations (id),
  scope       text check (char_length(scope) <= 120),     -- رف / تصنيف / الكل
  status      text not null default 'draft' check (status in ('draft', 'posted')),
  started_at  timestamptz not null default now(),
  posted_at   timestamptz,
  by_user     uuid default auth.uid()
);
create table ph.stock_count_lines (
  count_id      bigint not null references ph.stock_counts (id),
  item_id       bigint not null references ph.items (id),
  batch_id      bigint not null references ph.batches (id),
  counted_units numeric(14, 2) not null check (counted_units >= 0),
  system_units  numeric(14, 2),                              -- بيتملي وقت الترحيل
  primary key (count_id, batch_id)
);
create trigger stock_counts_locked before update or delete on ph.stock_counts for each row execute function ph.forbid_posted_header();

create function ph.post_stock_count(p_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare
  c ph.stock_counts;
  l record;
  v_sys numeric;
  v_branch smallint;
begin
  perform ph.require_role(array['owner', 'manager']);
  select * into strict c from ph.stock_counts where id = p_id for update;
  if c.status <> 'draft' then raise exception 'الجرد ده اترحّل قبل كده'; end if;
  for l in select * from ph.stock_count_lines where count_id = p_id loop
    select coalesce(sum(sb.qty_units), 0) into v_sys
    from ph.stock_balances sb where sb.batch_id = l.batch_id and sb.location_id = c.location_id;
    update ph.stock_count_lines set system_units = v_sys where count_id = p_id and batch_id = l.batch_id;
    if l.counted_units <> v_sys then
      insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
      values (l.item_id, l.batch_id, c.location_id, l.counted_units - v_sys,
              (select unit_cost from ph.batches where id = l.batch_id), 'count', p_id);
    end if;
  end loop;
  select branch_id into v_branch from ph.locations where id = c.location_id;
  update ph.stock_counts set status = 'posted', posted_at = now(), no = ph.next_doc_no('CNT', v_branch) where id = p_id
  returning no into c.no;
  return c.no;
end $$;
-- سطور الجرد بتتقفل بعد الترحيل (الترحيل نفسه بيكتب system_units قبل ما يقفل الرأس)
create trigger stock_count_lines_locked before insert or update or delete on ph.stock_count_lines
  for each row execute function ph.forbid_posted_lines('stock_counts', 'count_id');

-- -----------------------------------------------------------------------------------------------------
-- تسوية: تالف، منتهي اتشال، فرق، أو تسوية النقل من فارمافلاي. كل سطر حركة على تشغيلة
-- {"location_id": 1, "reason": "damaged", "note": "…", "lines": [{"batch_id": 9, "qty_units": -2}]}
-- -----------------------------------------------------------------------------------------------------
create table ph.stock_adjustments (
  id          bigint generated always as identity primary key,
  no          text unique,
  location_id smallint references ph.locations (id),
  reason      text not null check (reason in ('damaged', 'expired', 'count', 'transfer', 'reconcile', 'other')),
  at          timestamptz not null default now(),
  note        text check (char_length(note) <= 300),
  source      text not null default 'ph' check (source in ('ph', 'pharmafly')),
  legacy_no   text,
  by_user     uuid default auth.uid()
);
create trigger stock_adjustments_locked before update or delete on ph.stock_adjustments for each row execute function ph.forbid_change();

create function ph.post_adjustment(p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_adj    ph.stock_adjustments;
  v_loc    ph.locations;
  l        jsonb;
  bt       ph.batches;
begin
  perform ph.require_role(array['owner', 'manager']);
  if coalesce(p ->> 'reason', '') not in ('damaged', 'expired', 'count', 'other') then raise exception 'سبب التسوية مش معروف'; end if;
  select * into strict v_loc from ph.locations where id = (p ->> 'location_id')::smallint;
  insert into ph.stock_adjustments (no, location_id, reason, note)
  values (ph.next_doc_no('ADJ', v_loc.branch_id), v_loc.id, p ->> 'reason', p ->> 'note') returning * into v_adj;
  for l in select * from jsonb_array_elements(p -> 'lines') loop
    select * into strict bt from ph.batches where id = (l ->> 'batch_id')::bigint;
    insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
    values (bt.item_id, bt.id, v_loc.id, (l ->> 'qty_units')::numeric, bt.unit_cost, 'adjust', v_adj.id);
  end loop;
  return v_adj.no;
end $$;
