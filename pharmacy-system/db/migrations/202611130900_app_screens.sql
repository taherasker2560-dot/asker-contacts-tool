-- 202611130900_app_screens
-- المطلوب: شاشات البرنامج (لوحة النهارده، الكاشير، الأصناف، الصلاحية، الطلبيات، العملاء، الموردين، الإعدادات) محتاجة
--   دوال وعروض جاهزة من القاعدة: بحث الكاشير بالرصيد والسعر، البدايل، «اتطلب»، المزمنين، توقّع الصلاحية، لوحة النهارده… (طلب المالك 2026-11-13)
-- ليه: الشاشة بتعرض بس، والحساب كله في القاعدة (نفس الرقم في الكاشير والموبايل والبوت).
-- الرجوع (بالترتيب):
--   drop view ph.v_dashboard, ph.v_top_items_30d, ph.v_top_items_today, ph.v_item_list, ph.v_staff, ph.v_item_buys,
--     ph.v_supplier_card, ph.v_customer_pick, ph.v_refills_due, ph.v_chronic_suggestions, ph.v_expiry_risk, ph.v_sales_hourly, ph.v_order_advice;
--   drop function ph.my_open_shift(), ph.pos_lookup(text, integer), ph.item_alternatives(bigint), ph.mark_ordered(jsonb),
--     ph.add_chronic(bigint, bigint, integer);
--   الـ v_expiring: create or replace بالتعريف القديم مايشيلش أعمدة: drop view ph.v_expiring cascade ثم التعريف القديم من db/09.
--   alter table ph.settings drop column demo_data;

alter table ph.settings add column demo_data boolean not null default false;   -- داتا تجريبية (الشاشات بتكتب كده فوق)

-- الصلاحية: مين المورد (رقمه) والمكان (عشان المرتجع للمورد من الشاشة)
create or replace view ph.v_expiring with (security_invoker = true) as
select v.item_id, v.name_en, v.name_ar, v.location, v.batch_id, v.expiry, v.packs, v.units,
       (v.expiry - current_date) as days_left,
       case when v.expiry < current_date then 'expired'
            when v.expiry < current_date + 30 then 'red'
            else 'yellow' end as level,
       (select s.name from ph.purchase_invoice_lines pl
          join ph.purchase_invoices pi on pi.id = pl.invoice_id join ph.suppliers s on s.id = pi.supplier_id
         where pl.batch_id = v.batch_id) as supplier,   -- لمين نرجّعه
       (select pi.supplier_id from ph.purchase_invoice_lines pl join ph.purchase_invoices pi on pi.id = pl.invoice_id
         where pl.batch_id = v.batch_id) as supplier_id, v.location_id
from ph.v_stock v
where v.qty_units > 0 and v.expiry is not null
  and v.expiry < current_date + coalesce((select near_expiry_days from ph.settings where id = 1), 90);

-- وردية اليوزر المفتوحة (الكاشير مابيشوفش جدول الورديات نفسه): رقمها، والدرج، والمفروض فيه دلوقتي
create function ph.my_open_shift()
returns table (id bigint, account_id smallint, account text, opened_at timestamptz, opening_cash numeric, expected_cash numeric, sales_count bigint)
language sql stable security definer set search_path = '' as $$
  select sh.id, sh.account_id, a.name, sh.opened_at, sh.opening_cash,
         sh.opening_cash + coalesce((select sum(m.amount) from ph.money_moves m where m.shift_id = sh.id and m.account_id = sh.account_id), 0),
         (select count(*) from ph.sales s where s.shift_id = sh.id)
  from ph.shifts sh join ph.cash_accounts a on a.id = sh.account_id
  where sh.status = 'open' and sh.opened_by = auth.uid()
  order by sh.opened_at desc limit 1
$$;


-- -----------------------------------------------------------------------------------------------------
-- للواجهة: النواقص مع أحسن مورد، بحث الكاشير، البدايل، «علّمها اتطلب»، العملاء المزمنين
-- -----------------------------------------------------------------------------------------------------
create view ph.v_order_advice as
select sh.item_id, sh.name_en, sh.name_ar, sh.pack_parts, sh.onhand_units, sh.sold_30d_units, sh.min_units, sh.order_packs,
       sh.qty_by_owner, sh.ordered_today_from, bo.best_supplier_id, s.name as best_supplier, bo.best_pct, bo.second_pct,
       bo.gap_pct, bo.suppliers_count
