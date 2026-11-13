#!/usr/bin/env bash
# بيجرب طريقة التعديل على قاعدة فيها داتا (زي اللاب بعد التجربة): تعديل بيضيف حاجة، وتعديل فيه غلط، وتعديل اتعدّل بعد تطبيقه.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-migrate.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
new_db ph_migrate
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/checks.sql >/dev/null 2>&1      # يوم شغل كامل = داتا حقيقية الشكل
M=$(mktemp -d); trap 'rm -rf "$M"; psql "$PGURL" -qX -c "drop database if exists $DB" >/dev/null' EXIT
fails=0
check() { if [ "$1" = "$2" ]; then echo "OK   $3"; else echo "FAIL $3: طلع «$1» والمتوقع «$2»"; fails=$((fails + 1)); fi; }
q() { psql "$URL" -qXAt -c "$1"; }
SALES_BEFORE=$(q "select count(*) || '|' || sum(total) from ph.sales")

cat > "$M/202611140001_item_shelf.sql" <<'EOF'
-- 202611140001_item_shelf
-- المطلوب: مكان الصنف على الرف. الرجوع: alter table ph.items drop column shelf;
alter table ph.items add column shelf text check (char_length(shelf) <= 20);
update ph.items set shelf = 'A1' where id = 1259;
EOF
cat > "$M/202611140002_broken.sql" <<'EOF'
alter table ph.items add column half_done integer;
select 1 / 0;   -- غلط في نص الملف
EOF

out=$(bash tools/migrate.sh "$URL" "$M" 2>&1 || true)
check "$(echo "$out" | grep -c 'اتطبق: 202611140001_item_shelf')|$(echo "$out" | grep -c 'فشل: 202611140002_broken')" "1|1" "التعديل السليم اتطبق، واللي فيه غلط وقف"
# المتوقع: تعديلات المشروع الحقيقية (اتطبقت مع التسطيب الجديد) + السليم بتاع الاختبار + base، من غير اللي فيه غلط
REAL=$(ls db/migrations/*.sql 2>/dev/null | xargs -rn1 basename | sed 's/\.sql$//')
WANT=$(printf '%s\n' $REAL 202611140001_item_shelf base | LC_ALL=C sort | paste -sd, -)
check "$(q "select string_agg(version, ',' order by version collate \"C\") from ph.schema_migrations")" "$WANT" "اللي فيه غلط مااتسجلش"
check "$(q "select count(*) from information_schema.columns where table_schema = 'ph' and table_name = 'items' and column_name in ('shelf', 'half_done')")" "1" "ومفيش منه حاجة اتطبقت نص نص (العمود half_done مااتعملش)"
check "$(q "select shelf from ph.items where id = 1259")" "A1" "التعديل السليم شغال على الداتا الموجودة"

printf -- "-- 202611140002_broken (بعد التصليح)\nalter table ph.items add column half_done integer;\n" > "$M/202611140002_broken.sql"
out=$(bash tools/migrate.sh "$URL" "$M" 2>&1)
check "$(echo "$out" | tail -1)" "تعديلات جديدة: 1" "بعد التصليح: اتطبق هو بس"
out=$(bash tools/migrate.sh "$URL" "$M" 2>&1)
check "$(echo "$out" | tail -1)" "تعديلات جديدة: 0" "التشغيل تاني مابيعملش حاجة"

echo "-- تعديل بعد التطبيق" >> "$M/202611140001_item_shelf.sql"
code=0; out=$(bash tools/migrate.sh "$URL" "$M" 2>&1) || code=$?
check "$code|$(echo "$out" | grep -c 'اتعدّل بعدها')" "2|1" "ملف اتطبق واتعدّل بعدها = التحديث بيوقف"

check "$(q "select count(*) || '|' || sum(total) from ph.sales")" "$SALES_BEFORE" "الفواتير زي ما هي"
check "$(q "select count(*) from ph.health_check() where not ok")" "0" "الفحص الذاتي سليم بعد التعديلات"
[ "$fails" = 0 ] && echo "MIGRATE OK" || { echo "$fails FAILED"; exit 1; }
