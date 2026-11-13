-- =====================================================================================================
-- بيانات تجريبية للعرض والتجربة (مش داتا الصيدلية): 76 صنف من السوق، 6 موردين، 40 عميل بأسامي متخيّلة،
-- 5 شهور تاريخ (بيع وشرا ومرتجع وتحصيل وسداد) بتدخل بـ ph.import_history زي نسخة فارمافلاي بالظبط،
-- والنهارده شغال: وردية مفتوحة وبيع حقيقي من الكاشير وعروض موردين.
-- الشاشات بتكتب «بيانات تجريبية» فوق (settings.demo_data).
-- بتتحط على قاعدة فاضية بعد ملفات db/ والتعديلات: tools/demo.sh (Linux). مابتتحطش على قاعدة اللاب اللي عليها داتا الصيدلية.
-- اليوزرات: taher (المالك) و cashier و pharmacist، وكلمة السر للكل: demo-pass-1 (للتجربة بس).
-- =====================================================================================================
\set ON_ERROR_STOP on
select setseed(0.4242);

insert into ph.settings (pharmacy_name, demo_data) values ('صيدلية عسكر', true);
insert into ph.branches (name, phone, address) values ('الفرع الرئيسي', '0233334444', 'شارع النيل');
insert into ph.cash_accounts (branch_id, name, kind) values (1, 'درج الكاشير', 'drawer'), (1, 'الخزنة', 'safe'), (1, 'فيزا البنك', 'bank'), (1, 'محفظة / InstaPay', 'wallet');
insert into ph.payment_methods values ('cash', 'كاش', 1), ('card', 'فيزا', 3), ('wallet', 'محفظة', 4), ('instapay', 'InstaPay', 4), ('credit', 'آجل', null);
insert into ph.categories (code, name_ar) values
  ('pain_fever', 'مسكنات وخافض حرارة'), ('antibiotic', 'مضادات حيوية'), ('blood_pressure_heart', 'ضغط وقلب'),
  ('anticoagulant', 'سيولة'), ('cholesterol', 'كوليسترول'), ('diabetes', 'سكر'), ('gi_rx', 'معدة (روشتة)'),
  ('stomach_simple', 'معدة وهضم'), ('cold_allergy', 'برد وحساسية'), ('respiratory_rx', 'صدر'),
  ('vitamins_supplements', 'فيتامينات ومكملات'), ('neuro_psych', 'أعصاب'), ('controlled_pain', 'جدول'),
  ('skin_drug', 'جلدية'), ('cosmetic', 'تجميل'), ('baby', 'أطفال'), ('supplies_devices', 'مستلزمات');

