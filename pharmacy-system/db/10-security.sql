-- =====================================================================================================
-- (10 من 10) الأمان: RLS على كل جدول، ومين يقرا إيه، ومين يكتب فين
--   الكتابة في الدفاتر والمستندات المرحّلة: من دوال post_* بس (بتتأكد من الدور جواها).
--   المسودات والبيانات الأساسية (أصناف، عملاء، موردين…): بالدور.
-- =====================================================================================================

revoke all on all tables in schema ph from public, anon;
revoke all on all functions in schema ph from public, anon;
grant usage on schema ph to authenticated, anon;

-- كل الجداول: RLS مفعّل، والمالك والمدير يشوفوا كل حاجة
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'ph' loop
    execute format('alter table ph.%I enable row level security', t.tablename);
    execute format('create policy managers_read on ph.%I for select to authenticated using (ph.has_role(array[''owner'', ''manager'']))', t.tablename);
  end loop;
end $$;

-- القراية لكل الموظفين اللي بيبيعوا (من غير الفلوس وحسابات الموردين)
do $$
declare t text;
begin
  foreach t in array array[
    'settings', 'branches', 'manufacturers', 'categories', 'generics', 'items', 'item_barcodes', 'price_changes',
    'locations', 'batches', 'stock_balances', 'stock_moves', 'transfers', 'transfer_lines',
    'customers', 'customer_meds', 'party_balances', 'payment_methods',
    'sales', 'sale_lines', 'sale_payments', 'sale_returns', 'sale_return_lines',
    'item_stock_rules', 'shortage_marks', 'supplier_offers', 'suppliers', 'supplier_reps', 'supplier_item_names',
    'purchase_orders', 'purchase_order_lines', 'online_orders', 'outreach_cycles', 'outreach_log', 'attachments'
  ] loop
    execute format('create policy staff_read on ph.%I for select to authenticated using (ph.has_role(array[''pharmacist'', ''cashier'']))', t);
  end loop;
end $$;
-- الكاشير مايشوفش رصيد المورد: party_balances للعملاء بس
alter policy staff_read on ph.party_balances using (ph.has_role(array['pharmacist', 'cashier']) and party_type = 'customer');
-- سجل أدوية الجدول: الصيدلي (مسؤول عنه) والمالك والمدير، مش الكاشير
create policy pharmacist_read on ph.controlled_register for select to authenticated using (ph.has_role(array['pharmacist']));
-- كل واحد يشوف سطره في الموظفين، والتوصيل يشوف طلباته
create policy self_read on ph.staff for select to authenticated using (user_id = auth.uid());
create policy driver_read on ph.online_orders for select to authenticated using (driver = auth.uid());

-- صلاحيات الجداول (الـ RLS فوق بيحدد الصفوف)
grant select on all tables in schema ph to authenticated;

-- بيانات أساسية: المالك والمدير يضيفوا ويعدّلوا، والصيدلي في الأصناف والعملاء والنواقص
grant insert, update on ph.settings, ph.branches, ph.staff, ph.manufacturers, ph.categories, ph.generics, ph.items,
  ph.item_barcodes, ph.locations, ph.suppliers, ph.supplier_reps, ph.supplier_item_names, ph.customers, ph.customer_meds,
  ph.cash_accounts, ph.payment_methods, ph.expense_categories, ph.item_stock_rules, ph.shortage_marks,
  ph.supplier_offers, ph.attachments, ph.outreach_cycles, ph.outreach_log, ph.device_keys, ph.online_orders to authenticated;
do $$
declare t text;
begin
  foreach t in array array['settings', 'branches', 'staff', 'manufacturers', 'categories', 'generics', 'items', 'item_barcodes',
    'locations', 'suppliers', 'supplier_reps', 'supplier_item_names', 'customers', 'customer_meds', 'cash_accounts',
    'payment_methods', 'expense_categories', 'item_stock_rules', 'shortage_marks', 'supplier_offers', 'attachments',
    'outreach_cycles', 'outreach_log', 'device_keys', 'online_orders'] loop
    execute format('create policy managers_write on ph.%I for insert to authenticated with check (ph.has_role(array[''owner'', ''manager'']))', t);
    execute format('create policy managers_update on ph.%I for update to authenticated using (ph.has_role(array[''owner'', ''manager''])) with check (ph.has_role(array[''owner'', ''manager'']))', t);
  end loop;
