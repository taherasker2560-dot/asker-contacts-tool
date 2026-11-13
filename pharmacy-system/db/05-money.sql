-- =====================================================================================================
-- (5 من 10) الفلوس: الخزن (درج/خزنة/بنك/محفظة)، الورديات، دفتر الخزن، دفتر حسابات العملاء والموردين،
--           التحصيل من العملاء، السداد للموردين، المصروفات
-- =====================================================================================================

create table ph.cash_accounts (
  id        smallint generated always as identity primary key,
  branch_id smallint not null references ph.branches (id),
  name      text not null unique check (char_length(name) between 2 and 60),
  kind      text not null check (kind in ('drawer', 'safe', 'bank', 'wallet')),
  active    boolean not null default true
);

-- طريقة الدفع ← الخزنة اللي الفلوس بتدخلها. credit = آجل على العميل (مالوش خزنة)
create table ph.payment_methods (
  code       text primary key check (code in ('cash', 'card', 'wallet', 'instapay', 'credit')),
  name_ar    text not null,
  account_id smallint references ph.cash_accounts (id),
  check ((code = 'credit') = (account_id is null))
);

create table ph.shifts (
  id           bigint generated always as identity primary key,
  account_id   smallint not null references ph.cash_accounts (id),   -- الدرج
  opened_by    uuid not null default auth.uid(),
  opened_at    timestamptz not null default now(),
  opening_cash numeric(12, 2) not null default 0 check (opening_cash >= 0),
  closed_at    timestamptz,
  counted_cash numeric(12, 2) check (counted_cash >= 0),
  status       text not null default 'open' check (status in ('open', 'closed'))
);
create unique index shifts_one_open_per_drawer on ph.shifts (account_id) where status = 'open';

-- دفتر الخزن: موجب = دخل، سالب = خرج
create table ph.money_moves (
  id           bigint generated always as identity primary key,
  at           timestamptz not null default now(),
  business_day date not null default ph.business_day(),
  account_id   smallint not null references ph.cash_accounts (id),
  amount       numeric(14, 2) not null check (amount <> 0),
  doc_type     text not null check (doc_type in ('sale', 'sale_return', 'payment', 'expense', 'purchase', 'shift')),
  doc_id       bigint not null,
  shift_id     bigint references ph.shifts (id),
  by_user      uuid default auth.uid()
);
create index on ph.money_moves (account_id, at);
create index on ph.money_moves (business_day);
create trigger money_moves_locked before update or delete on ph.money_moves for each row execute function ph.forbid_change();

-- دفتر الحسابات: موجب = الرصيد بيزيد (العميل عليه أكتر / إحنا علينا للمورد أكتر)
create table ph.party_ledger (
  id           bigint generated always as identity primary key,
  at           timestamptz not null default now(),
  business_day date not null default ph.business_day(),
  party_type   text not null check (party_type in ('customer', 'supplier')),
  party_id     bigint not null,
  amount       numeric(14, 2) not null check (amount <> 0),
  doc_type     text not null check (doc_type in ('opening', 'sale', 'sale_return', 'payment', 'purchase',
                                                 'purchase_return', 'adjust')),
  doc_id       bigint not null,
  note         text check (char_length(note) <= 300),
  by_user      uuid default auth.uid()
);
create index on ph.party_ledger (party_type, party_id, at);
create trigger party_ledger_locked before update or delete on ph.party_ledger for each row execute function ph.forbid_change();

create table ph.party_balances (
  party_type text not null check (party_type in ('customer', 'supplier')),
  party_id   bigint not null,
  balance    numeric(14, 2) not null default 0,
  updated_at timestamptz not null default now(),
  primary key (party_type, party_id)
);

create function ph.apply_party_move() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.party_type = 'customer' and not exists (select 1 from ph.customers where id = new.party_id) then
    raise exception 'عميل مش موجود: %', new.party_id;
  end if;
  if new.party_type = 'supplier' and not exists (select 1 from ph.suppliers where id = new.party_id) then
    raise exception 'مورد مش موجود: %', new.party_id;
  end if;
  insert into ph.party_balances as b (party_type, party_id, balance, updated_at)
  values (new.party_type, new.party_id, new.amount, now())
  on conflict (party_type, party_id) do update set balance = b.balance + excluded.balance, updated_at = now();
  return new;
end $$;
create trigger party_ledger_apply after insert on ph.party_ledger for each row execute function ph.apply_party_move();

-- رصيد أول المدة للعملاء والموردين (النقل من فارمافلاي): [{party_type, party_id, amount}]
create function ph.post_opening_balances(p_rows jsonb) returns integer
language plpgsql security definer set search_path = '' as $$
declare r jsonb; n integer := 0;
begin
  perform ph.require_role(array['owner']);
  for r in select * from jsonb_array_elements(p_rows) loop
    continue when coalesce((r ->> 'amount')::numeric, 0) = 0;
    insert into ph.party_ledger (party_type, party_id, amount, doc_type, doc_id, note)
    values (r ->> 'party_type', (r ->> 'party_id')::bigint, (r ->> 'amount')::numeric, 'opening', 0, 'رصيد أول المدة');
    n := n + 1;
  end loop;
  return n;
