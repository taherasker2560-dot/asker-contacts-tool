-- اختبار يوم شغل كامل على داتا تجريبية: شرا ← بيع ← آجل ← تحصيل ← مرتجع ← وردية ← مرتجع للمورد ← تحويل ← جرد
-- ← صلاحية ← نواقص ← عروض ← تقارير ← صلاحيات ← الموقع ← حماية الدفاتر. أي نتيجة غلط بتوقف التشغيل.
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;

\ir helpers.sql

-- ---------------------------------------------------------------- داتا أساسية (كـ superuser)
insert into ph.settings (pharmacy_name) values ('صيدلية عسكر');
insert into ph.branches (name) values ('الفرع الرئيسي');
insert into auth.users values ('00000000-0000-0000-0000-0000000000a1'), ('00000000-0000-0000-0000-0000000000c1'),
                              ('00000000-0000-0000-0000-0000000000b1'), ('00000000-0000-0000-0000-0000000000d1');
insert into ph.staff (user_id, branch_id, name, role, can_override_limit) values
  ('00000000-0000-0000-0000-0000000000a1', 1, 'المالك', 'owner', true),
  ('00000000-0000-0000-0000-0000000000c1', 1, 'كاشير', 'cashier', false),
  ('00000000-0000-0000-0000-0000000000b1', 1, 'صيدلي', 'pharmacist', false);
insert into ph.suppliers (code, name, kind) values ('AMG', 'مخزن AMG', 'warehouse'), ('IBNSINA', 'ابن سينا', 'company');
insert into ph.locations (branch_id, name, kind, is_default_sale) values (1, 'الرئيسي', 'main', true);
insert into ph.locations (branch_id, name, kind, supplier_id, counts_as_stock) values (1, 'انتظار ابن سينا', 'waiting', 10001, false);
insert into ph.cash_accounts (branch_id, name, kind) values (1, 'درج 1', 'drawer'), (1, 'الخزنة', 'safe'), (1, 'فيزا', 'bank'), (1, 'محفظة', 'wallet');
insert into ph.payment_methods values ('cash', 'كاش', 1), ('card', 'فيزا', 3), ('wallet', 'محفظة', 4), ('credit', 'آجل', null);
insert into ph.categories (code, name_ar) values ('pain_fever', 'مسكنات');
insert into ph.items (id, name_en, name_ar, pack_parts, public_price, category_id) values (1259, 'PANADOL EXTRA 24 TAB', 'بنادول اكسترا', 3, 90, 1);
insert into ph.items (id, name_en, pack_parts, public_price, is_controlled, sell_by_unit) values (2001, 'TRAMADOL 50MG 10 CAP', 1, 50, true, false);
insert into ph.items (name_en, pack_parts, public_price) values ('NEW ITEM SYRUP', 1, 40);
insert into ph.item_barcodes values ('6221234567890', 1259);
insert into ph.customers (name, phone, credit_limit) values ('الحاج سيد', '201000000001', 100);
insert into ph.expense_categories (name) values ('كهربا');
select tst.eq((select id from ph.items where name_en = 'NEW ITEM SYRUP'), 1000000::bigint, 'الصنف الجديد بياخد رقم من مليون (القديم برقم فارمافلاي)');

set role authenticated;

-- ---------------------------------------------------------------- الشرا (المالك)
select tst.as_user('00000000-0000-0000-0000-0000000000a1');
insert into ph.purchase_invoices (supplier_id, supplier_doc_no, location_id) values (10000, 'A-77', 1);
insert into ph.purchase_invoice_lines (invoice_id, item_id, packs, bonus_packs, public_price, cost_total, expiry) values
  (1, 1259, 10, 1, 95, 750, current_date + 400),
  (1, 1259, 2, 0, 80, 120, current_date + 60),       -- تشغيلة قديمة بسعرها القديم
  (1, 2001, 5, 0, 50, 200, current_date + 300);