from ph.v_shortages sh
left join ph.v_best_offer bo on bo.item_id = sh.item_id
left join ph.suppliers s on s.id = bo.best_supplier_id;

-- بحث الكاشير: باركود بالظبط أو رقم الصنف أو جزء من الاسم، ومعاه الرصيد وأقرب صلاحية وسعر العلبة اللي هتتباع (أقرب تشغيلة)
create function ph.pos_lookup(q text, max_rows integer default 12)
returns table (id bigint, name_en text, name_ar text, pack_parts integer, pack_name text, unit_name text, sell_by_unit boolean,
               price_pack numeric, onhand_units numeric, nearest_expiry date, is_controlled boolean, needs_rx boolean,
               gkey text, exact boolean)
language sql stable security definer set search_path = '' as $$
  with hits as (
    select b.item_id as id, true as exact from ph.item_barcodes b where b.barcode = btrim(q)
    union all
    select i.id, i.id::text = btrim(q) from ph.items i
    where i.active and char_length(btrim(q)) >= 2
      and (i.name_en ilike '%' || btrim(q) || '%' or i.name_ar ilike '%' || btrim(q) || '%' or i.id::text = btrim(q))
  ), best as (select h.id, bool_or(h.exact) as exact from hits h group by h.id)
  select i.id, i.name_en, i.name_ar, i.pack_parts, i.pack_name, i.unit_name, i.sell_by_unit,
         coalesce(fb.public_price, i.public_price), coalesce(o.units, 0), fb.expiry, i.is_controlled, i.needs_rx, i.gkey, b.exact
  from best b
  join ph.items i on i.id = b.id and i.active
  left join ph.v_onhand o on o.item_id = i.id
  left join lateral (
    select bt.public_price, bt.expiry from ph.stock_balances sb join ph.batches bt on bt.id = sb.batch_id
    join ph.locations l on l.id = sb.location_id and l.is_default_sale
    where sb.item_id = i.id and sb.qty_units > 0 and (bt.expiry is null or bt.expiry >= current_date)
    order by bt.expiry nulls last, bt.id limit 1
  ) fb on true
  where ph.has_role(array['owner', 'manager', 'pharmacist', 'cashier'])
  order by b.exact desc, (coalesce(o.units, 0) > 0) desc, i.name_en
  limit least(greatest(coalesce(max_rows, 12), 1), 50)
$$;

-- البدايل: نفس المادة الفعالة والشكل، وعليها رصيد
create function ph.item_alternatives(p_item bigint)
returns table (id bigint, name_en text, name_ar text, price_pack numeric, onhand_units numeric, pack_parts integer)
language sql stable security definer set search_path = '' as $$
  select i.id, i.name_en, i.name_ar, i.public_price, o.units, i.pack_parts
  from ph.items src
  join ph.items i on i.gkey = src.gkey and i.id <> src.id and i.active
  join ph.v_onhand o on o.item_id = i.id and o.units > 0
  where src.id = p_item and src.gkey is not null and ph.has_role(array['owner', 'manager', 'pharmacist', 'cashier'])
  order by o.units desc limit 10
$$;

-- «علّمها اتطلب»: طلبية متبعتة للمورد (المالك بعتها من الواتس بنفسه)
-- {"supplier_id": 10000, "message": "…", "items": [{"item_id": 1, "packs": 3, "expected_pct": 28}]}
create function ph.mark_ordered(p jsonb) returns text
language plpgsql volatile security definer set search_path = '' as $$
declare v_id bigint; v_no text;
begin
  perform ph.require_role(array['owner', 'manager', 'pharmacist', 'bot']);
  if jsonb_array_length(coalesce(p -> 'items', '[]')) = 0 then raise exception 'الطلبية فاضية'; end if;
  insert into ph.purchase_orders (no, supplier_id, status, message_text, sent_at)
  values (ph.next_doc_no('PO', (select min(id) from ph.branches)), (p ->> 'supplier_id')::integer, 'sent', p ->> 'message', now())
  returning id, no into v_id, v_no;
  insert into ph.purchase_order_lines (order_id, item_id, packs, expected_pct)
  select v_id, (x ->> 'item_id')::bigint, (x ->> 'packs')::numeric, (x ->> 'expected_pct')::numeric
  from jsonb_array_elements(p -> 'items') x;
  return v_no;
end $$;

