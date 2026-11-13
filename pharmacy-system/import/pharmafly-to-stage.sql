-- ربط جداول فارمافلاي (pf_raw، من copy.py) بالشكل الموحّد (stage). بعده: select ph.import_history('…');
-- مكتوب على اللي اتأكد من النسخة الحقيقية (MAPPING.md، جدول «اللي اتأكد»). من غير داتا: أسامي جداول وأعمدة وقواعد بس.
--
-- الاختيارات اللي لسه بتتقاس (pf_raw.map_options): غيّرها بـ update قبل التشغيل، وأعد النقل في قاعدة فاضية، وقارن
-- عدد balance_reconciled و stock_reconciled في ph.import_issues. الاختيار الصح = الأقل فروق.
--   ticket_discount    subtract: العميل دفع الإجمالي − Discount (الافتراضي) | ignore: Discount مش بيتطرح
--   customer_pay_ops   أكواد CashFlow اللي تتنقل تحصيل من عميل (موجب = تحصيل، سالب = رجّعناله). الافتراضي 4,15.
--                      2 مش داخل لأنه غالبًا نفس فلوس تذكرة التحصيل/البيع (متسجل مرتين). جرّب 2,4,15 لو الفروق كتير
--   zero_tickets       on: تذاكر الصفر (Total = 0) تحصيل (الافتراضي) | off
--   supplier_pay_ops   أكواد الدفع لمورد (الافتراضي 9,55: المبلغ بالسالب = دفعناله)
--   customer_balance   cards_credit: رصيد العميل النهارده = Cards.Credit (الافتراضي) | last_ticket: آخر NewBalance في التذاكر
--                      | none: خطر، زي supplier_balance
--   supplier_balance   cards_credit: رصيد المورد = Cards.Credit (الافتراضي) | cards_credit_neg: عكس الإشارة (لو كل الموردين طلعوا فرق)
--                      | none: خطر، النقل بيعتبر رصيد كل مورد صفر ويسوّيه
--   waiting_stock      false: مخازن الانتظار (5، 6، 7) مش بتتحسب في الرصيد اللي بيتباع (الافتراضي) | true
--   from_ts            أقدم وقت يتنقل (التذاكر اللي تاريخها 1980 غلط). الافتراضي 2017-01-01
-- كله في عملية واحدة: يا يتملى stage كله يا ولا حاجة.

create table if not exists pf_raw.map_options (k text primary key, v text not null);
insert into pf_raw.map_options values
  ('ticket_discount', 'subtract'), ('customer_pay_ops', '4,15'), ('zero_tickets', 'on'), ('supplier_pay_ops', '9,55'),
  ('customer_balance', 'cards_credit'), ('supplier_balance', 'cards_credit'), ('waiting_stock', 'false'), ('from_ts', '2017-01-01')
on conflict (k) do nothing;

begin;
truncate stage.locations, stage.suppliers, stage.customers, stage.items, stage.batches, stage.purchases, stage.purchase_lines,
         stage.sales, stage.sale_lines, stage.payments, stage.adjustments, stage.current_stock, stage.current_balances;

create temp table o on commit drop as select k, v from pf_raw.map_options;
create function pg_temp.opt(p text) returns text language sql stable as $$ select v from pg_temp.o where k = p $$;
-- الصلاحية: سنين غريبة (8466، 2206، 1900) = مش معروفة
create function pg_temp.exp(d timestamp) returns date language sql immutable as $$
  select case when d >= '2015-01-01' and d < '2041-01-01' then d::date end $$;
-- مفتاح التشغيلة = الصنف + الصلاحية (فارمافلاي مابيسجلش رقم تشغيلة)
create function pg_temp.bkey(item bigint, d timestamp) returns text language sql immutable as $$
  select case when pg_temp.exp(d) is not null then item || ':' || pg_temp.exp(d) end $$;