select tst.eq(ph.post_purchase_invoice(1) like 'PI-%-000001', true, 'ترحيل فاتورة الشرا ورقمها');
select tst.eq((select sum(qty_units) from ph.stock_balances where item_id = 1259), 39.00, 'الرصيد: (10+1+2) علبة × 3 = 39 شريط');
select tst.eq((select public_price from ph.items where id = 1259), 95.00, 'السعر الرسمي زاد لـ 95 (التشغيلة القديمة فضلت 80)');
select tst.eq((select count(*) from ph.price_changes where item_id = 1259 and source = 'purchase'), 1::bigint, 'تغيير السعر اتسجل');
select tst.eq((select balance from ph.party_balances where party_type = 'supplier' and party_id = 10000), 1070.00, 'علينا للمورد 750 + 120 + 200');
select tst.eq((select real_discount from ph.purchase_invoice_lines where id = 1), 0.2823, 'الخصم الفعلي بعد البونص 28.23%');
select tst.fails($$update ph.purchase_invoices set supplier_doc_no = 'X' where id = 1$$, 'اترحّل', 'الفاتورة المرحّلة مابتتعدلش');
select tst.fails($$insert into ph.purchase_invoice_lines (invoice_id, item_id, packs, public_price, cost_total) values (1, 1259, 1, 95, 70)$$,
                     'مرحّل', 'مفيش سطر يتضاف لفاتورة مرحّلة');
select tst.fails($$insert into ph.purchase_invoices (supplier_id, supplier_doc_no, location_id) values (10000, 'A-77', 1)$$,
                     'duplicate key', 'نفس فاتورة المورد ماتتدخلش مرتين');
select tst.fails($$insert into ph.stock_moves (item_id, batch_id, location_id, qty_units, doc_type, doc_id) values (1259, 1, 1, 5, 'purchase', 1)$$,
                     'permission denied', 'حتى المالك مايكتبش في دفتر المخزون مباشرة');

-- ---------------------------------------------------------------- البيع (الكاشير)
select tst.as_user('00000000-0000-0000-0000-0000000000c1');
select tst.eq(ph.open_shift(1::smallint, 200), 1::bigint, 'الكاشير فتح وردية');
select tst.eq((ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000001","shift_id":1,
  "lines":[{"item_id":1259,"packs":1,"units":1}],"payments":[{"method":"cash","amount":106.67}]}') ->> 'total')::numeric,
  106.67, 'بيع علبة + شريط من التشغيلة الأقرب صلاحية بسعرها القديم: 4 × 80÷3');
select tst.eq((select qty_units from ph.stock_balances where batch_id = 2), 2.00, 'التشغيلة القديمة فضل فيها 2 شريط');
select tst.eq((ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000001","shift_id":1,
  "lines":[{"item_id":1259,"packs":1,"units":1}],"payments":[{"method":"cash","amount":106.67}]}') ->> 'repeat')::boolean,
  true, 'نفس الفاتورة اتبعتت تاني (النت قطع): ماتسجلتش مرتين');
select tst.eq((select qty_units from ph.stock_balances where batch_id = 2), 2.00, 'والرصيد ماتغيرش');
select tst.eq((ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000002","shift_id":1,
  "lines":[{"item_id":1259,"packs":1}],"payments":[{"method":"card","amount":85}]}') ->> 'total')::numeric,
  85.00, 'علبة من تشغيلتين: 2 بسعر 80 + 1 بسعر 95');
select tst.eq((select count(*) from ph.sale_lines where sale_id = 2), 2::bigint, 'الفاتورة فيها سطر لكل تشغيلة');
select tst.fails($$select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000003","lines":[{"item_id":1259,"packs":100}],"payments":[]}')$$,
                     'الرصيد مايكفيش', 'مفيش بيع أكتر من الرصيد');
select tst.eq((select count(*) from ph.sales where client_uuid = '11111111-0000-0000-0000-000000000003'), 0::bigint, 'والفاتورة اللي فشلت ماتسجلش منها حاجة');
select tst.fails($$select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000004","lines":[{"item_id":2001,"packs":1}],"payments":[{"method":"cash","amount":50}]}')$$,
                     'صنف جدول', 'صنف جدول من غير روشتة مايتباعش');
select tst.fails($$select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000005","rx":{"patient":"م","doctor":"د"},"lines":[{"item_id":2001,"units":1}],"payments":[]}')$$,
                     'مابيتباعش', 'صنف مابيتباعش بالوحدة');
select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000006","shift_id":1,"rx":{"patient":"مريض","doctor":"د. علي","no":"55"},
  "lines":[{"item_id":2001,"packs":1}],"payments":[{"method":"cash","amount":50}]}');
select tst.eq((select count(*) from ph.controlled_register), 0::bigint, 'الكاشير مايشوفش سجل الجدول');
select tst.as_user('00000000-0000-0000-0000-0000000000b1');
select tst.eq((select patient from ph.controlled_register), 'مريض', 'صنف الجدول اتسجل في السجل لوحده (الصيدلي شايفه)');
select tst.as_user('00000000-0000-0000-0000-0000000000c1');

