#!/usr/bin/env bash
# التقارير السبعة + ملخص الصبح على القاعدة التجريبية (tools/demo-seed.sql): الأرقام بتطابق الدفاتر، والصلاحيات مظبوطة.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-reports.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
new_db ph_rep
PGOPTIONS='-c client_min_messages=warning' psql "$URL" -qX -v ON_ERROR_STOP=1 -f tools/demo-seed.sql >/dev/null
out=$(psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/report-checks.sql 2>&1) && rc=0 || rc=$?
echo "$out" | grep -E 'OK|FAIL|ERROR' | sed 's/^psql:[^ ]* NOTICE:  //; s/^NOTICE:  //'
[ "$rc" = 0 ] && echo "REPORTS OK ($(echo "$out" | grep -c 'OK  ') فحص)" || { echo "REPORTS FAILED"; exit 1; }
