-- =====================================================================================================
-- ربط فارمافلاي ← stage (Postgres). بيقرا pf_raw (نسخة جداول فارمافلاي زي ما هي، import/copy.py) ويملا stage.*.
-- بعده: select ph.import_history('pharmafly <التاريخ>');
-- القواعد من MAPPING.md و profile.py (الجولة 1 و 2) على النسخة الحقيقية (13 نوفمبر 2026). مفيش داتا هنا، قواعد بس.
--   - التذكرة: SalesReturn 1 = بيع، 2 = مرتجع (الإجمالي والسطور بالسالب). Total قبل الخصم، Discount مبلغ،
--     PaidByCustomer = اللي اتدفع. رصيد العميل بعدها = اللي قبله + Total − Discount − PaidByCustomer.
--   - تذكرة Total = 0 = تحصيل (أو رد فلوس) مش بيع، وسطرها «أصناف متنوعة» (صنف 1) مايتنقلش.
--   - سطر البيع: السعر للعلبة، الكمية بالوحدة = Packs × iParts + Units، والقيمة = SalesPrice × (Packs + Units ÷ iParts).
--   - التحصيل قبل أغسطس 2021: CashFlow.Operation = 4 (من غير تذكرة). بعدها Operation 2 نسخة من التذكرة: مايتاخدش.
--   - دفع المورد: CashFlow.Operation = 9 (بالسالب).
--   - التشغيلة = «رقم الصنف:الصلاحية» (yyyy-mm-dd) في البيع والشرا والرصيد. من غير صلاحية = من غير تشغيلة.
--   - التاريخ الغلط (قبل 2018 أو بعد وقت النسخة): أقرب تاريخ سليم قبله أو بعده بالترتيب (رقم التذكرة)، أو وقت الإدخال (ztime).
-- =====================================================================================================
\set ON_ERROR_STOP on
begin;

truncate stage.locations, stage.suppliers, stage.customers, stage.items, stage.batches, stage.purchases, stage.purchase_lines,
         stage.sales, stage.sale_lines, stage.payments, stage.adjustments, stage.current_stock, stage.current_balances;

-- وقت النسخة = آخر تذكرة. أي تاريخ بعده أو قبل 2018 غلط
create temp table t_lim on commit drop as
select timestamp '2018-01-01' as lo, (select max("ztime") from pf_raw."posTickets" where "ztime" < now() + interval '1 day') + interval '1 hour' as hi;

-- ---------------------------------------------------------------- المخازن
insert into stage.locations (code, name, kind, counts_as_stock, is_default_sale)
select s."ID"::text, coalesce(nullif(btrim(s."Name"), ''), 'مخزن ' || s."ID"),
       case when s."ID" = 1 then 'main' when s."ID" = 2 then 'damaged' when s."Name" like '%انتظار%' then 'waiting' else 'main' end,
       s."ID" <> 2, s."ID" = 1
from pf_raw."Stores" s;

-- ---------------------------------------------------------------- الموردين والعملاء (كلهم في Cards)
insert into stage.suppliers (code, name, kind)
select c."Id"::text, coalesce(nullif(btrim(c."Name"), ''), 'مورد ' || c."Id"), 'warehouse'
from pf_raw."Cards" c
where coalesce(c."IsVendor", false) or c."Id" in (select "vendor_id" from pf_raw."PurchaseInvoices");

-- التليفون جوه الاسم (179 عميل) أو في Telephones
create temp table t_cust on commit drop as
select c."Id", c."Name", c."CreditLimit", c."District", c."AddressDetails", c."JoiningDate",
       array(select m[1] from regexp_matches(coalesce(c."Name", ''), '(01[0125][0-9]{8})', 'g') m) as name_phones
from pf_raw."Cards" c
where not coalesce(c."IsVendor", false) and c."Id" not in (select code::bigint from stage.suppliers);

