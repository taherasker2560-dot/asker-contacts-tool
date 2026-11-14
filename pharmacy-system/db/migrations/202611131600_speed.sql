-- 202611131600_speed
-- المطلوب (المالك 2026-11-13 على اللاب: «ليه الشاشات بتاخد وقت وهي بتحمّل؟ ده مش طبيعي في برامج الصيدلية»).
-- السبب (اتقاس): صلاحيات الصفوف (RLS) بتنده ph.has_role() و auth.uid() مع كل صف. الدالتين security definer
--   فمش بيتحسبوا مرة واحدة: شاشة بتقرا 30 ألف فاتورة = 30 ألف فحص صلاحية. وv_sales_daily كان بيحسب التكلفة
--   باستعلام لكل فاتورة.
-- الحل: (1) كل سياسة بقت (SELECT ph.has_role(...)) و (SELECT auth.uid()): نفس الشرط بالظبط، بس بيتحسب مرة واحدة
--   في الاستعلام (initplan). (2) v_sales_daily بنفس الأعمدة والأرقام بس بتجميع واحد بدل استعلام لكل فاتورة،
--   وبيقرا الأيام المطلوبة بس لما يتفلتر بالتاريخ. (3) فهارس للبحث بالعميل والتاريخ.
-- الرجوع: السياسات: نفس الـ DO اللي تحت بالعكس (شيل (SELECT …) من حوالين الدالتين). الـ view: التعريف القديم في db/09-reports.sql.
--   drop index ph.sales_posted_day_idx, ph.sale_returns_day_idx, ph.sale_return_lines_return_idx, ph.sales_customer_day_idx,
--     ph.purchase_invoice_lines_batch_idx;

-- (1) السياسات
do $$
declare
  p  record;
  q  text;
  c  text;
  rx text := 'ph\.has_role\((ARRAY\[[^\]]*\])\)';
  sql text;
begin
  for p in select tablename, policyname, qual, with_check from pg_policies where schemaname = 'ph' loop
    q := p.qual; c := p.with_check;
    if q is not null and q !~ '\(SELECT ph\.has_role' then
      q := regexp_replace(regexp_replace(q, rx, '(SELECT ph.has_role(\1))', 'g'), 'auth\.uid\(\)', '(SELECT auth.uid())', 'g');
    end if;
    if c is not null and c !~ '\(SELECT ph\.has_role' then
      c := regexp_replace(regexp_replace(c, rx, '(SELECT ph.has_role(\1))', 'g'), 'auth\.uid\(\)', '(SELECT auth.uid())', 'g');
    end if;
    if q is distinct from p.qual or c is distinct from p.with_check then
      sql := format('alter policy %I on ph.%I', p.policyname, p.tablename);
      if q is not null then sql := sql || ' using (' || q || ')'; end if;
      if c is not null then sql := sql || ' with check (' || c || ')'; end if;
      execute sql;
    end if;
  end loop;
end $$;

-- (2) البيع اليومي: نفس الأعمدة، تجميع واحد للبيع وواحد للتكلفة وواحد للمرتجع
create or replace view ph.v_sales_daily with (security_invoker = true) as
with s as (
  select x.business_day, count(*) as invoices, sum(x.total) as total, sum(x.paid) as paid, sum(x.on_credit) as on_credit
  from ph.sales x where x.status = 'posted' group by x.business_day
), c as (
  select x.business_day, sum(round(l.qty_units * coalesce(l.unit_cost, 0), 2)) as cost
  from ph.sales x join ph.sale_lines l on l.sale_id = x.id where x.status = 'posted' group by x.business_day
), r as (
  select x.business_day, sum(x.total) as returns from ph.sale_returns x group by x.business_day
), rc as (
  select x.business_day, sum(round(rl.qty_units * coalesce(sl.unit_cost, b.unit_cost, 0), 2)) as returns_cost
  from ph.sale_returns x join ph.sale_return_lines rl on rl.return_id = x.id
  join ph.batches b on b.id = rl.batch_id left join ph.sale_lines sl on sl.id = rl.sale_line_id
  group by x.business_day
)
select s.business_day, s.invoices, s.total, s.paid, s.on_credit,
       coalesce(r.returns, 0)                                                        as returns,
       s.total - coalesce(r.returns, 0)                                              as net_sales,
       coalesce(c.cost, 0) - coalesce(rc.returns_cost, 0)                            as net_cost,
       (s.total - coalesce(r.returns, 0)) - (coalesce(c.cost, 0) - coalesce(rc.returns_cost, 0)) as gross_profit
from s left join c on c.business_day = s.business_day
left join r on r.business_day = s.business_day
left join rc on rc.business_day = s.business_day;

-- (3) فهارس
create index if not exists sales_posted_day_idx on ph.sales (business_day) include (total, paid, on_credit, discount) where status = 'posted';
create index if not exists sale_returns_day_idx on ph.sale_returns (business_day);
create index if not exists sale_return_lines_return_idx on ph.sale_return_lines (return_id);
create index if not exists sales_customer_day_idx on ph.sales (customer_id, business_day) where customer_id is not null and status = 'posted';
-- «قرّب يخلص» بيدوّر على مورد كل تشغيلة (v_expiring): من غير الفهرس ده بيقرا كل سطور الشرا لكل تشغيلة
create index if not exists purchase_invoice_lines_batch_idx on ph.purchase_invoice_lines (batch_id);
analyze ph.purchase_invoice_lines; analyze ph.sales; analyze ph.sale_lines; analyze ph.sale_returns; analyze ph.stock_balances; analyze ph.stock_moves;
