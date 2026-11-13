#!/usr/bin/env bash
# اختبار ضغط: كذا كاشير بيبيعوا ويدوّروا في نفس الوقت، وبعدها الفحص الذاتي لازم يطلع كله سليم.
# 90% بيع (صنف من 200، علبة لـ 3) و10% بحث. داتا متولّدة، مش داتا الصيدلية.
# الاستخدام: CLIENTS=4 SECONDS_=30 PGURL=postgresql:///postgres bash pharmacy-system/tests/soak.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
CLIENTS="${CLIENTS:-4}"; DURATION="${SECONDS_:-30}"
PGBENCH="${PGBENCH:-$(command -v pgbench || echo /usr/lib/postgresql/16/bin/pgbench)}"
new_db ph_soak
CASHIER=00000000-0000-0000-0000-0000000000c1
psql "$URL" -qX -v ON_ERROR_STOP=1 -f tests/soak-setup.sql >/dev/null

OUT=$(PGOPTIONS="-c role=authenticated -c request.jwt.claim.sub=$CASHIER" \
      "$PGBENCH" -n -c "$CLIENTS" -j "$CLIENTS" -T "$DURATION" -f tests/soak-sale.sql@9 -f tests/soak-search.sql@1 "$URL" 2>&1)
echo "$OUT" | grep -E "number of transactions actually processed|number of failed|latency average|tps =" | sed 's/^/  /'
SALES_RUN=$(echo "$OUT" | awk '/SQL script 1/{f=1} f && /- [0-9]+ transactions/{print $2; exit}')
FAILED=$(echo "$OUT" | awk -F': ' '/number of failed transactions/{print $2+0; exit}')
read -r SALES BAD MAXNO < <(psql "$URL" -qXAt -F ' ' -c "select (select count(*) from ph.sales), (select count(*) from ph.health_check() where not ok), (select max(split_part(no, '-', 3)::int) from ph.sales)")
echo "  فواتير اتسجلت: $SALES · آخر رقم: $MAXNO · قواعد فشلت في الفحص: $BAD"
[ "${FAILED:-0}" = 0 ] && [ "$SALES" = "$SALES_RUN" ] && [ "$MAXNO" = "$SALES" ] && [ "$BAD" = 0 ] \
  && echo "SOAK OK" || { echo "SOAK FAILED"; psql "$URL" -qX -c "select * from ph.health_check() where not ok"; exit 1; }