insert into stage.customers (code, name, phones, credit_limit, area, address, created_at)
select c."Id"::text,
       coalesce(nullif(btrim(regexp_replace(regexp_replace(coalesce(c."Name", ''), '01[0125][0-9]{8}', '', 'g'), '^[\s\-_/.:,]+|[\s\-_/.:,]+$', '', 'g')), ''),
                nullif(btrim(c."Name"), ''), 'عميل ' || c."Id"),
       c.name_phones || coalesce(array(select t."Tel" from pf_raw."Telephones" t where t."CustomerID" = c."Id" and t."Tel" is not null order by t."ID"), '{}'),
       nullif(c."CreditLimit", 0), nullif(btrim(c."District"), ''), nullif(btrim(c."AddressDetails"), ''),
       case when c."JoiningDate" >= (select lo from t_lim) then c."JoiningDate" end
from t_cust c;

-- ---------------------------------------------------------------- الأصناف (صنف 1 «أصناف متنوعة» مايتنقلش)
-- الباركود: CrossRefrences.ref + Items.barcode لو مش الرقم المتكرر على آلاف الأصناف
create temp table t_badbar on commit drop as
select "barcode" from pf_raw."Items" where "barcode" > 0 group by 1 having count(*) > 5;

insert into stage.items (code, name_en, name_ar, pack_parts, public_price, category, is_fridge, active, barcodes)
select i."ID", coalesce(nullif(btrim(i."name"), ''), 'ITEM ' || i."ID"),
       case when i."DESCRIPTION" ~ '[ء-ي]' then btrim(i."DESCRIPTION") when i."name" ~ '[ء-ي]' then btrim(i."name") end,
       -- السعر أقل من نص قرش بيتقرّب لصفر والقاعدة بترفضه: يتساب فاضي
       greatest(1, coalesce(i."Parts", 1)), case when i."SalesPrice" >= 0.005 then i."SalesPrice" end, cat."name",
       coalesce(i."FridgeItem", false),
       coalesce(i."IsActive", true) and not coalesce(i."Archived", false) and not coalesce(i."FreezedItem", false),
       array(select distinct b from (
               select btrim(x."ref") as b from pf_raw."CrossRefrences" x where x."itemID" = i."ID" and coalesce(x."IsActive", true)
               union all
               select i."barcode"::text where i."barcode" > 0 and i."barcode" <> 100000 + i."ID"
                                         and i."barcode" not in (select "barcode" from t_badbar)) z
             where b is not null and b <> '')
from pf_raw."Items" i
left join pf_raw."Categories" cat on cat."id" = i."form_id";
-- صنف 1 «أصناف متنوعة»: سطره في تذكرة الدفع (بصفر) مايتنقلش، بس فيه بيع حقيقي بسعر عليه (آلاف التذاكر، منها على
-- حسابات عملاء). من غيره إجمالي التذكرة وحساب العميل مايطابقوش فارمافلاي. فبيتنقل كصنف خدمة.

-- عدد الوحدات في العلبة لكل صنف (للتحويل)
create temp table t_parts on commit drop as
select code as id, pack_parts as parts from stage.items;

-- ---------------------------------------------------------------- التذاكر: تاريخ مظبوط لكل تذكرة
create temp table t_tk on commit drop as
with x as (
  select t.*, case when t."ztime" >= l.lo and t."ztime" <= l.hi then t."ztime" end as ok_t
  from pf_raw."posTickets" t cross join t_lim l
)
select x.*, coalesce(x.ok_t,
         (select y."ztime" from pf_raw."posTickets" y, t_lim l where y."ID" < x."ID" and y."ztime" between l.lo and l.hi order by y."ID" desc limit 1),
         (select y."ztime" from pf_raw."posTickets" y, t_lim l where y."ID" > x."ID" and y."ztime" between l.lo and l.hi order by y."ID" limit 1)) as at_ok
from x;
create index on t_tk ("ID");

