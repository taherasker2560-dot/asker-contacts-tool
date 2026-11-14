-- التقارير على القاعدة التجريبية: كل رقم لازم يطابق الدفاتر من طريق تاني، والصلاحيات مظبوطة.
-- بيشتغل من tests/check-reports.sh بعد tools/demo-seed.sql
\i tests/helpers.sql
select id as owner_id from auth.users where username = 'taher' \gset
select id as cashier_id from auth.users where username = 'cashier' \gset
select id as bot_id from auth.users where username = 'bot' \gset
select (ph.business_day() - 29) as f, ph.business_day() as t \gset
set role authenticated;
select tst.as_user(:'owner_id');

-- 1) المبيعات: الملخص = مجموع اليومي، وربح الأصناف − الخصم = صافي البيع
select tst.eq((ph.rep_sales_summary(:'f', :'t') #>> '{cur,net_sales}')::numeric,
              (select sum(net_sales) from ph.v_sales_daily where business_day between :'f' and :'t'), 'ملخص المبيعات = مجموع الأيام');
select tst.eq(abs((select sum(sales) from ph.rep_item_profit(:'f', :'t', 5000))
                  - (select coalesce(sum(discount), 0) from ph.sales where status = 'posted' and business_day between :'f' and :'t')
                  - (ph.rep_sales_summary(:'f', :'t') #>> '{cur,net_sales}')::numeric) < 2, true, 'بيع الأصناف − الخصم = صافي المبيعات');
select tst.eq((ph.rep_sales_summary(:'f', :'t') #>> '{prev,to}')::date, (:'f')::date - 1, 'الفترة اللي قبلها بتخلص قبل الفترة بيوم');
select tst.eq((select count(*) from ph.rep_heatmap(:'f', :'t'))::integer, 168, 'الزحمة: 7 أيام × 24 ساعة');
select tst.eq((select sum(invoices) from ph.rep_by_staff(:'f', :'t'))::numeric,
              (select count(*) from ph.sales where status = 'posted' and business_day between :'f' and :'t')::numeric, 'فواتير الموظفين = كل الفواتير');
select tst.eq((select count(*) from ph.rep_by_shift(:'f', :'t') where status = 'open')::integer, 1, 'الوردية المفتوحة ظاهرة');

-- 2) المخزون
select tst.eq((select sum(cost_value) from ph.rep_stock_value()), (select round(sum(cost_value), 2) from ph.v_stock where qty_units > 0), 'قيمة المخزون = مجموع التشغيلات');
select tst.eq((select count(*) from ph.rep_dead_stock(90) where item_id between 3001 and 3005)::integer, 5, 'الراكد: الأصناف اللي مااتباعتش');
select tst.eq((select bool_and(days_left <= 14) from ph.rep_runout(14)), true, 'هيخلص: كله خلال 14 يوم');
select tst.eq((select sum(cost_value) from ph.rep_expiry_months(12) where month is not null) > 0, true, 'قيمة الصلاحية كل شهر');

-- 3) المشتريات والموردين
select tst.eq((select bool_and(best_pct >= worst_pct and missed_value >= 0) from ph.rep_discount_compare(180)), true, 'مقارنة الخصومات: الأحسن ≥ الأوحش');
select tst.eq((select sum(total) from ph.rep_supplier_month(:'f', :'t')),
              (select sum(total) from ph.purchase_invoices where status = 'posted' and invoice_date between :'f' and :'t'), 'فواتير الموردين = فواتير الشرا');
select tst.eq((select count(*) from ph.rep_price_changes((:'t')::date - 90, :'t'))::integer, 6, 'الأسعار اللي اتغيرت');

-- 4) العملاء
select tst.eq((select bool_and(b_0_30 + b_31_60 + b_61_90 + b_90p = balance) from ph.rep_dues_aging()), true, 'عمر الدين: الشرايح = الرصيد');
select tst.eq((select sum(balance) from ph.rep_dues_aging()),
              (select sum(balance) from ph.party_balances where party_type = 'customer' and balance > 0), 'المديونيات = أرصدة العملاء');
select tst.eq((select count(*) from ph.rep_lapsed_customers(45))::integer >= 4, true, 'عملاء بطلوا ييجوا');
select tst.eq((select max(sales) from ph.rep_top_customers(:'f', :'t', 50)) > 0, true, 'أحسن العملاء');

-- 5) الطلبيات
select tst.eq((select bool_and(lines_received <= lines and packs_received <= packs_ordered) from ph.rep_order_fill(:'f', :'t')), true, 'وصول الطلبية ≤ اللي اتطلب');
select tst.eq((select count(*) from ph.rep_late_orders(24) where supplier = 'مخزن AMG' and item_id = 1301)::integer, 1, 'الطلبية المتأخرة ظاهرة');

-- 6) الفلوس
select tst.eq((select sum(closing) from ph.rep_cash_flow(:'f', :'t')), (select sum(balance) from ph.v_cash_balances), 'آخر الخزن = أرصدة الخزن');
select tst.eq((select bool_and(net_profit = gross_profit - expenses) from ph.rep_pnl_monthly(12)), true, 'صافي الربح = الإجمالي − المصروفات');
select tst.eq((select sum(total) from ph.rep_expenses(:'f', :'t')),
              (select sum(amount) from ph.expenses where business_day between :'f' and :'t'), 'المصروفات حسب النوع = كل المصروفات');

-- 7) المتجر
select tst.eq((select count(*) from ph.rep_store_orders((:'t')::date - 31, :'t'))::integer, 34, 'طلبات المتجر');
select tst.eq((select count(*) from ph.rep_store_no_image(500) r join ph.items i on i.id = r.item_id where i.image_path is not null)::integer, 0, 'من غير صورة = فعلًا من غير صورة');

-- ملخص الصبح
select tst.eq(ph.morning_brief_text() like 'صباح الخير%', true, 'ملخص الصبح كرسالة');
select tst.eq((ph.morning_brief() ->> 'health_failures')::integer, 0, 'ملخص الصبح: القاعدة سليمة');

-- الصلاحيات: البوت بياخد الملخص بس، والكاشير ولا حاجة
select tst.as_user(:'bot_id');
select tst.eq((ph.morning_brief() ->> 'shortages')::integer >= 0, true, 'البوت بيقرا ملخص الصبح');
select tst.eq(ph.morning_brief() ->> 'health_failures', null, 'البوت مابيشوفش تفاصيل الفحص');
select tst.fails($$select ph.rep_dead_stock(90)$$, 'مش مسموح', 'البوت مايشوفش التقارير');
select tst.as_user(:'cashier_id');
select tst.fails($$select ph.rep_sales_summary(current_date, current_date)$$, 'مش مسموح', 'الكاشير مايشوفش الأرباح');
select tst.fails($$select ph.morning_brief()$$, 'مش مسموح', 'الكاشير مايشوفش الملخص');
reset role;
set role anon;
select tst.fails($$select ph.rep_stock_value()$$, 'permission denied', 'من غير دخول: ممنوع');
reset role;
