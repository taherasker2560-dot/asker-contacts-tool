#!/usr/bin/env bash
# ملف الربط (import/pharmafly-to-stage.sql، اللي اتجرب على النسخة الحقيقية على اللاب) على نسخة فارمافلاي متولّدة
# (tests/pharmafly-fake.py) بنفس الجداول والقواعد: النقل لازم يطابق أرصدة العملاء والمخزون اللي اتحسبت وقت التوليد،
# ورصيد الموردين مايتصفّرش (202611132000)، والفرق الحقيقي لازم يبان.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-pharmafly-map.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
FAKE=$(mktemp)
RUNS=0
python3 tests/pharmafly-fake.py "${DAYS:-120}" > "$FAKE"
fails=0
check() { if [ "$1" = "$2" ]; then echo "OK   $3"; else echo "FAIL $3: طلع «$1» والمتوقع «$2»"; fails=$((fails + 1)); fi; }
q() { psql "$URL" -qXAt -c "$1"; }

run() {   # $1 = تعديل على النسخة قبل الربط (SQL)
  [ -n "${DB:-}" ] && psql "$PGURL" -qX -c "drop database if exists $DB" >/dev/null
  RUNS=$((RUNS + 1)); new_db "ph_pfmap$RUNS" >/dev/null
  trap 'rm -f "$FAKE"; psql "$PGURL" -qX -c "drop database if exists $DB" >/dev/null' EXIT
  psql "$URL" -qX -v ON_ERROR_STOP=1 >/dev/null <<'SQL'
insert into ph.settings (pharmacy_name) values ('تجربة الربط');
insert into ph.branches (name) values ('الفرع');
insert into ph.cash_accounts (branch_id, name, kind) values (1, 'درج', 'drawer');
insert into ph.payment_methods values ('cash', 'كاش', 1), ('credit', 'آجل', null);
SQL
  psql "$URL" -qX -v ON_ERROR_STOP=1 -f "$FAKE" >/dev/null
  psql "$URL" -qX -v ON_ERROR_STOP=1 -c "$1" >/dev/null
  PGOPTIONS='-c client_min_messages=warning' psql "$URL" -qX -v ON_ERROR_STOP=1 -f import/pharmafly-to-stage.sql >/dev/null
  psql "$URL" -qX -v ON_ERROR_STOP=1 -c "select ph.import_history('fake')" >/dev/null
}

# 1) النسخة زي ما اتولّدت
run "select 1"
check "$(q "select count(*) from ph.import_issues where kind = 'balance_reconciled'")" "0" "حساب كل عميل = آخر NewBalance في فارمافلاي من غير تسوية"
check "$(q "select count(*) from ph.import_issues where kind = 'stock_reconciled' and item_id <> 1")" "0" "رصيد كل صنف = Work من غير تسوية (ومعاه الجرد من ItemCards)، غير صنف 1 الوهمي"
check "$(q "select abs((select coalesce(sum(balance), 0) from ph.party_balances where party_type = 'supplier')
                     - (select sum(\"Credit\") from pf_raw.\"Cards\" where \"IsVendor\")) < 1")" "t" "رصيد الموردين من تاريخهم ومااتصفّرش (رصيدهم مش في الربط)"
check "$(q "select count(*) from ph.health_check() where not ok")" "0" "الفحص الذاتي سليم بعد النقل"
check "$(q "select (select count(*) from ph.sales) = (select count(*) from pf_raw.\"posTickets\" where \"Total\" > 0)")" "t" "كل تذكرة بيع اتنقلت فاتورة، حتى اللي تاريخها غلط (من غير تذاكر التحصيل)"
check "$(q "select (select count(*) from ph.sale_returns) = (select count(*) from pf_raw.\"posTickets\" where \"Total\" < 0)")" "t" "كل تذكرة مرتجع اتنقلت مرتجع"
check "$(q "select (select count(*) from ph.sales where ph.business_day(at) < '2017-01-01') ")" "0" "تذكرة تاريخها 1980 اتنقلت بتاريخ سليم"
check "$(q "select count(*) from ph.sale_lines where item_id = 1 and line_total = 0")" "0" "سطر «أصناف متنوعة» بصفر (تذكرة التحصيل) مااتنقلش"
check "$(q "select abs((select sum(total) from ph.sales) - (select sum(\"Total\" - \"Discount\") from pf_raw.\"posTickets\" where \"Total\" > 0)) < 1")" "t" "صافي البيع = فارمافلاي (Total − Discount)"
check "$(q "select count(*) > 0 from ph.payments where kind = 'from_customer'")" "t" "التحصيل من العملاء اتنقل"
check "$(q "select (select count(*) from ph.payments where kind = 'from_customer' and legacy_no like 'C%') = (select count(*) from pf_raw.\"CashFlow\" where \"Operation\" = 4)")" "t" "CashFlow 4 اتنقل، و 2 (نسخة التذكرة) لأ"
check "$(q "select (select count(*) from ph.payments where kind = 'to_supplier') = (select count(*) from pf_raw.\"CashFlow\" where \"Operation\" = 9)")" "t" "الدفع للموردين (CashFlow 9) اتنقل"
check "$(q "select count(*) from ph.purchase_returns")" "$(q "select count(*) from pf_raw.\"PurchaseInvoices\" where \"SalesReturn\" = 2")" "مرتجع الشرا اتنقل"
check "$(q "select count(*) > 0 from ph.stock_moves m join ph.stock_adjustments a on a.id = m.doc_id where m.doc_type = 'adjust' and a.reason = 'count'")" "t" "الجرد من ItemCards (5 و 6) اتنقل"
check "$(q "select phone from ph.customers where legacy_id = '9'")" "201000000009" "التليفون اتاخد من جوه الاسم"
check "$(q "select name from ph.customers where legacy_id = '9'")" "عميل 9" "والاسم من غير التليفون"
check "$(q "select phone from ph.customers where legacy_id = '7'")" "201122334455" "والتليفون من جدول Telephones"
check "$(q "select count(*) from ph.item_barcodes where barcode = '999'")" "0" "الباركود المتكرر على كل الأصناف مااتاخدش"
check "$(q "select count(*) from ph.item_barcodes where barcode = '6220000000005'")" "1" "باركود CrossRefrences اتاخد"
check "$(q "select count(*) from ph.import_issues where kind = 'credit_without_customer'")" "0" "مفيش تذكرة كاش اتسجلت آجل غلط"

# 2) لو رصيد عميل في فارمافلاي مختلف عن تاريخه: لازم يبان تسوية للعميل ده بس
run "update pf_raw.\"posTickets\" set \"NewBalance\" = \"NewBalance\" + 100 where \"ID\" = (select max(\"ID\") from pf_raw.\"posTickets\" where \"CustomerID\" = 12)"
check "$(q "select count(*) || ':' || max((detail->>'diff')::numeric) from ph.import_issues where kind = 'balance_reconciled'")" "1:100.00" "فرق 100 ج في حساب عميل واحد بيبان تسوية ليه هو بس"

[ "$fails" = 0 ] && echo "PFMAP OK" || { echo "PFMAP FAILED ($fails)"; exit 1; }
