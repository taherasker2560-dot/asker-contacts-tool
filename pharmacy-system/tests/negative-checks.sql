-- البيع قبل إدخال فاتورة الشرا (202611141000): مقفول = مفيش بيع من غير رصيد. مفتوح = بيتباع على تشغيلة «مستنية فاتورة»،
-- ولما الفاتورة تترحّل السالب بيتقفل من الكمية الجديدة، والرصيد الإجمالي صح، والفحص سليم.
-- بيشتغل من tests/check-negative.sh بعد tools/demo-seed.sql
\i tests/helpers.sql
select id as owner_id from auth.users where username = 'taher' \gset
set role authenticated;
select tst.as_user(:'owner_id');
insert into ph.items (id, name_en, name_ar, pack_parts, public_price) values (990001, 'NEG TEST 10 TAB', 'صنف تجربة السالب', 1, 50);
select id as loc from ph.locations where is_default_sale limit 1 \gset
select id as sup from ph.suppliers order by id limit 1 \gset

-- 1) مقفول: الصنف رصيده صفر مايتباعش
update ph.settings set allow_negative_stock = false where id = 1;
select tst.fails($$select ph.post_sale('{"client_uuid":"99999999-0000-0000-0000-000000000001","lines":[{"item_id":990001,"packs":2}],"payments":[{"method":"cash","amount":100}]}')$$,
                 'الرصيد مايكفيش', 'الإعداد مقفول: صنف رصيده صفر مايتباعش');

-- 2) مفتوح: بيتباع، والسالب على تشغيلة «مستنية فاتورة» من غير صلاحية
update ph.settings set allow_negative_stock = true where id = 1;
select tst.eq((ph.post_sale('{"client_uuid":"99999999-0000-0000-0000-000000000002","lines":[{"item_id":990001,"packs":2}],"payments":[{"method":"cash","amount":100}]}') ->> 'total')::numeric,
              100.00, 'الإعداد مفتوح: علبتين اتباعوا والصنف رصيده صفر، بسعر الصنف');
select tst.eq((select sum(qty_units) from ph.stock_balances where item_id = 990001), -2.00, 'الرصيد بقى بالسالب 2');
select tst.eq((select b.source || ':' || coalesce(b.expiry::text, '-') from ph.stock_balances sb join ph.batches b on b.id = sb.batch_id
               where sb.item_id = 990001 and sb.qty_units < 0), 'unbatched:-', 'السالب على تشغيلة «مستنية فاتورة» من غير صلاحية');
select tst.eq((select count(*) from ph.health_check() where not ok), 0::bigint, 'الفحص الذاتي سليم (السالب مسموح)');

-- 3) فاتورة الشرا بتقفل السالب من الكمية الجديدة
insert into ph.purchase_invoices (supplier_id, supplier_doc_no, location_id) values (:sup, 'NEG-1', :loc) returning id as inv \gset
insert into ph.purchase_invoice_lines (invoice_id, item_id, packs, bonus_packs, public_price, cost_total, expiry)
values (:inv, 990001, 10, 0, 50, 350, current_date + 400);
select ph.post_purchase_invoice(:inv) as invno \gset
select tst.eq((select sum(qty_units) from ph.stock_balances where item_id = 990001), 8.00, 'بعد الفاتورة: الرصيد 10 − 2 = 8');
select tst.eq((select count(*) from ph.stock_balances where item_id = 990001 and qty_units < 0), 0::bigint, 'مفيش تشغيلة بالسالب');
select tst.eq((select sb.qty_units from ph.stock_balances sb join ph.batches b on b.id = sb.batch_id
               where sb.item_id = 990001 and b.expiry = current_date + 400), 8.00, 'التشغيلة الجديدة (بصلاحيتها) فيها 8');
select tst.eq((select count(*) from ph.stock_adjustments where note = 'تسوية البيع قبل فاتورة الشرا ' || :'invno'), 1::bigint,
              'مستند تسوية واحد عليه رقم الفاتورة');
select tst.eq((select count(*) from ph.health_check() where not ok), 0::bigint, 'الفحص الذاتي سليم بعد التسوية');

-- 4) بيع تاني بعد الفاتورة بيمشي عادي من التشغيلة الحقيقية
select tst.eq((ph.post_sale('{"client_uuid":"99999999-0000-0000-0000-000000000003","lines":[{"item_id":990001,"packs":1}],"payments":[{"method":"cash","amount":50}]}') ->> 'total')::numeric,
              50.00, 'بيع بعد الفاتورة من التشغيلة الجديدة');
select tst.eq((select sum(qty_units) from ph.stock_balances where item_id = 990001), 7.00, 'الرصيد 7');
