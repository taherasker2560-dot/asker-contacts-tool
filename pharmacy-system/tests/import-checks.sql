-- اختبار النقل: بعد import-sample.sql. البرنامج لازم يبان كأنه شغال من 2018، وأرصدته = فارمافلاي النهارده بالظبط.
\set ON_ERROR_STOP on
\set QUIET on
set client_min_messages = notice;
\ir helpers.sql

create temp table result as select ph.import_history('عينة تجريبية', '2026-11-13 03:00+02') as s;

-- ---------------------------------------------------------------- اللي اتنقل
select tst.eq((select (s ->> 'sales')::int from result), 6, 'اتنقلت 6 فواتير بيع');
select tst.eq((select (s ->> 'sale_returns')::int from result), 1, 'ومرتجع بيع');
select tst.eq((select (s ->> 'purchases')::int || '/' || (s ->> 'purchase_returns')::int from result), '4/1', '4 فواتير شرا ومرتجع للمورد');
select tst.eq((select (s ->> 'payments')::int from result), 4, '4 تحصيل وسداد');
select tst.eq((select (s ->> 'adjustments')::int from result), 3, 'تسويتين من فارمافلاي + تسوية النقل');
select tst.eq((select s ->> 'first_day' from result), '2018-03-01', 'البرنامج بيبدأ من أول مارس 2018');
select tst.eq((select s -> 'skipped' from result), '{"sales": 0, "payments": 0, "purchases": 0, "sale_lines": 0, "purchase_lines": 0}'::jsonb, 'مفيش ولا سطر اتساب');

-- ---------------------------------------------------------------- كأنه شغال من 2018
select tst.eq((select business_day from ph.sales where legacy_no = '1002'), '2018-03-02'::date, 'بيع 1:30 بالليل اتحسب على يوم 2 مارس');
select tst.eq((select string_agg(no, ',' order by at) from ph.sales),
              'S-2018-000001,S-2018-000002,S-2020-000001,S-2021-000001,S-2022-000001,S-2026-000001', 'أرقامنا مسلسلة لكل سنة');
select tst.eq((select no from ph.sales where legacy_no = '1006'), 'S-2022-000001', 'وتقدر تدوّر برقم تذكرة فارمافلاي');
select tst.eq((select real_discount from ph.purchase_invoice_lines l join ph.purchase_invoices i on i.id = l.invoice_id where i.legacy_no = '501'),
              0.3182, 'خصم فاتورة 2018 الفعلي بعد البونص');
select tst.eq((select min(at)::date || ' → ' || (select balance_after from ph.v_item_card where item_id = 1259 order by at desc, doc_id desc limit 1)
               from ph.v_item_card where item_id = 1259), '2018-03-01 → 117.00', 'كارت البنادول من 2018 لحد رصيده النهارده');
select tst.eq((select total from ph.v_sales_daily where business_day = '2018-03-02'), 140.00, 'تقرير البيع اليومي فيه 2018');
select tst.eq((select string_agg(amount::text, ',' order by at) from ph.v_party_statement
               where party_type = 'customer' and party_id = (select id from ph.customers where legacy_id = 'C1')),
              '60.00,-60.00,800.00,-300.00,-80.00,20.00', 'كشف حساب الحاج سيد من 2018 كامل');

-- ---------------------------------------------------------------- الأرصدة = فارمافلاي النهارده
select tst.eq((select string_agg(x, ' | ' order by x) from (
                 select i.name_en || ' @' || l.legacy_id || ' = ' || sum(b.qty_units) as x
                 from ph.stock_balances b join ph.items i on i.id = b.item_id join ph.locations l on l.id = b.location_id
                 group by i.name_en, l.legacy_id having sum(b.qty_units) <> 0) t),
              (select string_agg(x, ' | ' order by x) from (
                 select i.name_en || ' @' || c.location_code || ' = ' || sum(c.qty_units)::numeric(14, 2) as x
                 from stage.current_stock c join ph.items i on i.id = c.item_code group by i.name_en, c.location_code) t),
              'رصيد كل صنف في كل مكان = فارمافلاي');
select tst.eq((select qty_units from ph.stock_balances b join ph.batches t on t.id = b.batch_id where t.legacy_key = 'W2'), 27.00,
              'التشغيلة W2 = 27 زي فارمافلاي');
select tst.eq((select string_agg(coalesce(c.legacy_id, s.legacy_id) || '=' || b.balance, ',' order by coalesce(c.legacy_id, s.legacy_id))
               from ph.party_balances b
               left join ph.customers c on b.party_type = 'customer' and c.id = b.party_id
               left join ph.suppliers s on b.party_type = 'supplier' and s.id = b.party_id where b.balance <> 0),
              'C1=440.00,C2=15.00,V1=1180.00,V2=2100.00', 'حسابات العملاء والموردين = فارمافلاي');