-- «مزمن»: العميل بياخد الصنف ده كل كام يوم. آخر شرا بيتحسب من البيع
create function ph.add_chronic(p_customer bigint, p_item bigint, p_every integer) returns void
language plpgsql volatile security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager', 'pharmacist']);
  insert into ph.customer_meds (customer_id, item_id, every_days, last_bought)
  values (p_customer, p_item, p_every,
          (select max(s.business_day) from ph.sales s join ph.sale_lines l on l.sale_id = s.id
            where s.customer_id = p_customer and l.item_id = p_item and s.status = 'posted'))
  on conflict (customer_id, item_id) do update set every_days = excluded.every_days, active = true;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- للواجهة: لوحة النهارده، البيع بالساعة، توقّع الصلاحية، المزمنين، المورد، العملاء، الموظفين
-- -----------------------------------------------------------------------------------------------------
-- البيع بالساعة: النهارده وزي النهارده الأسبوع اللي فات (يوم الصيدلية من 6 الصبح)
create view ph.v_sales_hourly as
select h.hr,
  coalesce((select sum(s.total) from ph.sales s where s.status = 'posted' and s.business_day = ph.business_day()
            and extract(hour from s.at at time zone 'Africa/Cairo') = h.hr), 0) as today,
  coalesce((select sum(s.total) from ph.sales s where s.status = 'posted' and s.business_day = ph.business_day() - 7
            and extract(hour from s.at at time zone 'Africa/Cairo') = h.hr), 0) as last_week
from generate_series(0, 23) h(hr)
where ph.has_role(array['owner', 'manager', 'pharmacist']);

-- توقّع الصلاحية: بسرعة البيع الحالية والبيع من الأقرب صلاحية الأول، كام وحدة هتخلص صلاحيتها قبل ما تتباع
create view ph.v_expiry_risk with (security_invoker = true) as
select x.item_id, x.name_en, x.name_ar, x.batch_id, x.expiry, x.location, x.qty_units, x.packs, x.units, x.days_left,
       x.daily_rate, x.at_risk_units, round(x.at_risk_units * x.unit_cost, 2) as at_risk_value
from (
  select v.item_id, v.name_en, v.name_ar, v.batch_id, v.expiry, v.location, v.qty_units, v.packs, v.units,
         (v.expiry - current_date) as days_left,
         round(coalesce(s.units, 0) / 30.0, 3) as daily_rate,
         coalesce(b.unit_cost, 0) as unit_cost,
         greatest(0, v.qty_units - greatest(0, floor(coalesce(s.units, 0) / 30.0 * (v.expiry - current_date))
                  - coalesce(sum(v.qty_units) over (partition by v.item_id order by v.expiry, v.batch_id
                                                    rows between unbounded preceding and 1 preceding), 0))) as at_risk_units
  from ph.v_stock v
  join ph.batches b on b.id = v.batch_id
  left join ph.v_sales_30d s on s.item_id = v.item_id
  where v.qty_units > 0 and v.counts_as_stock and v.expiry is not null and v.expiry >= current_date
    and v.expiry < current_date + 365
) x
where x.at_risk_units > 0;

-- عملاء شكلهم مزمنين: نفس الصنف 4 مرات أو أكتر في آخر 8 شهور بفترات منتظمة، ومش متسجلين «مزمن»
create view ph.v_chronic_suggestions with (security_invoker = true) as
with buys as (
  select s.customer_id, l.item_id, s.business_day as d
  from ph.sales s join ph.sale_lines l on l.sale_id = s.id
  where s.status = 'posted' and s.customer_id is not null and s.business_day > ph.business_day() - 240
  group by 1, 2, 3
), gaps as (
  select b.*, b.d - lag(b.d) over (partition by b.customer_id, b.item_id order by b.d) as gap from buys b
), st as (
  select customer_id, item_id, count(*) as times, avg(gap) as avg_gap, stddev_pop(gap) as sd_gap, max(d) as last_bought
  from gaps group by 1, 2
)
select st.customer_id, c.name as customer, c.phone, st.item_id, i.name_en, i.name_ar, st.times,
       round(st.avg_gap)::integer as every_days, st.last_bought, st.last_bought + round(st.avg_gap)::integer as next_due
from st
join ph.customers c on c.id = st.customer_id
join ph.items i on i.id = st.item_id
where st.times >= 4 and st.avg_gap between 7 and 90 and coalesce(st.sd_gap, 0) <= st.avg_gap * 0.2
  and not exists (select 1 from ph.customer_meds m where m.customer_id = st.customer_id and m.item_id = st.item_id);

