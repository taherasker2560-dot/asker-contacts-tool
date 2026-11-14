-- تعديل السرعة (202611131800): الكاش والفحص المحفوظ بيدّوا نفس الأرقام بالظبط زي الحساب المباشر.
-- بيشتغل من tests/check-speed.sh بعد tools/demo-seed.sql
\i tests/helpers.sql
select id as owner_id from auth.users where username = 'taher' \gset
select id as cashier_id from auth.users where username = 'cashier' \gset
set role authenticated;
select tst.as_user(:'owner_id');

-- 1) الكاش = الحساب المباشر: صافي التكلفة لكل يوم خلص لازم يطابق الحساب من سطور البيع
--    (v_sales_daily بياخد التكلفة من ph.sales_day_cost لما العدد والإجمالي يطابقوا)
select tst.eq(
  (select count(*) from ph.v_sales_daily d
     join lateral (select coalesce(sum(round(l.qty_units * coalesce(l.unit_cost, 0), 2)), 0) as c
                   from ph.sales x join ph.sale_lines l on l.sale_id = x.id
                   where x.status = 'posted' and x.business_day = d.business_day) live on true
   where d.business_day < ph.business_day()
     and d.net_cost <> live.c - coalesce((select sum(round(rl.qty_units * coalesce(sl.unit_cost, b.unit_cost, 0), 2))
                                          from ph.sale_returns sr join ph.sale_return_lines rl on rl.return_id = sr.id
                                          join ph.batches b on b.id = rl.batch_id left join ph.sale_lines sl on sl.id = rl.sale_line_id
                                          where sr.business_day = d.business_day), 0))::integer,
  0, 'الكاش بيدّي نفس صافي التكلفة زي الحساب المباشر لكل يوم');

-- 2) كل يوم خلص اتخزن في الكاش بعد warm_sales_cache
select ph.warm_sales_cache();
select tst.eq(
  (select count(*) from ph.sales where status = 'posted' and business_day < ph.business_day() group by business_day having true limit 1) is not null, true, 'فيه أيام مبيعات خلصت');
select tst.eq(
  (select count(distinct business_day) from ph.sales where status = 'posted' and business_day < ph.business_day()),
  (select count(*) from ph.sales_day_cost), 'كل يوم خلص ليه سطر في الكاش');

-- 3) فاتورة متأخرة دخلت على يوم قديم (النت كان قاطع) = اليوم ده بيتحسب تكلفته من الأول، مش من الكاش القديم
select business_day as oldday, cost as oldcost from ph.sales_day_cost order by business_day limit 1 \gset
-- نزوّد فاتورة بيع على نفس اليوم القديم (عن طريق post_sale عشان الدفاتر تتكتب صح)
select i.id as it, b.id as bt from ph.items i join ph.batches b on b.item_id = i.id
  join ph.stock_balances sb on sb.batch_id = b.id and sb.qty_units > 5 limit 1 \gset
-- الإدخال التاريخي بيتحاكي زي النقل (مش من البرنامج): بصلاحية صاحب القاعدة، والدفاتر محميّة من الكتابة المباشرة للموظفين
reset role;
insert into ph.sales (branch_id, location_id, at, business_day, shift_id, status, subtotal, discount, total, paid, on_credit, source, no, client_uuid)
  values (1, (select id from ph.locations where is_default_sale limit 1), (:'oldday'::date + time '13:00') at time zone 'Africa/Cairo',
          :'oldday'::date, (select id from ph.shifts where status = 'open' order by id desc limit 1), 'posted',
          100, 0, 100, 100, 0, 'pharmafly', ph.next_doc_no('S', 1::smallint, :'oldday'::date), gen_random_uuid())
  returning id as newsale \gset
insert into ph.sale_lines (sale_id, item_id, batch_id, qty_units, unit_price, unit_cost, line_total)
  values (:'newsale', :'it', :'bt', 1, 100, 60, 100);
insert into ph.sale_payments (sale_id, method, amount) values (:'newsale', 'cash', 100);
insert into ph.stock_moves (at, business_day, item_id, batch_id, location_id, qty_units, unit_cost, doc_type, doc_id)
  values ((:'oldday'::date + time '13:00') at time zone 'Africa/Cairo', :'oldday'::date, :'it', :'bt',
          (select id from ph.locations where is_default_sale limit 1), -1, 60, 'sale', :'newsale');
set role authenticated;
select tst.as_user(:'owner_id');
-- قبل التحديث: الكاش القديم لسه زي ما هو، بس v_sales_daily بيكتشف إن العدد اتغير فبيحسب من الأول
select tst.eq(
  (select net_cost from ph.v_sales_daily where business_day = :'oldday')
    = (:'oldcost'::numeric + 60), true, 'فاتورة متأخرة على يوم قديم = التكلفة اتزادت فورًا (الكاش القديم مااتاخدش)');
select ph.warm_sales_cache();
select tst.eq((select cost from ph.sales_day_cost where business_day = :'oldday'), :'oldcost'::numeric + 60,
              'بعد warm: الكاش اتحدّث لليوم ده');

-- 4) health_run بيحفظ، و health_last بيرجّع نفس نتيجة health_check بالظبط
select count(*) from ph.health_run();   -- بيفحص ويحفظ
select tst.eq(
  (select string_agg(check_name || '=' || ok::text, '|' order by check_name) from ph.health_last()),
  (select string_agg(check_name || '=' || ok::text, '|' order by check_name) from ph.health_check()),
  'health_last = health_check (نفس القواعد ونفس النتيجة)');
select tst.eq((select count(*) from ph.health_last()), 10::bigint, 'الفحص المحفوظ 10 قواعد');
select tst.eq((select bool_and(ok) from ph.health_last()), true, 'كل القواعد سليمة في المحفوظ');

-- 5) health_check نفسه لسه سليم بعد الفاتورة المتأخرة
select tst.eq((select string_agg(check_name, '، ') from ph.health_check() where not ok), null, 'الفحص المباشر سليم');

-- 6) الكاشير مايقدرش يشغّل الفحص المحفوظ ولا يكتب الكاش
select tst.as_user(:'cashier_id');
select tst.fails($$select * from ph.health_run()$$, 'مش مسموح', 'الكاشير مايشغّلش الفحص الكامل');
select tst.fails($$select * from ph.health_last()$$, 'مش مسموح', 'الكاشير مايشوفش الفحص المحفوظ');

-- 7) أعمار المديونيات: مجموع الشرائح = الرصيد (بعد تعديل الأداء)
select tst.as_user(:'owner_id');
select tst.eq(
  (select count(*) from ph.rep_dues_aging() a where round(a.b_0_30 + a.b_31_60 + a.b_61_90 + a.b_90p, 2) <> round(a.balance, 2))::integer,
  0, 'أعمار المديونيات: الشرائح الأربعة = الرصيد لكل عميل');

-- 8) الراكد: كل صنف راكد مفيهوش بيع في آخر 90 يوم، وعنده رصيد
select tst.eq(
  (select count(*) from ph.rep_dead_stock(90) d
   where exists (select 1 from ph.sale_lines l join ph.sales s on s.id = l.sale_id
                 where l.item_id = d.item_id and s.status = 'posted' and s.business_day > ph.business_day() - 90))::integer,
  0, 'الراكد: مفيش صنف راكد اتباع في آخر 90 يوم');