-- ---------------------------------------------------------------- الأصناف (w = قد إيه بيتطلب)
create temp table demo_items (code int, name_en text, name_ar text, parts int, price numeric, cat text, gkey text, ctrl bool, fridge bool, w int);
insert into demo_items values
 (1001,'PANADOL EXTRA 24 TAB','بنادول اكسترا',3,96,'pain_fever','paracetamol+caffeine|tab',false,false,30),
 (1002,'PANADOL ADVANCE 24 TAB','بنادول ادفانس',3,72,'pain_fever','paracetamol|tab',false,false,18),
 (1003,'ABIMOL 500MG 20 TAB','ابيمول 500',2,24,'pain_fever','paracetamol|tab',false,false,14),
 (1004,'CETAL 500MG 20 TAB','سيتال 500',2,22,'pain_fever','paracetamol|tab',false,false,10),
 (1005,'BRUFEN 400MG 30 TAB','بروفين 400',3,63,'pain_fever','ibuprofen|tab',false,false,16),
 (1006,'CATAFLAM 50MG 20 TAB','كتافلام 50',2,84,'pain_fever','diclofenac potassium|tab',false,false,20),
 (1007,'VOLTAREN 75MG 3 AMP','فولتارين 75 امبول',3,45,'pain_fever','diclofenac sodium|inj',false,false,8),
 (1008,'CATAFAST 50MG 9 SACHETS','كتافاست 50 اكياس',9,99,'pain_fever','diclofenac potassium|sachet',false,false,9),
 (1101,'AUGMENTIN 1G 14 TAB','اوجمنتين 1 جم',2,212,'antibiotic','amoxicillin+clavulanic|tab',false,false,14),
 (1102,'HIBIOTIC 1G 16 TAB','هاي بيوتك 1 جم',2,148,'antibiotic','amoxicillin+clavulanic|tab',false,false,10),
 (1103,'CURAM 1G 14 TAB','كيورام 1 جم',2,176,'antibiotic','amoxicillin+clavulanic|tab',false,false,7),
 (1104,'FLUMOX 500MG 16 CAP','فلوموكس 500',2,58,'antibiotic','amoxicillin+flucloxacillin|cap',false,false,8),
 (1105,'ZITHROMAX 500MG 3 TAB','زيثروماكس 500',1,234,'antibiotic','azithromycin|tab',false,false,6),
 (1106,'XITHRONE 500MG 3 TAB','زيثرون 500',1,118,'antibiotic','azithromycin|tab',false,false,9),
 (1107,'CIPROCIN 500MG 10 TAB','سيبروسين 500',1,52,'antibiotic','ciprofloxacin|tab',false,false,6),
 (1108,'FLAGYL 500MG 20 TAB','فلاجيل 500',2,34,'antibiotic','metronidazole|tab',false,false,9),
 (1201,'CONCOR 5MG 30 TAB','كونكور 5',3,96,'blood_pressure_heart','bisoprolol|tab',false,false,12),
 (1202,'BISOCOR 5MG 30 TAB','بيسوكور 5',3,61,'blood_pressure_heart','bisoprolol|tab',false,false,6),
 (1203,'CONCOR AM 5/5 30 TAB','كونكور ايه ام',3,168,'blood_pressure_heart','bisoprolol+amlodipine|tab',false,false,5),
 (1204,'NORVASC 5MG 20 TAB','نورفاسك 5',2,118,'blood_pressure_heart','amlodipine|tab',false,false,7),
 (1205,'TAREG 80MG 28 TAB','تاريج 80',4,190,'blood_pressure_heart','valsartan|tab',false,false,5),
 (1206,'ELIQUIS 5MG 60 TAB','اليكويس 5',6,960,'anticoagulant','apixaban|tab',false,false,3),
 (1207,'ASPOCID 75MG 30 TAB','اسبوسيد 75',3,18,'anticoagulant','aspirin|tab',false,false,12),
 (1208,'LIPITOR 20MG 30 TAB','ليبيتور 20',3,310,'cholesterol','atorvastatin|tab',false,false,5),
 (1209,'ATOR 20MG 30 TAB','اتور 20',3,120,'cholesterol','atorvastatin|tab',false,false,7),
 (1301,'GLUCOPHAGE 1000MG 30 TAB','جلوكوفاج 1000',3,70,'diabetes','metformin|tab',false,false,12),
 (1302,'CIDOPHAGE 1000MG 30 TAB','سيدوفاج 1000',3,39,'diabetes','metformin|tab',false,false,9),
 (1303,'AMARYL 2MG 30 TAB','اماريل 2',3,92,'diabetes','glimepiride|tab',false,false,6),
 (1304,'JANUVIA 100MG 28 TAB','جانوفيا 100',4,612,'diabetes','sitagliptin|tab',false,false,3),
 (1305,'GALVUS MET 50/1000 30 TAB','جالفس ميت',3,330,'diabetes','vildagliptin+metformin|tab',false,false,3),
 (1306,'INSULATARD PENFILL 5 CART','انسولاتارد',5,410,'diabetes','insulin nph|inj',false,true,2),
 (1401,'NEXIUM 40MG 14 TAB','نيكسيوم 40',2,252,'gi_rx','esomeprazole|tab',false,false,7),
 (1402,'ESMOPRAZOLE 40MG 14 TAB','ايزموبرازول 40',2,86,'gi_rx','esomeprazole|tab',false,false,6),
 (1403,'OMEZ 20MG 14 CAP','اوميز 20',2,45,'gi_rx','omeprazole|cap',false,false,9),
 (1404,'ANTINAL 200MG 24 CAP','انتينال',3,42,'stomach_simple','nifuroxazide|cap',false,false,14),
 (1405,'MOTILIUM 10MG 30 TAB','موتيليوم',3,58,'stomach_simple','domperidone|tab',false,false,8),
 (1406,'SPASMO-DIGESTIN 20 TAB','سبازمو دايجستين',2,40,'stomach_simple','digestive enzymes|tab',false,false,7),
 (1407,'GAVISCON 200ML SYRUP','جافيسكون شراب',1,98,'stomach_simple','alginate|syrup',false,false,6),
 (1408,'DULCOLAX 5MG 30 TAB','دولكولاكس',3,36,'stomach_simple','bisacodyl|tab',false,false,5),
 (1501,'CONGESTAL 20 TAB','كونجستال',2,42,'cold_allergy','paracetamol+chlorphenamine+pseudoephedrine|tab',false,false,16),
 (1502,'COMTREX 20 TAB','كومتريكس',2,46,'cold_allergy','paracetamol+chlorphenamine+pseudoephedrine|tab',false,false,12),
 (1503,'OTRIVIN 0.1% NASAL SPRAY','اوتريفين بخاخ',1,52,'cold_allergy','xylometazoline|spray',false,false,10),
 (1504,'TELFAST 180MG 20 TAB','تلفاست 180',2,152,'cold_allergy','fexofenadine|tab',false,false,7),
 (1505,'ZYRTEC 10MG 20 TAB','زيرتك 10',2,74,'cold_allergy','cetirizine|tab',false,false,8),
 (1506,'BRONCHICUM SYRUP 100ML','برونشيكم شراب',1,62,'cold_allergy','thyme|syrup',false,false,7),
 (1507,'VENTOLIN INHALER','فنتولين بخاخة',1,68,'respiratory_rx','salbutamol|inhaler',false,false,5),
 (1601,'VITACID C 1000MG 10 EFF','فيتاسيد سي فوار',1,42,'vitamins_supplements','vitamin c|eff',false,false,14),
 (1602,'CENTRUM 30 TAB','سنتروم',1,420,'vitamins_supplements','multivitamin|tab',false,false,4),
 (1603,'OCTA D3 DROPS 15ML','اوكتا د3 نقط',1,77,'vitamins_supplements','vitamin d|drops',false,false,6),
 (1604,'MILGA 30 TAB','ميلجا',3,102,'vitamins_supplements','vitamin b complex|tab',false,false,8),
 (1605,'NEUROTON 30 TAB','نيوروتون',3,72,'vitamins_supplements','vitamin b complex|tab',false,false,7),
 (1606,'FERROGLOBIN 30 CAP','فيروجلوبين',3,185,'vitamins_supplements','iron|cap',false,false,4),
 (1607,'OMEGA 3 PLUS 30 CAP','اوميجا 3 بلس',3,230,'vitamins_supplements','omega 3|cap',false,false,4),
 (1701,'CIPRALEX 10MG 28 TAB','سيبراليكس 10',4,240,'neuro_psych','escitalopram|tab',false,false,3),
 (1702,'TRAMADOL 50MG 10 CAP','ترامادول 50',1,48,'controlled_pain','tramadol|cap',true,false,2),
 (1703,'NEUROVIT 20 TAB','نيوروفيت',2,64,'vitamins_supplements','vitamin b complex|tab',false,false,5),
 (1801,'FUCIDIN CREAM 15G','فيوسيدين كريم',1,64,'skin_drug','fusidic acid|cream',false,false,7),
 (1802,'BEPANTHEN CREAM 30G','بيبانثين كريم',1,118,'skin_drug','dexpanthenol|cream',false,false,8),
 (1803,'MEBO OINTMENT 30G','ميبو مرهم',1,92,'skin_drug','beta sitosterol|ointment',false,false,5),
 (1804,'VICHY CAPITAL SOLEIL SPF50','فيشي واقي شمس',1,980,'cosmetic',null,false,false,2),
 (1805,'LA ROCHE CICAPLAST 40ML','لاروش سيكابلاست',1,720,'cosmetic',null,false,false,2),
 (1901,'BEBELAC 2 400G','بيبيلاك 2',1,399,'baby','infant formula 2|powder',false,false,6),
 (1902,'SIMILAC 2 400G','سيميلاك 2',1,420,'baby','infant formula 2|powder',false,false,5),
 (1903,'PAMPERS SIZE 4 44','بامبرز مقاس 4',1,520,'baby',null,false,false,5),
 (1904,'DISFLATYL DROPS 30ML','ديسفلاتيل نقط',1,48,'baby','simethicone|drops',false,false,7),
 (2001,'SYRINGE 3CC','سرنجة 3 سم',1,3,'supplies_devices',null,false,false,20),
 (2002,'ALCOHOL 70% 120ML','كحول 70%',1,25,'supplies_devices',null,false,false,8),
 (2003,'GLUCOSE TEST STRIPS 50','شرايط سكر 50',1,340,'supplies_devices',null,false,false,3),
 (2004,'SURGICAL MASK 50','كمامات 50',1,120,'supplies_devices',null,false,false,3),
 (2005,'BLOOD PRESSURE MONITOR','جهاز ضغط',1,1450,'supplies_devices',null,false,false,1),
 (2006,'COTTON 100G','قطن 100 جم',1,30,'supplies_devices',null,false,false,6),
 (2007,'ELASTIC BANDAGE 10CM','رباط ضاغط 10 سم',1,45,'supplies_devices',null,false,false,4),
 (2008,'THERMOMETER DIGITAL','ترمومتر ديجيتال',1,95,'supplies_devices',null,false,false,3),
 (2009,'ORS SACHETS 10','محلول معالجة الجفاف',1,30,'stomach_simple','oral rehydration|sachet',false,false,6),
 (2010,'PANADOL CHILD SYRUP 100ML','بنادول أطفال شراب',1,48,'baby','paracetamol|syrup',false,false,9);