-- السطور بالوحدة والقيمة
create temp table t_ln on commit drop as
select p."ID", p."TicketID", p."ItemID",
       coalesce(nullif(p."iParts", 0), pt.parts, 1) as parts,
       p."Packs" * coalesce(nullif(p."iParts", 0), pt.parts, 1) + p."Units" as qty_units,
       p."SalesPrice" * (p."Packs" + p."Units"::numeric / coalesce(nullif(p."iParts", 0), pt.parts, 1)) as value,
       p."SalesPrice" / coalesce(nullif(p."iParts", 0), pt.parts, 1) as unit_price,
       case when p."ExpDate" is not null then p."ItemID" || ':' || to_char(p."ExpDate", 'YYYY-MM-DD') end as batch_key
from pf_raw."posItems" p
left join t_parts pt on pt.id = p."ItemID"
where p."ItemID" <> 1 or p."SalesPrice" <> 0;   -- صنف 1 بصفر (سطر تذكرة الدفع) مايتنقلش

-- البيع والمرتجع (التذاكر اللي إجماليها مش صفر)
-- المرتجع: كل حاجة بالموجب في stage (النوع هو اللي بيحدد الاتجاه). paid للمرتجع = اللي رجع كاش
-- السطور بالقرش (زي ما import_history بيقرّبها)
insert into stage.sale_lines (doc_key, line_no, item_code, batch_key, qty_units, unit_price, line_total)
select 'T' || l."TicketID", row_number() over (partition by l."TicketID" order by l."ID"), l."ItemID", l.batch_key,
       case when t."Total" < 0 then -l.qty_units else l.qty_units end, abs(l.unit_price),
       round((case when t."Total" < 0 then -l.value else l.value end)::numeric, 2)
from t_ln l join t_tk t on t."ID" = l."TicketID"
where t."Total" <> 0 and t.at_ok is not null;

-- صافي التذكرة = فارمافلاي بالظبط (Total − Discount، بالموجب للمرتجع). مجموع السطور مش دايمًا = Total
-- (900 تذكرة تقريبًا، وكسور القروش): الفرق بيتحسب خصم، عشان الصافي وحساب العميل يطابقوا فارمافلاي
-- السطور أقل من صافي التذكرة:
--   أقل من جنيه = كسور قروش (تقريب كل سطر لقرش): الفرق بيتحط على آخر سطر.
--   جنيه أو أكتر (سعر اتعدّل أو سطر اتمسح في فارمافلاي): سطر «أصناف متنوعة» (صنف 1) بالفرق، عشان العميل يتحاسب
--   على اللي فارمافلاي حاسبه عليه من غير ما سعر صنف حقيقي يتغير.
create temp table t_gap on commit drop as
select 'T' || t."ID" as doc_key, s.last_no,
       round(abs(t."Total" - coalesce(t."Discount", 0))::numeric, 2) - coalesce(s.st, 0) as gap
from t_tk t
left join (select doc_key, sum(line_total) as st, max(line_no) as last_no from stage.sale_lines
           where qty_units > 0 and line_total >= 0 group by 1) s on s.doc_key = 'T' || t."ID"
where t."Total" <> 0 and t.at_ok is not null;
update stage.sale_lines l set line_total = l.line_total + d.gap
from t_gap d where l.doc_key = d.doc_key and l.line_no = d.last_no and d.gap > 0 and d.gap < 1;
insert into stage.sale_lines (doc_key, line_no, item_code, batch_key, qty_units, unit_price, line_total)
select d.doc_key, (select coalesce(max(line_no), 0) + 1 from stage.sale_lines l where l.doc_key = d.doc_key), 1, null, 1, d.gap, d.gap
from t_gap d where d.gap >= 1 or (d.gap > 0 and d.last_no is null);

create temp table t_st on commit drop as
select doc_key, sum(line_total) as st from stage.sale_lines where qty_units > 0 and line_total >= 0 group by 1;

