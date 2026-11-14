-- =====================================================================================================
-- (7 من 10) البيع: فاتورة البيع، الدفع، الآجل وحد العميل، سجل أدوية الجدول، مرتجع البيع
--   الكاشير بيبعت الفاتورة كلها في نداء واحد ph.post_sale(...). ولو النت واقف بيحفظها عنده ويبعتها بعدين
--   بنفس client_uuid، فمابتتسجلش مرتين.
-- =====================================================================================================

create table ph.sales (
  id           bigint generated always as identity primary key,
  no           text unique,
  branch_id    smallint not null references ph.branches (id),
  location_id  smallint not null references ph.locations (id),
  at           timestamptz not null default now(),       -- وقت البيع الفعلي (حتى لو اتبعتت بعد ما النت رجع)
  business_day date not null,
  shift_id     bigint references ph.shifts (id),
  customer_id  bigint references ph.customers (id),
  channel      text not null default 'counter' check (channel in ('counter', 'phone', 'store', 'delivery')),
  status       text not null default 'draft' check (status in ('draft', 'posted')),
  subtotal     numeric(14, 2) not null default 0,
  discount     numeric(14, 2) not null default 0 check (discount >= 0),
  total        numeric(14, 2) not null default 0,
  paid         numeric(14, 2) not null default 0,
  on_credit    numeric(14, 2) not null default 0,       -- اللي اتكتب على العميل
  client_uuid  uuid not null unique,                    -- رقم الفاتورة على جهاز الكاشير
  rx_patient   text check (char_length(rx_patient) <= 80),
  rx_doctor    text check (char_length(rx_doctor) <= 80),
  rx_no        text check (char_length(rx_no) <= 40),
  note         text check (char_length(note) <= 300),
  posted_at    timestamptz,
  source       text not null default 'ph' check (source in ('ph', 'pharmafly')),
  legacy_no    text,                                     -- رقم التذكرة في فارمافلاي
  by_user      uuid default auth.uid(),
  check (discount <= subtotal),
  check (on_credit = 0 or customer_id is not null)
);
create index on ph.sales (business_day);
create index on ph.sales (legacy_no) where legacy_no is not null;
create index on ph.sales (customer_id, at);

create table ph.sale_lines (
  id         bigint generated always as identity primary key,
  sale_id    bigint not null references ph.sales (id),
  item_id    bigint not null references ph.items (id),
  batch_id   bigint not null references ph.batches (id),
  qty_units  numeric(14, 2) not null check (qty_units > 0),
  unit_price numeric(14, 4) not null check (unit_price >= 0),   -- سعر الوحدة = سعر العلبة على التشغيلة ÷ pack_parts
  line_total numeric(14, 2) not null check (line_total >= 0),
  unit_cost  numeric(14, 4)                                     -- عشان الربح
);
create index on ph.sale_lines (sale_id);
create index on ph.sale_lines (item_id);

create table ph.sale_payments (
  sale_id    bigint not null references ph.sales (id),
  method     text not null references ph.payment_methods (code),
  account_id smallint references ph.cash_accounts (id),
  amount     numeric(14, 2) not null check (amount > 0),
  primary key (sale_id, method)
);

-- سجل أدوية الجدول: بيتكتب لوحده مع البيع
create table ph.controlled_register (
  id        bigint generated always as identity primary key,
  sale_id   bigint not null references ph.sales (id),
  item_id   bigint not null references ph.items (id),
  qty_units numeric(14, 2) not null,
  at        timestamptz not null,
  patient   text not null,
  doctor    text not null,
  rx_no     text
);

create trigger sales_locked before update or delete on ph.sales for each row execute function ph.forbid_posted_header();
create trigger sale_lines_locked before update or delete on ph.sale_lines for each row execute function ph.forbid_change();
create trigger sale_payments_locked before update or delete on ph.sale_payments for each row execute function ph.forbid_change();
create trigger controlled_register_locked before update or delete on ph.controlled_register for each row execute function ph.forbid_change();