insert into stage.items (code, name_en, name_ar, pack_parts, public_price, category, gkey, is_controlled, is_fridge, needs_rx, barcodes)
select code, name_en, name_ar, parts, price, cat, gkey, ctrl, fridge,
       cat in ('antibiotic', 'blood_pressure_heart', 'anticoagulant', 'cholesterol', 'diabetes', 'gi_rx', 'respiratory_rx', 'neuro_psych', 'controlled_pain'),
       array['622' || lpad((code * 7919 % 9999999999)::text, 10, '0')]
from demo_items;

insert into stage.locations values ('S1', 'المخزن الرئيسي', 'main', null, true, true), ('S2', 'مخزن انتظار ابن سينا', 'waiting', 'IBNSINA', false, false);
insert into stage.suppliers (code, name, kind) values
  ('NEWCITY', 'مخزن نيو سيتي', 'warehouse'), ('AMG', 'مخزن AMG', 'warehouse'), ('REDA', 'مخزن رضا عطية', 'warehouse'),
  ('ELFATH', 'مخزن الفتح', 'warehouse'), ('PHARMA', 'فارما', 'company'), ('IBNSINA', 'ابن سينا', 'company');
create temp table demo_sup (n int, code text, disc numeric);
insert into demo_sup values (0, 'NEWCITY', 28), (1, 'AMG', 26.5), (2, 'REDA', 25.5), (3, 'ELFATH', 25.7), (4, 'PHARMA', 22), (5, 'IBNSINA', 23);

insert into stage.customers (code, name, phones, credit_limit, area, created_at)
select 'C' || n, nm, array['010' || lpad((20000000 + n * 7351)::text, 8, '0')], lim, area, (ph.business_day() - 400 + n)::timestamp
from (values
  (1,'الحاج سيد عبد الله',3000,'المنيل'),(2,'مدام هالة محمود',1500,'جاردن سيتي'),(3,'أ. محمود فتحي',1000,'المنيل'),(4,'الحاجة نعمات',2000,'الروضة'),
  (5,'م. كريم سامي',0,'المعادي'),(6,'د. أميرة رضا',0,'جاردن سيتي'),(7,'عم حسن',500,'المنيل'),(8,'أم يوسف',800,'الروضة'),
  (9,'أ. عادل منصور',1500,'المنيل'),(10,'مدام سلوى',0,'قصر العيني'),(11,'الحاج عبد الفتاح',2500,'الروضة'),(12,'نادية إبراهيم',0,'المنيل'),
  (13,'شريف منير',0,'المعادي'),(14,'رانيا عصام',600,'المنيل'),(15,'محمد جمال',0,'الروضة'),(16,'أحمد طارق',0,'جاردن سيتي'),
  (17,'منى صلاح',1000,'المنيل'),(18,'إيمان فوزي',0,'الروضة'),(19,'هشام بدر',0,'قصر العيني'),(20,'سامية علي',1200,'المنيل'),
  (21,'الحاج رشاد',2000,'الروضة'),(22,'مدام عفاف',0,'المنيل'),(23,'أ. سمير',800,'المنيل'),(24,'ياسمين حسام',0,'المعادي'),
  (25,'الحاجة فاطمة',1500,'الروضة'),(26,'عمرو دياب الجزار',0,'المنيل'),(27,'خالد مصطفى',0,'جاردن سيتي'),(28,'دعاء محمد',0,'المنيل'),
  (29,'م. وليد',1000,'الروضة'),(30,'أم كريم',700,'المنيل'),(31,'الحاج صبري',2500,'الروضة'),(32,'هبة الله',0,'المنيل'),
  (33,'سيد البقال',600,'المنيل'),(34,'نرمين عادل',0,'المعادي'),(35,'أ. فوزية',0,'المنيل'),(36,'طارق الشاذلي',0,'الروضة'),
  (37,'مدام نجلاء',1000,'المنيل'),(38,'الحاج محمود',1800,'الروضة'),(39,'لبنى يسري',0,'جاردن سيتي'),(40,'عم سعيد',400,'المنيل')
) c(n, nm, lim, area);

