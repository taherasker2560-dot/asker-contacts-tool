-- =====================================================================================================
-- (12) الثبات في التجربة: فحص ذاتي للقاعدة + سجل المشاكل
-- =====================================================================================================
-- ph.health_check(): كل قاعدة لازم تفضل صح مهما حصل. أي سطر ok = false معناه مشكلة حقيقية لازم تتشاف.
--   بيتنده من التقرير اليومي على اللاب، وبعد النقل، وبعد اختبار الضغط، ومن الموبايل (المالك والمدير).
-- ph.trial_notes: أي حد بيجرب يسجّل المشكلة أو الملاحظة في وقتها، والمالك يقفلها لما تتصلح.
-- =====================================================================================================

create function ph.health_check() returns table (check_name text, ok boolean, detail text)
language plpgsql stable security definer set search_path = '' as $$
declare
  n     bigint;
  v_txt text;
begin
  -- من البرنامج: المالك والمدير بس. من اتصال مباشر بالقاعدة (سكريبتات اللاب): مسموح
  if auth.uid() is not null then perform ph.require_role(array['owner', 'manager']); end if;

  -- 1) رصيد كل تشغيلة = مجموع دفتر الحركة
  select count(*) into n from (
    select m.item_id from (select item_id, location_id, batch_id, sum(qty_units) q from ph.stock_moves group by 1, 2, 3) m
    full join ph.stock_balances b using (item_id, location_id, batch_id)
    where coalesce(m.q, 0) <> coalesce(b.qty_units, 0)) d;
  return query select 'الرصيد = دفتر الحركة', n = 0, n || ' تشغيلة مختلفة';

  -- 2) مفيش رصيد بالسالب (إلا لو الإعداد سامح)
  select count(*) into n from ph.stock_balances where qty_units < 0;
  return query select 'مفيش رصيد بالسالب',
    n = 0 or coalesce((select allow_negative_stock from ph.settings where id = 1), false), n || ' تشغيلة بالسالب';

  -- 3) حساب كل عميل ومورد = مجموع دفتره
  select count(*) into n from (
    select l.party_id from (select party_type, party_id, sum(amount) a from ph.party_ledger group by 1, 2) l
    full join ph.party_balances b using (party_type, party_id)
    where coalesce(l.a, 0) <> coalesce(b.balance, 0)) d;
  return query select 'الحسابات = دفتر الحسابات', n = 0, n || ' حساب مختلف';

  -- 4) كل فاتورة بيع: الإجمالي = السطور − الخصم، والمدفوع + الآجل = الإجمالي، والدفع = المدفوع
  select count(*) into n from ph.sales s
  where s.status = 'posted' and (
        s.subtotal <> coalesce((select sum(l.line_total) from ph.sale_lines l where l.sale_id = s.id), 0)
     or s.total <> s.subtotal - s.discount
     or s.paid + s.on_credit <> s.total
     or s.paid <> coalesce((select sum(p.amount) from ph.sale_payments p where p.sale_id = s.id), 0));
  return query select 'حساب فواتير البيع مظبوط', n = 0, n || ' فاتورة';

  -- 5) كل سطر بيع ليه حركة مخزون بنفس الكمية
  select count(*) into n from (
    select s.id from ph.sales s
    where s.status = 'posted'
      and coalesce((select sum(l.qty_units) from ph.sale_lines l where l.sale_id = s.id), 0)
       <> -coalesce((select sum(m.qty_units) from ph.stock_moves m where m.doc_type = 'sale' and m.doc_id = s.id), 0)) d;
  return query select 'البيع طلّع من المخزون نفس الكمية', n = 0, n || ' فاتورة';

  -- 6) كل فاتورة شرا: الإجمالي = تكلفة السطور
  select count(*) into n from ph.purchase_invoices i
  where i.status = 'posted'
    and i.total <> coalesce((select sum(l.cost_total) from ph.purchase_invoice_lines l where l.invoice_id = i.id), 0);
  return query select 'حساب فواتير الشرا مظبوط', n = 0, n || ' فاتورة';

  -- 7) أرقام المستندات مسلسلة من غير فراغات ولا تكرار (لكل نوع وسنة)
  select string_agg(k || ' ناقص ' || gap, '، ') into v_txt from (
    select split_part(no, '-', 1) || '-' || split_part(no, '-', 2) as k,
           max(split_part(no, '-', 3)::integer) - count(distinct no) as gap
    from (select no from ph.sales union all select no from ph.sale_returns union all select no from ph.purchase_invoices
          union all select no from ph.purchase_returns union all select no from ph.payments union all select no from ph.expenses
          union all select no from ph.stock_adjustments union all select no from ph.transfers union all select no from ph.stock_counts) x
    where no ~ '^[A-Z]+-[0-9]{4}-[0-9]+$'
    group by 1) g
  where gap <> 0;
  return query select 'الأرقام مسلسلة', v_txt is null, coalesce(v_txt, '');

  -- 8) مفيش بيع من تشغيلة منتهية (بعد البرنامج ما اشتغل، مش تاريخ فارمافلاي)
  select count(*) into n from ph.sale_lines l join ph.sales s on s.id = l.sale_id join ph.batches b on b.id = l.batch_id
  where s.source = 'ph' and b.expiry is not null and b.expiry < s.business_day;
  return query select 'مفيش بيع منتهي', n = 0, n || ' سطر';

  -- 9) وضع النقل مقفول
  return query select 'وضع النقل مقفول', not coalesce((select import_mode from ph.settings where id = 1), false), '';

  -- 10) مفيش وردية مفتوحة من أكتر من يوم (تنبيه)
  select count(*) into n from ph.shifts where status = 'open' and opened_at < now() - interval '24 hours';
  return query select 'الورديات اتقفلت', n = 0, n || ' وردية مفتوحة من أكتر من يوم';
end $$;

-- -----------------------------------------------------------------------------------------------------
-- سجل المشاكل في التجربة
-- -----------------------------------------------------------------------------------------------------
create table ph.trial_notes (
  id         bigint generated always as identity primary key,
  at         timestamptz not null default now(),
  by_user    uuid default auth.uid(),
  area       text not null check (area in ('sales', 'purchases', 'stock', 'accounts', 'reports', 'import', 'install', 'bot', 'other')),
  severity   text not null check (severity in ('blocker', 'bug', 'annoyance', 'idea')),   -- واقف / غلط / مزعج / فكرة
  note       text not null check (char_length(note) between 3 and 2000),
  status     text not null default 'open' check (status in ('open', 'fixed', 'wontfix')),
  fixed_note text check (char_length(fixed_note) <= 500),           -- اتصلح إزاي / في أنهي تعديل
  fixed_at   timestamptz
);
alter table ph.trial_notes enable row level security;
create policy staff_read on ph.trial_notes for select to authenticated
  using (ph.has_role(array['owner', 'manager', 'pharmacist', 'cashier']));
create policy staff_add on ph.trial_notes for insert to authenticated
  with check (ph.has_role(array['owner', 'manager', 'pharmacist', 'cashier']) and by_user = auth.uid() and status = 'open');
create policy owner_close on ph.trial_notes for update to authenticated
  using (ph.has_role(array['owner', 'manager'])) with check (ph.has_role(array['owner', 'manager']));
grant select, insert, update on ph.trial_notes to authenticated;

revoke all on function ph.health_check() from public, anon;
grant execute on function ph.health_check() to authenticated;
