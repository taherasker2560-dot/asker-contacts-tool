# أداة مشتركة للاختبارات: قاعدة Postgres مؤقتة عليها ملفات db/ بالترتيب، وبتتمسح في الآخر.
# الاستخدام: . tests/lib.sh; new_db <بادئة>   ← بيرجّع $URL
PGURL="${PGURL:-postgresql:///postgres}"
new_db() {
  DB="${1:-ph_test}_$$"
  psql "$PGURL" -qX -v ON_ERROR_STOP=1 -c "create database $DB"
  trap 'psql "$PGURL" -qX -c "drop database if exists $DB" >/dev/null' EXIT
  URL="${PGURL%/*}/$DB"
  for f in db/[0-9][0-9]-*.sql; do PGOPTIONS='-c client_min_messages=warning' psql "$URL" -qX -v ON_ERROR_STOP=1 -f "$f"; done
}
