-- اختبارات المسودة: داتا تجريبية صغيرة + نتايج متوقعة. أي فرق بيوقف التشغيل برسالة.
\set ON_ERROR_STOP on

-- ---------- داتا تجريبية (كـ superuser، يعني من غير RLS) ----------
insert into auth.users values ('00000000-0000-0000-0000-000000000001'), ('00000000-0000-0000-0000-000000000002'),
                              ('00000000-0000-0000-0000-000000000003');
insert into ph.staff (user_id, name, role) values
  ('00000000-0000-0000-0000-000000000001', 'المالك', 'owner'),
  ('00000000-0000-0000-0000-000000000002', 'مساعد', 'assistant');
insert into ph.items (id, name_en, pack_parts, public_price) values (1, 'TEST TAB 30 TAB', 3, 90), (2, 'TEST SYRUP', 1, 40);
insert into ph.suppliers (code, name, kind) values ('AMG', 'مخزن تجربة', 'warehouse');
insert into ph.locations (name, kind) values ('الرئيسي', 'main');
insert into ph.batches (item_id, expiry) values (1, current_date + 400);
insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, kind) values
  (1, 1, 1, 30, 'purchase'),
  (1, 1, 1, -4, 'sale');
insert into ph.purchase_invoices (supplier_id, doc_no, invoice_date, total) values (1, 'A-1', current_date, 750);
insert into ph.purchase_invoice_lines (invoice_id, item_id, qty_packs, bonus_packs, public_price, cost_total)
  values (1, 1, 10, 1, 100, 750);
insert into ph.supplier_payments (supplier_id, amount, method) values (1, 500, 'cash');
insert into ph.customers (name, phone, credit_limit, balance_pf) values
  ('عميل فوق الحد', '201000000001', 500, 650),
  ('عميل تحت الحد', '201000000002', 1000, 200),
  ('عميل من غير حد', '201000000003', null, 90),
  ('عميل مش عليه حاجة', '201000000004', 300, 0);

do $$
declare r record;
begin
  -- الرصيد: 30 − 4 = 26 وحدة = 8 علب + 2 شريط (العلبة 3 شرايط)
  select * into r from ph.v_stock where item_id = 1;
  if r.qty_units <> 26 or r.packs <> 8 or r.units <> 2 then
    raise exception 'v_stock غلط: % وحدة = % علبة + %', r.qty_units, r.packs, r.units;
  end if;
  -- الخصم الفعلي: 1 − 750 ÷ (100 × 11) = 0.3182
  select real_discount into r from ph.purchase_invoice_lines where id = 1;
  if r.real_discount <> 0.3182 then raise exception 'real_discount غلط: %', r.real_discount; end if;
  -- حساب المورد: 750 − 500 = 250
  select balance into r from ph.v_supplier_balance where supplier_id = 1;
  if r.balance <> 250 then raise exception 'v_supplier_balance غلط: %', r.balance; end if;
  -- مخزن انتظار لازم يبقى له مورد
  begin
    insert into ph.locations (name, kind) values ('انتظار من غير مورد', 'waiting');
    raise exception 'مخزن انتظار من غير مورد اتقبل';
  exception when check_violation then null;
  end;
  -- كل جداول ph عليها RLS
  if exists (select 1 from pg_tables where schemaname = 'ph' and not rowsecurity) then
    raise exception 'فيه جدول من غير RLS';
  end if;
  -- سجل التعديلات اتكتب للفاتورة والحركة
  if (select count(*) from ph.audit_log where table_name in ('purchase_invoices', 'stock_moves')) <> 3 then
    raise exception 'audit_log ناقص';
  end if;
  -- العملاء اللي عليهم فلوس: 3، وواحد بس عدّى حده
  if (select count(*) from ph.v_customer_dues) <> 3 then raise exception 'v_customer_dues: العدد غلط'; end if;
  if (select string_agg(name, ',') from ph.v_customer_dues where over_limit) <> 'عميل فوق الحد' then
    raise exception 'v_customer_dues: فوق الحد غلط';
  end if;
  -- الرقم لازم يبقى أرقام بس (زي normPhone)
  begin
    insert into ph.customers (name, phone) values ('رقم غلط', '+20 100');
    raise exception 'رقم بمسافات اتقبل';
  exception when check_violation then null;
  end;
  raise notice 'OK: الرصيد، الخصم الفعلي، حساب المورد، مخزن الانتظار، RLS، سجل التعديلات، العملاء والحد';
end $$;

-- ---------- الصلاحيات (RLS) بحسابات مختلفة ----------
set role authenticated;

do $$ begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000001', false); end $$;
do $$ begin
  if (select count(*) from ph.purchase_invoices) <> 1 then raise exception 'المالك مش شايف فواتير الشرا'; end if;
  if (select count(*) from ph.items) <> 2 then raise exception 'المالك مش شايف الأصناف'; end if;
end $$;

do $$ begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000002', false); end $$;
do $$ begin
  if (select count(*) from ph.items) <> 2 then raise exception 'المساعد مش شايف الأصناف'; end if;
  if (select count(*) from ph.purchase_invoices) <> 0 then raise exception 'المساعد شايف فواتير الشرا'; end if;
  if (select count(*) from ph.supplier_payments) <> 0 then raise exception 'المساعد شايف التحصيل'; end if;
  insert into ph.sales (subtotal) values (90);   -- المساعد يقدر يبيع
  begin
    insert into ph.purchase_invoices (supplier_id, doc_no, invoice_date) values (1, 'X', current_date);
    raise exception 'المساعد قدر يضيف فاتورة شرا';
  exception when insufficient_privilege then null;
  end;
end $$;

