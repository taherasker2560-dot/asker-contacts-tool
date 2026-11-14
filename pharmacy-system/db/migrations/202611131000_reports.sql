-- 202611131000_reports
-- المطلوب (طلب المالك 2026-11-13): «تقارير لكل التفاصيل، ماتخليش حاجة الصيدلي بيحلم بيها إلا ويلاقي لها تقرير جاهز»، في 7 مجموعات:
--   1) المبيعات والربح  2) المخزون  3) المشتريات والموردين  4) العملاء  5) النواقص والطلبيات  6) الفلوس  7) المتجر
--   + ملخص الصبح (دالة واحدة بيقراها البرنامج أو يوزر البوت).
-- ليه: كل رقم بيتحسب هنا مرة واحدة، فالشاشة والموبايل والبوت بيقولوا نفس الرقم.
-- الصلاحية: التقارير للمالك والمدير. ملخص الصبح كمان ليوزر البوت (أرقام مجمّعة، من غير أسماء عملاء ولا موبايلات).
-- الرجوع:
--   drop function ph.morning_brief_text(), ph.morning_brief(), ph.rep_store_no_image(integer), ph.rep_store_orders(date, date),
--     ph.rep_pnl_monthly(integer), ph.rep_expenses(date, date), ph.rep_cash_flow(date, date), ph.rep_late_orders(integer),
--     ph.rep_order_fill(date, date), ph.rep_lapsed_customers(integer), ph.rep_top_customers(date, date, integer), ph.rep_dues_aging(),
--     ph.rep_price_changes(date, date), ph.rep_supplier_month(date, date), ph.rep_discount_compare(integer), ph.rep_expiry_months(integer),
--     ph.rep_runout(integer), ph.rep_dead_stock(integer), ph.rep_stock_value(), ph.rep_by_shift(date, date), ph.rep_by_staff(date, date),
--     ph.rep_heatmap(date, date), ph.rep_item_profit(date, date, integer), ph.rep_sales_monthly(integer), ph.rep_sales_summary(date, date),
--     ph.rep_sales_block(date, date);
--   alter table ph.items drop column image_path;

-- صورة الصنف في المتجر (المسار على جهاز الصيدلية)، عشان تقرير «أصناف لسه ملهاش صورة»
alter table ph.items add column image_path text check (char_length(image_path) <= 300);

-- =====================================================================================================
-- 1) المبيعات والربح
-- =====================================================================================================
-- أرقام فترة (من غير صلاحية: داخلية، بتتنده من الدوال اللي تحت بس)
create function ph.rep_sales_block(p_from date, p_to date) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'from', p_from, 'to', p_to,
    'net_sales', coalesce(sum(d.net_sales), 0), 'cost', coalesce(sum(d.net_cost), 0), 'profit', coalesce(sum(d.gross_profit), 0),
    'invoices', coalesce(sum(d.invoices), 0), 'returns', coalesce(sum(d.returns), 0), 'on_credit', coalesce(sum(d.on_credit), 0),
    'days', count(*) filter (where d.invoices > 0))
  from ph.v_sales_daily d where d.business_day between p_from and p_to
$$;
revoke all on function ph.rep_sales_block(date, date) from public, anon, authenticated;

-- الفترة، واللي قبلها بنفس الطول، ونفس التواريخ السنة اللي فاتت
create function ph.rep_sales_summary(p_from date, p_to date) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare n integer := p_to - p_from + 1;
begin
  perform ph.require_role(array['owner', 'manager']);
  return jsonb_build_object(
    'cur',  ph.rep_sales_block(p_from, p_to),
    'prev', ph.rep_sales_block(p_from - n, p_from - 1),
    'ly',   ph.rep_sales_block((p_from - interval '1 year')::date, (p_to - interval '1 year')::date));
end $$;