-- الأدوية المزمنة اللي ميعادها قرّب أو فات (خلال 3 أيام)
create view ph.v_refills_due with (security_invoker = true) as
select m.customer_id, c.name as customer, c.phone, m.item_id, i.name_en, i.name_ar, m.every_days, m.last_bought,
       m.last_bought + m.every_days as due_on, current_date - (m.last_bought + m.every_days) as days_late
from ph.customer_meds m
join ph.customers c on c.id = m.customer_id
join ph.items i on i.id = m.item_id
where m.active and m.last_bought is not null and m.last_bought + m.every_days <= current_date + 3;

-- اختيار العميل في الكاشير: الرصيد والحد
create view ph.v_customer_pick with (security_invoker = true) as
select c.id, c.name, c.phone, c.area, c.credit_limit, coalesce(b.balance, 0) as balance, c.active
from ph.customers c left join ph.party_balances b on b.party_type = 'customer' and b.party_id = c.id;

-- كارت المورد: رصيده، فواتيره وخصمه الفعلي في 90 يوم، وعروضه في 30 يوم
create view ph.v_supplier_card with (security_invoker = true) as
select s.id, s.name, s.kind, coalesce(pb.balance, 0) as balance,
  (select count(*) from ph.purchase_invoices i where i.supplier_id = s.id and i.status = 'posted' and i.invoice_date > current_date - 90) as invoices_90d,
  (select round(100 * (1 - sum(l.cost_total) / nullif(sum(l.public_price * (l.packs + l.bonus_packs)), 0)), 2)
     from ph.purchase_invoice_lines l join ph.purchase_invoices i on i.id = l.invoice_id
    where i.supplier_id = s.id and i.status = 'posted' and i.invoice_date > current_date - 90) as avg_discount_90d,
  (select max(i.invoice_date) from ph.purchase_invoices i where i.supplier_id = s.id and i.status = 'posted') as last_invoice,
  (select count(*) from ph.supplier_offers o where o.supplier_id = s.id and o.offered_at > now() - interval '30 days') as offers_30d
from ph.suppliers s
left join ph.party_balances pb on pb.party_type = 'supplier' and pb.party_id = s.id
where s.active;

-- آخر شرا للصنف من كل مورد (الخصم الفعلي بعد البونص)
create view ph.v_item_buys with (security_invoker = true) as
select distinct on (l.item_id, i.supplier_id) l.item_id, i.supplier_id, s.name as supplier, i.invoice_date,
       round(l.real_discount * 100, 2) as discount_pct, l.packs, l.bonus_packs, l.public_price
from ph.purchase_invoice_lines l
join ph.purchase_invoices i on i.id = l.invoice_id
join ph.suppliers s on s.id = i.supplier_id
where i.status = 'posted'
order by l.item_id, i.supplier_id, i.invoice_date desc, l.id desc;

-- الموظفين (المالك بس): اسم الدخول والدور وآخر دخول
create view ph.v_staff as
select s.user_id, u.username, s.name, s.role, (s.active and u.active) as active, u.kind, u.last_login_at, u.locked_until
from ph.staff s join auth.users u on u.id = s.user_id
where ph.has_role(array['owner']);

-- قايمة الأصناف بالرصيد وأقرب صلاحية (شاشة الأصناف)
create view ph.v_item_list with (security_invoker = true) as
select i.id, i.name_en, i.name_ar, c.name_ar as category, c.code as category_code, i.pack_parts, i.pack_name, i.unit_name,
       i.public_price, coalesce(o.units, 0) as onhand_units,
       floor(coalesce(o.units, 0) / i.pack_parts) as packs,
       coalesce(o.units, 0) - floor(coalesce(o.units, 0) / i.pack_parts) * i.pack_parts as units,
       (select min(b.expiry) from ph.stock_balances sb join ph.batches b on b.id = sb.batch_id
         where sb.item_id = i.id and sb.qty_units > 0 and b.expiry >= current_date) as nearest_expiry,
       i.is_controlled, i.is_fridge, i.needs_rx, i.gkey, i.active
from ph.items i
left join ph.categories c on c.id = i.category_id
left join ph.v_onhand o on o.item_id = i.id;

-- الأكثر مبيعًا النهارده وفي آخر 30 يوم
create view ph.v_top_items_today with (security_invoker = true) as
select l.item_id, i.name_en, i.name_ar, sum(l.qty_units) as units, round(sum(l.qty_units) / i.pack_parts, 1) as packs,
       sum(l.line_total) as value, count(distinct l.sale_id) as invoices