-- -----------------------------------------------------------------------------------------------------
-- ph.post_sale: فاتورة كاملة في نداء واحد
-- {
--   "client_uuid": "…",  "at": "2026-11-13T20:15:00+02:00",  "location_id": 1,  "shift_id": 5,
--   "customer_id": 100001,  "channel": "counter",  "discount": 0,  "override_limit": false,
--   "rx": {"patient": "…", "doctor": "…", "no": "…"},
--   "lines":    [{"item_id": 3, "packs": 1, "units": 1}],
--   "payments": [{"method": "cash", "amount": 120}]        ← الباقي (لو فيه) آجل على العميل
-- }
-- -----------------------------------------------------------------------------------------------------
create function ph.post_sale(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uuid   uuid := (p ->> 'client_uuid')::uuid;
  v_sale   ph.sales;
  v_loc    ph.locations;
  v_at     timestamptz := coalesce((p ->> 'at')::timestamptz, now());
  v_cust   ph.customers;
  v_shift  ph.shifts;
  l        jsonb;
  pay      jsonb;
  it       ph.items;
  b        record;
  v_need   numeric;
  v_price  numeric;
  v_line   numeric;
  v_sub    numeric := 0;
  v_disc   numeric := coalesce((p ->> 'discount')::numeric, 0);
  v_total  numeric;
  v_paid   numeric := 0;
  v_credit numeric;
  v_amount numeric;
  v_method ph.payment_methods;
  v_acc    smallint;
  v_bal    numeric;
  v_items  bigint[] := '{}';
begin
  perform ph.require_role(array['owner', 'manager', 'pharmacist', 'cashier']);
  if v_uuid is null then raise exception 'client_uuid مطلوب'; end if;

  -- نفس الفاتورة اتبعتت قبل كده (النت قطع بعد ما اتسجلت): رجّع اللي اتسجل
  select * into v_sale from ph.sales where client_uuid = v_uuid;
  if found then
    return jsonb_build_object('sale_id', v_sale.id, 'no', v_sale.no, 'total', v_sale.total, 'repeat', true);
  end if;

  if (p ->> 'location_id') is not null then
    select * into v_loc from ph.locations where id = (p ->> 'location_id')::smallint;
  else
    select * into v_loc from ph.locations where is_default_sale order by id limit 1;
  end if;
  if v_loc.id is null then raise exception 'مفيش مكان بيع'; end if;
  if (p ->> 'customer_id') is not null then
    select * into strict v_cust from ph.customers where id = (p ->> 'customer_id')::bigint;
  end if;
  if (p ->> 'shift_id') is not null then
    select * into strict v_shift from ph.shifts where id = (p ->> 'shift_id')::bigint;
  end if;
  if jsonb_array_length(coalesce(p -> 'lines', '[]')) = 0 then raise exception 'الفاتورة فاضية'; end if;

  -- صنف جدول: لازم اسم المريض والدكتور قبل أي حاجة
  if exists (select 1 from jsonb_array_elements(p -> 'lines') x join ph.items i on i.id = (x ->> 'item_id')::bigint
             where i.is_controlled)
     and (coalesce(btrim(p #>> '{rx,patient}'), '') = '' or coalesce(btrim(p #>> '{rx,doctor}'), '') = '') then
    raise exception 'في الفاتورة صنف جدول: لازم اسم المريض والدكتور';
  end if;

  insert into ph.sales (branch_id, location_id, at, business_day, shift_id, customer_id, channel, client_uuid,
                        rx_patient, rx_doctor, rx_no, note)
  values (v_loc.branch_id, v_loc.id, v_at, ph.business_day(v_at), v_shift.id, v_cust.id,
          coalesce(p ->> 'channel', 'counter'), v_uuid, p #>> '{rx,patient}', p #>> '{rx,doctor}', p #>> '{rx,no}', p ->> 'note')
  returning * into v_sale;

  for l in select * from jsonb_array_elements(p -> 'lines') loop
    select * into it from ph.items where id = (l ->> 'item_id')::bigint and active;
    if not found then raise exception 'صنف مش موجود أو موقوف: %', l ->> 'item_id'; end if;
    if coalesce((l ->> 'units')::numeric, 0) > 0 and not it.sell_by_unit then
      raise exception '% مابيتباعش بالـ%', it.name_en, it.unit_name;
    end if;
    v_need := coalesce((l ->> 'packs')::numeric, 0) * it.pack_parts + coalesce((l ->> 'units')::numeric, 0);
    if v_need <= 0 then raise exception 'كمية غلط في %', it.name_en; end if;
    v_items := v_items || it.id;

    -- الأقرب صلاحية الأول، وكل تشغيلة بسعرها
    for b in select * from ph.pick_batches(it.id, v_loc.id, v_need) loop
      v_price := round(coalesce(b.public_price, it.public_price) / it.pack_parts, 4);
      v_line  := round(v_price * b.qty_units, 2);
      insert into ph.sale_lines (sale_id, item_id, batch_id, qty_units, unit_price, line_total, unit_cost)
      values (v_sale.id, it.id, b.batch_id, b.qty_units, v_price, v_line, b.unit_cost);
      insert into ph.stock_moves (at, business_day, item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
      values (v_at, v_sale.business_day, it.id, b.batch_id, v_loc.id, -b.qty_units, b.unit_cost, 'sale', v_sale.id);
      if it.is_controlled then
        insert into ph.controlled_register (sale_id, item_id, qty_units, at, patient, doctor, rx_no)
        values (v_sale.id, it.id, b.qty_units, v_at, p #>> '{rx,patient}', p #>> '{rx,doctor}', p #>> '{rx,no}');
      end if;
      v_sub := v_sub + v_line;
    end loop;
  end loop;

  if v_disc < 0 or v_disc > v_sub then raise exception 'الخصم (%) أكبر من الفاتورة (%)', v_disc, v_sub; end if;
  v_total := v_sub - v_disc;

  for pay in select * from jsonb_array_elements(coalesce(p -> 'payments', '[]')) loop
    v_amount := (pay ->> 'amount')::numeric;
    continue when coalesce(v_amount, 0) = 0 or pay ->> 'method' = 'credit';
    select * into v_method from ph.payment_methods where code = pay ->> 'method';
    if not found then raise exception 'طريقة دفع مش معروفة: %', pay ->> 'method'; end if;
    -- الكاش بيدخل درج الوردية لو فيه وردية، وغير كده الخزنة المتسجلة للطريقة
    v_acc := case when v_method.code = 'cash' and v_shift.id is not null then v_shift.account_id else v_method.account_id end;
    insert into ph.sale_payments (sale_id, method, account_id, amount) values (v_sale.id, v_method.code, v_acc, v_amount);
    insert into ph.money_moves (at, business_day, account_id, amount, doc_type, doc_id, shift_id)
    values (v_at, v_sale.business_day, v_acc, v_amount, 'sale', v_sale.id, v_shift.id);
    v_paid := v_paid + v_amount;
  end loop;
  if v_paid > v_total then raise exception 'المدفوع (%) أكتر من الإجمالي (%): سجّل اللي اتاخد بس', v_paid, v_total; end if;

  -- الباقي آجل: لازم عميل، ومايعدّيش حده إلا بصلاحية
  v_credit := v_total - v_paid;
  if v_credit > 0 then
    if v_cust.id is null then raise exception 'فاضل % ومفيش عميل: اختار العميل أو كمّل الدفع', v_credit; end if;
    select coalesce(pb.balance, 0) into v_bal from ph.party_balances pb
     where pb.party_type = 'customer' and pb.party_id = v_cust.id;
    v_bal := coalesce(v_bal, 0);
    if v_bal + v_credit > v_cust.credit_limit
       and not (coalesce((p ->> 'override_limit')::boolean, false)
                and exists (select 1 from ph.staff s where s.user_id = auth.uid() and s.active and s.can_override_limit)) then
      raise exception 'العميل % هيعدّي حده: الحد % وعليه % والفاتورة دي %', v_cust.name, v_cust.credit_limit, v_bal, v_credit
        using errcode = '23514';
    end if;
    insert into ph.party_ledger (at, business_day, party_type, party_id, amount, doc_type, doc_id)
    values (v_at, v_sale.business_day, 'customer', v_cust.id, v_credit, 'sale', v_sale.id);
  end if;

  if v_cust.id is not null then
    update ph.customer_meds set last_bought = v_sale.business_day
     where customer_id = v_cust.id and item_id = any (v_items) and active;
  end if;

  update ph.sales
     set status = 'posted', posted_at = now(), subtotal = v_sub, discount = v_disc, total = v_total,
         paid = v_paid, on_credit = v_credit, no = ph.next_doc_no('S', v_loc.branch_id, v_sale.business_day)
   where id = v_sale.id
  returning * into v_sale;
  return jsonb_build_object('sale_id', v_sale.id, 'no', v_sale.no, 'total', v_total, 'paid', v_paid,
                            'on_credit', v_credit, 'repeat', false);
end $$;

-- -----------------------------------------------------------------------------------------------------
-- مرتجع البيع: بيرجع لنفس التشغيلة، والفلوس ترجع كاش أو تتخصم من حساب العميل
-- {"client_uuid": "…", "sale_id": 12, "refund": "cash" | "credit", "shift_id": 7, "lines": [{"sale_line_id": 30, "qty_units": 1}]}
-- -----------------------------------------------------------------------------------------------------
create table ph.sale_returns (
  id           bigint generated always as identity primary key,
  no           text unique,
  sale_id      bigint references ph.sales (id),           -- فاضي بس في مرتجعات فارمافلاي اللي مش مربوطة بفاتورة
  location_id  smallint not null references ph.locations (id),
  customer_id  bigint references ph.customers (id),
  refund       text not null check (refund in ('cash', 'credit')),
  total        numeric(14, 2) not null default 0,
  at           timestamptz not null default now(),
  business_day date not null default ph.business_day(),
  client_uuid  uuid not null unique,
  source       text not null default 'ph' check (source in ('ph', 'pharmafly')),
  legacy_no    text,
  by_user      uuid default auth.uid(),
  check (sale_id is not null or source = 'pharmafly'),
  check (refund = 'cash' or customer_id is not null)
);
create table ph.sale_return_lines (
  id           bigint generated always as identity primary key,
  return_id    bigint not null references ph.sale_returns (id),
  sale_line_id bigint references ph.sale_lines (id),
  item_id      bigint not null references ph.items (id),
  batch_id     bigint not null references ph.batches (id),
  qty_units    numeric(14, 2) not null check (qty_units > 0),
  value        numeric(14, 2) not null check (value >= 0)
);
create unique index sale_return_lines_once on ph.sale_return_lines (return_id, sale_line_id) where sale_line_id is not null;
create index on ph.sale_return_lines (sale_line_id);
create trigger sale_return_lines_locked before update or delete on ph.sale_return_lines for each row execute function ph.forbid_change();

create function ph.post_sale_return(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uuid   uuid := (p ->> 'client_uuid')::uuid;
  v_ret    ph.sale_returns;
  s        ph.sales;
  l        jsonb;
  sl       ph.sale_lines;
  v_done   numeric;
  v_qty    numeric;
  v_value  numeric;
  v_total  numeric := 0;
  v_refund text;
  v_acc    smallint;
  v_shift  ph.shifts;
begin
  perform ph.require_role(array['owner', 'manager', 'pharmacist']);
  select * into v_ret from ph.sale_returns where client_uuid = v_uuid;
  if found then return jsonb_build_object('return_id', v_ret.id, 'no', v_ret.no, 'total', v_ret.total, 'repeat', true); end if;

  select * into strict s from ph.sales where id = (p ->> 'sale_id')::bigint;
  if s.status <> 'posted' then raise exception 'الفاتورة دي مش مرحّلة'; end if;
  v_refund := coalesce(p ->> 'refund', case when s.on_credit > 0 then 'credit' else 'cash' end);
  if v_refund = 'credit' and s.customer_id is null then raise exception 'مرتجع على الحساب محتاج عميل'; end if;

  insert into ph.sale_returns (no, sale_id, location_id, customer_id, refund, client_uuid)
  values (ph.next_doc_no('SR', s.branch_id), s.id, s.location_id, s.customer_id, v_refund, v_uuid) returning * into v_ret;

  for l in select * from jsonb_array_elements(p -> 'lines') loop
    select * into strict sl from ph.sale_lines where id = (l ->> 'sale_line_id')::bigint and sale_id = s.id;
    v_qty := (l ->> 'qty_units')::numeric;
    select coalesce(sum(rl.qty_units), 0) into v_done from ph.sale_return_lines rl where rl.sale_line_id = sl.id;
    if v_qty <= 0 or v_done + v_qty > sl.qty_units then
      raise exception 'مايتنفعش ترجّع % (اتباع % ورجع قبل كده %)', v_qty, sl.qty_units, v_done;
    end if;
    -- القيمة بنفس سعر البيع بعد نصيبها من خصم الفاتورة
    v_value := round(sl.line_total * v_qty / sl.qty_units * (1 - s.discount / nullif(s.subtotal, 0)), 2);
    insert into ph.sale_return_lines (return_id, sale_line_id, item_id, batch_id, qty_units, value)
    values (v_ret.id, sl.id, sl.item_id, sl.batch_id, v_qty, v_value);
    insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
    values (sl.item_id, sl.batch_id, s.location_id, v_qty, sl.unit_cost, 'sale_return', v_ret.id);
    v_total := v_total + v_value;
  end loop;

  if v_refund = 'cash' then
    -- الفلوس بتطلع من درج الوردية المفتوحة دلوقتي (لو اتبعتت)، وإلا خزنة الكاش
    if (p ->> 'shift_id') is not null then
      select * into strict v_shift from ph.shifts where id = (p ->> 'shift_id')::bigint and status = 'open';
    end if;
    v_acc := coalesce(v_shift.account_id, (select pm.account_id from ph.payment_methods pm where pm.code = 'cash'));
    insert into ph.money_moves (account_id, amount, doc_type, doc_id, shift_id) values (v_acc, -v_total, 'sale_return', v_ret.id, v_shift.id);
  else
    insert into ph.party_ledger (party_type, party_id, amount, doc_type, doc_id)
    values ('customer', s.customer_id, -v_total, 'sale_return', v_ret.id);
  end if;
  -- الإجمالي بيتكتب مرة واحدة هنا (الجدول مالوش تريجر قفل على الرأس، والتعديل من برا ممنوع بالصلاحيات)
  update ph.sale_returns set total = v_total where id = v_ret.id;
  return jsonb_build_object('return_id', v_ret.id, 'no', v_ret.no, 'total', v_total, 'repeat', false);
end $$;

-- -----------------------------------------------------------------------------------------------------
-- الوردية: فتح وقفل. القفل بيقارن اللي في الدرج باللي المفروض يكون، والفرق بيتسجل حركة «shift»
-- -----------------------------------------------------------------------------------------------------
create function ph.open_shift(p_account smallint, p_opening_cash numeric default 0) returns bigint
language plpgsql security definer set search_path = '' as $$
declare v_id bigint;
begin
  perform ph.require_role(array['owner', 'manager', 'pharmacist', 'cashier']);
  if not exists (select 1 from ph.cash_accounts where id = p_account and kind = 'drawer' and active) then
    raise exception 'الخزنة دي مش درج كاشير';
  end if;
  insert into ph.shifts (account_id, opening_cash) values (p_account, coalesce(p_opening_cash, 0)) returning id into v_id;
  return v_id;
end $$;

create function ph.close_shift(p_shift bigint, p_counted numeric) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  sh         ph.shifts;
  v_expected numeric;
  v_diff     numeric;
begin
  perform ph.require_role(array['owner', 'manager', 'pharmacist', 'cashier']);
  select * into strict sh from ph.shifts where id = p_shift for update;
  if sh.status <> 'open' then raise exception 'الوردية دي اتقفلت قبل كده'; end if;
  -- الدرج بس (الفيزا والمحفظة بيتسجلوا على الوردية بس بيروحوا خزنتهم)
  select sh.opening_cash + coalesce(sum(m.amount), 0) into v_expected
    from ph.money_moves m where m.shift_id = p_shift and m.account_id = sh.account_id;
  v_diff := p_counted - v_expected;
  if v_diff <> 0 then
    insert into ph.money_moves (account_id, amount, doc_type, doc_id, shift_id) values (sh.account_id, v_diff, 'shift', p_shift, p_shift);
  end if;
  update ph.shifts set status = 'closed', closed_at = now(), counted_cash = p_counted where id = p_shift;
  return jsonb_build_object('expected', v_expected, 'counted', p_counted, 'diff', v_diff);
end $$;