do $$ begin perform set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-000000000003', false); end $$;
do $$ begin
  if (select count(*) from ph.items) <> 0 then raise exception 'حساب مش موظف شايف الأصناف'; end if;
end $$;

reset role;
do $$ begin raise notice 'OK: صلاحيات المالك والمساعد والغريب'; end $$;

-- ---------- المرحلة ١: views على جداول البوت ----------
insert into public.ar_store_items (id, name, status, price, cat) values (1, 'TEST TAB 30 TAB', 'available', 90, 'pain_fever');
insert into public.ar_store_arabic values (1, 'تيست اقراص');
insert into public.ar_store_generic values (1, 'tab', 'paracetamol', 'paracetamol|tab');
insert into public.ar_stock (item_id, name, packs, units, parts, exp_near) values
  (1, 'TEST TAB 30 TAB', 2, 1, 3, current_date + 60),
  (2, 'TEST SYRUP', 5, 0, 1, current_date + 150),
  (3, 'TEST CREAM', 1, 0, 1, current_date + 500),
  (4, 'EMPTY ITEM', 0, 0, 1, current_date + 30);
insert into public.ar_shortages (name_key, product_name, suggested_qty, order_qty) values
  ('TEST TAB 30 TAB', 'TEST TAB 30 TAB', 3.6, null),
  ('TEST SYRUP', 'TEST SYRUP', 2, 5);
insert into public.ar_shortages (name_key, product_name, is_active) values ('OLD ITEM', 'OLD ITEM', false);
insert into public.ar_names values ('TEST TAB 30 TAB', 'TEST TAB 30 TAB', 'تيست اقراص');
insert into public.ar_orders (name_key, product_name, supplier) values ('TEST SYRUP', 'TEST SYRUP', 'مخزن تجربة');
insert into public.ar_orders (name_key, product_name, supplier, ordered_at) values ('TEST TAB 30 TAB', 'TEST TAB 30 TAB', 'امبارح', now() - interval '2 days');
insert into public.ar_supplier_lists values (1, 'AMG', current_date - 20), (2, 'AMG', current_date - 1), (3, 'REDA', current_date - 2);
insert into public.ar_supplier_items (id, list_id, supplier, item_id, discount_pct, match_status, review) values
  (1, 1, 'AMG', 1, 40, 'strong', 'accepted'),     -- قايمة قديمة: مش بتتحسب
  (2, 2, 'AMG', 1, 28, 'strong', 'accepted'),
  (3, 3, 'REDA', 1, 25, 'good', 'pending'),
  (4, 3, 'REDA', 2, 30, 'weak', 'pending'),       -- مطابقة ضعيفة من غير موافقة: مش بتتحسب
  (5, 3, 'REDA', 3, 50, 'strong', 'rejected');    -- المالك رفضها
insert into public.ar_inbox (received_at) values (now()), (now() - interval '3 days');
insert into public.ar_inbox (received_at, hidden_at) values (now(), now());
insert into public.ar_store_orders values (1, 'new'), (2, 'done');
insert into public.ar_documents (status) values ('new'), ('entered');
insert into public.ar_sync_log values (1, now() - interval '1 hour', 'ok', false), (2, now(), 'ok', true);

do $$
declare r record;
begin
  select * into r from ph.v_items_now where id = 1;
  if r.name_ar <> 'تيست اقراص' or r.gkey <> 'paracetamol|tab' then raise exception 'v_items_now غلط'; end if;

  if (select count(*) from ph.v_stock_now) <> 3 then raise exception 'v_stock_now لازم يشيل الصنف اللي رصيده صفر'; end if;

  if (select level from ph.v_expiring where item_id = 1) <> 'red' then raise exception 'صلاحية 60 يوم لازم تبقى red'; end if;
  if (select level from ph.v_expiring where item_id = 2) <> 'yellow' then raise exception 'صلاحية 150 يوم لازم تبقى yellow'; end if;
  if exists (select 1 from ph.v_expiring where item_id in (3, 4)) then raise exception 'v_expiring فيه صنف مش لازم يظهر'; end if;

  if (select count(*) from ph.v_shortages_now) <> 2 then raise exception 'v_shortages_now لازم يبقى النشط بس'; end if;
  select * into r from ph.v_shortages_now where name_key = 'TEST SYRUP';
  if r.qty <> 5 or not r.qty_by_owner or r.ordered_today_from <> 'مخزن تجربة' then raise exception 'v_shortages_now (الكمية/اتطلب) غلط'; end if;
  select * into r from ph.v_shortages_now where name_key = 'TEST TAB 30 TAB';
  if r.qty <> 3.6 or r.ordered_today_from is not null then raise exception 'v_shortages_now: طلب امبارح اتحسب النهارده'; end if;

  select * into r from ph.v_best_offer where item_id = 1;
  if r.best_supplier <> 'AMG' or r.best_pct <> 28 or r.second_supplier <> 'REDA' or r.gap_pct <> 3 or r.suppliers_count <> 2 then
    raise exception 'v_best_offer غلط: % % / % % فرق %', r.best_supplier, r.best_pct, r.second_supplier, r.second_pct, r.gap_pct;
  end if;
  if exists (select 1 from ph.v_best_offer where item_id in (2, 3)) then raise exception 'v_best_offer حسب مطابقة ضعيفة أو مرفوضة'; end if;

  select * into r from ph.v_today;
  if r.shortages_active <> 2 or r.ordered_today <> 1 or r.inbox_today <> 1 or r.expiring_90d <> 1
     or r.store_orders_new <> 1 or r.documents_new <> 1 or r.last_shortage_sync is null then
    raise exception 'v_today غلط: %', row_to_json(r);
  end if;
  raise notice 'OK: views المرحلة ١ (الأصناف، الرصيد، الصلاحية، النواقص، أحسن خصم، اللوحة)';
end $$;
