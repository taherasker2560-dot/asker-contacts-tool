#!/usr/bin/env python3
"""(3ب) معنى أكواد فارمافلاي: أعداد ومجاميع بس، من غير ولا اسم عميل ولا تليفون ولا ملاحظة.

الاستخدام:  python3 profile.py <الشغل>
بيكتب <الشغل>/profile.md. بيجاوب على أسئلة ملف الربط (MAPPING.md): المرتجع إزاي، السعر للعلبة ولا للوحدة، الخصم نسبة
ولا مبلغ، أكواد CashFlow، التليفونات فين، والأرصدة. كل سؤال استعلام لوحده: لو واحد وقع بيتكتب الغلط ويكمّل.
قراية بس. نفس الاتصال بتاع discover.py (MSSQL_HOST / MSSQL_USER / MSSQL_PASSWORD / MSSQL_DB).
"""
import os
import sys
import time

from discover import connect

SAMPLE = 20000   # آخر كام تذكرة/فاتورة للمقارنات التقيلة (عشان الجهاز مايتقلش)

# كل سؤال: (العنوان، الاستعلام). الاستعلامات بترجّع أعداد ومجاميع وأكواد بس.
Q = [
    # ------------------------------------------------------------------ التذاكر
    ('التذاكر حسب SalesReturn (أول 15 قيمة)', """
        select top 15 SalesReturn, count(*) n, sum(case when Total < 0 then 1 else 0 end) neg_total,
               round(sum(Total), 0) sum_total, min(ztime) first, max(ztime) last
        from posTickets group by SalesReturn order by count(*) desc"""),
    ('SalesReturn > 1: هل هو رقم تذكرة موجودة؟', """
        select count(*) n,
               sum(case when o.ID is not null then 1 else 0 end) points_to_ticket,
               sum(case when o.ID is not null and o.ID < t.ID then 1 else 0 end) points_to_older_ticket,
               sum(case when t.Total < 0 then 1 else 0 end) neg_total
        from posTickets t left join posTickets o on o.ID = t.SalesReturn where t.SalesReturn > 1"""),
    ('أنواع التذاكر: إجمالي صفر/موجب/سالب، ومدفوع، وعميل', """
        select case when Total > 0 then 'total>0' when Total < 0 then 'total<0' else 'total=0' end kind,
               count(*) n, sum(case when CustomerID > 0 then 1 else 0 end) with_customer,
               sum(case when PaidByCustomer <> 0 then 1 else 0 end) paid_nonzero,
               sum(case when abs(PaidByCustomer - Total) < 0.01 then 1 else 0 end) paid_eq_total,
               sum(case when PaidByCustomer < Total - 0.01 then 1 else 0 end) paid_less,
               sum(case when PaidByCustomer > Total + 0.01 then 1 else 0 end) paid_more,
               sum(case when l.TicketID is null then 1 else 0 end) no_lines
        from posTickets t left join (select distinct TicketID from posItems) l on l.TicketID = t.ID group by case when Total > 0 then 'total>0' when Total < 0 then 'total<0' else 'total=0' end"""),
    ('أعمدة الخصم والتحصيل في التذاكر', """
        select count(*) n,
               sum(case when Discount <> 0 then 1 else 0 end) discount_nz, max(Discount) discount_max,
               sum(case when DiscountPercent <> 0 then 1 else 0 end) discount_pct_nz, max(DiscountPercent) discount_pct_max,
               sum(case when DiscountOnItems <> 0 then 1 else 0 end) disc_on_items_nz,
               sum(case when ChargeValue <> 0 then 1 else 0 end) charge_nz,
               sum(case when SubTotal <> 0 then 1 else 0 end) subtotal_nz,
               sum(case when xPaid <> 0 then 1 else 0 end) xpaid_nz,
               sum(case when Collected = 1 then 1 else 0 end) collected,
               sum(case when VatValue <> 0 or SalesTaxValue <> 0 then 1 else 0 end) tax_nz
        from posTickets"""),
    ('Discount في التذكرة: نسبة ولا مبلغ؟ (التذاكر اللي فيها خصم)', """
        select count(*) n,
               sum(case when abs(DiscountPercent * SubTotal / 100 - Discount) < 0.05 then 1 else 0 end) disc_eq_pct_of_subtotal,
               sum(case when abs(SubTotal - Discount - Total) < 0.05 then 1 else 0 end) total_eq_sub_minus_disc,
               sum(case when abs(SubTotal * (1 - Discount / 100) - Total) < 0.05 then 1 else 0 end) total_eq_sub_times_pct
        from posTickets where Discount <> 0 and SubTotal <> 0"""),
    ('CustomerType و MethodOfPaymentID و StoreID في التذاكر', """
        select 'CustomerType' col, CustomerType v, count(*) n from posTickets group by CustomerType
        union all select 'MethodOfPaymentID', MethodOfPaymentID, count(*) from posTickets group by MethodOfPaymentID
        union all select 'StoreID', StoreID, count(*) from posTickets group by StoreID
        order by 1, 3 desc"""),
    ('التواريخ: ztime و zEndTime و InvoiceDate', """
        select count(*) n,
               sum(case when ztime < '2018-01-01' then 1 else 0 end) ztime_before_2018,
               sum(case when ztime > getdate() + 1 then 1 else 0 end) ztime_future,
               sum(case when zEndTime is null then 1 else 0 end) endtime_null,
               sum(case when InvoiceDate is null then 1 else 0 end) invoicedate_null,
               sum(case when abs(datediff(minute, ztime, zEndTime)) > 60 then 1 else 0 end) end_far_from_start
        from posTickets"""),
    ('الرقم بيمشي مع الوقت؟ (تذاكر رقمها أكبر وتاريخها أقدم من اللي قبلها)', f"""
        select count(*) n, sum(case when ztime < prev then 1 else 0 end) older_than_previous
        from (select top {SAMPLE} ztime, lag(ztime) over (order by ID) prev from posTickets order by ID desc) x"""),
    ('NewBalance في التذاكر = رصيد العميل؟ (اللي قبله + الإجمالي − المدفوع)', f"""
        select count(*) n,
               sum(case when abs(NewBalance - (prev + Total - PaidByCustomer)) < 0.05 then 1 else 0 end) eq_prev_plus_total_minus_paid,
               sum(case when abs(NewBalance - (prev - Total + PaidByCustomer)) < 0.05 then 1 else 0 end) eq_prev_minus_total_plus_paid
        from (select top {SAMPLE} NewBalance, Total, PaidByCustomer,
                     lag(NewBalance) over (partition by CustomerID order by ID) prev
              from posTickets where CustomerID > 0 order by ID desc) x where prev is not null"""),

    # ------------------------------------------------------------------ سطور البيع
    ('سطور البيع: الإشارة والوحدات والبونص', """
        select count(*) n,
               sum(case when p.Packs < 0 or p.Units < 0 then 1 else 0 end) negative_qty,
               sum(case when p.Units <> 0 then 1 else 0 end) units_nz,
               sum(case when p.Packs <> 0 and p.Units <> 0 then 1 else 0 end) packs_and_units,
               sum(case when p.Bonus <> 0 then 1 else 0 end) bonus_nz,
               sum(case when p.IsContent = 1 then 1 else 0 end) is_content,
               sum(case when p.Discount <> 0 then 1 else 0 end) discount_nz, max(p.Discount) discount_max,
               sum(case when p.ExtraDiscount <> 0 then 1 else 0 end) extra_discount_nz,
               sum(case when p.ExpDate is null then 1 else 0 end) expdate_null,
               sum(case when p.SalesPrice = 0 then 1 else 0 end) zero_price,
               sum(case when it.ID is null then 1 else 0 end) unknown_item,
               sum(case when t.ID is null then 1 else 0 end) orphan_line
        from posItems p left join Items it on it.ID = p.ItemID left join posTickets t on t.ID = p.TicketID"""),
    ('سطور البيع في تذاكر المرتجع (SalesReturn > 0): الكمية بالسالب؟', """
        select count(*) n, sum(case when p.Packs < 0 or p.Units < 0 then 1 else 0 end) negative_qty,
               sum(case when p.Packs > 0 or p.Units > 0 then 1 else 0 end) positive_qty
        from posItems p join posTickets t on t.ID = p.TicketID where t.SalesReturn > 0"""),
    ('عدد الوحدات في العلبة: Parts و iParts في السطر و Items.Parts', """
        select count(*) n,
               sum(case when p.Parts = it.Parts then 1 else 0 end) parts_eq_item,
               sum(case when p.iParts = it.Parts then 1 else 0 end) iparts_eq_item,
               sum(case when p.Parts is null then 1 else 0 end) parts_null,
               sum(case when p.iParts is null then 1 else 0 end) iparts_null,
               sum(case when p.IsContent = 1 and p.Units <> 0 then 1 else 0 end) content_with_units
        from posItems p join Items it on it.ID = p.ItemID"""),
    ('سعر السطر: للعلبة ولا للوحدة؟ (SalesPrice ÷ سعر الصنف)', f"""
        select count(*) n,
               sum(case when abs(p.SalesPrice - it.SalesPrice) < 0.01 then 1 else 0 end) eq_item_pack_price,
               sum(case when it.Parts > 1 and abs(p.SalesPrice - it.SalesPrice / it.Parts) < 0.01 then 1 else 0 end) eq_item_unit_price,
               sum(case when abs(p.SalesPrice - it.UnitPrice) < 0.01 then 1 else 0 end) eq_item_unitprice_col
        from (select top {SAMPLE} * from posItems order by ID desc) p join Items it on it.ID = p.ItemID
        where p.SalesPrice > 0"""),
    ('إجمالي التذكرة = مجموع السطور بأنهي معادلة؟ (آخر التذاكر)', f"""
        with t as (select top {SAMPLE} * from posTickets where Total <> 0 order by ID desc),
        l as (select p.TicketID,
                     sum(p.SalesPrice * p.Packs + p.SalesPrice * p.Units / nullif(it.Parts, 0)) a_pack_price,
                     sum((p.SalesPrice * p.Packs + p.SalesPrice * p.Units / nullif(it.Parts, 0)) * (1 - p.Discount / 100)) b_line_pct,
                     sum(p.SalesPrice * p.Packs + p.SalesPrice * p.Units / nullif(it.Parts, 0) - p.Discount) c_line_value,
                     sum(p.SalesPrice * (p.Packs * it.Parts + p.Units)) d_unit_price,
                     sum(p.SalesPrice * p.Packs + p.SalesPrice * p.Units / nullif(p.iParts, 0)) e_iparts
              from posItems p join Items it on it.ID = p.ItemID where p.TicketID in (select ID from t) group by p.TicketID)
        select count(*) n,
               sum(case when abs(l.a_pack_price - t.Total) < 0.05 then 1 else 0 end) total_eq_a,
               sum(case when abs(l.a_pack_price - t.Discount - t.Total) < 0.05 then 1 else 0 end) total_eq_a_minus_disc,
               sum(case when abs(l.a_pack_price * (1 - t.Discount / 100) - t.Total) < 0.05 then 1 else 0 end) total_eq_a_times_pct,
               sum(case when abs(l.a_pack_price - t.SubTotal) < 0.05 then 1 else 0 end) subtotal_eq_a,
               sum(case when abs(l.b_line_pct - t.Total) < 0.05 then 1 else 0 end) total_eq_b,
               sum(case when abs(l.c_line_value - t.Total) < 0.05 then 1 else 0 end) total_eq_c,
               sum(case when abs(l.d_unit_price - t.Total) < 0.05 then 1 else 0 end) total_eq_d,
               sum(case when abs(l.e_iparts - t.Total) < 0.05 then 1 else 0 end) total_eq_e,
               sum(case when abs(abs(l.a_pack_price) - abs(t.Total)) < 0.05 then 1 else 0 end) abs_total_eq_a
        from t join l on l.TicketID = t.ID"""),
    ('الصنف اللي بيتكرر بسعر صفر (غالبًا «أصناف متنوعة» في تذاكر الدفع)', """
        select top 5 p.ItemID, it.name, count(*) n, sum(case when t.Total = 0 then 1 else 0 end) in_zero_tickets
        from posItems p join posTickets t on t.ID = p.TicketID left join Items it on it.ID = p.ItemID
        where p.SalesPrice = 0 group by p.ItemID, it.name order by count(*) desc"""),
    ('Cost في سطر البيع: تكلفة العلبة ولا الوحدة؟', f"""
        select count(*) n,
               sum(case when abs(p.Cost - it.CostPrice) < 0.01 then 1 else 0 end) eq_item_cost,
               sum(case when it.Parts > 1 and abs(p.Cost - it.CostPrice / it.Parts) < 0.01 then 1 else 0 end) eq_item_cost_per_unit,
               sum(case when p.Cost = 0 then 1 else 0 end) zero_cost,
               sum(case when p.Cost > p.SalesPrice then 1 else 0 end) cost_above_price
        from (select top {SAMPLE} * from posItems order by ID desc) p join Items it on it.ID = p.ItemID"""),
    ('NewPacks/NewUnits في السطر = الرصيد بعد البيع؟', f"""
        select count(*) n, sum(case when NewPacks is null then 1 else 0 end) null_newpacks,
               sum(case when StoreNewPacks is null then 1 else 0 end) null_storenewpacks,
               sum(case when NewPacks < 0 then 1 else 0 end) negative_newpacks
        from (select top {SAMPLE} * from posItems order by ID desc) p"""),

    # ------------------------------------------------------------------ الأصناف
    ('الأصناف: الاسم عربي ولا إنجليزي، والباركود، والحالة', """
        select count(*) n,
               sum(case when name like '%[^ -~]%' then 1 else 0 end) name_non_ascii,
               sum(case when DESCRIPTION like '%[^ -~]%' then 1 else 0 end) descr_non_ascii,
               sum(case when DESCRIPTION is not null and DESCRIPTION <> '' then 1 else 0 end) descr_filled,
               sum(case when NameOld is not null and NameOld <> '' then 1 else 0 end) nameold_filled,
               sum(case when barcode is null or barcode = 0 then 1 else 0 end) no_barcode,
               sum(case when IsActive = 0 then 1 else 0 end) inactive, sum(case when Archived = 1 then 1 else 0 end) archived,
               sum(case when ServiceItem = 1 then 1 else 0 end) service_item, sum(case when FridgeItem = 1 then 1 else 0 end) fridge,
               sum(case when ReorderDifficult = 1 then 1 else 0 end) reorder_difficult,
               min(ID) min_id, max(ID) max_id
        from Items"""),
    ('الباركود المكرر بين الأصناف', """
        select count(*) dup_barcodes, sum(n) items_involved
        from (select barcode, count(*) n from Items where barcode > 0 group by barcode having count(*) > 1) x"""),
    ('Items.Parts (عدد الوحدات في العلبة)', """
        select top 12 Parts, count(*) n from Items group by Parts order by count(*) desc"""),
    ('التصنيف: form_id و MainCategoryID بيشاوروا على Categories؟', """
        select count(*) n,
               sum(case when c1.id is not null then 1 else 0 end) form_id_in_categories,
               sum(case when c2.id is not null then 1 else 0 end) maincat_in_categories,
               count(distinct i.form_id) distinct_form_id
        from Items i left join Categories c1 on c1.id = i.form_id left join Categories c2 on c2.id = i.MainCategoryID"""),
    ('CrossRefrences.ref: باركودات تانية؟ (أطوال و أرقام)', """
        select len(ref) len_ref, case when ref not like '%[^0-9]%' then 'digits' else 'other' end kind, count(*) n
        from CrossRefrences group by len(ref), case when ref not like '%[^0-9]%' then 'digits' else 'other' end
        order by n desc"""),

    # ------------------------------------------------------------------ العملاء والموردين (Cards)
    ('Cards: مين عميل ومين مورد', """
        select count(*) n, sum(case when IsCustomer = 1 then 1 else 0 end) customers,
               sum(case when IsCreditCustomer = 1 then 1 else 0 end) credit_customers,
               sum(case when IsVendor = 1 then 1 else 0 end) vendors, sum(case when IsEmployee = 1 then 1 else 0 end) employees,
               sum(case when IsSalesRep = 1 or IsDeliveryBoy = 1 then 1 else 0 end) reps_delivery,
               sum(case when IsActive = 0 then 1 else 0 end) inactive,
               sum(case when CreditLimit > 0 then 1 else 0 end) has_limit, sum(case when Credit <> 0 then 1 else 0 end) credit_nz
        from Cards"""),
    ('التليفونات متسجلة فين؟ (عدد اللي فيه رقم موبايل مصري في كل عمود)', """
        select 'Name' col, sum(case when Name like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) n from Cards
        union all select 'ShortName', sum(case when ShortName like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) from Cards
        union all select 'Title', sum(case when Title like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) from Cards
        union all select 'AddressDetails', sum(case when AddressDetails like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) from Cards
        union all select 'StreetName', sum(case when StreetName like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) from Cards
        union all select 'NameOnCheck', sum(case when NameOnCheck like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) from Cards
        union all select 'IDCard', sum(case when IDCard like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) from Cards
        union all select 'InsuranceNo', sum(case when InsuranceNo like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) from Cards
        union all select 'Email', sum(case when Email like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) from Cards
        union all select 'PinNumber', sum(case when PinNumber between 1000000000 and 1599999999 then 1 else 0 end) from Cards
        union all select 'Telephones', count(*) from Telephones
        union all select 'posTickets.subCustomer', sum(case when subCustomer like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) from posTickets
        union all select 'posTickets.xMemo', sum(case when xMemo like '%01[0125][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]%' then 1 else 0 end) from posTickets"""),
    ('الروابط: التذاكر والفواتير والخزنة بتشاور على Cards؟', """
        select 'posTickets.CustomerID' col, count(*) n, sum(case when c.Id is not null then 1 else 0 end) found,
               sum(case when c.IsVendor = 1 then 1 else 0 end) is_vendor
        from posTickets t left join Cards c on c.Id = t.CustomerID where t.CustomerID > 0
        union all
        select 'PurchaseInvoices.vendor_id', count(*), sum(case when c.Id is not null then 1 else 0 end), sum(case when c.IsVendor = 1 then 1 else 0 end)
        from PurchaseInvoices p left join Cards c on c.Id = p.vendor_id where p.vendor_id > 0
        union all
        select 'CashFlow.DealerID', count(*), sum(case when c.Id is not null then 1 else 0 end), sum(case when c.IsVendor = 1 then 1 else 0 end)
        from CashFlow f left join Cards c on c.Id = f.DealerID where f.DealerID > 0"""),

    # ------------------------------------------------------------------ الخزنة (CashFlow)
    ('CashFlow حسب Operation', """
        select Operation, count(*) n, sum(case when DealerID > 0 then 1 else 0 end) with_dealer,
               sum(case when d.IsVendor = 1 then 1 else 0 end) dealer_vendor, sum(case when d.IsCustomer = 1 then 1 else 0 end) dealer_customer,
               sum(case when Amount < 0 then 1 else 0 end) negative, round(sum(Amount), 0) sum_amount,
               min(ztime) first, max(ztime) last
        from CashFlow f left join Cards d on d.Id = f.DealerID group by Operation order by count(*) desc"""),
    ('CashFlow: الحسابات (AccountID) والأسماء', """
        select f.AccountID, a.Name, a.Type, count(*) n from CashFlow f left join CashAccounts a on a.ID = f.AccountID
        group by f.AccountID, a.Name, a.Type order by count(*) desc"""),
    ('CashFlow.NewBalance = رصيد الحساب ولا رصيد العميل/المورد؟', f"""
        select Operation, count(*) n,
               sum(case when abs(NewBalance - (pa + Amount)) < 0.05 then 1 else 0 end) account_plus,
               sum(case when abs(NewBalance - (pd + Amount)) < 0.05 then 1 else 0 end) dealer_plus,
               sum(case when abs(NewBalance - (pd - Amount)) < 0.05 then 1 else 0 end) dealer_minus
        from (select top {SAMPLE} Operation, Amount, NewBalance,
                     lag(NewBalance) over (partition by AccountID order by ID) pa,
                     lag(NewBalance) over (partition by DealerID order by ID) pd
              from CashFlow order by ID desc) x group by Operation order by count(*) desc"""),
    ('حسابات الخزنة التانية (CashAccountsOthers) و CashAccounts', """
        select 'CashAccounts' t, ID, Name, cast(Type as bigint) type_or_dc from CashAccounts
        union all select 'CashAccountsOthers', ID, Name, DebitCredit from CashAccountsOthers order by 1, 2"""),

    # ------------------------------------------------------------------ الشرا
    ('فواتير الشرا: الأنواع والمرتجع', """
        select InvoiceType, SalesReturn, Settled, count(*) n, round(sum(total), 0) sum_total,
               sum(case when total < 0 then 1 else 0 end) neg_total, sum(case when Paid <> 0 then 1 else 0 end) paid_nz,
               min(inv_date) first, max(inv_date) last
        from PurchaseInvoices group by InvoiceType, SalesReturn, Settled order by count(*) desc"""),
    ('فواتير الشرا: الخصم والإضافات', """
        select count(*) n, sum(case when Discount <> 0 then 1 else 0 end) discount_nz, sum(case when extradiscount <> 0 then 1 else 0 end) extradisc_nz,
               sum(case when extracharge <> 0 then 1 else 0 end) extracharge_nz, sum(case when AmountAdjustment <> 0 then 1 else 0 end) adjust_nz,
               sum(case when OnePercentValue <> 0 then 1 else 0 end) onepct_nz, sum(case when VatValue <> 0 then 1 else 0 end) vat_nz,
               sum(case when inv_code is null or inv_code = '' then 1 else 0 end) no_supplier_doc,
               sum(case when abs(datediff(day, inv_date, ztime)) > 3 then 1 else 0 end) date_far_from_entry
        from PurchaseInvoices"""),
    ('سطور الشرا: البونص والمرتجع والتشغيلة', """
        select count(*) n, sum(case when bonus <> 0 then 1 else 0 end) bonus_nz, sum(case when units <> 0 then 1 else 0 end) units_nz,
               sum(case when packs < 0 then 1 else 0 end) neg_packs, sum(case when Returned <> 0 then 1 else 0 end) returned_nz,
               sum(case when PatchNumber is not null and PatchNumber <> '' then 1 else 0 end) patch_filled,
               sum(case when expirydate is null then 1 else 0 end) expiry_null,
               sum(case when trade_discount <> 0 then 1 else 0 end) trade_disc_nz, max(trade_discount) trade_disc_max,
               sum(case when ExtraDiscount <> 0 then 1 else 0 end) extra_disc_nz
        from PurchaseItems"""),
    ('سطر الشرا: CostPrice و RowValue بأنهي معادلة؟', f"""
        select count(*) n,
               sum(case when abs(p.CostPrice - p.sprice * (1 - p.trade_discount / 100)) < 0.02 then 1 else 0 end) cost_eq_price_minus_pct,
               sum(case when abs(p.RowValue - p.CostPrice * p.packs) < 0.05 then 1 else 0 end) rowvalue_eq_cost_x_packs,
               sum(case when abs(p.RowValue - p.CostPrice * (p.packs + p.units / nullif(cast(it.Parts as float), 0))) < 0.05 then 1 else 0 end) rowvalue_eq_cost_x_qty,
               sum(case when abs(p.sprice - it.SalesPrice) < 0.01 then 1 else 0 end) sprice_eq_item_price
        from (select top {SAMPLE} * from PurchaseItems order by ID desc) p join Items it on it.ID = p.item_id"""),
    ('إجمالي فاتورة الشرا = مجموع السطور؟', f"""
        with i as (select top {SAMPLE} * from PurchaseInvoices order by ID desc),
        l as (select inv_id, sum(RowValue) rv, sum(CostPrice * packs) cp from PurchaseItems where inv_id in (select ID from i) group by inv_id)
        select count(*) n, sum(case when abs(l.rv - i.total) < 0.5 then 1 else 0 end) total_eq_rowvalue,
               sum(case when abs(l.cp - i.total) < 0.5 then 1 else 0 end) total_eq_cost_x_packs,
               sum(case when abs(l.rv - i.Discount - i.total) < 0.5 then 1 else 0 end) total_eq_rowvalue_minus_disc,
               sum(case when abs(abs(l.rv) - abs(i.total)) < 0.5 then 1 else 0 end) abs_total_eq_rowvalue
        from i join l on l.inv_id = i.ID"""),

    # ------------------------------------------------------------------ المخزن
    ('المخازن (Stores)', "select ID, Name, Hidden from Stores order by ID"),
    ('الرصيد الحالي (Work) لكل مخزن', """
        select w.StoreID, count(*) rows_n, count(distinct w.item_id) items, sum(case when w.Packs < 0 or w.Units < 0 then 1 else 0 end) negative,
               sum(case when w.exp_date is null then 1 else 0 end) no_expiry, sum(case when w.exp_date < getdate() then 1 else 0 end) expired,
               sum(case when w.Packs = 0 and w.Units = 0 then 1 else 0 end) zero_rows,
               sum(case when it.ID is null then 1 else 0 end) unknown_item
        from Work w left join Items it on it.ID = w.item_id group by w.StoreID order by w.StoreID"""),
    ('Work: الوحدات أكبر من عدد العلبة؟ (لازم تتحول)', """
        select count(*) n, sum(case when w.Units >= it.Parts and it.Parts > 0 then 1 else 0 end) units_ge_parts
        from Work w join Items it on it.ID = w.item_id where w.Units <> 0"""),
    ('كارت الصنف (ItemCards) حسب Operation', """
        select Operation, count(*) n, sum(case when Packs < 0 or Units < 0 then 1 else 0 end) negative,
               min(ztime) first, max(ztime) last from ItemCards group by Operation order by count(*) desc"""),
    ('الجرد/التسوية (StockAdjustment) حسب Status', """
        select Status, count(*) n, sum(case when Packs < 0 or Units < 0 then 1 else 0 end) negative,
               min(DateAdded) first, max(DateAdded) last from StockAdjustment group by Status order by count(*) desc"""),
    ('التحويل بين المخازن (Transfers)', """
        select FromId, ToId, count(*) docs, (select count(*) from TransferedItems ti where ti.TransferID in
               (select ID from Transfers t2 where t2.FromId = t.FromId and t2.ToId = t.ToId)) lines
        from Transfers t group by FromId, ToId order by docs desc"""),
    ('الورديات (Shifts) و EndOfPeriod', """
        select 'Shifts' t, count(*) n, min(zStartTime) first, max(zStartTime) last from Shifts
        union all select 'EndOfPeriod', count(*), min(StartTime), max(EndTime) from EndOfPeriod"""),
    ('posTicketsX / posItemsX (نسخ مؤقتة؟)', """
        select 'posTicketsX' t, count(*) n, sum(case when p.ID is not null then 1 else 0 end) id_also_in_posTickets
        from posTicketsX x left join posTickets p on p.ID = x.ID
        union all select 'posItemsX', count(*), sum(case when p.ID is not null then 1 else 0 end) from posItemsX x left join posItems p on p.ID = x.ID"""),
]