-- ---------------------------------------------------------------- الشرا: كل صنف كل 7–14 يوم، من مورده وأحيانًا من مورد تاني
create temp table demo_days as
select d::date as d from generate_series(ph.business_day() - 150, ph.business_day() - 1, interval '1 day') d;
create temp table demo_buys as
select i.code, k, (ph.business_day() - 150 + (i.code % 9) + k * (16 - least(i.w, 30) / 3))::date as d,
       ((i.code + case when k % 3 = 0 then 1 else 0 end) % 6) as sup,
       greatest(1, ceil(i.w * (16 - least(i.w, 30) / 3) * 0.5))::int as packs,   -- حوالي بيع الفترة + 15%
       case when k % 4 = 0 then 1 else 0 end as with_bonus
from demo_items i, generate_series(0, 30) k
where (ph.business_day() - 150 + (i.code % 9) + k * (16 - least(i.w, 30) / 3)) < ph.business_day();
insert into stage.purchases (doc_key, legacy_no, supplier_code, supplier_doc_no, at, location_code, paid)
select 'P' || b.code || '_' || b.k, null, s.code, s.code || '-' || b.code || b.k, b.d + time '11:30', 'S1', 0
from demo_buys b join demo_sup s on s.n = b.sup;
insert into stage.purchase_lines (doc_key, line_no, item_code, batch_key, packs, bonus_packs, public_price, cost_total, expiry)
select 'P' || b.code || '_' || b.k, 1, b.code, 'B' || b.code || '_' || b.k, b.packs,
       case when b.with_bonus = 1 then greatest(1, b.packs / 10) else 0 end, i.price,
       round(b.packs * i.price * (1 - (s.disc + (random()::numeric * 4 - 2)) / 100), 2),
       b.d + 380 + (random()::numeric * 520)::int
from demo_buys b join demo_items i on i.code = b.code join demo_sup s on s.n = b.sup;
-- أصناف عليها تشغيلة قربت تخلص (عشان «توقّع الصلاحية»)
update stage.purchase_lines l set expiry = ph.business_day() + 18 + ((l.item_code % 7) * 9)::int
where l.item_code in (1008, 1107, 1407, 1603, 1904, 1305, 1506, 1803)
  and l.doc_key = (select 'P' || l.item_code || '_' || (max(b.k) - 1) from demo_buys b where b.code = l.item_code);
update stage.purchase_lines set packs = packs * 4, cost_total = cost_total * 4 where expiry < ph.business_day() + 90;
insert into stage.batches (batch_key, item_code, expiry, public_price, unit_cost)
select l.batch_key, l.item_code, l.expiry, l.public_price, round(l.cost_total / ((l.packs + l.bonus_packs) * i.parts), 4)
from stage.purchase_lines l join demo_items i on i.code = l.item_code;

-- ---------------------------------------------------------------- البيع: 120–230 تذكرة في اليوم، الذروة بالليل
create temp table demo_w as
select code, parts, price, sum(w) over (order by code) - w as lo, sum(w) over (order by code) as hi from demo_items;
create temp table demo_tk as
select row_number() over (order by x.at) as n, x.*
from (
  select d.d, (d.d + make_interval(hours => hr, mins => (random()::numeric * 59)::int))::timestamp as at,
         case when random()::numeric < 0.11 then 'C' || (1 + (random()::numeric * 39)::int) end as cust,
         case when random()::numeric < 0.08 then (random()::numeric * 6)::int else 0 end as disc
  from demo_days d
  cross join lateral generate_series(1, 120 + (random()::numeric * 110)::int + case when extract(dow from d.d) in (4, 5) then 30 else 0 end) t
  cross join lateral (select (array[9,10,10,11,11,12,12,12,13,13,14,14,15,15,16,16,17,17,17,18,18,18,19,19,19,19,20,20,20,20,20,21,21,21,21,22,22,22,23,23,24,24,25])[1 + floor(random()::numeric * 43 + 0 * t)::int] as hr) h
) x;
insert into stage.sales (doc_key, legacy_no, at, location_code, customer_code, kind, discount, paid)
select 'T' || t.n, (100000 + t.n)::text, t.at, 'S1', t.cust, 'sale', t.disc,
       case when t.cust is not null and c.credit_limit > 0 and random()::numeric < 0.55 then 0 else 999999 end
from demo_tk t left join stage.customers c on c.code = t.cust;
-- عملاء بطّلوا ييجوا من حوالي شهرين (لتقرير «عملاء بطلوا ييجوا»)
update stage.sales set customer_code = null, paid = 999999
where customer_code in ('C26', 'C27', 'C34', 'C36', 'C39') and at > (ph.business_day() - 55)::timestamp;
insert into stage.sale_lines (doc_key, line_no, item_code, batch_key, qty_units, unit_price, line_total)
select 'T' || t.n, ln, w.code, null, q.qty, round(w.price / w.parts, 4), round(q.qty * w.price / w.parts, 2)
from demo_tk t
cross join lateral generate_series(1, 1 + (random()::numeric + 0 * t.n < 0.45)::int + (random()::numeric + 0 * t.n < 0.15)::int) ln
cross join lateral (select random()::numeric * (select max(hi) from demo_w) + 0 * ln as r) rr
cross join lateral (select * from demo_w where hi > rr.r order by hi limit 1) w
cross join lateral (select case when w.parts > 1 and random()::numeric < 0.3 then 1 + (random()::numeric * (w.parts - 2))::int
                                else w.parts * (1 + (random()::numeric < 0.12)::int) end as qty) q;
