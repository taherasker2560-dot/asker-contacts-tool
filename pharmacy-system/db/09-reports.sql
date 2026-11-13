-- =====================================================================================================
-- (9 من 10) التقارير: الرصيد، الصلاحية، كارت الصنف، البيع اليومي والربح، حسابات العملاء والموردين،
--           الخزن، الراكد، سجل أدوية الجدول
--   كلها security_invoker: كل واحد بيشوف اللي صلاحيته تسمح بيه بس.
-- =====================================================================================================

-- الرصيد: علب + وحدات لكل تشغيلة ومكان
create view ph.v_stock with (security_invoker = true) as
select sb.item_id, i.name_en, i.name_ar, sb.location_id, l.name as location, l.counts_as_stock,
       sb.batch_id, b.expiry, b.public_price,
       sb.qty_units,
       floor(sb.qty_units / i.pack_parts)                         as packs,
       sb.qty_units - floor(sb.qty_units / i.pack_parts) * i.pack_parts as units,
       round(sb.qty_units * coalesce(b.unit_cost, 0), 2)          as cost_value
from ph.stock_balances sb
join ph.items i on i.id = sb.item_id
join ph.batches b on b.id = sb.batch_id
join ph.locations l on l.id = sb.location_id
where sb.qty_units <> 0;

-- الصلاحية: التشغيلات اللي عليها رصيد وقربت تخلص (red = أقل من شهر، yellow = لحد near_expiry_days)
create view ph.v_expiring with (security_invoker = true) as
select v.item_id, v.name_en, v.name_ar, v.location, v.batch_id, v.expiry, v.packs, v.units,
       (v.expiry - current_date) as days_left,
       case when v.expiry < current_date then 'expired'
            when v.expiry < current_date + 30 then 'red'
            else 'yellow' end as level,
       (select s.name from ph.purchase_invoice_lines pl
          join ph.purchase_invoices pi on pi.id = pl.invoice_id join ph.suppliers s on s.id = pi.supplier_id
         where pl.batch_id = v.batch_id) as supplier   -- لمين نرجّعه
from ph.v_stock v
where v.qty_units > 0 and v.expiry is not null
  and v.expiry < current_date + coalesce((select near_expiry_days from ph.settings where id = 1), 90);

-- كارت الصنف: كل حركة والرصيد بعدها
create view ph.v_item_card with (security_invoker = true) as
select m.item_id, m.at, m.business_day, m.doc_type, m.doc_id, m.location_id, m.batch_id, m.qty_units,
       sum(m.qty_units) over (partition by m.item_id order by m.at, m.id) as balance_after
from ph.stock_moves m;

-- البيع اليومي: عدد الفواتير، الإجمالي، الكاش، الآجل، التكلفة، والربح التقريبي (بعد المرتجع)
create view ph.v_sales_daily with (security_invoker = true) as
with s as (
  select s.business_day, count(*) as invoices, sum(s.total) as total, sum(s.paid) as paid, sum(s.on_credit) as on_credit,
         sum((select coalesce(sum(round(sl.qty_units * coalesce(sl.unit_cost, 0), 2)), 0)
              from ph.sale_lines sl where sl.sale_id = s.id)) as cost
  from ph.sales s where s.status = 'posted' group by s.business_day
),
r as (
  select ph.business_day(r.at) as business_day, sum(r.total) as returns,
         sum((select coalesce(sum(round(rl.qty_units * coalesce(sl.unit_cost, 0), 2)), 0)
              from ph.sale_return_lines rl join ph.sale_lines sl on sl.id = rl.sale_line_id where rl.return_id = r.id)) as returns_cost
  from ph.sale_returns r group by 1
)
select s.business_day, s.invoices, s.total, s.paid, s.on_credit,
       coalesce(r.returns, 0)                                         as returns,
       s.total - coalesce(r.returns, 0)                               as net_sales,
       s.cost - coalesce(r.returns_cost, 0)                           as net_cost,
       (s.total - coalesce(r.returns, 0)) - (s.cost - coalesce(r.returns_cost, 0)) as gross_profit
from s left join r on r.business_day = s.business_day;

-- حسابات العملاء: اللي عليهم فلوس وحد كل واحد
create view ph.v_customer_dues with (security_invoker = true) as
select c.id, c.name, c.phone, c.credit_limit, pb.balance,
       (pb.balance > c.credit_limit) as over_limit,
       (select max(pl.at) from ph.party_ledger pl where pl.party_type = 'customer' and pl.party_id = c.id and pl.amount < 0) as last_payment
from ph.customers c
join ph.party_balances pb on pb.party_type = 'customer' and pb.party_id = c.id
where pb.balance > 0;

-- حسابات الموردين
create view ph.v_supplier_balances with (security_invoker = true) as
select s.id, s.name, coalesce(pb.balance, 0) as balance,
       (select max(pi.invoice_date) from ph.purchase_invoices pi where pi.supplier_id = s.id and pi.status = 'posted') as last_invoice,
       (select max(p.at) from ph.payments p where p.kind = 'to_supplier' and p.party_id = s.id) as last_payment
from ph.suppliers s
left join ph.party_balances pb on pb.party_type = 'supplier' and pb.party_id = s.id
where s.active;

-- كشف حساب (عميل أو مورد) بالرصيد بعد كل حركة
create view ph.v_party_statement with (security_invoker = true) as
select pl.party_type, pl.party_id, pl.at, pl.doc_type, pl.doc_id, pl.amount, pl.note,
       sum(pl.amount) over (partition by pl.party_type, pl.party_id order by pl.at, pl.id) as balance_after
from ph.party_ledger pl;

-- رصيد كل خزنة
create view ph.v_cash_balances with (security_invoker = true) as
select a.id, a.name, a.kind, coalesce(sum(m.amount), 0) as balance
from ph.cash_accounts a left join ph.money_moves m on m.account_id = a.id
group by a.id, a.name, a.kind;

-- الراكد: عليه رصيد ومااتباعش من 90 يوم
create view ph.v_slow_movers with (security_invoker = true) as
select i.id as item_id, i.name_en, o.units as onhand_units,
       (select max(s.business_day) from ph.sale_lines sl join ph.sales s on s.id = sl.sale_id
         where sl.item_id = i.id and s.status = 'posted') as last_sold
from ph.items i join ph.v_onhand o on o.item_id = i.id
where o.units > 0
  and not exists (select 1 from ph.sale_lines sl join ph.sales s on s.id = sl.sale_id
                  where sl.item_id = i.id and s.status = 'posted' and s.business_day > ph.business_day() - 90);
