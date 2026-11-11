-- =====================================================================================================
-- نظام صيدلية عسكر — المرحلة ١: شاشات بتقرا من جداول البوت الحالية (ar_*) من غير ما تكتب فيها
-- =====================================================================================================
-- الحالة: مسودة. ماتتطبقتش. محتاجة schema-draft.sql الأول (عشان schema ph).
-- كل view هنا security_invoker = true: يعني الصلاحيات الحالية بتاعت جداول ar_* (المالك بس) هي اللي بتتطبق.
-- مفيش ولا view بتكتب في ar_*. الرجوع: drop view لكل واحدة (أو drop schema ph cascade).
-- =====================================================================================================

-- الأصناف: كارت الصيدلية كله (≈ ٣٢ ألف) مع العربي والمادة الفعالة
create or replace view ph.v_items_now with (security_invoker = true) as
select s.id,
       s.name                                   as name_en,
       coalesce(s.arabic_name, a.arabic_name)   as name_ar,
       s.status,                                -- available / on_order / unavailable
       s.price,
       s.cat                                    as category,
       s.needs_rx,
       g.gkey,
       g.ingredients,
       g.form
from public.ar_store_items s
left join public.ar_store_arabic a on a.item_id = s.id
left join public.ar_store_generic g on g.item_id = s.id;

-- الرصيد الفعلي: علب + وحدات، ومخازن الانتظار لوحدها (لحد قرار المالك)
create or replace view ph.v_stock_now with (security_invoker = true) as
select k.item_id,
       k.name,
       k.arabic_name,
       k.packs,
       k.units,
       k.parts                                  as pack_parts,
       k.exp_near,
       k.price,
       k.other                                  as waiting_stores,
       k.data_at
from public.ar_stock k
where k.packs > 0 or k.units > 0;

-- الصلاحية: اللي فاضله أقل من ٦ شهور، الأقرب الأول
create or replace view ph.v_expiring with (security_invoker = true) as
select k.item_id,
       k.name,
       k.arabic_name,
       k.packs,
       k.units,
       k.exp_near,
       (k.exp_near - current_date)              as days_left,
       case when k.exp_near < current_date + 90 then 'red'
            when k.exp_near < current_date + 180 then 'yellow' end as level
from public.ar_stock k
where k.exp_near is not null
  and k.exp_near < current_date + 180
  and (k.packs > 0 or k.units > 0);

-- النواقص النشطة: العربي، الكمية (اللي المالك كتبها بتكسب)، واتطلب النهارده من مين
create or replace view ph.v_shortages_now with (security_invoker = true) as
select sh.name_key,
       sh.product_name,
       n.arabic_name,
       coalesce(sh.order_qty, sh.suggested_qty) as qty,
       (sh.order_qty is not null)               as qty_by_owner,
       o.supplier                               as ordered_today_from
from public.ar_shortages sh
left join public.ar_names n on n.name_key = sh.name_key
left join lateral (
  select ao.supplier
  from public.ar_orders ao
  where ao.name_key = sh.name_key
    and (ao.ordered_at at time zone 'Africa/Cairo')::date = (now() at time zone 'Africa/Cairo')::date
  order by ao.ordered_at desc
  limit 1
) o on true
where sh.is_active;

-- أحسن خصم لكل صنف من آخر قايمة لكل مخزن (المطابقة القوية/الكويسة أو اللي المالك وافق عليها)
create or replace view ph.v_best_offer with (security_invoker = true) as
with last_list as (
  select distinct on (l.supplier) l.id, l.supplier, l.list_date
  from public.ar_supplier_lists l
  order by l.supplier, l.list_date desc, l.id desc
),
offers as (
  select i.item_id, i.supplier, i.discount_pct, i.price, ll.list_date,
         row_number() over (partition by i.item_id order by i.discount_pct desc nulls last) as rnk,
         count(*) over (partition by i.item_id) as suppliers_count
  from public.ar_supplier_items i
  join last_list ll on ll.id = i.list_id
  where i.item_id is not null
    and i.discount_pct is not null
    and (i.match_status in ('strong', 'good') or i.review = 'accepted')
    and i.review not in ('rejected', 'not_stocked')
)
select b.item_id,
       b.supplier        as best_supplier,
       b.discount_pct    as best_pct,
       s2.supplier       as second_supplier,
       s2.discount_pct   as second_pct,
       b.discount_pct - coalesce(s2.discount_pct, b.discount_pct) as gap_pct,
       b.suppliers_count,
       b.list_date
from offers b
left join offers s2 on s2.item_id = b.item_id and s2.rnk = 2
where b.rnk = 1;

-- اللوحة: سطر واحد بأرقام النهارده (توقيت القاهرة)
create or replace view ph.v_today with (security_invoker = true) as
select
  (select count(*) from public.ar_shortages where is_active)                                  as shortages_active,
  (select count(distinct name_key) from public.ar_orders
     where (ordered_at at time zone 'Africa/Cairo')::date = (now() at time zone 'Africa/Cairo')::date) as ordered_today,
  (select count(*) from public.ar_inbox
     where hidden_at is null
       and (received_at at time zone 'Africa/Cairo')::date = (now() at time zone 'Africa/Cairo')::date) as inbox_today,
  (select count(*) from public.ar_stock
     where exp_near < current_date + 90 and (packs > 0 or units > 0))                         as expiring_90d,
  (select count(*) from public.ar_store_orders where status = 'new')                           as store_orders_new,
  (select count(*) from public.ar_documents where status = 'new')                              as documents_new,
  (select max(at) from public.ar_sync_log where status = 'ok' and not dry_run)                 as last_shortage_sync;