delete from stage.sale_lines a using stage.sale_lines b
where a.doc_key = b.doc_key and a.item_code = b.item_code and a.line_no > b.line_no;

-- عملاء مزمنين: نفس الصنف كل 28–31 يوم
insert into stage.sales (doc_key, legacy_no, at, location_code, customer_code, kind, discount, paid)
select 'CH' || c.n || '_' || k, null, (ph.business_day() - 148 + c.n * 3 + k * c.every + (random()::numeric * 2)::int) + time '20:15', 'S1', 'C' || c.n, 'sale', 0,
       case when c.n in (1, 4, 11) then 0 else 999999 end
from (values (1, 1201, 30), (2, 1301, 30), (3, 1208, 30), (4, 1206, 29), (9, 1304, 28), (11, 1303, 30), (17, 1203, 31),
             (20, 1301, 30), (21, 1207, 30), (25, 1205, 28), (31, 1604, 30), (38, 1209, 30)) c(n, item, every)
cross join generate_series(0, 4) k
where (ph.business_day() - 148 + c.n * 3 + k * c.every) < ph.business_day() - 1;
insert into stage.sale_lines (doc_key, line_no, item_code, batch_key, qty_units, unit_price, line_total)
select 'CH' || c.n || '_' || k, 1, c.item, null, i.parts, round(i.price / i.parts, 4), i.price
from (values (1, 1201, 30), (2, 1301, 30), (3, 1208, 30), (4, 1206, 29), (9, 1304, 28), (11, 1303, 30), (17, 1203, 31),
             (20, 1301, 30), (21, 1207, 30), (25, 1205, 28), (31, 1604, 30), (38, 1209, 30)) c(n, item, every)
cross join generate_series(0, 4) k join demo_items i on i.code = c.item
where exists (select 1 from stage.sales s where s.doc_key = 'CH' || c.n || '_' || k);

-- مرتجعات قليلة
insert into stage.sales (doc_key, legacy_no, at, location_code, customer_code, kind, ref_doc_key, discount, paid)
select 'R' || t.n, null, t.at + interval '26 hours', 'S1', t.cust, 'return', 'T' || t.n, 0, 999999
from demo_tk t where t.n % 211 = 0 and t.at + interval '26 hours' < ph.business_day()::timestamp;
insert into stage.sale_lines (doc_key, line_no, item_code, batch_key, qty_units, unit_price, line_total)
select 'R' || substr(l.doc_key, 2), 1, l.item_code, null, l.qty_units, l.unit_price, l.line_total
from stage.sale_lines l where l.line_no = 1 and exists (select 1 from stage.sales s where s.doc_key = 'R' || substr(l.doc_key, 2));

-- التحصيل: العملاء بيدفعوا كل أسبوع تقريبًا آجل الأسبوع اللي قبله
insert into stage.payments (doc_key, at, kind, party_code, amount)
select 'Y' || x.cust || '_' || x.wk, (x.wk_start + 7) + time '13:00', 'from_customer', x.cust, round(x.credit * 0.97)
from (
  select s.customer_code as cust, date_trunc('week', s.at)::date as wk_start, to_char(s.at, 'IYYYIW') as wk, sum(l.line_total) as credit
  from stage.sales s join stage.sale_lines l on l.doc_key = s.doc_key
  where s.paid = 0 and s.kind = 'sale' group by 1, 2, 3
) x where x.wk_start + 7 < ph.business_day() and x.credit > 20;
-- السداد للموردين: كل 10 أيام حوالي 80% من شرا الفترة
insert into stage.payments (doc_key, at, kind, party_code, amount)
select 'V' || x.sup || '_' || x.slot, (ph.business_day() - 150 + x.slot * 10 + 12) + time '12:00', 'to_supplier', x.sup, round(x.cost * 0.8)
from (
  select p.supplier_code as sup, ((p.at::date - (ph.business_day() - 150)) / 10) as slot, sum(l.cost_total) as cost
  from stage.purchases p join stage.purchase_lines l on l.doc_key = p.doc_key group by 1, 2
) x where ph.business_day() - 150 + x.slot * 10 + 12 < ph.business_day();

-- ---------------------------------------------------------------- رصيد أول المدة، وجرد قبل النهارده، والرصيد النهارده
create temp table demo_rate as
select i.code as item_code, i.parts,
       coalesce((select sum(l.qty_units) from stage.sale_lines l join stage.sales s on s.doc_key = l.doc_key
                  where s.kind = 'sale' and l.item_code = i.code), 0) / 150.0 as per_day
from demo_items i;
-- أول المدة: رصيد 25 يوم في تشغيلة لوحدها
insert into stage.batches (batch_key, item_code, expiry, public_price, unit_cost)
select 'B' || i.code || '_open', i.code, ph.business_day() + 150 + (i.code % 11) * 20, i.price, round(i.price * 0.74 / i.parts, 4)
from demo_items i;
insert into stage.adjustments (doc_key, line_no, legacy_no, at, location_code, item_code, batch_key, qty_units, reason)
select 'OPEN', row_number() over (order by r.item_code), 'جرد أول المدة', (ph.business_day() - 151) + time '08:00', 'S1', r.item_code,
       'B' || r.item_code || '_open', ceil(r.per_day * 25 / r.parts) * r.parts + r.parts, 'count'
from demo_rate r;
-- اللي فاضل حسب التاريخ لكل صنف
create temp table demo_left as
select r.item_code, r.parts, r.per_day,
       coalesce((select sum(a.qty_units) from stage.adjustments a where a.item_code = r.item_code), 0)
     + coalesce((select sum((l.packs + l.bonus_packs) * r.parts) from stage.purchase_lines l join stage.purchases p on p.doc_key = l.doc_key
                  where not p.is_return and l.item_code = r.item_code), 0)
     - coalesce((select sum(l.qty_units) from stage.sale_lines l join stage.sales s on s.doc_key = l.doc_key
                  where s.kind = 'sale' and l.item_code = r.item_code), 0)
     + coalesce((select sum(l.qty_units) from stage.sale_lines l join stage.sales s on s.doc_key = l.doc_key
                  where s.kind = 'return' and l.item_code = r.item_code), 0) as left_units
