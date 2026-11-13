-- =====================================================================================================
-- (6 من 10) المشتريات: طلبيات للموردين، فواتير الشرا (بالبونص والخصم والصلاحية)، مرتجعات للموردين
-- =====================================================================================================

-- الطلبية: اللي اتطلب من مين (بديل «اتطلب» في البوت). مابتحركش مخزون ولا فلوس
create table ph.purchase_orders (
  id           bigint generated always as identity primary key,
  no           text unique,
  supplier_id  integer not null references ph.suppliers (id),
  rep_id       integer references ph.supplier_reps (id),
  status       text not null default 'draft' check (status in ('draft', 'sent', 'received', 'cancelled')),
  message_text text check (char_length(message_text) <= 20000),
  created_at   timestamptz not null default now(),
  sent_at      timestamptz,                -- المالك دَاس «علّمها اتطلب» بعد ما بعتها من الواتس بنفسه
  by_user      uuid default auth.uid()
);
create table ph.purchase_order_lines (
  order_id     bigint not null references ph.purchase_orders (id),
  item_id      bigint not null references ph.items (id),
  packs        numeric(12, 2) not null check (packs > 0),
  expected_pct numeric(5, 2) check (expected_pct between 0 and 100),
  primary key (order_id, item_id)
);
create index on ph.purchase_order_lines (item_id);

-- -----------------------------------------------------------------------------------------------------
-- فاتورة الشرا: مسودة (من صورة الواتس أو بإيدك) ← مراجعة ← ترحيل
-- -----------------------------------------------------------------------------------------------------
create table ph.purchase_invoices (
  id              bigint generated always as identity primary key,
  no              text unique,                          -- رقمنا
  supplier_id     integer not null references ph.suppliers (id),
  supplier_doc_no text check (char_length(supplier_doc_no) <= 60),   -- رقم فاتورة المورد
  invoice_date    date not null default current_date,
  location_id     smallint not null references ph.locations (id),
  order_id        bigint references ph.purchase_orders (id),
  attachment_id   bigint references ph.attachments (id),
  status          text not null default 'draft' check (status in ('draft', 'posted')),
  total           numeric(14, 2),                       -- بيتحسب وقت الترحيل = مجموع التكلفة
  paid_amount     numeric(14, 2) not null default 0 check (paid_amount >= 0),
  paid_account_id smallint references ph.cash_accounts (id),
  created_at      timestamptz not null default now(),
  posted_at       timestamptz,
  by_user         uuid default auth.uid(),
  unique (supplier_id, supplier_doc_no),                -- نفس فاتورة المورد ماتتدخلش مرتين
  check (paid_amount = 0 or paid_account_id is not null)
);

create table ph.purchase_invoice_lines (
  id           bigint generated always as identity primary key,
  invoice_id   bigint not null references ph.purchase_invoices (id),
  item_id      bigint not null references ph.items (id),
  packs        numeric(12, 2) not null check (packs > 0),
  bonus_packs  numeric(12, 2) not null default 0 check (bonus_packs >= 0),
  public_price numeric(12, 2) not null check (public_price > 0),   -- سعر الجمهور على العلبة في الفاتورة
  cost_total   numeric(14, 2) not null check (cost_total >= 0),    -- اللي هندفعه في السطر ده
  expiry       date,
  batch_id     bigint references ph.batches (id),                  -- بيتملي وقت الترحيل
  -- الخصم الفعلي بعد البونص (نفس معادلة مستشار الطلبيات): 1 − التكلفة ÷ (سعر الجمهور × (العدد + البونص))
  real_discount numeric(7, 4) generated always as
    (1 - cost_total / nullif(public_price * (packs + bonus_packs), 0)) stored
);
create index on ph.purchase_invoice_lines (invoice_id);
create index on ph.purchase_invoice_lines (item_id);

create trigger purchase_invoices_locked before update or delete on ph.purchase_invoices
  for each row execute function ph.forbid_posted_header();
create trigger purchase_invoice_lines_locked before insert or update or delete on ph.purchase_invoice_lines
  for each row execute function ph.forbid_posted_lines('purchase_invoices', 'invoice_id');
create trigger audit_purchase_invoices after update or delete on ph.purchase_invoices for each row execute function ph.audit();

