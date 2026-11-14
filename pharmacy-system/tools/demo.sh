#!/usr/bin/env bash
# قاعدة تجريبية كاملة للعرض والتطوير على Linux: الأساس + البيانات التجريبية.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tools/demo.sh <اسم القاعدة>
set -euo pipefail
cd "$(dirname "$0")/.."
PGURL="${PGURL:-postgresql:///postgres}"; NAME="${1:-asker_demo}"; URL="${PGURL%/*}/$NAME"
psql "$PGURL" -qX -v ON_ERROR_STOP=1 -c "drop database if exists $NAME with (force)" -c "create database $NAME"
for f in db/[0-9][0-9]-*.sql; do PGOPTIONS='-c client_min_messages=warning' psql "$URL" -qX -v ON_ERROR_STOP=1 -f "$f"; done
bash tools/migrate.sh "$URL" db/migrations >/dev/null
PGOPTIONS='-c client_min_messages=warning' psql "$URL" -qX -v ON_ERROR_STOP=1 -f tools/demo-seed.sql
