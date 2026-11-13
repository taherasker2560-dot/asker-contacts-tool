-- 202611131400_purchases_cash
-- المطلوب (المالك 2026-11-13 على اللاب: «فين المشتريات والخزن؟»): شاشة فواتير الشرا وشاشة الخزن.
--   فواتير الشرا والترحيل موجودين في القاعدة من الأول (06-purchases)، والناقص: قايمة جاهزة للشاشة.
--   الخزن: حركة كل خزنة بالرصيد بعد كل حركة، و«تحويل بين الخزن» (توريد الدرج للخزنة مثلًا) اللي مكانش موجود.
-- الرجوع:
--   drop view ph.v_cash_moves, ph.v_purchase_invoices; drop function ph.post_cash_transfer(jsonb); drop table ph.cash_transfers;
--   (لو مفيش حركات تحويل) alter table ph.money_moves drop constraint money_moves_doc_type_check,
--     add constraint money_moves_doc_type_check check (doc_type in ('sale', 'sale_return', 'payment', 'expense', 'purchase', 'shift'));

-- -----------------------------------------------------------------------------------------------------
-- التحويل بين الخزن: سطرين في دفتر الفلوس (− من، + لـ) في عملية واحدة، برقم مسلسل CT
-- -----------------------------------------------------------------------------------------------------
create table ph.cash_transfers (
  id           bigint generated always as identity primary key,
  no           text unique,
  from_account smallint not null references ph.cash_accounts (id),
  to_account   smallint not null references ph.cash_accounts (id),
  amount       numeric(14, 2) not null check (amount > 0),
  note         text check (char_length(note) <= 300),
  at           timestamptz not null default now(),
  business_day date not null default ph.business_day(),
  client_uuid  uuid unique,
  by_user      uuid default auth.uid(),
  check (from_account <> to_account)
);
create trigger cash_transfers_locked before update or delete on ph.cash_transfers for each row execute function ph.forbid_change();
alter table ph.cash_transfers enable row level security;
create policy managers_read on ph.cash_transfers for select to authenticated using (ph.has_role(array['owner', 'manager']));
grant select on ph.cash_transfers to authenticated;

alter table ph.money_moves drop constraint money_moves_doc_type_check,
  add constraint money_moves_doc_type_check
  check (doc_type in ('sale', 'sale_return', 'payment', 'expense', 'purchase', 'shift', 'transfer'));