from ph.sale_lines l join ph.sales s on s.id = l.sale_id join ph.items i on i.id = l.item_id
where s.status = 'posted' and s.business_day = ph.business_day()
group by l.item_id, i.name_en, i.name_ar, i.pack_parts;

create view ph.v_top_items_30d with (security_invoker = true) as
select l.item_id, i.name_en, i.name_ar, sum(l.qty_units) as units, round(sum(l.qty_units) / i.pack_parts, 1) as packs,
       sum(l.line_total) as value, round(sum(l.line_total) - sum(l.qty_units * coalesce(l.unit_cost, 0)), 2) as profit
from ph.sale_lines l join ph.sales s on s.id = l.sale_id join ph.items i on i.id = l.item_id
where s.status = 'posted' and s.business_day > ph.business_day() - 30
group by l.item_id, i.name_en, i.name_ar, i.pack_parts;


-- -----------------------------------------------------------------------------------------------------
-- لوحة النهارده: سطر واحد (المالك والمدير والصيدلي). «نفس الوقت الأسبوع اللي فات» = لحد نفس الساعة بالظبط
create view ph.v_dashboard as
select ph.business_day() as day,
  (select coalesce(sum(total), 0) from ph.sales where status = 'posted' and business_day = ph.business_day()) as sales_today,
  (select count(*) from ph.sales where status = 'posted' and business_day = ph.business_day()) as invoices_today,
  (select coalesce(sum(total), 0) from ph.sale_returns where business_day = ph.business_day()) as returns_today,
  (select coalesce(sum(on_credit), 0) from ph.sales where status = 'posted' and business_day = ph.business_day()) as credit_today,
  (select coalesce(gross_profit, 0) from ph.v_sales_daily where business_day = ph.business_day()) as profit_today,
  (select coalesce(sum(total), 0) from ph.sales where status = 'posted' and business_day = ph.business_day() - 7
      and at <= now() - interval '7 days') as sales_last_week_same_time,
  (select coalesce(sum(m.amount), 0) + coalesce((select sum(sh.opening_cash) from ph.shifts sh where sh.status = 'open'), 0)
     from ph.money_moves m join ph.cash_accounts a on a.id = m.account_id and a.kind = 'drawer'
     join ph.shifts sh on sh.id = m.shift_id and sh.status = 'open') as cash_in_drawer,
  (select count(*) from ph.shifts where status = 'open') as open_shifts,
  (select coalesce(sum(balance), 0) from ph.party_balances where party_type = 'customer' and balance > 0) as customers_due,
  (select count(*) from ph.v_customer_dues where over_limit) as customers_over_limit,
  (select coalesce(sum(balance), 0) from ph.party_balances where party_type = 'supplier' and balance > 0) as suppliers_due,
  (select count(*) from ph.v_shortages) as shortages,
  (select count(distinct pl.item_id) from ph.purchase_order_lines pl join ph.purchase_orders po on po.id = pl.order_id
      where po.status = 'sent' and ph.business_day(po.sent_at) = ph.business_day()) as ordered_today,
  (select count(*) from ph.v_expiring where level in ('expired', 'red')) as expiring_30d,
  (select coalesce(sum(at_risk_value), 0) from ph.v_expiry_risk) as expiry_risk_value,
  (select count(*) from ph.v_refills_due) as refills_due,
  (select count(*) from ph.trial_notes where status = 'open') as open_notes,
  (select demo_data from ph.settings where id = 1) as demo_data
where ph.has_role(array['owner', 'manager', 'pharmacist']);
grant select on ph.v_dashboard to authenticated;

grant select on ph.v_order_advice, ph.v_sales_hourly, ph.v_expiry_risk, ph.v_chronic_suggestions, ph.v_refills_due, ph.v_customer_pick,
  ph.v_supplier_card, ph.v_item_buys, ph.v_staff, ph.v_item_list, ph.v_top_items_today, ph.v_top_items_30d to authenticated;
revoke all on function ph.pos_lookup(text, integer), ph.item_alternatives(bigint), ph.mark_ordered(jsonb),
  ph.add_chronic(bigint, bigint, integer), ph.my_open_shift() from public, anon;
grant execute on function ph.pos_lookup(text, integer), ph.item_alternatives(bigint), ph.mark_ordered(jsonb),
  ph.add_chronic(bigint, bigint, integer), ph.my_open_shift() to authenticated;