select tst.eq((select sum(qty_units) from ph.stock_moves), (select sum(qty_units) from ph.stock_balances), 'الرصيد = مجموع الدفتر');

-- ---------------------------------------------------------------- اللي النقل لقاه في التاريخ
select tst.eq((select string_agg(kind, ',' order by kind) from ph.import_issues),
              'balance_reconciled,credit_without_customer,duplicate_barcode,duplicate_phone,missing_numbers,over_limit,sold_expired,sold_without_stock,stock_reconciled',
              'كل نوع مشكلة اتلقط مرة');
select tst.eq((select item_id || ' ' || at::date from ph.import_issues where kind = 'sold_without_stock'), '1060 2021-05-09',
              'بيع اوجمنتين قبل ما فاتورته تتدخل');
select tst.eq((select item_id from ph.import_issues where kind = 'sold_expired'), 1259::bigint, 'بيع بنادول من تشغيلة منتهية');
select tst.eq((select party || ' ' || (detail ->> 'max_balance') from ph.import_issues where kind = 'over_limit'), 'الحاج سيد 800.00',
              'الحاج سيد وصل 800 والحد 500');
select tst.eq((select detail ->> 'missing' || ' ' || (detail -> 'first' ->> 0) from ph.import_issues where kind = 'missing_numbers'), '1 1004',
              'تذكرة 1004 ناقصة (اتمسحت)');
select tst.eq((select item_id || ' ' || (detail ->> 'diff_units') from ph.import_issues where kind = 'stock_reconciled'), '2001 2',
              'الفرق الحقيقي الوحيد: ترامادول 2 مالهمش تاريخ (الأوجمنتين اختلف في التشغيلة بس)');
select tst.eq((select party || ' ' || (detail ->> 'diff') from ph.import_issues where kind = 'balance_reconciled'), 'مدام هالة 15',
              'حساب مدام هالة اتسوّى 15');
select tst.eq((select ref from ph.import_issues where kind = 'credit_without_customer'), '1001', 'تذكرة 1001 اتدفع فيها أقل ومفيش عميل');

-- ---------------------------------------------------------------- العملاء والباركود
select tst.eq((select phone || ' + ' || array_to_string(other_phones, ',') from ph.customers where legacy_id = 'C1'),
              '201001234567 + 201223334444', 'أرقام الحاج سيد اتظبطت');
select tst.eq((select coalesce(phone, '-') || ' + ' || array_to_string(other_phones, ',') from ph.customers where legacy_id = 'C2'),
              '- + 201001234567', 'الرقم المكرر راح لأول عميل بس');
select tst.eq((select item_id from ph.item_barcodes where barcode = '101060'), 1060::bigint, 'ستيكر فارمافلاي (100000 + الرقم) شغال');
select tst.eq((select item_id from ph.item_barcodes where barcode = '6221234500001'), 1060::bigint, 'باركود الشركة');

-- ---------------------------------------------------------------- بعد النقل: البرنامج بيشتغل عادي
select tst.eq((select import_mode from ph.settings), false, 'وضع النقل اتقفل');
set role authenticated;
select tst.as_user('00000000-0000-0000-0000-0000000000a1');
select tst.eq((ph.post_sale('{"client_uuid":"33333333-0000-0000-0000-000000000001","lines":[{"item_id":1259,"packs":1}],
  "payments":[{"method":"cash","amount":95}]}') ->> 'no'), 'S-2026-000002', 'أول بيعة بعد النقل: رقمها بيكمّل، ومن تشغيلة سليمة بسعرها 95');
select tst.eq((select level || ' ' || packs from ph.v_expiring where batch_id = (select id from ph.batches where legacy_key = 'W2')),
              'expired 9', 'الـ 9 علب المنتهية (W2) ظاهرين، ومااتباعوش');
select tst.eq((select count(*) > 0 from ph.import_issues), true, 'المالك شايف مشاكل النقل');
select tst.fails($$select count(*) from stage.items$$, 'permission denied', 'stage مقفولة على البرنامج');
select tst.fails($$select ph.import_history()$$, 'permission denied', 'النقل مش متاح من البرنامج');
reset role;
select tst.fails($$update ph.sales set total = 1 where legacy_no = '1006'$$, 'اترحّل', 'فواتير فارمافلاي المنقولة مابتتعدلش');
select tst.fails($$select ph.import_history()$$, 'فيها داتا', 'النقل مايتعملش مرتين على نفس القاعدة');
select tst.eq((select string_agg(check_name, '، ') from ph.health_check() where not ok), null, 'الفحص الذاتي سليم بعد النقل والبيع');