end $$;
-- الإعدادات والموظفين: المالك بس
alter policy managers_write on ph.settings with check (ph.has_role(array['owner']));
alter policy managers_update on ph.settings using (ph.has_role(array['owner'])) with check (ph.has_role(array['owner']));
alter policy managers_write on ph.staff with check (ph.has_role(array['owner']));
alter policy managers_update on ph.staff using (ph.has_role(array['owner'])) with check (ph.has_role(array['owner']));
-- الصيدلي: يضيف ويعدّل أصناف وعملاء ونواقص وعروض الموردين
do $$
declare t text;
begin
  foreach t in array array['items', 'item_barcodes', 'customers', 'customer_meds', 'shortage_marks', 'supplier_offers',
                           'supplier_item_names', 'attachments'] loop
    execute format('create policy pharmacist_write on ph.%I for insert to authenticated with check (ph.has_role(array[''pharmacist'']))', t);
    execute format('create policy pharmacist_update on ph.%I for update to authenticated using (ph.has_role(array[''pharmacist''])) with check (ph.has_role(array[''pharmacist'']))', t);
  end loop;
end $$;
-- الكاشير: يضيف عميل جديد بس
create policy cashier_add_customer on ph.customers for insert to authenticated with check (ph.has_role(array['cashier']));
-- التوصيل: يحدّث حالة طلباته
create policy driver_update on ph.online_orders for update to authenticated using (driver = auth.uid()) with check (driver = auth.uid());

-- المسودات (قبل الترحيل): الصيدلي فما فوق. بعد الترحيل التريجرات بتقفلها
grant insert, update, delete on ph.purchase_orders, ph.purchase_order_lines, ph.purchase_invoices, ph.purchase_invoice_lines,
  ph.purchase_returns, ph.purchase_return_lines, ph.transfers, ph.transfer_lines, ph.stock_counts, ph.stock_count_lines
  to authenticated;
do $$
declare t text;
begin
  foreach t in array array['purchase_orders', 'purchase_order_lines', 'purchase_invoices', 'purchase_invoice_lines',
    'purchase_returns', 'purchase_return_lines', 'transfers', 'transfer_lines', 'stock_counts', 'stock_count_lines'] loop
    execute format('create policy drafts_all on ph.%I for all to authenticated using (ph.has_role(array[''owner'', ''manager'', ''pharmacist''])) with check (ph.has_role(array[''owner'', ''manager'', ''pharmacist'']))', t);
  end loop;
end $$;

-- الدفاتر والبيع والفلوس: مفيش كتابة مباشرة خالص (ولا حتى المالك) — دوال الترحيل بس
revoke insert, update, delete on ph.stock_moves, ph.stock_balances, ph.batches, ph.money_moves, ph.party_ledger,
  ph.party_balances, ph.sales, ph.sale_lines, ph.sale_payments, ph.sale_returns, ph.sale_return_lines,
  ph.controlled_register, ph.payments, ph.expenses, ph.shifts, ph.doc_counters, ph.audit_log, ph.stock_openings
  from authenticated;

-- الدوال: الموظفين يناديوها (كل دالة بتتأكد من الدور جواها)، والموقع ليه دالتين بس
grant usage on schema extensions to authenticated, anon;
grant execute on function
  ph.my_role(), ph.has_role(text[]), ph.business_day(timestamptz), ph.find_items(text, integer),
  ph.post_sale(jsonb), ph.post_sale_return(jsonb), ph.open_shift(smallint, numeric), ph.close_shift(bigint, numeric),
  ph.post_purchase_invoice(bigint), ph.post_purchase_return(bigint), ph.post_transfer(bigint), ph.post_stock_count(bigint),
  ph.post_payment(jsonb), ph.post_expense(jsonb), ph.post_opening_stock(smallint, jsonb, text), ph.post_opening_balances(jsonb)
  to authenticated;
grant execute on function ph.store_catalog(text, integer), ph.store_place_order(jsonb) to anon, authenticated;
