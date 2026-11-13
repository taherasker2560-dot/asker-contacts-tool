#!/usr/bin/env bash
# تعديل السرعة (202611131800): الكاش والفحص المحفوظ بيدّوا نفس أرقام الحساب المباشر، والصلاحيات مظبوطة.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-speed.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
new_db ph_speed
PGOPTIONS='-c client_min_messages=warning' psql "$URL" -qX -v ON_ERROR_STOP=1 -f tools/demo-seed.sql >/dev/null
out=$(psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/speed-checks.sql 2>&1) && rc=0 || rc=$?
echo "$out" | grep -E 'OK|FAIL|ERROR' | sed 's/^psql:[^ ]* NOTICE:  //; s/^NOTICE:  //'
[ "$rc" = 0 ] && echo "SPEED OK ($(echo "$out" | grep -c 'OK  ') فحص)" || { echo "SPEED FAILED"; exit 1; }
