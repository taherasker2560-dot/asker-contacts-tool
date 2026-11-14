#!/usr/bin/env bash
# البيع قبل إدخال فاتورة الشرا (202611141000): مقفول ومفتوح، والفاتورة بتقفل السالب.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-negative.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
new_db ph_neg
PGOPTIONS='-c client_min_messages=warning' psql "$URL" -qX -v ON_ERROR_STOP=1 -f tools/demo-seed.sql >/dev/null
out=$(psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/negative-checks.sql 2>&1) && rc=0 || rc=$?
echo "$out" | grep -E 'OK|FAIL|ERROR' | sed 's/^psql:[^ ]* NOTICE:  //; s/^NOTICE:  //'
[ "$rc" = 0 ] && echo "NEGATIVE OK ($(echo "$out" | grep -c 'OK  ') فحص)" || { echo "NEGATIVE FAILED"; exit 1; }