def md_table(cols, rows):
    def cell(v):
        if v is None:
            return ''
        if isinstance(v, float):
            return f'{v:,.2f}'
        if isinstance(v, int):
            return f'{v:,}'
        return str(v).replace('|', '/').replace('\n', ' ')[:60]
    out = ['| ' + ' | '.join(cols) + ' |', '|' + '---|' * len(cols)]
    out += ['| ' + ' | '.join(cell(v) for v in r) + ' |' for r in rows]
    return '\n'.join(out)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    work = sys.argv[1]
    conn = connect(work)
    cur = conn.cursor()
    parts = ['# معنى أكواد فارمافلاي (أعداد بس)\n', f'المقارنات التقيلة على آخر {SAMPLE:,} صف.\n']
    for title, sql in Q:
        t0 = time.time()
        try:
            cur.execute(sql)
            cols = [d[0] for d in cur.description]
            rows = cur.fetchall()
            parts.append(f'## {title}\n\n{md_table(cols, rows)}\n\n_{time.time() - t0:.1f} ث_\n')
        except Exception as e:   # سؤال واحد وقع: نكتب السبب ونكمّل
            parts.append(f'## {title}\n\n**ماطلعش:** {str(e)[:300]}\n')
            try:
                conn.rollback()
            except Exception:
                pass
        print(f'{title} ({time.time() - t0:.1f} ث)', flush=True)
    path = os.path.join(work, 'profile.md')
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(parts))
    print(f'اتكتب: {path}')


if __name__ == '__main__':
    main()