from demo_rate r;
-- اللي المفروض يفضل: النواقص قليل، والتشغيلات اللي قربت تخلص مليانة (اتشرت زيادة)، والباقي من 6 لـ 30 يوم بيع
create temp table demo_target as
select d.*, case
    when d.item_code in (1101, 1201, 1301, 1404, 1501, 1601, 1006, 1105, 1504, 1902, 2003, 1702, 2005) then floor(d.per_day * 1.2)
    when d.item_code in (1008, 1107, 1407, 1603, 1904, 1305, 1506, 1803) then ceil(d.per_day * 95 / d.parts) * d.parts
    else least(greatest(d.left_units, ceil(d.per_day * 6 / d.parts) * d.parts), ceil(d.per_day * 30 / d.parts) * d.parts) end as target
from demo_left d;
-- جرد من يومين: الفرق بين التاريخ واللي المفروض
insert into stage.adjustments (doc_key, line_no, legacy_no, at, location_code, item_code, batch_key, qty_units, reason)
select 'CNT', row_number() over (order by t.item_code), 'جرد آخر الشهر', (ph.business_day() - 2) + time '08:30', 'S1', t.item_code,
       'B' || t.item_code || '_open', t.target - t.left_units, 'count'
from demo_target t where t.target <> t.left_units;
-- تحويل لمخزن انتظار ابن سينا
insert into stage.adjustments (doc_key, line_no, legacy_no, at, location_code, item_code, batch_key, qty_units, reason)
select 'TRF', row_number() over (order by x.code, x.sgn), 'تحويل', (ph.business_day() - 3) + time '10:00', x.loc, x.code, 'B' || x.code || '_open', x.qty, 'transfer'
from (select i.code, s.sgn, case when s.sgn < 0 then 'S1' else 'S2' end as loc, s.sgn * i.parts * 3 as qty
      from demo_items i cross join (values (-1), (1)) s(sgn) where i.code in (1102, 1209, 1402)) x;
-- الرصيد النهارده على التشغيلات: الأحدث شرا يفضل والأقدم يخلص الأول (زي البيع الفعلي من الأقرب صلاحية)
insert into stage.current_stock (location_code, item_code, batch_key, qty_units)
select 'S1', b.item_code, b.batch_key, greatest(0, least(b.units, t.target - 3 * (case when t.item_code in (1102, 1209, 1402) then t.parts else 0 end) - (b.cum - b.units)))
from (
  select x.*, sum(x.units) over (partition by x.item_code order by x.d desc, x.batch_key desc) as cum
  from (
    select l.item_code, l.batch_key, p.at as d, (l.packs + l.bonus_packs) * i.parts as units
    from stage.purchase_lines l join stage.purchases p on p.doc_key = l.doc_key and not p.is_return join demo_items i on i.code = l.item_code
    union all
    select r.item_code, 'B' || r.item_code || '_open', (ph.business_day() - 151)::timestamp, 1e9 from demo_rate r
  ) x
) b join demo_target t on t.item_code = b.item_code
where greatest(0, least(b.units, t.target - 3 * (case when t.item_code in (1102, 1209, 1402) then t.parts else 0 end) - (b.cum - b.units))) > 0;
insert into stage.current_stock (location_code, item_code, batch_key, qty_units)
select 'S2', i.code, 'B' || i.code || '_open', i.parts * 3 from demo_items i where i.code in (1102, 1209, 1402);

select ph.import_history('بيانات تجريبية', (ph.business_day()::timestamp + interval '6 hours') at time zone 'Africa/Cairo') - 'issues' as imported;
update ph.suppliers set code = legacy_id;
update ph.customers set source = 'counter';

-- ---------------------------------------------------------------- اليوزرات والقواعد
select auth.bootstrap_owner('taher', 'demo-pass-1', 'د. طاهر') as owner_id \gset
select set_config('request.jwt.claim.sub', :'owner_id', false);
select ph.create_user('cashier', 'demo-pass-1', 'محمد (كاشير)', 'cashier') as cashier_id \gset
select ph.create_user('pharmacist', 'demo-pass-1', 'د. سارة', 'pharmacist');
select ph.create_user('bot', null, 'بوت النواقص', 'bot');
insert into ph.item_stock_rules (item_id, min_units, max_units)
select i.code, ceil(r.per_day * 4), ceil(r.per_day * 16) from demo_items i join demo_rate r on r.item_code = i.code where r.per_day >= 0.6;
insert into ph.supplier_offers (supplier_id, item_id, source, discount_pct, quota, raw_text, offered_at)
select s.id, i.code, 'whatsapp', d.disc + (random()::numeric * 3 - 1), case when random()::numeric < 0.3 then 'كوته 2' end, i.name_ar || ' متاح', now() - (random()::numeric * interval '5 hours')
from demo_items i cross join demo_sup d join ph.suppliers s on s.code = d.code
where i.code in (1101, 1201, 1301, 1404, 1501, 1601, 1006, 1105, 1504, 1902) and random()::numeric < 0.55;
select ph.add_chronic(c.id, 1201, 30) from ph.customers c where c.legacy_id = 'C1';
select ph.add_chronic(c.id, 1206, 29) from ph.customers c where c.legacy_id = 'C4';
select ph.add_chronic(c.id, 1304, 28) from ph.customers c where c.legacy_id = 'C9';
update ph.customer_meds m set last_bought = current_date - m.every_days + (case when c.legacy_id = 'C1' then 2 else -3 end)
  from ph.customers c where c.id = m.customer_id and c.legacy_id in ('C1', 'C4');