-- {"from_account": 1, "to_account": 2, "amount": 5000, "note": "توريد الدرج", "client_uuid": "…"}
create function ph.post_cash_transfer(p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_from ph.cash_accounts; v_to ph.cash_accounts; t ph.cash_transfers;
  v_amount numeric := (p ->> 'amount')::numeric;
  v_bal numeric; v_sf bigint; v_st bigint; v_open numeric;
begin
  perform ph.require_role(array['owner', 'manager']);
  if (p ->> 'client_uuid') is not null then
    select * into t from ph.cash_transfers where client_uuid = (p ->> 'client_uuid')::uuid;
    if found then return t.no; end if;
  end if;
  select * into strict v_from from ph.cash_accounts where id = (p ->> 'from_account')::smallint and active;
  select * into strict v_to from ph.cash_accounts where id = (p ->> 'to_account')::smallint and active;
  if v_from.id = v_to.id then raise exception 'التحويل لازم بين خزنتين مختلفين'; end if;
  if coalesce(v_amount, 0) <= 0 then raise exception 'المبلغ لازم يكون أكبر من صفر'; end if;
  -- الدرج: الوردية المفتوحة عليه (الفكّة اللي في أولها جزء من اللي فيه، والتحويل بيتحسب في المفروض وقت القفل)
  select sh.id, sh.opening_cash into v_sf, v_open from ph.shifts sh where sh.account_id = v_from.id and sh.status = 'open' order by sh.opened_at desc limit 1;
  select sh.id into v_st from ph.shifts sh where sh.account_id = v_to.id and sh.status = 'open' order by sh.opened_at desc limit 1;
  select coalesce(sum(amount), 0) + coalesce(v_open, 0) into v_bal from ph.money_moves where account_id = v_from.id;
  if v_amount > v_bal then raise exception 'في % بس % ج: مايكفيش لتحويل %', v_from.name, v_bal, v_amount; end if;
  insert into ph.cash_transfers (no, from_account, to_account, amount, note, client_uuid)
  values (ph.next_doc_no('CT', v_from.branch_id), v_from.id, v_to.id, v_amount, nullif(btrim(p ->> 'note'), ''), (p ->> 'client_uuid')::uuid)
  returning * into t;
  insert into ph.money_moves (account_id, amount, doc_type, doc_id, shift_id)
  values (v_from.id, -v_amount, 'transfer', t.id, v_sf), (v_to.id, v_amount, 'transfer', t.id, v_st);
  return t.no;
end $$;
revoke all on function ph.post_cash_transfer(jsonb) from public, anon;
grant execute on function ph.post_cash_transfer(jsonb) to authenticated;

-- -----------------------------------------------------------------------------------------------------
-- حركة الخزن للشاشة: كل حركة برقم المستند وبيانها والرصيد بعدها (المالك والمدير)
-- -----------------------------------------------------------------------------------------------------
create view ph.v_cash_moves as
select m.id, m.account_id, a.name as account, m.at, m.business_day, m.doc_type, m.doc_id, m.amount, m.shift_id,
       sum(m.amount) over (partition by m.account_id order by m.at, m.id) as balance_after,
       case m.doc_type
         when 'sale' then (select s.no from ph.sales s where s.id = m.doc_id)
         when 'sale_return' then (select r.no from ph.sale_returns r where r.id = m.doc_id)
         when 'payment' then (select p.no from ph.payments p where p.id = m.doc_id)
         when 'expense' then (select e.no from ph.expenses e where e.id = m.doc_id)
         when 'purchase' then (select i.no from ph.purchase_invoices i where i.id = m.doc_id)
         when 'transfer' then (select t.no from ph.cash_transfers t where t.id = m.doc_id)
         when 'shift' then 'وردية ' || m.doc_id
       end as doc_no,
       case m.doc_type
         when 'sale' then coalesce((select c.name from ph.sales s join ph.customers c on c.id = s.customer_id where s.id = m.doc_id), 'بيع')
         when 'sale_return' then 'مرتجع بيع'
         when 'payment' then (select case p.kind when 'from_customer' then 'تحصيل من ' else 'دفع لـ ' end
                                     || coalesce((select c.name from ph.customers c where p.kind <> 'to_supplier' and c.id = p.party_id),
                                                 (select su.name from ph.suppliers su where p.kind = 'to_supplier' and su.id = p.party_id), '')
                              from ph.payments p where p.id = m.doc_id)
         when 'expense' then (select coalesce(ec.name, 'مصروف') || coalesce(' · ' || e.note, '') from ph.expenses e
                                left join ph.expense_categories ec on ec.id = e.category_id where e.id = m.doc_id)
         when 'purchase' then (select 'فاتورة شرا · ' || su.name from ph.purchase_invoices i join ph.suppliers su on su.id = i.supplier_id where i.id = m.doc_id)
         when 'transfer' then (select case when m.amount < 0 then 'تحويل لـ ' || ta.name else 'تحويل من ' || fa.name end || coalesce(' · ' || t.note, '')
                               from ph.cash_transfers t join ph.cash_accounts fa on fa.id = t.from_account join ph.cash_accounts ta on ta.id = t.to_account
                               where t.id = m.doc_id)
         when 'shift' then 'فرق الدرج عند قفل الوردية'
       end as description
from ph.money_moves m join ph.cash_accounts a on a.id = m.account_id
where ph.has_role(array['owner', 'manager']);
grant select on ph.v_cash_moves to authenticated;

-- -----------------------------------------------------------------------------------------------------
-- فواتير الشرا للشاشة: المورد، والإجمالي (المسودة من سطورها)، وعدد الأصناف، والخصم الفعلي
-- -----------------------------------------------------------------------------------------------------
create view ph.v_purchase_invoices with (security_invoker = true) as
select i.id, i.no, i.legacy_no, i.source, i.status, i.supplier_id, s.name as supplier, i.supplier_doc_no, i.invoice_date,
       i.location_id, i.order_id, i.paid_amount, i.paid_account_id, i.created_at, i.posted_at,
       coalesce(i.total, x.cost) as total, x.lines, x.packs, x.bonus, round(100 * (1 - x.cost / nullif(x.pub, 0)), 2) as real_discount_pct
from ph.purchase_invoices i
join ph.suppliers s on s.id = i.supplier_id
left join lateral (
  select count(*) as lines, coalesce(sum(l.packs), 0) as packs, coalesce(sum(l.bonus_packs), 0) as bonus,
         coalesce(sum(l.cost_total), 0) as cost, sum(l.public_price * (l.packs + l.bonus_packs)) as pub
  from ph.purchase_invoice_lines l where l.invoice_id = i.id
) x on true;
grant select on ph.v_purchase_invoices to authenticated;
