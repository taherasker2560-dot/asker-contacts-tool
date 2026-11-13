-- تاريخ تجريبي صغير بشكل stage (مش داتا الصيدلية): من مارس 2018 لنوفمبر 2026.
-- فيه عمدًا: بيع بعد نص الليل، بيع قبل ما فاتورة الشرا تتدخل، بيع من تشغيلة منتهية، عميل عدّى حده، تذكرة ممسوحة (1004)،
-- رقم تليفون مكرر، باركود مكرر، وصنف رصيده في فارمافلاي مالوش تاريخ.
\set ON_ERROR_STOP on

-- إعدادات البرنامج الجديد قبل النقل
insert into ph.settings (pharmacy_name) values ('صيدلية تجربة');
insert into ph.branches (name) values ('الفرع الرئيسي');
insert into ph.cash_accounts (branch_id, name, kind) values (1, 'درج 1', 'drawer');
insert into ph.payment_methods values ('cash', 'كاش', 1), ('credit', 'آجل', null);
insert into auth.users values ('00000000-0000-0000-0000-0000000000a1');
insert into ph.staff (user_id, branch_id, name, role) values ('00000000-0000-0000-0000-0000000000a1', 1, 'المالك', 'owner');

insert into stage.locations (code, name, kind, supplier_code, counts_as_stock, is_default_sale) values
  ('S1', 'المخزن الرئيسي', 'main', null, true, true),
  ('S2', 'مخزن انتظار ابن سينا', 'waiting', 'V2', false, false);
insert into stage.suppliers (code, name, kind) values ('V1', 'مخزن AMG', 'warehouse'), ('V2', 'ابن سينا', 'company');
insert into stage.customers (code, name, phones, credit_limit, created_at) values
  ('C1', 'الحاج سيد', '{01001234567,"0122 333 4444"}', 500, '2018-03-01'),
  ('C2', 'مدام هالة', '{"+20 100 123 4567"}', 0, '2019-01-01'),
  ('C3', 'عميل من غير رقم', '{abc}', 0, '2020-01-01');
insert into stage.items (code, name_en, name_ar, pack_parts, public_price, category, manufacturer, is_controlled, barcodes) values
  (1060, 'AUGMENTIN 1G 14TAB', 'اوجمنتين 1 جم', 1, 118, 'Antibiotic', 'GSK', false, '{6221234500001}'),
  (1259, 'PANADOL EXTRA 24 TAB', 'بنادول اكسترا', 3, 95, 'Pain', 'GSK', false, '{}'),
  (2001, 'TRAMADOL 50MG 10 CAP', null, 1, 50, null, null, true, '{6221234500001}');
insert into stage.batches (batch_key, item_code, expiry, public_price, unit_cost) values
  ('W1', 1259, '2019-12-31', 60, 13.6364),
  ('W2', 1259, '2024-06-30', 80, 20),
  ('W3', 1259, '2027-09-30', 95, 23.3333),
  ('W4', 1060, '2027-02-28', 118, 85);

insert into stage.purchases (doc_key, legacy_no, supplier_code, supplier_doc_no, at, location_code, is_return, paid) values
  ('P1', '501', 'V1', 'A-1', '2018-03-01 10:00', 'S1', false, 0),
  ('P2', '502', 'V1', 'A-2', '2021-05-10 11:00', 'S1', false, 600),
  ('PR1', '503', 'V1', null, '2021-06-01 12:00', 'S1', true, 0),
  ('P3', '504', 'V2', 'IS-9', '2023-08-01 13:00', 'S1', false, 0),
  ('P4', '505', 'V1', 'A-3', '2025-01-15 14:00', 'S1', false, 0);
