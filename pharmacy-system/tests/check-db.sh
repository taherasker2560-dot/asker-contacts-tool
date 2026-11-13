#!/usr/bin/env bash
# بيجرب قاعدة البيانات على Postgres محلي في قاعدة مؤقتة وبيمسحها في الآخر. مابيلمسش Supabase.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-db.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
new_db ph_test
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/checks.sql >/dev/null   # النتايج بتطلع كـ NOTICE
echo "DB OK"