create function ph.post_purchase_invoice(p_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare
  inv     ph.purchase_invoices;
  l       ph.purchase_invoice_lines;
  it      ph.items;
  v_units numeric;
  v_batch bigint;
  v_total numeric := 0;
  v_branch smallint;
begin
  perform ph.require_role(array['owner', 'manager', 'pharmacist']);
  select * into strict inv from ph.purchase_invoices where id = p_id for update;
  if inv.status <> 'draft' then raise exception 'الفاتورة دي اترحّلت قبل كده (%)', inv.no; end if;
  if not exists (select 1 from ph.purchase_invoice_lines where invoice_id = p_id) then
    raise exception 'الفاتورة فاضية';
  end if;
  perform set_config('ph.price_source', 'purchase', true);

  for l in select * from ph.purchase_invoice_lines where invoice_id = p_id order by id loop
    select * into strict it from ph.items where id = l.item_id;
    v_units := (l.packs + l.bonus_packs) * it.pack_parts;
    insert into ph.batches (item_id, expiry, public_price, unit_cost, source)
    values (it.id, l.expiry, l.public_price, round(l.cost_total / v_units, 4), 'purchase')
    returning id into v_batch;
    insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
    values (it.id, v_batch, inv.location_id, v_units, round(l.cost_total / v_units, 4), 'purchase', p_id);
    -- السطر بيتربط بالتشغيلة (التريجر بيسمح لأن الرأس لسه مسودة)
    update ph.purchase_invoice_lines set batch_id = v_batch where id = l.id;
    -- السعر الرسمي بيزيد بس (التشغيلة القديمة بتفضل بسعرها)
    if it.public_price is null or l.public_price > it.public_price then
      update ph.items set public_price = l.public_price where id = it.id;
    end if;
    v_total := v_total + l.cost_total;
  end loop;

  if inv.paid_amount > v_total then raise exception 'المدفوع (%) أكتر من الفاتورة (%)', inv.paid_amount, v_total; end if;
  insert into ph.party_ledger (party_type, party_id, amount, doc_type, doc_id)
  values ('supplier', inv.supplier_id, v_total, 'purchase', p_id);
  if inv.paid_amount > 0 then
    insert into ph.money_moves (account_id, amount, doc_type, doc_id) values (inv.paid_account_id, -inv.paid_amount, 'purchase', p_id);
    insert into ph.party_ledger (party_type, party_id, amount, doc_type, doc_id)
    values ('supplier', inv.supplier_id, -inv.paid_amount, 'payment', p_id);
  end if;

  select branch_id into v_branch from ph.locations where id = inv.location_id;
  update ph.purchase_invoices
     set status = 'posted', posted_at = now(), total = v_total, no = ph.next_doc_no('PI', v_branch, inv.invoice_date)
   where id = p_id
  returning no into inv.no;
  update ph.purchase_orders set status = 'received' where id = inv.order_id and status = 'sent';
  return inv.no;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- مرتجع للمورد (صلاحية، تالف، غلط، زيادة) ← بيقل المخزون وبيقل اللي علينا للمورد
-- -----------------------------------------------------------------------------------------------------
create table ph.purchase_returns (
  id             bigint generated always as identity primary key,
  no             text unique,
  supplier_id    integer not null references ph.suppliers (id),
  location_id    smallint not null references ph.locations (id),
  reason         text not null check (reason in ('expiry', 'damaged', 'wrong_item', 'overstock', 'other')),
  status         text not null default 'draft' check (status in ('draft', 'posted')),
  credit_note_no text check (char_length(credit_note_no) <= 60),   -- رقم إشعار الخصم من المورد
  attachment_id  bigint references ph.attachments (id),
  total          numeric(14, 2),
  created_at     timestamptz not null default now(),
  posted_at      timestamptz,
  by_user        uuid default auth.uid()
);
create table ph.purchase_return_lines (
  return_id bigint not null references ph.purchase_returns (id),
  batch_id  bigint not null references ph.batches (id),
  qty_units numeric(14, 2) not null check (qty_units > 0),
  value     numeric(14, 2) check (value >= 0),             -- فاضي = تكلفة التشغيلة × الكمية
  primary key (return_id, batch_id)
);
create trigger purchase_returns_locked before update or delete on ph.purchase_returns
  for each row execute function ph.forbid_posted_header();
create trigger purchase_return_lines_locked before insert or update or delete on ph.purchase_return_lines
  for each row execute function ph.forbid_posted_lines('purchase_returns', 'return_id');

create function ph.post_purchase_return(p_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare
  r       ph.purchase_returns;
  l       ph.purchase_return_lines;
  bt      ph.batches;
  v_value numeric;
  v_total numeric := 0;
  v_branch smallint;
begin
  perform ph.require_role(array['owner', 'manager']);
  select * into strict r from ph.purchase_returns where id = p_id for update;
  if r.status <> 'draft' then raise exception 'المرتجع ده اترحّل قبل كده'; end if;
  for l in select * from ph.purchase_return_lines where return_id = p_id loop
    select * into strict bt from ph.batches where id = l.batch_id;
    v_value := coalesce(l.value, round(coalesce(bt.unit_cost, 0) * l.qty_units, 2));
    insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
    values (bt.item_id, bt.id, r.location_id, -l.qty_units, bt.unit_cost, 'purchase_return', p_id);
    v_total := v_total + v_value;
  end loop;
  if v_total > 0 then
    insert into ph.party_ledger (party_type, party_id, amount, doc_type, doc_id)
    values ('supplier', r.supplier_id, -v_total, 'purchase_return', p_id);
  end if;
  select branch_id into v_branch from ph.locations where id = r.location_id;
  update ph.purchase_returns set status = 'posted', posted_at = now(), total = v_total, no = ph.next_doc_no('PR', v_branch)
   where id = p_id returning no into r.no;
  return r.no;
end $$;