-- ---------------------------------------------------------------- للتقارير: مصروفات، طلبيات اتبعتت، المتجر، أسعار اتغيرت، صور، راكد
update ph.items set sell_by_unit = false where pack_parts = 1;
update ph.items set image_path = 'store/' || id || '.jpg' where (id * 7) % 10 < 5;   -- نص الأصناف تقريبًا ليها صورة

-- المصروفات (تاريخ بس: الخزن بتبدأ من يوم التشغيل، زي النقل الحقيقي)
insert into ph.expense_categories (name) values ('إيجار'), ('مرتبات'), ('كهربا ومية'), ('نت وتليفون'), ('نظافة وصيانة'), ('نثريات');
do $$
declare r record;
begin
  for r in
    select x.d, c.id as cat, x.amount, x.note from (
      select m::date as d, 'إيجار' as cat, 12000::numeric as amount, 'إيجار الشهر' as note from generate_series(date_trunc('month', ph.business_day() - 150), ph.business_day() - 1, interval '1 month') m
      union all select (m + interval '27 days')::date, 'مرتبات', 28500, 'مرتبات الشهر' from generate_series(date_trunc('month', ph.business_day() - 150), ph.business_day() - 1, interval '1 month') m
      union all select (m + interval '9 days')::date, 'كهربا ومية', round(1700 + random()::numeric * 900), 'فاتورة الكهربا والمية' from generate_series(date_trunc('month', ph.business_day() - 150), ph.business_day() - 1, interval '1 month') m
      union all select (m + interval '4 days')::date, 'نت وتليفون', 650, 'النت والأرضي' from generate_series(date_trunc('month', ph.business_day() - 150), ph.business_day() - 1, interval '1 month') m
      union all select (m + interval '14 days')::date, 'نظافة وصيانة', round(350 + random()::numeric * 700), 'نظافة وصيانة التكييف' from generate_series(date_trunc('month', ph.business_day() - 150), ph.business_day() - 1, interval '1 month') m
      union all select d::date, 'نثريات', round(120 + random()::numeric * 300), 'شاي وأكياس وفكة' from generate_series(ph.business_day() - 150, ph.business_day() - 1, interval '6 days') d
    ) x join ph.expense_categories c on c.name = x.cat
    where x.d between ph.business_day() - 150 and ph.business_day() - 1
    order by x.d, x.amount desc
  loop
    insert into ph.expenses (no, category_id, amount, account_id, business_day, at, note)
    values (ph.next_doc_no('EX', 1::smallint, r.d), r.cat, r.amount, 2, r.d, (r.d + time '13:00') at time zone 'Africa/Cairo', r.note);
  end loop;
end $$;

-- الطلبيات الليلية في آخر 30 يوم: كل فاتورة شرا قبلها طلبية بالليل، وساعات صنف زيادة ماوصلش
do $$
declare r record; v_id bigint; v_at timestamptz;
begin
  for r in select pi.id, pi.supplier_id, pi.invoice_date from ph.purchase_invoices pi
           where pi.status = 'posted' and pi.invoice_date between ph.business_day() - 30 and ph.business_day() - 1 order by pi.invoice_date, pi.id loop
    v_at := ((r.invoice_date - 1) + time '22:30') at time zone 'Africa/Cairo';
    insert into ph.purchase_orders (no, supplier_id, status, message_text, created_at, sent_at)
    values (ph.next_doc_no('PO', 1::smallint, r.invoice_date - 1), r.supplier_id, 'sent', 'طلبية الليل', v_at, v_at) returning id into v_id;
    insert into ph.purchase_order_lines (order_id, item_id, packs)
    select v_id, l.item_id, l.packs from ph.purchase_invoice_lines l where l.invoice_id = r.id;
    if random() < 0.22 then   -- صنف اتطلب وماجاش
      insert into ph.purchase_order_lines (order_id, item_id, packs)
      select v_id, i.id, 2 from ph.items i where i.id not in (select l.item_id from ph.purchase_invoice_lines l where l.invoice_id = r.id)
      order by random() limit 1;
    end if;
  end loop;
  -- طلبية من يومين لسه ماوصلتش
  v_at := ((ph.business_day() - 2) + time '22:40') at time zone 'Africa/Cairo';
  insert into ph.purchase_orders (no, supplier_id, status, message_text, created_at, sent_at)
  values (ph.next_doc_no('PO', 1::smallint, ph.business_day() - 2), (select id from ph.suppliers where code = 'AMG'), 'sent', 'طلبية الليل', v_at, v_at) returning id into v_id;
  insert into ph.purchase_order_lines (order_id, item_id, packs) values (v_id, 1301, 3), (v_id, 1504, 2), (v_id, 1902, 4);
end $$;

-- طلبات المتجر في آخر 30 يوم (أسامي متخيّلة)
insert into ph.online_orders (created_at, name, phone, address, notes, items, total, status, delivery_fee)
select at, nm, '0111' || lpad((3000000 + k * 7919 % 999999)::text, 7, '0'), 'المنيل، شارع ' || (k % 9 + 1), null,
       jsonb_build_array(jsonb_build_object('item_id', i.id, 'name', i.name_en, 'packs', 1 + k % 2, 'price', i.public_price)),
       i.public_price * (1 + k % 2), st, 15
from (
  select k, (now() - make_interval(days => (k * 37) % 30, hours => (k * 5) % 9)) as at,
         (array['أ. منة', 'م. سامح', 'رحاب', 'أبو علي', 'د. نهى', 'كريم', 'سلمى', 'عم فتحي'])[1 + k % 8] as nm,
         case when k <= 2 then 'new' when k = 3 then 'confirmed' when k = 4 then 'out' when k % 9 = 0 then 'cancelled' else 'delivered' end as st,
         (array[1001, 1101, 1201, 1404, 1501, 1702, 2006, 2008, 1005, 1302])[1 + k % 10] as item
  from generate_series(1, 34) k
) x join ph.items i on i.id = x.item;

