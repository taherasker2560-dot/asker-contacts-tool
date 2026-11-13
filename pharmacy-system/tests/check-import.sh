#!/usr/bin/env bash
# بيجرب النقل من فارمافلاي على تاريخ تجريبي (2018–2026) في قاعدة Postgres مؤقتة. مابيلمسش Supabase.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-import.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
new_db ph_import
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/import-sample.sql
[ "${KEEP:-}" = 1 ] && { echo "DB: $URL"; trap - EXIT; }
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/import-checks.sql >/dev/null   # النتايج بتطلع كـ NOTICE
echo "IMPORT OK"