-- ---------------------------------------------------------------- المخازن
insert into stage.locations (code, name, kind, counts_as_stock, is_default_sale)
select s."ID"::text,
       coalesce(nullif(btrim(s."Name"), ''), 'مخزن ' || s."ID"),
       case when s."ID" = 1 then 'main' when s."ID" = 2 or s."Name" like '%هالك%' or s."Name" like '%منته%' then 'damaged'
            when s."Name" like '%انتظار%' then 'waiting' else 'main' end,
       case when s."ID" = 1 then true when s."ID" = 2 or s."Name" like '%هالك%' or s."Name" like '%منته%' then false
            when s."Name" like '%انتظار%' then pg_temp.opt('waiting_stock')::boolean else false end,
       s."ID" = 1
from pf_raw."Stores" s;
-- مخازن مذكورة في الحركة ومش في Stores (زي 8)
insert into stage.locations (code, name, kind, counts_as_stock, is_default_sale)
select x.id::text, 'مخزن ' || x.id || ' (من فارمافلاي)', 'main', false, false
from (select "StoreID" id from pf_raw."Work" union select "StoreID" from pf_raw."posTickets"
      union select "StoreID" from pf_raw."PurchaseInvoices" union select "FromId" from pf_raw."Transfers" union select "ToId" from pf_raw."Transfers") x
where x.id is not null and not exists (select 1 from stage.locations l where l.code = x.id::text);

-- ---------------------------------------------------------------- الموردين والعملاء (Cards)
insert into stage.suppliers (code, name, kind)
select c."Id"::text, coalesce(nullif(btrim(c."Name"), ''), 'مورد ' || c."Id"), 'warehouse'
from pf_raw."Cards" c where coalesce(c."IsVendor", false);

-- التليفون مكتوب جوه الاسم: بيتشال من الاسم ويتحط في التليفونات
insert into stage.customers (code, name, phones, credit_limit, created_at)
select c."Id"::text,
       coalesce(nullif(btrim(regexp_replace(regexp_replace(coalesce(c."Name", ''), '(\+?2)?0?1[0125][0-9]{8}', ' ', 'g'),
                                            '[\s\-_/\\()،,.:]+', ' ', 'g')), ''), 'عميل ' || c."Id"),
       array(select distinct '0' || m[1]
             from regexp_matches(coalesce(c."Name", '') || ' ' || coalesce((select string_agg(t."Tel", ' ') from pf_raw."Telephones" t
                                                                             where t."CustomerID" = c."Id"), ''),
                                 '(?:\+?2)?0?(1[0125][0-9]{8})', 'g') m),
       case when c."CreditLimit" > 0 then c."CreditLimit" end,
       case when c."JoiningDate" >= '2000-01-01' and c."JoiningDate" <= now() then c."JoiningDate" end
from pf_raw."Cards" c where not coalesce(c."IsVendor", false);

-- ---------------------------------------------------------------- الأصناف
-- Items.barcode فيه قيمة متكررة على آلاف الأصناف: بيتاخد بس لو بتاع صنف واحد. الباركود الحقيقي في CrossRefrences
insert into stage.items (code, name_en, name_ar, pack_parts, public_price, category, is_fridge, active, barcodes)
select i."ID",
       coalesce(nullif(btrim(i."name"), ''), 'ITEM ' || i."ID"),
       case when i."DESCRIPTION" ~ '[ء-ي]' then btrim(i."DESCRIPTION") end,
       greatest(1, coalesce(i."Parts", 1)),
       i."SalesPrice",
       c."name",
       coalesce(i."FridgeItem", false),
       coalesce(i."IsActive", true) and not coalesce(i."Archived", false),
       array(select distinct btrim(r."ref") from pf_raw."CrossRefrences" r
             where r."itemID" = i."ID" and coalesce(r."IsActive", true) and btrim(r."ref") ~ '^[0-9]{7,16}$'
             union
             select i."barcode"::text where i."barcode" > 0 and bc.n = 1)
from pf_raw."Items" i left join pf_raw."Categories" c on c."id" = i."form_id"
left join (select "barcode", count(*) n from pf_raw."Items" group by 1) bc on bc."barcode" = i."barcode";

