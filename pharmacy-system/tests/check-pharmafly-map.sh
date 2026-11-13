#!/usr/bin/env bash
# ملف الربط (import/pharmafly-to-stage.sql) على نسخة فارمافلاي متولّدة (tests/pharmafly-fake.py) بنفس جداول النسخة الحقيقية:
# النقل لازم يطابق أرصدة العملاء والموردين والمخزون اللي اتحسبت وقت التوليد، والاختيار الغلط لازم يبان في الفروق.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-pharmafly-map.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
FAKE=$(mktemp)
RUNS=0
python3 tests/pharmafly-fake.py "${DAYS:-120}" > "$FAKE"
fails=0
check() { if [ "$1" = "$2" ]; then echo "OK   $3"; else echo "FAIL $3: طلع «$1» والمتوقع «$2»"; fails=$((fails + 1)); fi; }

run() {   # $1 = اسم، $2 = أوامر الاختيارات (update pf_raw.map_options …)
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
  psql "$URL" -qX -v ON_ERROR_STOP=1 -c "create table pf_raw.map_options (k text primary key, v text not null)" -c "$2" >/dev/null
  psql "$URL" -qX -v ON_ERROR_STOP=1 -f import/pharmafly-to-stage.sql >/dev/null
  psql "$URL" -qX -v ON_ERROR_STOP=1 -c "select ph.import_history('fake')" >/dev/null
}
q() { psql "$URL" -qXAt -c "$1"; }

# 1) الاختيارات الصح (زي ما الداتا اتولّدت)
run "صح" "select 1"   # الافتراضي
check "$(q "select count(*) from ph.import_issues where kind = 'balance_reconciled'")" "0" "حسابات العملاء والموردين = فارمافلاي من غير تسوية"
check "$(q "select count(*) from ph.import_issues where kind = 'stock_reconciled'")" "0" "رصيد كل صنف = فارمافلاي من غير تسوية"
check "$(q "select count(*) from ph.health_check() where not ok")" "0" "الفحص الذاتي سليم بعد النقل"
check "$(q "select (select count(*) from ph.sales) = (select count(*) from pf_raw.\"posTickets\" where \"SalesReturn\" = 1 and \"Total\" <> 0 and \"ztime\" > '2000-01-01')")" "t" "كل تذكرة بيع اتنقلت فاتورة (من غير تذاكر التحصيل ولا تاريخ 1980)"
check "$(q "select (select count(*) from ph.sale_returns) = (select count(*) from pf_raw.\"posTickets\" where \"SalesReturn\" = 2)")" "t" "كل تذكرة مرتجع اتنقلت مرتجع"
check "$(q "select count(*) from ph.sale_lines where item_id = 1")" "0" "سطر «أصناف متنوعة» الوهمي مااتنقلش"
check "$(q "select abs((select sum(total) from ph.sales) - (select sum(\"Total\" - \"Discount\") from pf_raw.\"posTickets\" where \"SalesReturn\" = 1 and \"Total\" <> 0 and \"ztime\" > '2000-01-01')) < 1")" "t" "إجمالي البيع = فارمافلاي (بعد الخصم)"
check "$(q "select count(*) > 0 from ph.payments where kind = 'from_customer'")" "t" "التحصيل من العملاء اتنقل"
check "$(q "select (select count(*) from ph.payments where kind = 'to_supplier') = (select count(*) from pf_raw.\"CashFlow\" where \"Operation\" = 9)")" "t" "الدفع للموردين (CashFlow 9) اتنقل"
check "$(q "select count(*) from ph.purchase_returns")" "$(q "select count(*) from pf_raw.\"PurchaseInvoices\" where \"SalesReturn\" = 2")" "مرتجع الشرا اتنقل"
check "$(q "select phone from ph.customers where legacy_id = '9'")" "201000000009" "التليفون اتاخد من جوه الاسم (بالصيغة الدولية زي باقي البرنامج)"
check "$(q "select name from ph.customers where legacy_id = '9'")" "عميل 9" "والاسم من غير التليفون"
check "$(q "select phone from ph.customers where legacy_id = '7'")" "201122334455" "والتليفون من جدول Telephones"
check "$(q "select count(*) from ph.item_barcodes where barcode = '999'")" "0" "الباركود المتكرر على كل الأصناف مااتاخدش"
check "$(q "select count(*) from ph.item_barcodes where barcode = '6220000000005'")" "1" "باركود CrossRefrences اتاخد"
check "$(q "select count(*) from ph.locations where legacy_id in ('2', '5', '6', '7') and counts_as_stock")" "0" "الهالك ومخازن الانتظار مش بتتحسب في الرصيد اللي بيتباع"
check "$(q "select count(*) > 0 from ph.batches where source = 'import' and expiry is not null and legacy_key like '%:%'")" "t" "التشغيلة = الصنف + الصلاحية"
check "$(q "select count(*) from ph.import_issues where kind = 'credit_without_customer'")" "0" "مفيش تذكرة كاش اتسجلت آجل غلط"

# 2) لو التحصيل اتاخد مرتين (CashFlow 2 + تذكرة الصفر): الفروق لازم تبان
run "تحصيل مرتين" "insert into pf_raw.map_options values ('supplier_balance', 'cards_credit'), ('customer_pay_ops', '2,4,15')"
n=$(q "select count(*) from ph.import_issues where kind = 'balance_reconciled'")
check "$([ "$n" -gt 0 ] && echo t)" "t" "اختيار غلط (التحصيل مرتين) بيطلّع فروق في الحسابات ($n حساب)"

# 3) لو الخصم مااتطرحش: الفروق لازم تبان
run "الخصم مااتطرحش" "insert into pf_raw.map_options values ('supplier_balance', 'cards_credit'), ('ticket_discount', 'ignore')"
n=$(q "select count(*) from ph.import_issues where kind = 'balance_reconciled'")
check "$([ "$n" -gt 0 ] && echo t)" "t" "اختيار غلط (الخصم) بيطلّع فروق في الحسابات ($n حساب)"

[ "$fails" = 0 ] && echo "PFMAP OK" || { echo "PFMAP FAILED ($fails)"; exit 1; }