insert into stage.sales (doc_key, legacy_no, at, location_code, customer_code, kind, discount, paid)
select 'T' || t."ID", t."ID"::text, t.at_ok, coalesce(t."StoreID", 1)::text,
       case when t."CustomerID" > 0 then t."CustomerID"::text end,
       case when t."Total" < 0 then 'return' else 'sale' end,
       greatest(coalesce(s.st, 0) - round(abs(t."Total" - coalesce(t."Discount", 0))::numeric, 2), 0),
       round((case when t."Total" < 0 then -coalesce(t."PaidByCustomer", 0) else coalesce(t."PaidByCustomer", 0) end)::numeric, 2)
from t_tk t
left join t_st s on s.doc_key = 'T' || t."ID"
where t."Total" <> 0 and t.at_ok is not null;

-- ---------------------------------------------------------------- التحصيل
-- (أ) تذكرة الصفر: PaidByCustomer موجب = تحصيل، سالب = رد فلوس للعميل
insert into stage.payments (doc_key, legacy_no, at, kind, party_code, amount)
select 'T' || t."ID", t."ID"::text, t.at_ok,
       case when t."PaidByCustomer" > 0 then 'from_customer' else 'to_customer' end,
       t."CustomerID"::text, round(abs(t."PaidByCustomer")::numeric, 2)
from t_tk t
where t."Total" = 0 and t."CustomerID" > 0 and abs(t."PaidByCustomer") >= 0.005 and t.at_ok is not null;
-- (ب) العميل دفع في تذكرة البيع أكتر من صافيها: الزيادة تحصيل من حسابه
insert into stage.payments (doc_key, legacy_no, at, kind, party_code, amount)
select 'T' || t."ID" || 'X', t."ID"::text, t.at_ok, 'from_customer', t."CustomerID"::text,
       round((t."PaidByCustomer" - (t."Total" - coalesce(t."Discount", 0)))::numeric, 2)
from t_tk t
where t."Total" > 0 and t."CustomerID" > 0 and t.at_ok is not null
  and t."PaidByCustomer" - (t."Total" - coalesce(t."Discount", 0)) >= 0.005;
-- (ب2) مرتجع رجعله كاش أكتر من قيمة المرتجع: الزيادة رد فلوس للعميل
insert into stage.payments (doc_key, legacy_no, at, kind, party_code, amount)
select 'T' || t."ID" || 'X', t."ID"::text, t.at_ok, 'to_customer', t."CustomerID"::text,
       round((-t."PaidByCustomer" - abs(t."Total" - coalesce(t."Discount", 0)))::numeric, 2)
from t_tk t
where t."Total" < 0 and t."CustomerID" > 0 and t.at_ok is not null
  and -t."PaidByCustomer" - abs(t."Total" - coalesce(t."Discount", 0)) >= 0.005;
-- (ج) قبل أغسطس 2021: Operation 4 في الخزنة
insert into stage.payments (doc_key, legacy_no, at, kind, party_code, amount)
select 'C' || f."ID", 'C' || f."ID", f."ztime", case when f."Amount" > 0 then 'from_customer' else 'to_customer' end,
       f."DealerID"::text, round(abs(f."Amount")::numeric, 2)
from pf_raw."CashFlow" f cross join t_lim l
where f."Operation" = 4 and f."DealerID" > 0 and abs(f."Amount") >= 0.005 and f."ztime" between l.lo and l.hi
  and f."DealerID"::text in (select code from stage.customers);
-- (د) الدفع للمورد: Operation 9 (و 55) بالسالب
insert into stage.payments (doc_key, legacy_no, at, kind, party_code, amount)
select 'C' || f."ID", 'C' || f."ID", f."ztime", 'to_supplier', f."DealerID"::text, round(-f."Amount"::numeric, 2)
from pf_raw."CashFlow" f cross join t_lim l
where f."Operation" in (9, 55) and f."DealerID" > 0 and f."Amount" <= -0.005 and f."ztime" between l.lo and l.hi
  and f."DealerID"::text in (select code from stage.suppliers);