-- ---------------------------------------------------------------- الآجل وحد العميل
select tst.eq((ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000007","customer_id":100000,
  "lines":[{"item_id":1259,"packs":1}],"payments":[]}') ->> 'on_credit')::numeric, 95.00, 'بيع آجل 95 والحد 100');
select tst.fails($$select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000008","customer_id":100000,"lines":[{"item_id":1259,"units":1}],"payments":[]}')$$,
                     'هيعدّي حده', 'الآجل فوق الحد مايعدّيش');
select tst.fails($$select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000008","customer_id":100000,"override_limit":true,"lines":[{"item_id":1259,"units":1}],"payments":[]}')$$,
                     'هيعدّي حده', 'والكاشير مايقدرش يتخطى الحد');
select tst.fails($$select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000009","lines":[{"item_id":1259,"units":1}],"payments":[{"method":"cash","amount":10}]}')$$,
                     'ومفيش عميل', 'فاضل فلوس من غير عميل = مايتسجلش');
select tst.fails($$select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000009","lines":[{"item_id":1259,"units":1}],"payments":[{"method":"cash","amount":500}]}')$$,
                     'أكتر من الإجمالي', 'المدفوع مايزيدش عن الإجمالي');
select tst.as_user('00000000-0000-0000-0000-0000000000a1');
select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000008","customer_id":100000,"override_limit":true,
  "lines":[{"item_id":1259,"units":1}],"payments":[]}');
select tst.eq((select balance from ph.party_balances where party_type = 'customer' and party_id = 100000), 126.67, 'المالك عدّى الحد بصلاحيته: عليه 126.67');
select tst.as_user('00000000-0000-0000-0000-0000000000c1');
select ph.post_payment('{"kind":"from_customer","party_id":100000,"amount":50,"shift_id":1}');
select tst.eq((select balance from ph.party_balances where party_type = 'customer' and party_id = 100000), 76.67, 'العميل دفع 50 في الدرج');
select tst.fails($$select ph.post_payment('{"kind":"to_supplier","party_id":10000,"amount":10,"account_id":1}')$$,
                     'مش مسموح', 'الكاشير مايدفعش لمورد');
select tst.fails($$select ph.post_sale_return('{"client_uuid":"22222222-0000-0000-0000-000000000001","sale_id":1,"lines":[{"sale_line_id":1,"qty_units":1}]}')$$,
                     'مش مسموح', 'الكاشير مايعملش مرتجع');