-- ---------------------------------------------------------------- الشرا ومرتجع الشرا
-- الوقت = وقت الإدخال (ztime): inv_date فيه سنين غلط. رقم فاتورة المورد = inv_code
insert into stage.purchases (doc_key, legacy_no, supplier_code, supplier_doc_no, at, location_code, is_return, paid)
select 'P' || p."ID", p."ID"::text, p."vendor_id"::text, nullif(btrim(p."inv_code"), ''), p."ztime",
       coalesce(p."StoreID", 1)::text, p."SalesReturn" = 2, 0
from pf_raw."PurchaseInvoices" p
where p."ztime" >= pg_temp.opt('from_ts')::timestamp and p."ztime" <= now()
  and exists (select 1 from stage.suppliers s where s.code = p."vendor_id"::text);

-- العلب = علب + وحدات ÷ عدد العلبة. التكلفة = CostPrice (تكلفة العلبة بعد خصم المورد) × العلب. البونص لوحده
insert into stage.purchase_lines (doc_key, line_no, item_code, batch_key, packs, bonus_packs, public_price, cost_total, expiry)
select 'P' || l."inv_id", row_number() over (partition by l."inv_id" order by l."ID"), l."item_id",
       pg_temp.bkey(l."item_id", l."expirydate"),
       abs(coalesce(l."packs", 0) + coalesce(l."units", 0)::numeric / greatest(1, coalesce(i."Parts", 1))),
       greatest(0, coalesce(l."bonus", 0)), nullif(l."sprice", 0)::numeric,
       round(abs(coalesce(l."CostPrice", 0) * (coalesce(l."packs", 0) + coalesce(l."units", 0)::numeric / greatest(1, coalesce(i."Parts", 1))))::numeric, 2),
       pg_temp.exp(l."expirydate")
from pf_raw."PurchaseItems" l
join pf_raw."Items" i on i."ID" = l."item_id"
where exists (select 1 from stage.purchases p where p.doc_key = 'P' || l."inv_id")
  and coalesce(l."packs", 0) + coalesce(l."units", 0) <> 0;

-- ---------------------------------------------------------------- البيع والمرتجع (posTickets)
-- SalesReturn: 1 بيع، 2 مرتجع. السطر = SalesPrice × (Packs + Units ÷ iParts)، والكمية بالوحدة = Packs × iParts + Units.
-- صنف 1 («أصناف متنوعة») بسعر صفر = سطر وهمي في تذاكر التحصيل: مايتنقلش. السطر اللي إشارته عكس التذكرة مايتنقلش.
create temp table t_lines on commit drop as
select l."TicketID" as tid, l."ID" as lid, l."ItemID" as item,
       abs(coalesce(l."Packs", 0) * greatest(1, coalesce(l."iParts", 1)) + coalesce(l."Units", 0))::numeric as qty,
       round(abs(coalesce(l."SalesPrice", 0) * (coalesce(l."Packs", 0) + coalesce(l."Units", 0)::numeric / greatest(1, coalesce(l."iParts", 1))))::numeric, 2) as val,
       sign(coalesce(l."Packs", 0) * greatest(1, coalesce(l."iParts", 1)) + coalesce(l."Units", 0)) as sgn,
       pg_temp.bkey(l."ItemID", l."ExpDate") as bkey
from pf_raw."posItems" l
where not (l."ItemID" = 1 and coalesce(l."SalesPrice", 0) = 0)
  and coalesce(l."Packs", 0) * greatest(1, coalesce(l."iParts", 1)) + coalesce(l."Units", 0) <> 0;

create temp table t_tix on commit drop as
select t."ID" as tid, t."ztime" as at, coalesce(t."StoreID", 1)::text as loc,
       case when t."CustomerID" > 0 and exists (select 1 from stage.customers c where c.code = t."CustomerID"::text) then t."CustomerID"::text end as cust,
       case when t."SalesReturn" = 2 then 'return' else 'sale' end as kind,
       coalesce(t."Total", 0)::numeric as total, coalesce(t."Discount", 0)::numeric as disc, coalesce(t."PaidByCustomer", 0)::numeric as paid,
       coalesce(case when t."SalesReturn" = 2 then x.neg else x.pos end, 0) as st