-- ---------------------------------------------------------------- الشرا والمرتجع للمورد
-- التاريخ: inv_date، إلا لو غلط أو بعيد عن وقت الإدخال بأكتر من 30 يوم ← ztime
insert into stage.purchases (doc_key, legacy_no, supplier_code, supplier_doc_no, at, location_code, is_return, paid)
select 'P' || i."ID", i."ID"::text, i."vendor_id"::text, nullif(btrim(i."inv_code"), ''),
       case when i."inv_date" between l.lo and l.hi and abs(extract(epoch from (i."inv_date" - i."ztime"))) <= 30 * 86400 then i."inv_date"
            else i."ztime" end,
       coalesce(i."StoreID", 1)::text, i."SalesReturn" = 2, 0
from pf_raw."PurchaseInvoices" i cross join t_lim l
where i."vendor_id" > 0
  and (i."inv_date" between l.lo and l.hi or i."ztime" between l.lo and l.hi);

insert into stage.purchase_lines (doc_key, line_no, item_code, batch_key, packs, bonus_packs, public_price, cost_total, expiry)
select 'P' || p."inv_id", row_number() over (partition by p."inv_id" order by p."ID"), p."item_id",
       case when p."expirydate" is not null then p."item_id" || ':' || to_char(p."expirydate", 'YYYY-MM-DD') end,
       abs(p."packs" + p."units"::numeric / coalesce(pt.parts, 1)), greatest(coalesce(p."bonus", 0), 0),
       case when p."sprice" >= 0.005 then p."sprice" end,
       -- تكلفة العلبة = CostPrice، ولو فاضية: sprice × (1 − trade_discount ÷ 100)
       -- بالقرش: إجمالي الفاتورة = مجموع السطور زي ما هي متسجلة (فحص health_check)
       round(abs(coalesce(p."CostPrice", p."sprice" * (1 - coalesce(p."trade_discount", 0) / 100), 0)
           * (p."packs" + p."units"::numeric / coalesce(pt.parts, 1)))::numeric, 2),
       p."expirydate"::date
from pf_raw."PurchaseItems" p
join stage.purchases h on h.doc_key = 'P' || p."inv_id"
left join t_parts pt on pt.id = p."item_id"
where p."item_id" <> 1;

-- ---------------------------------------------------------------- الجرد والتالف وباقي حركات كارت الصنف
-- ItemCards فيه 28 نوع عملية من غير أسامي. اتجربت على النسخة: العمليات دي بس هي اللي بتقرّب رصيد الصنف من Work
-- (من 6,507 صنف مطابق لـ 10,943 من 12,117 صنف ليهم كارت): 5 و 6 = الجرد (عجز/زيادة، نفس عدد StockAdjustment)،
-- 10 و 11 و 19 و 25 و 40 و 16 و 17 و 29 = تالف/صرف/تسويات تانية. الكمية بإشارتها (Packs × عدد الوحدات + Units).
-- الباقي (3 و 22 و 26 و 31 و 4 و 15 و 9 و 7 و 14 و 12 و 20/21) مكرر مع البيع/الشرا أو أرقامه مش منطقية: مايتنقلش.
-- مستند لكل (عملية، وقت، مخزن). التاريخ الغلط: السطر بيتساب.
insert into stage.adjustments (doc_key, line_no, legacy_no, at, location_code, item_code, batch_key, qty_units, reason)
select 'IC' || k."Operation" || ':' || to_char(k."ztime", 'YYYYMMDDHH24MISS') || ':' || coalesce(k."StoreID", 1),
       row_number() over (partition by k."Operation", date_trunc('second', k."ztime"), coalesce(k."StoreID", 1) order by k."ID"),
       'IC' || k."ID", k."ztime", coalesce(k."StoreID", 1)::text, k."ItemID",
       case when k."ExpiryDate" is not null then k."ItemID" || ':' || to_char(k."ExpiryDate", 'YYYY-MM-DD') end,
       k."Packs" * coalesce(pt.parts, 1) + k."Units",
       case when k."Operation" in (5, 6) then 'count' else 'other' end