end $$;

-- -----------------------------------------------------------------------------------------------------
-- التحصيل من العملاء والسداد للموردين (مستند واحد للنوعين)
-- -----------------------------------------------------------------------------------------------------
create table ph.payments (
  id            bigint generated always as identity primary key,
  no            text unique,
  kind          text not null check (kind in ('from_customer', 'to_supplier')),
  party_id      bigint not null,
  amount        numeric(12, 2) not null check (amount > 0),
  account_id    smallint not null references ph.cash_accounts (id),
  receipt_no    text check (char_length(receipt_no) <= 60),     -- رقم إيصال التحصيل بتاع المورد
  attachment_id bigint references ph.attachments (id),
  note          text check (char_length(note) <= 300),
  at            timestamptz not null default now(),
  client_uuid   uuid unique,
  by_user       uuid default auth.uid()
);
create trigger payments_locked before update or delete on ph.payments for each row execute function ph.forbid_change();

create function ph.post_payment(p jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_kind   text := p ->> 'kind';
  v_amount numeric := (p ->> 'amount')::numeric;
  v_acc    ph.cash_accounts;
  v_pay    ph.payments;
  v_shift  ph.shifts;
begin
  if v_kind = 'from_customer' then
    perform ph.require_role(array['owner', 'manager', 'pharmacist', 'cashier']);
  else
    perform ph.require_role(array['owner', 'manager']);
  end if;
  if (p ->> 'client_uuid') is not null then
    select * into v_pay from ph.payments where client_uuid = (p ->> 'client_uuid')::uuid;
    if found then return jsonb_build_object('payment_id', v_pay.id, 'no', v_pay.no, 'repeat', true); end if;
  end if;
  -- لو الدفع كاش من الدرج في وردية مفتوحة: بيتحسب على الوردية
  if (p ->> 'shift_id') is not null then
    select * into strict v_shift from ph.shifts where id = (p ->> 'shift_id')::bigint and status = 'open';
  end if;
  select * into strict v_acc from ph.cash_accounts
   where id = coalesce(v_shift.account_id, (p ->> 'account_id')::smallint) and active;
  insert into ph.payments (no, kind, party_id, amount, account_id, receipt_no, attachment_id, note, client_uuid)
  values (ph.next_doc_no(case when v_kind = 'from_customer' then 'RC' else 'PY' end, v_acc.branch_id),
          v_kind, (p ->> 'party_id')::bigint, v_amount, v_acc.id, p ->> 'receipt_no',
          (p ->> 'attachment_id')::bigint, p ->> 'note', (p ->> 'client_uuid')::uuid)
  returning * into v_pay;
  -- تحصيل: الخزنة بتزيد ورصيد العميل بيقل. سداد: الخزنة بتقل ورصيد المورد بيقل
  insert into ph.money_moves (account_id, amount, doc_type, doc_id, shift_id)
  values (v_acc.id, case when v_kind = 'from_customer' then v_amount else -v_amount end, 'payment', v_pay.id, v_shift.id);
  insert into ph.party_ledger (party_type, party_id, amount, doc_type, doc_id)
  values (case when v_kind = 'from_customer' then 'customer' else 'supplier' end, v_pay.party_id, -v_amount, 'payment', v_pay.id);
  return jsonb_build_object('payment_id', v_pay.id, 'no', v_pay.no, 'repeat', false);
end $$;

-- -----------------------------------------------------------------------------------------------------
-- المصروفات
-- -----------------------------------------------------------------------------------------------------
create table ph.expense_categories (
  id   smallint generated always as identity primary key,
  name text not null unique check (char_length(name) between 2 and 60)   -- كهربا، ميه، إيجار، مرتبات، نت، توصيل…
);

create table ph.expenses (
  id            bigint generated always as identity primary key,
  no            text unique,
  category_id   smallint not null references ph.expense_categories (id),
  amount        numeric(12, 2) not null check (amount > 0),
  account_id    smallint not null references ph.cash_accounts (id),
  business_day  date not null default ph.business_day(),
  attachment_id bigint references ph.attachments (id),
  note          text check (char_length(note) <= 300),
  at            timestamptz not null default now(),
  by_user       uuid default auth.uid()
);
create trigger expenses_locked before update or delete on ph.expenses for each row execute function ph.forbid_change();

create function ph.post_expense(p jsonb) returns text
language plpgsql security definer set search_path = '' as $$
declare v_acc ph.cash_accounts; v_exp ph.expenses;
begin
  perform ph.require_role(array['owner', 'manager']);
  select * into strict v_acc from ph.cash_accounts where id = (p ->> 'account_id')::smallint and active;
  insert into ph.expenses (no, category_id, amount, account_id, attachment_id, note)
  values (ph.next_doc_no('EX', v_acc.branch_id), (p ->> 'category_id')::smallint, (p ->> 'amount')::numeric,
          v_acc.id, (p ->> 'attachment_id')::bigint, p ->> 'note')
  returning * into v_exp;
  insert into ph.money_moves (account_id, amount, doc_type, doc_id) values (v_acc.id, -v_exp.amount, 'expense', v_exp.id);
  return v_exp.no;
end $$;