insert into stage.purchase_lines (doc_key, line_no, item_code, batch_key, packs, bonus_packs, public_price, cost_total, expiry) values
  ('P1', 1, 1259, 'W1', 10, 1, 60, 450, '2019-12-31'),
  ('P2', 1, 1259, 'W2', 20, 0, 80, 1200, '2024-06-30'),
  ('P2', 2, 1060, null, 5, 0, 110, 400, '2022-12-31'),
  ('PR1', 1, 1259, 'W2', 2, 0, 80, 120, null),
  ('P3', 1, 1259, 'W3', 30, 0, 95, 2100, '2027-09-30'),
  ('P4', 1, 1060, 'W4', 10, 0, 118, 850, '2027-02-28');

insert into stage.sales (doc_key, legacy_no, at, location_code, customer_code, kind, ref_doc_key, discount, paid) values
  ('T1001', '1001', '2018-03-02 12:00', 'S1', null, 'sale', null, 0, 70),      -- اتدفع أقل ومفيش عميل
  ('T1002', '1002', '2018-03-03 01:30', 'S1', 'C1', 'sale', null, 0, 0),       -- بعد نص الليل = يوم 2 مارس
  ('T1003', '1003', '2020-02-01 18:00', 'S1', null, 'sale', null, 0, 60),      -- من تشغيلة منتهية
  ('T1005', '1005', '2021-05-09 20:00', 'S1', null, 'sale', null, 0, 110),     -- قبل ما فاتورة الشرا تتدخل
  ('T1006', '1006', '2022-01-10 19:00', 'S1', 'C1', 'sale', null, 0, 0),       -- العميل عدّى حده
  ('T1007', '1007', '2024-03-03 17:00', 'S1', 'C1', 'return', 'T1006', 0, 0),
  ('T1008', '1008', '2026-11-01 21:00', 'S1', null, 'sale', null, 6, 230);
insert into stage.sale_lines (doc_key, line_no, item_code, batch_key, qty_units, unit_price, line_total) values
  ('T1001', 1, 1259, 'W1', 4, 20, 80),
  ('T1002', 1, 1259, 'W1', 3, 20, 60),
  ('T1003', 1, 1259, 'W1', 3, 20, 60),
  ('T1005', 1, 1060, null, 1, 110, 110),
  ('T1006', 1, 1259, 'W2', 30, null, 800),
  ('T1007', 1, 1259, 'W2', 3, null, 80),
  ('T1008', 1, 1060, 'W4', 2, 118, 236);

insert into stage.payments (doc_key, legacy_no, at, kind, party_code, amount) values
  ('PAY1', 'C-1', '2018-04-01 10:00', 'from_customer', 'C1', 60),
  ('PAY2', 'C-2', '2022-02-01 10:00', 'from_customer', 'C1', 300),
  ('PAY3', 'V-1', '2023-01-01 10:00', 'to_supplier', 'V1', 1000),
  ('PAY4', 'C-3', '2024-04-01 10:00', 'to_customer', 'C1', 20);

insert into stage.adjustments (doc_key, line_no, legacy_no, at, location_code, item_code, batch_key, qty_units, reason) values
  ('ADJ1', 1, '90', '2020-01-05 09:00', 'S1', 1259, 'W1', -23, 'expired'),
  ('ADJ2', 1, '91', '2023-09-01 09:00', 'S1', 1259, 'W3', -6, 'transfer'),
  ('ADJ2', 2, '91', '2023-09-01 09:00', 'S2', 1259, 'W3', 6, 'transfer');

-- فارمافلاي النهارده
insert into stage.current_stock (location_code, item_code, batch_key, qty_units) values
  ('S1', 1259, 'W2', 27), ('S1', 1259, 'W3', 84), ('S2', 1259, 'W3', 6),
  ('S1', 1060, 'W4', 8), ('S1', 1060, 'W9', 4),       -- W9: تشغيلة مش معروفة لينا (نفس الصنف، المجموع مظبوط)
  ('S1', 2001, 'W5', 2);                               -- رصيد مالوش أي تاريخ
insert into stage.current_balances (party_type, party_code, balance) values
  ('customer', 'C1', 440), ('customer', 'C2', 15), ('supplier', 'V1', 1180), ('supplier', 'V2', 2100);