from pf_raw."ItemCards" k cross join t_lim l
join t_parts pt on pt.id = k."ItemID"
where k."Operation" in (5, 6, 10, 11, 16, 17, 19, 25, 29, 40) and k."ItemID" <> 1
  and k."ztime" between l.lo and l.hi and k."Packs" * coalesce(pt.parts, 1) + k."Units" <> 0;

-- ---------------------------------------------------------------- الرصيد النهارده (للمطابقة)
insert into stage.current_stock (location_code, item_code, batch_key, qty_units)
select w."StoreID"::text, w."item_id",
       case when w."exp_date" is not null then w."item_id" || ':' || to_char(w."exp_date", 'YYYY-MM-DD') end,
       w."Packs" * coalesce(pt.parts, 1) + w."Units"
from pf_raw."Work" w left join t_parts pt on pt.id = w."item_id"
where w."item_id" <> 1 and w."Packs" * coalesce(pt.parts, 1) + w."Units" <> 0;

-- العميل: NewBalance في آخر حركة (تذكرة أو Operation 4)، أيهم أحدث
insert into stage.current_balances (party_type, party_code, balance)
select 'customer', x.cid::text, round(x.bal::numeric, 2)   -- بالقرش (زي باقي الفلوس)
from (
  select distinct on (cid) cid, bal
  from (select "CustomerID" as cid, "NewBalance" as bal, "ztime" as t, "ID" as id, 1 as src from pf_raw."posTickets" where "CustomerID" > 0
        union all
        select "DealerID", "NewBalance", "ztime", "ID", 2 from pf_raw."CashFlow" where "Operation" = 4 and "DealerID" > 0) m
  order by cid, t desc, src, id desc
) x
where x.cid::text in (select code from stage.customers) and abs(x.bal) >= 0.005;

-- ---------------------------------------------------------------- التشغيلات (كل مفتاح اتذكر، بسعر وتكلفة آخر شرا ليه)
insert into stage.batches (batch_key, item_code, expiry, public_price, unit_cost)
select k.batch_key, k.item_code, k.expiry, lp.public_price, lp.unit_cost
from (select batch_key, min(item_code) as item_code, min(expiry) as expiry from (
        select batch_key, item_code, expiry from stage.purchase_lines
        union all select batch_key, item_code, split_part(batch_key, ':', 2)::date from stage.sale_lines
        union all select batch_key, item_code, split_part(batch_key, ':', 2)::date from stage.current_stock
        union all select batch_key, item_code, split_part(batch_key, ':', 2)::date from stage.adjustments) a
      where batch_key is not null group by batch_key) k
left join (
  select distinct on (l.batch_key) l.batch_key, l.public_price,
         case when l.packs + l.bonus_packs > 0 then l.cost_total / ((l.packs + l.bonus_packs) * coalesce(pt.parts, 1)) end as unit_cost
  from stage.purchase_lines l join stage.purchases h on h.doc_key = l.doc_key and not h.is_return
  left join t_parts pt on pt.id = l.item_code
  where l.batch_key is not null
  order by l.batch_key, h.at desc) lp on lp.batch_key = k.batch_key
where k.item_code in (select code from stage.items);

commit;

select 'locations' t, count(*) from stage.locations union all select 'suppliers', count(*) from stage.suppliers
union all select 'customers', count(*) from stage.customers union all select 'items', count(*) from stage.items
union all select 'batches', count(*) from stage.batches union all select 'sales', count(*) from stage.sales
union all select 'sale_lines', count(*) from stage.sale_lines union all select 'payments', count(*) from stage.payments
union all select 'purchases', count(*) from stage.purchases union all select 'purchase_lines', count(*) from stage.purchase_lines
union all select 'current_stock', count(*) from stage.current_stock union all select 'current_balances', count(*) from stage.current_balances
union all select 'adjustments', count(*) from stage.adjustments;