-- شهر بشهر (للمقارنة بنفس الشهر السنة اللي فاتت)
create function ph.rep_sales_monthly(p_months integer default 24)
returns table (month date, net_sales numeric, cost numeric, profit numeric, invoices bigint, returns numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select date_trunc('month', d.business_day)::date, sum(d.net_sales), sum(d.net_cost), sum(d.gross_profit), sum(d.invoices)::bigint, sum(d.returns)
  from ph.v_sales_daily d
  where d.business_day >= (date_trunc('month', ph.business_day()) - make_interval(months => least(greatest(p_months, 1), 120) - 1))::date
  group by 1 order by 1;
end $$;

-- ربح كل صنف في الفترة (بعد المرتجع): الأكتر ربحًا، والأقل، واللي بيتباع بخسارة
create function ph.rep_item_profit(p_from date, p_to date, p_limit integer default 500)
returns table (item_id bigint, name_en text, name_ar text, category text, pack_parts integer, units numeric, sales numeric,
               cost numeric, profit numeric, margin_pct numeric, invoices bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with s as (
    select l.item_id, sum(l.qty_units) as u, sum(l.line_total) as v, sum(round(l.qty_units * coalesce(l.unit_cost, 0), 2)) as c,
           count(distinct l.sale_id) as n
    from ph.sale_lines l join ph.sales x on x.id = l.sale_id
    where x.status = 'posted' and x.business_day between p_from and p_to group by 1
  ), r as (
    select rl.item_id, sum(rl.qty_units) as u, sum(rl.value) as v,
           sum(round(rl.qty_units * coalesce(sl.unit_cost, b.unit_cost, 0), 2)) as c
    from ph.sale_return_lines rl join ph.sale_returns sr on sr.id = rl.return_id
    join ph.batches b on b.id = rl.batch_id left join ph.sale_lines sl on sl.id = rl.sale_line_id
    where sr.business_day between p_from and p_to group by 1
  )
  select i.id, i.name_en, i.name_ar, c.name_ar, i.pack_parts,
         s.u - coalesce(r.u, 0), s.v - coalesce(r.v, 0), s.c - coalesce(r.c, 0),
         (s.v - coalesce(r.v, 0)) - (s.c - coalesce(r.c, 0)),
         round(100 * ((s.v - coalesce(r.v, 0)) - (s.c - coalesce(r.c, 0))) / nullif(s.v - coalesce(r.v, 0), 0), 1),
         s.n
  from s join ph.items i on i.id = s.item_id left join ph.categories c on c.id = i.category_id left join r on r.item_id = s.item_id
  order by 9 desc
  limit least(greatest(coalesce(p_limit, 500), 1), 5000);
end $$;

-- الزحمة: متوسط البيع لكل يوم في الأسبوع × ساعة (0 = الأحد … 6 = السبت)
create function ph.rep_heatmap(p_from date, p_to date)
returns table (dow integer, hr integer, avg_sales numeric, avg_invoices numeric)
language plpgsql stable security definer set search_path = '' as $$
declare v_tz text := coalesce((select time_zone from ph.settings where id = 1), 'Africa/Cairo');
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with days as (select extract(dow from d)::integer as dow, count(*) as n from generate_series(p_from, p_to, interval '1 day') d group by 1),
  s as (
    select extract(dow from x.business_day)::integer as dow, extract(hour from x.at at time zone v_tz)::integer as hr,
           sum(x.total) as v, count(*) as n
    from ph.sales x where x.status = 'posted' and x.business_day between p_from and p_to group by 1, 2
  )
  select dd.dow, h.hr, round(coalesce(s.v, 0) / dd.n, 2), round(coalesce(s.n, 0)::numeric / dd.n, 2)
  from days dd cross join generate_series(0, 23) h(hr) left join s on s.dow = dd.dow and s.hr = h.hr
  order by 1, 2;
end $$;

-- كل موظف: فواتيره وبيعه ومتوسط فاتورته ومرتجعاته (البيع المنقول من فارمافلاي ملوش يوزر)
create function ph.rep_by_staff(p_from date, p_to date)
returns table (user_id uuid, name text, role text, invoices bigint, sales numeric, avg_basket numeric, on_credit numeric,
               discount numeric, returns_count bigint, returns_value numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  -- اليوزر الفاضي (المنقول) بيتجمع تحت مفتاح صفر عشان الربط
  with s as (
    select coalesce(x.by_user, '00000000-0000-0000-0000-000000000000'::uuid) as k, count(*) as n, sum(x.total) as v,
           sum(x.on_credit) as cr, sum(x.discount) as ds
    from ph.sales x where x.status = 'posted' and x.business_day between p_from and p_to group by 1
  ), r as (
    select coalesce(sr.by_user, '00000000-0000-0000-0000-000000000000'::uuid) as k, count(*) as n, sum(sr.total) as v
    from ph.sale_returns sr where sr.business_day between p_from and p_to group by 1
  ), j as (select coalesce(s.k, r.k) as k, s.n as sn, s.v as sv, s.cr, s.ds, r.n as rn, r.v as rv from s full join r on r.k = s.k)
  select nullif(j.k, '00000000-0000-0000-0000-000000000000'::uuid),
         coalesce(st.name, case when j.k = '00000000-0000-0000-0000-000000000000'::uuid then 'فارمافلاي (قبل البرنامج)' else '؟' end),
         st.role, coalesce(j.sn, 0), coalesce(j.sv, 0), round(coalesce(j.sv, 0) / nullif(j.sn, 0), 2), coalesce(j.cr, 0), coalesce(j.ds, 0),
         coalesce(j.rn, 0), coalesce(j.rv, 0)
  from j left join ph.staff st on st.user_id = j.k
  order by 5 desc;
end $$;

-- كل وردية: بيعها، والمفروض في الدرج، واللي اتعدّ، والفرق
create function ph.rep_by_shift(p_from date, p_to date)
returns table (shift_id bigint, account text, opened_by text, opened_at timestamptz, closed_at timestamptz, status text,
               invoices bigint, sales numeric, opening_cash numeric, expected numeric, counted numeric, diff numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select sh.id, a.name, st.name, sh.opened_at, sh.closed_at, sh.status,
         (select count(*) from ph.sales x where x.shift_id = sh.id and x.status = 'posted'),
         (select coalesce(sum(x.total), 0) from ph.sales x where x.shift_id = sh.id and x.status = 'posted'),
         sh.opening_cash,
         sh.opening_cash + coalesce((select sum(m.amount) from ph.money_moves m
                                      where m.shift_id = sh.id and m.account_id = sh.account_id and m.doc_type <> 'shift'), 0),
         sh.counted_cash,
         coalesce((select sum(m.amount) from ph.money_moves m where m.shift_id = sh.id and m.doc_type = 'shift'), 0)
  from ph.shifts sh join ph.cash_accounts a on a.id = sh.account_id left join ph.staff st on st.user_id = sh.opened_by
  where ph.business_day(sh.opened_at) between p_from and p_to
  order by sh.opened_at desc;
end $$;

-- =====================================================================================================
-- 2) المخزون
-- =====================================================================================================
-- قيمة المخزون لكل مكان: بالتكلفة وبسعر البيع، والمنتهي لوحده
create function ph.rep_stock_value()
returns table (location_id smallint, location text, counts_as_stock boolean, items bigint, batches bigint,
               cost_value numeric, sale_value numeric, expired_cost numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select v.location_id, v.location, v.counts_as_stock, count(distinct v.item_id), count(*),
         round(sum(v.cost_value), 2),
         round(sum(v.qty_units * coalesce(v.public_price, i.public_price) / i.pack_parts), 2),
         round(coalesce(sum(v.cost_value) filter (where v.expiry < current_date), 0), 2)
  from ph.v_stock v join ph.items i on i.id = v.item_id
  where v.qty_units > 0
  group by 1, 2, 3 order by 1;
end $$;

-- الراكد (فلوس نايمة): عليه رصيد ومااتباعش من p_days يوم أو أكتر
create function ph.rep_dead_stock(p_days integer default 90)
returns table (item_id bigint, name_en text, name_ar text, pack_parts integer, onhand_units numeric, cost_value numeric,
               sale_value numeric, last_sold date, days_since integer, nearest_expiry date)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with st as (
    select v.item_id, sum(v.qty_units) as u, sum(v.cost_value) as c, sum(v.qty_units * coalesce(v.public_price, 0)) as pv,
           min(v.expiry) filter (where v.expiry >= current_date) as ne
    from ph.v_stock v where v.qty_units > 0 and v.counts_as_stock group by 1
  ), ls as (
    select l.item_id, max(x.business_day) as d from ph.sale_lines l join ph.sales x on x.id = l.sale_id
    where x.status = 'posted' group by 1
  )
  select i.id, i.name_en, i.name_ar, i.pack_parts, st.u, round(st.c, 2), round(st.pv / i.pack_parts, 2), ls.d,
         (ph.business_day() - ls.d), st.ne
  from st join ph.items i on i.id = st.item_id left join ls on ls.item_id = st.item_id
  where ls.d is null or ls.d <= ph.business_day() - greatest(coalesce(p_days, 90), 7)
  order by 6 desc nulls last;
end $$;

-- هيخلص من الرف خلال p_days يوم بسرعة بيع آخر 30 يوم (لسه عليه رصيد)
create function ph.rep_runout(p_days integer default 14)
returns table (item_id bigint, name_en text, name_ar text, pack_parts integer, onhand_units numeric, daily_rate numeric,
               days_left numeric, ordered_today boolean)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select i.id, i.name_en, i.name_ar, i.pack_parts, o.units, round(s.units / 30.0, 3), round(o.units / (s.units / 30.0), 1),
         exists (select 1 from ph.purchase_order_lines pl join ph.purchase_orders po on po.id = pl.order_id
                 where pl.item_id = i.id and po.status = 'sent' and ph.business_day(po.sent_at) = ph.business_day())
  from ph.v_onhand o join ph.v_sales_30d s on s.item_id = o.item_id and s.units > 0 join ph.items i on i.id = o.item_id
  where o.units > 0 and o.units / (s.units / 30.0) <= greatest(coalesce(p_days, 14), 1)
  order by 7;
end $$;

-- قيمة اللي بيخلص كل شهر (و«خلص فعلًا» في سطر لوحده: month = null)
create function ph.rep_expiry_months(p_months integer default 12)
returns table (month date, batches bigint, units numeric, cost_value numeric, sale_value numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select case when v.expiry < current_date then null else date_trunc('month', v.expiry)::date end, count(*), sum(v.qty_units),
         round(sum(v.cost_value), 2), round(sum(v.qty_units * coalesce(v.public_price, i.public_price) / i.pack_parts), 2)
  from ph.v_stock v join ph.items i on i.id = v.item_id
  where v.qty_units > 0 and v.counts_as_stock and v.expiry is not null
    and v.expiry < (date_trunc('month', current_date) + make_interval(months => least(greatest(p_months, 1), 36)))::date
  group by 1 order by 1 nulls first;
end $$;

-- =====================================================================================================
-- 3) المشتريات والموردين
-- =====================================================================================================
-- خصومات الموردين على نفس الصنف (آخر شرا من كل مورد في p_days يوم): الأحسن، الأوحش، الفرق،
-- وآخر مرة اشترينا من مين، وكام كان ممكن نوفّر لو اشترينا من الأحسن
create function ph.rep_discount_compare(p_days integer default 180)
returns table (item_id bigint, name_en text, name_ar text, suppliers bigint, best_supplier text, best_pct numeric,
               worst_supplier text, worst_pct numeric, spread numeric, last_supplier text, last_pct numeric, missed_value numeric,
               detail jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with b as (select * from ph.v_item_buys where invoice_date > current_date - greatest(coalesce(p_days, 180), 7)),
  agg as (
    select b.item_id, count(*) as n,
           (array_agg(b.supplier order by b.discount_pct desc, b.invoice_date desc))[1] as best_s, max(b.discount_pct) as best_p,
           (array_agg(b.supplier order by b.discount_pct asc, b.invoice_date desc))[1] as worst_s, min(b.discount_pct) as worst_p,
           (array_agg(b.supplier order by b.invoice_date desc))[1] as last_s,
           (array_agg(b.discount_pct order by b.invoice_date desc))[1] as last_p,
           (array_agg(b.public_price * (b.packs + b.bonus_packs) order by b.invoice_date desc))[1] as last_value,
           jsonb_agg(jsonb_build_object('supplier', b.supplier, 'pct', b.discount_pct, 'date', b.invoice_date) order by b.discount_pct desc) as d
    from b group by 1 having count(*) >= 2
  )
  select a.item_id, i.name_en, i.name_ar, a.n, a.best_s, a.best_p, a.worst_s, a.worst_p, a.best_p - a.worst_p, a.last_s, a.last_p,
         round(greatest(0, a.best_p - a.last_p) / 100 * a.last_value, 2), a.d
  from agg a join ph.items i on i.id = a.item_id
  order by 12 desc, 9 desc;
end $$;

-- فواتير كل مورد في الفترة: العدد، الإجمالي، البونص، الخصم الفعلي، اللي اتدفع، والمرتجع
create function ph.rep_supplier_month(p_from date, p_to date)
returns table (supplier_id integer, name text, invoices bigint, total numeric, public_value numeric, real_discount_pct numeric,
               bonus_packs numeric, paid numeric, returns numeric, balance numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with inv as (
    select pi.supplier_id, count(distinct pi.id) as n, sum(l.cost_total) as t, sum(l.public_price * (l.packs + l.bonus_packs)) as pv,
           sum(l.bonus_packs) as bp
    from ph.purchase_invoices pi join ph.purchase_invoice_lines l on l.invoice_id = pi.id
    where pi.status = 'posted' and pi.invoice_date between p_from and p_to group by 1
  ), pay as (
    select p.party_id::integer as supplier_id, sum(p.amount) as a from ph.payments p
    where p.kind = 'to_supplier' and ph.business_day(p.at) between p_from and p_to group by 1
  ), ret as (
    select pr.supplier_id, sum(pr.total) as a from ph.purchase_returns pr
    where pr.status = 'posted' and ph.business_day(pr.created_at) between p_from and p_to group by 1
  )
  select s.id, s.name, coalesce(inv.n, 0), coalesce(inv.t, 0), coalesce(inv.pv, 0),
         round(100 * (1 - inv.t / nullif(inv.pv, 0)), 2), coalesce(inv.bp, 0), coalesce(pay.a, 0), coalesce(ret.a, 0), coalesce(pb.balance, 0)
  from ph.suppliers s
  left join inv on inv.supplier_id = s.id left join pay on pay.supplier_id = s.id left join ret on ret.supplier_id = s.id
  left join ph.party_balances pb on pb.party_type = 'supplier' and pb.party_id = s.id
  where inv.n is not null or pay.a is not null or ret.a is not null
  order by 4 desc;
end $$;

-- أصناف سعرها اتغير، وأثره على قيمة اللي في المخزن
create function ph.rep_price_changes(p_from date, p_to date)
returns table (item_id bigint, name_en text, name_ar text, old_price numeric, new_price numeric, change_pct numeric,
               changed_at timestamptz, source text, onhand_units numeric, stock_effect numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select i.id, i.name_en, i.name_ar, pc.old_price, pc.new_price, round(100 * (pc.new_price - pc.old_price) / nullif(pc.old_price, 0), 1),
         pc.changed_at, pc.source, coalesce(o.units, 0), round(coalesce(o.units, 0) / i.pack_parts * (pc.new_price - pc.old_price), 2)
  from ph.price_changes pc join ph.items i on i.id = pc.item_id left join ph.v_onhand o on o.item_id = i.id
  where ph.business_day(pc.changed_at) between p_from and p_to
  order by pc.changed_at desc;
end $$;

-- =====================================================================================================
-- 4) العملاء
-- =====================================================================================================
-- المديونيات وبقالها قد إيه (الأقدم بيتسدد الأول): كام من الرصيد عمره أقل من شهر، شهرين، تلاتة، وأكتر
create function ph.rep_dues_aging()
returns table (customer_id bigint, name text, phone text, balance numeric, credit_limit numeric, over_limit boolean,
               last_payment timestamptz, oldest_unpaid date, age_days integer, b_0_30 numeric, b_31_60 numeric, b_61_90 numeric, b_90p numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with bal as (select pb.party_id, pb.balance from ph.party_balances pb where pb.party_type = 'customer' and pb.balance > 0),
  ch as (   -- المديونية من الأحدث للأقدم لحد ما توصل للرصيد
    select l.party_id, l.business_day, l.amount,
           sum(l.amount) over (partition by l.party_id order by l.at desc, l.id desc) as run
    from ph.party_ledger l join bal on bal.party_id = l.party_id
    where l.party_type = 'customer' and l.amount > 0
  ), alloc as (
    select ch.party_id, ch.business_day, greatest(0, least(ch.amount, bal.balance - (ch.run - ch.amount))) as part
    from ch join bal on bal.party_id = ch.party_id where ch.run - ch.amount < bal.balance
  ), ag as (
    select a.party_id, min(a.business_day) as oldest,
           sum(a.part) filter (where ph.business_day() - a.business_day <= 30) as b1,
           sum(a.part) filter (where ph.business_day() - a.business_day between 31 and 60) as b2,
           sum(a.part) filter (where ph.business_day() - a.business_day between 61 and 90) as b3,
           sum(a.part) filter (where ph.business_day() - a.business_day > 90) as b4
    from alloc a group by 1
  )
  select c.id, c.name, c.phone, bal.balance, c.credit_limit, bal.balance > c.credit_limit,
         (select max(p.at) from ph.payments p where p.kind = 'from_customer' and p.party_id = c.id),
         ag.oldest, ph.business_day() - ag.oldest,
         coalesce(ag.b1, 0), coalesce(ag.b2, 0), coalesce(ag.b3, 0), coalesce(ag.b4, 0)
  from bal join ph.customers c on c.id = bal.party_id left join ag on ag.party_id = bal.party_id
  order by 9 desc nulls last, 4 desc;
end $$;

-- أحسن العملاء في الفترة: الشرا والربح والزيارات
create function ph.rep_top_customers(p_from date, p_to date, p_limit integer default 50)
returns table (customer_id bigint, name text, phone text, invoices bigint, visits bigint, sales numeric, profit numeric,
               avg_basket numeric, last_visit date)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select c.id, c.name, c.phone, count(*), count(distinct x.business_day), sum(x.total),
         sum(x.total) - coalesce(sum((select sum(round(l.qty_units * coalesce(l.unit_cost, 0), 2)) from ph.sale_lines l where l.sale_id = x.id)), 0),
         round(sum(x.total) / count(*), 2), max(x.business_day)
  from ph.sales x join ph.customers c on c.id = x.customer_id
  where x.status = 'posted' and x.business_day between p_from and p_to
  group by c.id, c.name, c.phone
  order by 6 desc
  limit least(greatest(coalesce(p_limit, 50), 1), 500);
end $$;

-- عملاء بطّلوا ييجوا: كانوا بييجوا بانتظام (3 أيام أو أكتر في الـ 6 شهور اللي قبل فترة السكوت) ومن p_quiet يوم مفيش
create function ph.rep_lapsed_customers(p_quiet integer default 45)
returns table (customer_id bigint, name text, phone text, visits bigint, spent numeric, avg_gap_days numeric, last_visit date, days_away integer)
language plpgsql stable security definer set search_path = '' as $$
declare v_cut date := ph.business_day() - greatest(coalesce(p_quiet, 45), 14);
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with v as (
    select x.customer_id, count(distinct x.business_day) as n, sum(x.total) as t, min(x.business_day) as f, max(x.business_day) as l
    from ph.sales x
    where x.status = 'posted' and x.customer_id is not null and x.business_day > v_cut - 180
    group by 1
  )
  select c.id, c.name, c.phone, v.n, v.t, round((v.l - v.f)::numeric / nullif(v.n - 1, 0), 1), v.l, ph.business_day() - v.l
  from v join ph.customers c on c.id = v.customer_id and c.active
  where v.l <= v_cut and v.n >= 3
  order by 5 desc;
end $$;

-- =====================================================================================================
-- 5) النواقص والطلبيات
-- =====================================================================================================
-- نسبة وصول الطلبية: الصنف اللي اتطلب من مورد يعتبر وصل لو جه في فاتورة من نفس المورد خلال يومين
create function ph.rep_order_fill(p_from date, p_to date)
returns table (supplier_id integer, name text, orders bigint, lines bigint, lines_received bigint, fill_pct numeric,
               packs_ordered numeric, packs_received numeric, avg_days numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with ol as (
    select po.id as order_id, po.supplier_id, ph.business_day(po.sent_at) as d, pl.item_id, pl.packs
    from ph.purchase_orders po join ph.purchase_order_lines pl on pl.order_id = po.id
    where po.status = 'sent' and po.supplier_id is not null and ph.business_day(po.sent_at) between p_from and p_to
  ), m as (
    select ol.*, rcv.packs as got, rcv.invoice_date
    from ol left join lateral (
      select sum(l.packs + l.bonus_packs) as packs, min(pi.invoice_date) as invoice_date
      from ph.purchase_invoice_lines l join ph.purchase_invoices pi on pi.id = l.invoice_id
      where pi.status = 'posted' and pi.supplier_id = ol.supplier_id and l.item_id = ol.item_id
        and (pi.order_id = ol.order_id or pi.invoice_date between ol.d and ol.d + 2)
    ) rcv on true
  )
  select s.id, s.name, count(distinct m.order_id), count(*), count(*) filter (where m.got > 0),
         round(100.0 * count(*) filter (where m.got > 0) / count(*), 1), sum(m.packs), coalesce(sum(least(coalesce(m.got, 0), m.packs)), 0),
         round(avg(m.invoice_date - m.d) filter (where m.got > 0), 1)
  from m join ph.suppliers s on s.id = m.supplier_id
  group by s.id, s.name order by 6 asc;
end $$;

-- طلبيات اتأخرت: اتطلبت من أكتر من p_hours ساعة (في آخر أسبوعين) ولسه ماجتش في فاتورة
create function ph.rep_late_orders(p_hours integer default 24)
returns table (order_no text, supplier text, item_id bigint, name_en text, name_ar text, packs numeric, sent_at timestamptz, hours_waiting integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select po.no, s.name, i.id, i.name_en, i.name_ar, pl.packs, po.sent_at, (extract(epoch from now() - po.sent_at) / 3600)::integer
  from ph.purchase_orders po join ph.purchase_order_lines pl on pl.order_id = po.id
  join ph.suppliers s on s.id = po.supplier_id join ph.items i on i.id = pl.item_id
  where po.status = 'sent' and po.sent_at < now() - make_interval(hours => greatest(coalesce(p_hours, 24), 1))
    and po.sent_at > now() - interval '7 days'
    and not exists (
      select 1 from ph.purchase_invoice_lines l join ph.purchase_invoices pi on pi.id = l.invoice_id
      where pi.status = 'posted' and pi.supplier_id = po.supplier_id and l.item_id = pl.item_id
        and (pi.order_id = po.id or pi.invoice_date >= ph.business_day(po.sent_at)))
  order by po.sent_at;
end $$;

-- =====================================================================================================
-- 6) الفلوس
-- =====================================================================================================
-- حركة كل خزنة: أولها، الداخل والخارج (بالنوع)، وآخرها
create function ph.rep_cash_flow(p_from date, p_to date)
returns table (account_id smallint, account text, kind text, opening numeric, inflow numeric, outflow numeric, closing numeric, by_type jsonb)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select a.id, a.name, a.kind,
         coalesce((select sum(m.amount) from ph.money_moves m where m.account_id = a.id and m.business_day < p_from), 0),
         coalesce((select sum(m.amount) from ph.money_moves m where m.account_id = a.id and m.business_day between p_from and p_to and m.amount > 0), 0),
         coalesce((select -sum(m.amount) from ph.money_moves m where m.account_id = a.id and m.business_day between p_from and p_to and m.amount < 0), 0),
         coalesce((select sum(m.amount) from ph.money_moves m where m.account_id = a.id and m.business_day <= p_to), 0),
         coalesce((select jsonb_object_agg(t.doc_type, t.s) from (
                     select m.doc_type, sum(m.amount) as s from ph.money_moves m
                     where m.account_id = a.id and m.business_day between p_from and p_to group by 1) t), '{}')
  from ph.cash_accounts a where a.active order by a.id;
end $$;

create function ph.rep_expenses(p_from date, p_to date)
returns table (category text, entries bigint, total numeric, share_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select coalesce(c.name, 'من غير تصنيف'), count(*), sum(e.amount), round(100 * sum(e.amount) / nullif(sum(sum(e.amount)) over (), 0), 1)
  from ph.expenses e left join ph.expense_categories c on c.id = e.category_id
  where e.business_day between p_from and p_to group by 1 order by 3 desc;
end $$;

-- صافي الربح شهر بشهر = الربح الإجمالي − المصروفات
create function ph.rep_pnl_monthly(p_months integer default 12)
returns table (month date, net_sales numeric, cost numeric, gross_profit numeric, expenses numeric, net_profit numeric, net_margin_pct numeric)
language plpgsql stable security definer set search_path = '' as $$
declare v_from date := (date_trunc('month', ph.business_day()) - make_interval(months => least(greatest(p_months, 1), 60) - 1))::date;
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  with s as (select date_trunc('month', d.business_day)::date as m, sum(d.net_sales) as ns, sum(d.net_cost) as c, sum(d.gross_profit) as gp
             from ph.v_sales_daily d where d.business_day >= v_from group by 1),
  e as (select date_trunc('month', x.business_day)::date as m, sum(x.amount) as ex from ph.expenses x where x.business_day >= v_from group by 1),
  months as (select generate_series(v_from, date_trunc('month', ph.business_day())::date, interval '1 month')::date as m)
  select mo.m, coalesce(s.ns, 0), coalesce(s.c, 0), coalesce(s.gp, 0), coalesce(e.ex, 0), coalesce(s.gp, 0) - coalesce(e.ex, 0),
         round(100 * (coalesce(s.gp, 0) - coalesce(e.ex, 0)) / nullif(s.ns, 0), 1)
  from months mo left join s on s.m = mo.m left join e on e.m = mo.m order by 1;
end $$;

-- =====================================================================================================
-- 7) المتجر الأونلاين
-- =====================================================================================================
create function ph.rep_store_orders(p_from date, p_to date)
returns table (id bigint, created_at timestamptz, name text, phone text, items_count integer, total numeric, delivery_fee numeric,
               status text, sale_no text, minutes_to_sale integer)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select o.id, o.created_at, o.name, o.phone, jsonb_array_length(o.items), o.total, o.delivery_fee, o.status, s.no,
         (extract(epoch from s.at - o.created_at) / 60)::integer
  from ph.online_orders o left join ph.sales s on s.id = o.sale_id
  where ph.business_day(o.created_at) between p_from and p_to
  order by o.created_at desc;
end $$;

-- أصناف متاحة في المتجر لسه ملهاش صورة (الأكتر بيعًا الأول: دي اللي تستاهل تتصوّر الأول)
create function ph.rep_store_no_image(p_limit integer default 200)
returns table (item_id bigint, name_en text, name_ar text, onhand_units numeric, pack_parts integer, sold_30d_units numeric)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform ph.require_role(array['owner', 'manager']);
  return query
  select i.id, i.name_en, i.name_ar, o.units, i.pack_parts, coalesce(s.units, 0)
  from ph.items i join ph.v_onhand o on o.item_id = i.id and o.units > 0 left join ph.v_sales_30d s on s.item_id = i.id
  where i.active and coalesce(btrim(i.image_path), '') = ''
  order by 6 desc, i.name_en
  limit least(greatest(coalesce(p_limit, 200), 1), 2000);
end $$;

-- =====================================================================================================
-- ملخص الصبح: امبارح بالأرقام + اللي محتاج يتعمل النهارده. أرقام مجمّعة بس (يوزر البوت يقدر يقراه)
-- =====================================================================================================
create function ph.morning_brief() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_day   date := ph.business_day() - 1;
  y       jsonb;
  lw      jsonb;
  v_top   jsonb;
  v_bad   integer;
begin
  perform ph.require_role(array['owner', 'manager', 'bot']);
  y  := ph.rep_sales_block(v_day, v_day);
  lw := ph.rep_sales_block(v_day - 7, v_day - 7);
  select coalesce(jsonb_agg(t order by t.v desc), '[]') into v_top from (
    select coalesce(i.name_ar, i.name_en) as name, sum(l.line_total) as v, round(sum(l.qty_units) / i.pack_parts, 1) as packs
    from ph.sale_lines l join ph.sales s on s.id = l.sale_id join ph.items i on i.id = l.item_id
    where s.status = 'posted' and s.business_day = v_day group by i.id, i.name_ar, i.name_en, i.pack_parts
    order by 2 desc limit 3) t;
  begin   -- الفحص للمالك والمدير بس؛ يوزر البوت مايشوفش تفاصيله
    select count(*) into v_bad from ph.health_check() h where not h.ok;
  exception when others then v_bad := null;
  end;
  return jsonb_build_object(
    'day', v_day,
    'yesterday', y,
    'same_day_last_week', lw,
    'change_pct', round(100 * ((y ->> 'net_sales')::numeric - (lw ->> 'net_sales')::numeric) / nullif((lw ->> 'net_sales')::numeric, 0), 1),
    'top_items', v_top,
    'shortages', (select count(*) from ph.v_shortages where ordered_today_from is null),
    'expiring_30d', (select count(*) from ph.v_expiring where level in ('expired', 'red')),
    'expiry_risk_value', (select coalesce(round(sum(at_risk_value)), 0) from ph.v_expiry_risk),
    'refills_due', (select count(*) from ph.v_refills_due),
    'customers_over_limit', (select count(*) from ph.v_customer_dues where over_limit),
    'customers_due', (select coalesce(sum(balance), 0) from ph.party_balances where party_type = 'customer' and balance > 0),
    'late_order_lines', (select count(*) from ph.purchase_orders po join ph.purchase_order_lines pl on pl.order_id = po.id
                          where po.status = 'sent' and po.sent_at < now() - interval '24 hours' and po.sent_at > now() - interval '7 days'
                            and not exists (select 1 from ph.purchase_invoice_lines l join ph.purchase_invoices pi on pi.id = l.invoice_id
                                            where pi.status = 'posted' and pi.supplier_id = po.supplier_id and l.item_id = pl.item_id
                                              and (pi.order_id = po.id or pi.invoice_date >= ph.business_day(po.sent_at)))),
    'open_shifts_old', (select count(*) from ph.shifts where status = 'open' and opened_at < now() - interval '18 hours'),
    'open_notes', (select count(*) from ph.trial_notes where status = 'open'),
    'health_failures', v_bad);
end $$;

-- نفس الملخص كرسالة جاهزة (البرنامج بيعرضها، والبوت يقدر يبعتها للمالك بس)
create function ph.morning_brief_text() returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  b jsonb := ph.morning_brief();
  y jsonb := b -> 'yesterday';
  t text;
  r jsonb;
  ch numeric := (b ->> 'change_pct')::numeric;
begin
  t := 'صباح الخير ☀️ ملخص ' || to_char((b ->> 'day')::date, 'DD/MM') || E'\n'
    || '💰 المبيعات: ' || to_char((y ->> 'net_sales')::numeric, 'FM999,999,990') || ' ج'
    || case when ch is null then '' else ' (' || case when ch >= 0 then '▲ ' else '▼ ' end || abs(ch) || '% عن نفس اليوم الأسبوع اللي فات)' end || E'\n'
    || '📈 الربح التقريبي: ' || to_char((y ->> 'profit')::numeric, 'FM999,999,990') || ' ج · ' || (y ->> 'invoices') || ' فاتورة' || E'\n';
  if jsonb_array_length(b -> 'top_items') > 0 then
    t := t || '🏆 الأكتر بيعًا:';
    for r in select * from jsonb_array_elements(b -> 'top_items') loop t := t || ' ' || (r ->> 'name') || '،'; end loop;
    t := rtrim(t, '،') || E'\n';
  end if;
  t := t || E'\nالنهارده:\n'
    || '🚚 نواقص محتاجة تتطلب: ' || (b ->> 'shortages') || E'\n'
    || '⏳ صلاحية أقل من شهر: ' || (b ->> 'expiring_30d') || ' تشغيلة (في خطر ' || to_char((b ->> 'expiry_risk_value')::numeric, 'FM999,999,990') || ' ج)' || E'\n'
    || '💊 عملاء ميعاد علبتهم: ' || (b ->> 'refills_due') || E'\n';
  if (b ->> 'late_order_lines')::integer > 0 then t := t || '⚠️ أصناف اتطلبت وماوصلتش: ' || (b ->> 'late_order_lines') || E'\n'; end if;
  if (b ->> 'customers_over_limit')::integer > 0 then t := t || '⚠️ عملاء عدّوا حد الآجل: ' || (b ->> 'customers_over_limit') || E'\n'; end if;
  if (b ->> 'open_shifts_old')::integer > 0 then t := t || '⚠️ وردية مفتوحة من امبارح: ' || (b ->> 'open_shifts_old') || E'\n'; end if;
  if (b ->> 'health_failures')::integer > 0 then t := t || '🛑 فحص القاعدة فيه ' || (b ->> 'health_failures') || ' مشكلة' || E'\n';
  elsif (b ->> 'health_failures') is not null then t := t || '✅ القاعدة سليمة' || E'\n'; end if;
  return t;
end $$;

-- -----------------------------------------------------------------------------------------------------
revoke all on function
  ph.rep_sales_summary(date, date), ph.rep_sales_monthly(integer), ph.rep_item_profit(date, date, integer), ph.rep_heatmap(date, date),
  ph.rep_by_staff(date, date), ph.rep_by_shift(date, date), ph.rep_stock_value(), ph.rep_dead_stock(integer), ph.rep_runout(integer),
  ph.rep_expiry_months(integer), ph.rep_discount_compare(integer), ph.rep_supplier_month(date, date), ph.rep_price_changes(date, date),
  ph.rep_dues_aging(), ph.rep_top_customers(date, date, integer), ph.rep_lapsed_customers(integer), ph.rep_order_fill(date, date),
  ph.rep_late_orders(integer), ph.rep_cash_flow(date, date), ph.rep_expenses(date, date), ph.rep_pnl_monthly(integer),
  ph.rep_store_orders(date, date), ph.rep_store_no_image(integer), ph.morning_brief(), ph.morning_brief_text()
  from public, anon;
grant execute on function
  ph.rep_sales_summary(date, date), ph.rep_sales_monthly(integer), ph.rep_item_profit(date, date, integer), ph.rep_heatmap(date, date),
  ph.rep_by_staff(date, date), ph.rep_by_shift(date, date), ph.rep_stock_value(), ph.rep_dead_stock(integer), ph.rep_runout(integer),
  ph.rep_expiry_months(integer), ph.rep_discount_compare(integer), ph.rep_supplier_month(date, date), ph.rep_price_changes(date, date),
  ph.rep_dues_aging(), ph.rep_top_customers(date, date, integer), ph.rep_lapsed_customers(integer), ph.rep_order_fill(date, date),
  ph.rep_late_orders(integer), ph.rep_cash_flow(date, date), ph.rep_expenses(date, date), ph.rep_pnl_monthly(integer),
  ph.rep_store_orders(date, date), ph.rep_store_no_image(integer), ph.morning_brief(), ph.morning_brief_text()
  to authenticated;