-- ---------------------------------------------------------------- مرتجع البيع (الصيدلي) وقفل الوردية
select tst.as_user('00000000-0000-0000-0000-0000000000b1');
select tst.eq((ph.post_sale_return('{"client_uuid":"22222222-0000-0000-0000-000000000001","sale_id":1,"shift_id":1,
  "lines":[{"sale_line_id":1,"qty_units":1}]}') ->> 'total')::numeric, 26.67, 'مرتجع شريط بسعر البيع');
select tst.eq((select qty_units from ph.stock_balances where batch_id = 2), 1.00, 'الشريط رجع لنفس التشغيلة');
select tst.fails($$select ph.post_sale_return('{"client_uuid":"22222222-0000-0000-0000-000000000002","sale_id":1,"lines":[{"sale_line_id":1,"qty_units":4}]}')$$,
                     'مايتنفعش', 'مايرجعش أكتر من اللي اتباع');
select tst.as_user('00000000-0000-0000-0000-0000000000c1');
-- المفروض في الدرج = 200 + 106.67 + 50 (جدول) + 50 (تحصيل) − 26.67 (مرتجع) = 380
select tst.eq((ph.close_shift(1, 379) ->> 'expected')::numeric, 380.00, 'قفل الوردية: المفروض 380');
select tst.as_user('00000000-0000-0000-0000-0000000000a1');
select tst.eq((select balance from ph.v_cash_balances where id = 1), 179.00, 'الدرج = حركات اليوم − 1 جنيه عجز');

-- ---------------------------------------------------------------- المورد: سداد ومرتجع ومصروف (المالك)
select ph.post_payment('{"kind":"to_supplier","party_id":10000,"amount":500,"account_id":2,"receipt_no":"R-9"}');
insert into ph.purchase_returns (supplier_id, location_id, reason) values (10000, 1, 'damaged');
insert into ph.purchase_return_lines (return_id, batch_id, qty_units) values (1, 3, 1);
select ph.post_purchase_return(1);
select tst.eq((select balance from ph.v_supplier_balances where id = 10000), 530.00, 'المورد: 1070 − 500 سداد − 40 مرتجع');
select ph.post_expense('{"category_id":1,"amount":300,"account_id":2,"note":"كهربا نوفمبر"}');
select tst.eq((select balance from ph.v_cash_balances where id = 2), -800.00, 'الخزنة: سداد 500 + كهربا 300');

-- ---------------------------------------------------------------- تحويل لمخزن الانتظار وجرد
insert into ph.transfers (from_location, to_location) values (1, 2);
insert into ph.transfer_lines values (1, 1259, 3);
select ph.post_transfer(1);
select tst.eq((select units from ph.v_onhand where item_id = 1259), 26.00, 'مخزن الانتظار مابيتحسبش في الرصيد');
insert into ph.stock_counts (location_id, scope) values (1, 'رف المسكنات');
insert into ph.stock_count_lines (count_id, item_id, batch_id, counted_units)
  select 1, 1259, 1, qty_units - 1 from ph.stock_balances where batch_id = 1 and location_id = 1;
select ph.post_stock_count(1);
select tst.eq((select qty_units from ph.stock_moves where doc_type = 'count'), -1.00, 'الجرد سجّل عجز شريط');
select tst.eq((select balance_after from ph.v_item_card where item_id = 1259 order by at desc, doc_id desc limit 1),
                  (select sum(qty_units) from ph.stock_balances where item_id = 1259), 'كارت الصنف = الرصيد');

-- ---------------------------------------------------------------- الصلاحية والمنتهي
select ph.post_opening_stock(1::smallint, jsonb_build_array(
  jsonb_build_object('item_id', 1000000, 'packs', 2, 'expiry', current_date - 5, 'unit_cost', 30),
  jsonb_build_object('item_id', 1000000, 'packs', 1, 'expiry', current_date + 10, 'unit_cost', 30)));
select tst.fails($$select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000010","lines":[{"item_id":1000000,"packs":2}],"payments":[]}')$$,
                     'الرصيد مايكفيش', 'المنتهي مايتباعش');
select tst.eq((select string_agg(level, ',' order by expiry) from ph.v_expiring where item_id = 1000000), 'expired,red', 'الصلاحية: منتهي + أحمر');
select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000011","lines":[{"item_id":1000000,"packs":1}],"payments":[{"method":"cash","amount":40}]}');

-- ---------------------------------------------------------------- النواقص (من غير ملف ولا لاب)
insert into ph.item_stock_rules (item_id, min_units) values (1000000, 5);
select tst.eq((select order_packs from ph.v_shortages where item_id = 1000000), 1::numeric, 'ناقص لوحده: الرصيد الصالح 0 والحد 5');
select tst.eq((select count(*) from ph.v_shortages where item_id = 1259), 0::bigint, 'البنادول مش ناقص');
insert into ph.shortage_marks (item_id, order_packs) values (1000000, 6);
select tst.eq((select order_packs from ph.v_shortages where item_id = 1000000), 6::numeric, 'الكمية اللي المالك كتبها بتكسب');
insert into ph.purchase_orders (supplier_id, status, sent_at) values (10000, 'sent', now());
insert into ph.purchase_order_lines (order_id, item_id, packs) values (1, 1000000, 6);
select tst.eq((select ordered_today_from from ph.v_shortages where item_id = 1000000), 'مخزن AMG', '«اتطلب النهارده من …»');
update ph.shortage_marks set deferred_until = current_date + 3 where item_id = 1000000;
select tst.eq((select count(*) from ph.v_shortages where item_id = 1000000), 0::bigint, 'المؤجّل مابيظهرش');

-- ---------------------------------------------------------------- عروض الموردين وأحسن خصم
insert into ph.supplier_offers (supplier_id, item_id, source, discount_pct, raw_text) values
  (10000, 1259, 'whatsapp', 28, 'بنادول اكسترا خصم 28'), (10001, 1259, 'list', 25, 'PANADOL EXTRA');
select tst.eq((select best_pct || '/' || second_pct || '/' || gap_pct from ph.v_best_offer where item_id = 1259),
                  '28.00/25.00/3.00', 'أحسن خصم: AMG 28 وبعده ابن سينا 25');

-- ---------------------------------------------------------------- التقارير
select tst.eq((select net_sales from ph.v_sales_daily where business_day = ph.business_day()),
                  (select sum(total) from ph.sales) - (select sum(total) from ph.sale_returns), 'البيع الصافي = البيع − المرتجع');
select tst.eq((select gross_profit > 0 and gross_profit = net_sales - net_cost from ph.v_sales_daily where business_day = ph.business_day()),
                  true, 'الربح = الصافي − التكلفة');
select tst.eq((select balance || '/' || over_limit from ph.v_customer_dues), '76.67/false', 'العملاء اللي عليهم فلوس');
update ph.customers set credit_limit = 50 where id = 100000;
select tst.eq((select over_limit from ph.v_customer_dues), true, 'لما الحد قل بقى «عدّى الحد»');
select tst.eq((select count(*) from ph.audit_log where table_name = 'customers'), 1::bigint, 'تغيير حد العميل اتسجل');
select tst.eq((select string_agg(no, ',' order by id) from ph.sales),
                  (select string_agg(n, ',') from (select 'S-' || extract(year from ph.business_day()) || '-' || lpad(g::text, 6, '0') n
                                                   from generate_series(1, 6) g) x), 'أرقام الفواتير مسلسلة من غير فراغات');

-- ---------------------------------------------------------------- الصلاحيات
select tst.as_user('00000000-0000-0000-0000-0000000000c1');
select tst.eq((select count(*) from ph.purchase_invoices), 0::bigint, 'الكاشير مايشوفش فواتير الشرا');
select tst.eq((select count(*) from ph.money_moves), 0::bigint, 'ولا حركة الخزن');
select tst.eq((select count(*) from ph.party_balances where party_type = 'supplier'), 0::bigint, 'ولا حسابات الموردين');
select tst.eq((select count(*) from ph.items), 3::bigint, 'بس بيشوف الأصناف');
select tst.eq((select id from ph.find_items('6221234567890')), 1259::bigint, 'البحث بالباركود');
select tst.eq((select id from ph.find_items('panadol') limit 1), 1259::bigint, 'البحث بجزء من الاسم');
update ph.items set public_price = 1 where id = 1259;
select tst.eq((select public_price from ph.items where id = 1259), 95.00, 'الكاشير مايغيّرش سعر (التعديل مابيلمسش ولا صف)');
select tst.as_user('00000000-0000-0000-0000-0000000000b1');
select tst.fails($$select ph.post_expense('{"category_id":1,"amount":5,"account_id":2}')$$, 'مش مسموح', 'الصيدلي مايسجلش مصروف');
select tst.as_user('00000000-0000-0000-0000-0000000000d1');
select tst.eq((select count(*) from ph.items), 0::bigint, 'حساب مش موظف مابيشوفش حاجة');
select tst.fails($$select ph.post_sale('{"client_uuid":"11111111-0000-0000-0000-000000000099","lines":[{"item_id":1259,"units":1}]}')$$,
                     'مش مسموح', 'ومايبيعش');

-- ---------------------------------------------------------------- الموقع (من غير تسجيل دخول)
reset role;
set role anon;
select tst.eq((select available from ph.store_catalog('PANADOL')), true, 'الموقع: البنادول متاح (من غير ما يبان الرصيد)');
select tst.eq((select count(*) from ph.store_catalog('TRAMADOL')), 0::bigint, 'صنف الجدول مش على الموقع');
select tst.fails($$select count(*) from ph.items$$, 'permission denied', 'الموقع مايقراش جدول الأصناف');
select ph.store_place_order('{"name":"عميل الموقع","phone":"01000000002","address":"شارع النيل 5","items":[{"id":1259,"qty":2,"price":1}]}');
reset role;
select tst.eq((select total from ph.online_orders), 190.00, 'سعر الطلب من القاعدة مش من المتصفح');

-- ---------------------------------------------------------------- الدفاتر مابتتعدلش ولا من superuser
select tst.fails($$update ph.stock_moves set qty_units = 1 where id = 1$$, 'مابيتعدلش', 'دفتر المخزون مابيتعدلش');
select tst.fails($$delete from ph.money_moves where id = 1$$, 'مابيتعدلش', 'دفتر الخزن مابيتمسحش');
select tst.fails($$update ph.party_ledger set amount = 1 where id = 1$$, 'مابيتعدلش', 'دفتر الحسابات مابيتعدلش');
select tst.fails($$update ph.sales set total = 1 where id = 1$$, 'اترحّل', 'فاتورة البيع المرحّلة مابتتعدلش');
select tst.eq((select sum(qty_units) from ph.stock_moves), (select sum(qty_units) from ph.stock_balances), 'الرصيد = مجموع الدفتر');
select tst.eq((select sum(amount) from ph.party_ledger where party_type = 'customer'),
                  (select sum(balance) from ph.party_balances where party_type = 'customer'), 'رصيد العملاء = مجموع الدفتر');