from pf_raw."posTickets" t
left join (select tid, sum(val) filter (where sgn > 0) as pos, sum(val) filter (where sgn < 0) as neg
           from pg_temp.t_lines group by tid) x on x.tid = t."ID"
where t."ztime" >= pg_temp.opt('from_ts')::timestamp and t."ztime" <= now();

insert into stage.sales (doc_key, legacy_no, at, location_code, customer_code, kind, discount, paid)
select 'T' || x.tid, x.tid::text, x.at, x.loc, x.cust, x.kind, x.d,
       case when x.kind = 'sale' then least(greatest(x.paid, 0), x.st - x.d)
            else least(greatest(-x.paid, 0), x.st - x.d) end   -- المرتجع: اللي رجع كاش
from (select t.*, case when pg_temp.opt('ticket_discount') = 'subtract' then least(greatest(abs(t.disc), 0), t.st) else 0 end as d
      from pg_temp.t_tix t where t.st > 0) x;

insert into stage.sale_lines (doc_key, line_no, item_code, batch_key, qty_units, unit_price, line_total)
select 'T' || l.tid, row_number() over (partition by l.tid order by l.lid), l.item, l.bkey, l.qty,
       round(l.val / l.qty, 4), l.val
from pg_temp.t_lines l join pg_temp.t_tix t on t.tid = l.tid
where t.st > 0 and l.sgn = case when t.kind = 'return' then -1 else 1 end;

-- ---------------------------------------------------------------- التحصيل والسداد
-- (أ) تذاكر الصفر: تحصيل من العميل (PaidByCustomer)
insert into stage.payments (doc_key, legacy_no, at, kind, party_code, amount)
select 'TZ' || t.tid, t.tid::text, t.at, case when t.paid > 0 then 'from_customer' else 'to_customer' end, t.cust, abs(t.paid)
from pg_temp.t_tix t
where pg_temp.opt('zero_tickets') = 'on' and t.st = 0 and t.total = 0 and t.paid <> 0 and t.cust is not null;
-- (ب) العميل دفع في تذكرة البيع أكتر من إجماليها = الباقي سداد من حسابه
insert into stage.payments (doc_key, legacy_no, at, kind, party_code, amount)
select 'TX' || s.doc_key, s.legacy_no, s.at, 'from_customer', s.customer_code, t.paid - (t.st - s.discount)
from stage.sales s join pg_temp.t_tix t on 'T' || t.tid = s.doc_key
where s.kind = 'sale' and s.customer_code is not null and t.paid > t.st - s.discount + 0.009;
-- (ج) الخزنة: تحصيل من العملاء بالأكواد اللي في الاختيارات
insert into stage.payments (doc_key, legacy_no, at, kind, party_code, amount)
select 'CF' || f."ID", f."ID"::text, f."ztime", case when f."Amount" > 0 then 'from_customer' else 'to_customer' end,
       f."DealerID"::text, abs(f."Amount")::numeric
from pf_raw."CashFlow" f
where f."Operation"::text = any (string_to_array(pg_temp.opt('customer_pay_ops'), ','))
  and f."DealerID" > 0 and f."Amount" <> 0 and f."ztime" >= pg_temp.opt('from_ts')::timestamp and f."ztime" <= now()
  and exists (select 1 from stage.customers c where c.code = f."DealerID"::text);
-- (د) الدفع للموردين: بالسالب = دفعناله
insert into stage.payments (doc_key, legacy_no, at, kind, party_code, amount)
select 'CF' || f."ID", f."ID"::text, f."ztime", 'to_supplier', f."DealerID"::text, -f."Amount"::numeric
from pf_raw."CashFlow" f
where f."Operation"::text = any (string_to_array(pg_temp.opt('supplier_pay_ops'), ','))
  and f."DealerID" > 0 and f."Amount" < 0 and f."ztime" >= pg_temp.opt('from_ts')::timestamp and f."ztime" <= now()
  and exists (select 1 from stage.suppliers s where s.code = f."DealerID"::text)
on conflict (doc_key) do nothing;