-- أسعار اتغيرت (البضاعة القديمة بتفضل بسعرها المطبوع)
alter table ph.items disable trigger items_price_log;
create temp table demo_price (id bigint, pct numeric, ago int);
insert into demo_price values (1001, 12, 3), (1101, 15, 9), (1201, 8, 16), (1404, 10, 22), (1702, -5, 27), (2008, 20, 34);
insert into ph.price_changes (item_id, old_price, new_price, changed_at, source)
select i.id, i.public_price, round(i.public_price * (1 + d.pct / 100)), now() - make_interval(days => d.ago), 'manual'
from demo_price d join ph.items i on i.id = d.id;
update ph.items i set public_price = round(i.public_price * (1 + d.pct / 100)) from demo_price d where d.id = i.id;
alter table ph.items enable trigger items_price_log;

-- أصناف راكدة: رصيد قديم مابيتحركش (فلوس نايمة)
insert into ph.items (id, name_en, name_ar, category_id, pack_parts, public_price, sell_by_unit)
select v.id, v.en, v.ar, (select id from ph.categories where code = v.cat), 1, v.price, false
from (values (3001, 'VICHY NORMADERM GEL 200ML', 'فيشي نورماديرم جل', 'cosmetic', 690),
             (3002, 'NEBULIZER COMPRESSOR', 'جهاز بخار', 'supplies_devices', 1850),
             (3003, 'BIODERMA SENSIBIO H2O 500ML', 'بيوديرما سنسيبيو', 'cosmetic', 820),
             (3004, 'WALKING CANE ADJUSTABLE', 'عكاز ألومنيوم', 'supplies_devices', 380),
             (3005, 'BABY BOTTLE STERILIZER', 'جهاز تعقيم رضّاعات', 'baby', 1450)) v(id, en, ar, cat, price);
select ph.post_opening_stock(1::smallint, jsonb_agg(jsonb_build_object('item_id', id, 'packs', n, 'expiry', (current_date + 500 + (id % 7)::int * 30)::text, 'unit_cost', round(public_price * 0.78, 2))), 'رصيد قديم')
from (select i.id, i.public_price, (array[4, 2, 5, 3, 2])[i.id - 3000] as n from ph.items i where i.id between 3001 and 3005) x;

-- ---------------------------------------------------------------- النهارده: وردية وبيع حقيقي من الكاشير
select set_config('request.jwt.claim.sub', :'cashier_id', false);
select ph.open_shift(1::smallint, 500) as shift_id \gset
select set_config('demo.shift', :'shift_id', false);
do $$
declare
  v_shift  bigint := current_setting('demo.shift')::bigint;
  v_start  timestamptz := (ph.business_day()::timestamp + interval '9 hours') at time zone 'Africa/Cairo';
  v_span   interval := greatest(now() - ((ph.business_day()::timestamp + interval '9 hours') at time zone 'Africa/Cairo'), interval '30 minutes');
  v_n      integer := least(110, greatest(25, (extract(epoch from v_span) / 600)::integer));
  k        integer;
  it       record;
  v_item   bigint;
  v_cust   bigint;
  v_method text;
  v_at     timestamptz;
  v_sale   jsonb;
  v_total  numeric;
begin
  for k in 1 .. v_n loop
    v_at := least(now() - interval '2 minutes', v_start + v_span * (k::numeric / v_n) * (0.6 + random()::numeric * 0.4));
    select o.item_id into v_item from ph.v_onhand o join ph.items i on i.id = o.item_id
     where o.units >= i.pack_parts * 2 and not i.is_controlled and i.id < 3000 order by random()::numeric limit 1;
    continue when v_item is null;
    select p.id, p.pack_parts, p.price_pack into it from ph.pos_lookup(v_item::text, 1) p;
    v_total := it.price_pack;
    v_method := (array['cash', 'cash', 'cash', 'card', 'wallet'])[1 + (random()::numeric * 4)::int];
    v_cust := null;
    if k % 9 = 0 then
      select c.id into v_cust from ph.v_customer_pick c where c.credit_limit - c.balance > v_total order by random()::numeric limit 1;
    end if;
    begin
      v_sale := ph.post_sale(jsonb_build_object('client_uuid', gen_random_uuid(), 'at', v_at, 'shift_id', v_shift,
                  'customer_id', v_cust, 'lines', jsonb_build_array(jsonb_build_object('item_id', it.id, 'packs', 1)),
                  'payments', case when v_cust is not null then '[]'::jsonb
                                   else jsonb_build_array(jsonb_build_object('method', v_method, 'amount', v_total)) end));
    exception when others then null;   -- صنف خلص في النص: نكمل
    end;
  end loop;
end $$;
select ph.post_payment(jsonb_build_object('kind', 'from_customer', 'party_id', (select id from ph.customers where legacy_id = 'C2'), 'amount', 200, 'shift_id', :shift_id));

select set_config('request.jwt.claim.sub', :'owner_id', false);
select ph.mark_ordered(jsonb_build_object('supplier_id', (select id from ph.suppliers where code = 'NEWCITY'), 'message', 'طلبية تجريبية',
                       'items', jsonb_build_array(jsonb_build_object('item_id', 1404, 'packs', 10, 'expected_pct', 28))));
insert into ph.trial_notes (area, severity, note) values
  ('sales', 'idea', 'زرار «آخر فاتورة» في الكاشير عشان نطبعها تاني بسرعة'),
  ('stock', 'annoyance', 'عايز أشوف مكان الصنف على الرف في البحث');
select set_config('request.jwt.claim.sub', '', false);
select (select count(*) from ph.sales) as sales, (select count(*) from ph.sales where business_day = ph.business_day()) as sales_today,
       (select count(*) from ph.health_check() where not ok) as health_failures;
