-- 202611141000_sell_before_purchase
-- المطلوب (المالك 2026-11-13): «عايز أبيع بالسالب عادي: صنف جه في الفاتورة بس لسه مادخلش مشتريات، والعميل جاي ياخده».
-- الإعداد ph.settings.allow_negative_stock كان موجود من الأول بس مقفول ومالوش زرار، ولما يتفتح:
--   (1) البيع بالسالب كان بيتسجل على آخر تشغيلة للصنف (ممكن تكون قديمة أو منتهية)،
--   (2) ولما فاتورة الشرا تتدخل بعدين بتشغيلة جديدة، السالب كان بيفضل زي ما هو للأبد.
-- الحل: (1) الجزء اللي بالسالب بيتسجل على تشغيلة «مستنية فاتورة» للصنف (من غير صلاحية، بسعر الصنف وآخر تكلفة).
--   (2) ترحيل فاتورة الشرا بيقفل أي سالب للصنف في نفس المخزن من الكمية الجديدة (الأقرب صلاحية)، بمستند تسوية واحد
--   مكتوب عليه رقم الفاتورة. إجمالي رصيد الصنف ماتغيرش، بس السالب بيروح للتشغيلة الحقيقية.
--   (3) الإعداد بيتفتح لصيدلية عسكر، وفيه زرار في الإعدادات (المالك والمدير).
-- مابيتغيرش: الفواتير والدفاتر القديمة، والمنتهي لسه مابيتباعش، والفحص الذاتي (السالب مسموح لما الإعداد مفتوح).
-- الرجوع: update ph.settings set allow_negative_stock = false; وتعريفات ph.pick_batches (db/04-stock.sql)
--   و ph.post_purchase_invoice (db/06-purchases.sql).

update ph.settings set allow_negative_stock = true where id = 1;

create or replace function ph.pick_batches(p_item bigint, p_location smallint, p_units numeric)
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
    -- مسموح بالسالب: الباقي على تشغيلة «مستنية فاتورة» للصنف (مش آخر تشغيلة: ممكن تكون قديمة أو منتهية).
    -- ترحيل فاتورة الشرا بعدين بيقفل السالب ده من الكمية الجديدة
    select * into v_batch from ph.batches b where b.item_id = p_item and b.source = 'unbatched' and b.expiry is null
    order by b.id desc limit 1;
    if not found then
      insert into ph.batches (item_id, public_price, unit_cost, source)
      values (p_item, (select i.public_price from ph.items i where i.id = p_item),
              (select b.unit_cost from ph.batches b where b.item_id = p_item and b.unit_cost is not null order by b.id desc limit 1),
              'unbatched')
      returning * into v_batch;
    end if;
    batch_id := v_batch.id; qty_units := v_left; public_price := v_batch.public_price; unit_cost := v_batch.unit_cost;
    return next;
  end if;
end $$;


create or replace function ph.post_purchase_invoice(p_id bigint) returns text
language plpgsql security definer set search_path = '' as $$
declare
  inv     ph.purchase_invoices;
  l       ph.purchase_invoice_lines;
  it      ph.items;
  v_units numeric;
  v_batch bigint;
  v_total numeric := 0;
  v_branch smallint;
  neg     record;
  src     record;
  v_need  numeric;
  v_take  numeric;
  v_adj   bigint;
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

  -- البيع قبل الفاتورة: أي سالب للأصناف دي في نفس المخزن بيتقفل من الكمية اللي لسه داخلة (الأقرب صلاحية الأول)
  for neg in select sb.item_id, sb.batch_id, -sb.qty_units as need from ph.stock_balances sb
             where sb.location_id = inv.location_id and sb.qty_units < 0
               and sb.item_id in (select pl.item_id from ph.purchase_invoice_lines pl where pl.invoice_id = p_id)
             order by sb.item_id, sb.batch_id
  loop
    v_need := neg.need;
    for src in select pl.batch_id, sb.qty_units as avail, b.unit_cost
               from ph.purchase_invoice_lines pl
               join ph.stock_balances sb on sb.batch_id = pl.batch_id and sb.location_id = inv.location_id
               join ph.batches b on b.id = pl.batch_id
               where pl.invoice_id = p_id and pl.item_id = neg.item_id and sb.qty_units > 0
               order by b.expiry nulls last, pl.id
    loop
      exit when v_need <= 0;
      v_take := least(v_need, src.avail);
      if v_adj is null then
        insert into ph.stock_adjustments (no, location_id, reason, note)
        values (ph.next_doc_no('ADJ', v_branch), inv.location_id, 'other', 'تسوية البيع قبل فاتورة الشرا ' || inv.no)
        returning id into v_adj;
      end if;
      insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
      values (neg.item_id, src.batch_id, inv.location_id, -v_take, src.unit_cost, 'adjust', v_adj);
      insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
      values (neg.item_id, neg.batch_id, inv.location_id, v_take, src.unit_cost, 'adjust', v_adj);
      v_need := v_need - v_take;
    end loop;
  end loop;
  return inv.no;
end $$;