-- ---------------------------------------------------------------- التشغيلات (الصنف + الصلاحية)
-- التكلفة = آخر تكلفة شرا لنفس الصنف والصلاحية، وإلا آخر تكلفة للصنف، وإلا Items.CostPrice
insert into stage.batches (batch_key, item_code, expiry, public_price, unit_cost)
select k.bkey, k.item, split_part(k.bkey, ':', 2)::date, i."SalesPrice",
       coalesce(cb.c, ci.c, nullif(i."CostPrice", 0)) / greatest(1, coalesce(i."Parts", 1))
from (select distinct batch_key as bkey, item_code as item from stage.purchase_lines where batch_key is not null
      union select bkey, item from pg_temp.t_lines where bkey is not null
      union select pg_temp.bkey(w."item_id", w."exp_date"), w."item_id" from pf_raw."Work" w where pg_temp.exp(w."exp_date") is not null) k
join pf_raw."Items" i on i."ID" = k.item
left join (select distinct on (pg_temp.bkey("item_id", "expirydate")) pg_temp.bkey("item_id", "expirydate") as bkey, "CostPrice" as c
           from pf_raw."PurchaseItems" where "CostPrice" > 0 and pg_temp.exp("expirydate") is not null
           order by pg_temp.bkey("item_id", "expirydate"), "ID" desc) cb on cb.bkey = k.bkey
left join (select distinct on ("item_id") "item_id", "CostPrice" as c from pf_raw."PurchaseItems" where "CostPrice" > 0
           order by "item_id", "ID" desc) ci on ci."item_id" = k.item;

-- ---------------------------------------------------------------- الرصيد النهارده (Work) للمطابقة
insert into stage.current_stock (location_code, item_code, batch_key, qty_units)
select w."StoreID"::text, w."item_id", pg_temp.bkey(w."item_id", w."exp_date"),
       coalesce(w."Packs", 0) * greatest(1, coalesce(i."Parts", 1)) + coalesce(w."Units", 0)
from pf_raw."Work" w join pf_raw."Items" i on i."ID" = w."item_id"
where coalesce(w."Packs", 0) * greatest(1, coalesce(i."Parts", 1)) + coalesce(w."Units", 0) <> 0;

-- ---------------------------------------------------------------- رصيد العملاء والموردين النهارده
insert into stage.current_balances (party_type, party_code, balance)
select 'customer', c.code,
       coalesce(case pg_temp.opt('customer_balance') when 'cards_credit' then k."Credit" when 'last_ticket' then lt."NewBalance" end, 0)::numeric
from stage.customers c
left join pf_raw."Cards" k on k."Id"::text = c.code
left join (select distinct on ("CustomerID") "CustomerID", "NewBalance" from pf_raw."posTickets" where "CustomerID" > 0
           order by "CustomerID", "ID" desc) lt on lt."CustomerID"::text = c.code
where pg_temp.opt('customer_balance') <> 'none';
insert into stage.current_balances (party_type, party_code, balance)
select 'supplier', s.code, case pg_temp.opt('supplier_balance') when 'cards_credit_neg' then -k."Credit" else k."Credit" end
from stage.suppliers s join pf_raw."Cards" k on k."Id"::text = s.code
where pg_temp.opt('supplier_balance') in ('cards_credit', 'cards_credit_neg');

-- ---------------------------------------------------------------- الملخص (أعداد بس)
select 'stage' as what,
       (select count(*) from stage.items) items, (select count(*) from stage.customers) customers, (select count(*) from stage.suppliers) suppliers,
       (select count(*) from stage.sales where kind = 'sale') sales, (select count(*) from stage.sales where kind = 'return') returns,
       (select count(*) from stage.sale_lines) sale_lines, (select count(*) from stage.purchases) purchases,
       (select count(*) from stage.purchase_lines) purchase_lines, (select count(*) from stage.payments) payments,
       (select count(*) from stage.current_stock) stock_rows, (select count(*) from stage.current_balances) balances,
       (select count(*) from pg_temp.t_tix where st = 0 and total <> 0) tickets_without_lines,
       (select count(*) from pf_raw."posTickets" where "ztime" < pg_temp.opt('from_ts')::timestamp or "ztime" > now()) tickets_bad_date;
commit;
