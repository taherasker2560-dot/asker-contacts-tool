#!/usr/bin/env bash
# الشاشات من أولها لآخرها في Chromium على البيانات التجريبية: Postgres + PostgREST + Caddy (Docker) زي التسطيب بالظبط.
# محتاج: Docker وصورتين postgrest/postgrest:v12.2.3 و caddy:2.8.4، و Playwright (موجود في بيئة Claude).
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-ui.sh [فولدر للصور]
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
new_db ph_ui
WEB="${UI_PORT:-8091}"; API="${UI_API_PORT:-3401}"
trap 'docker rm -f ph-ui-postgrest ph-ui-caddy >/dev/null 2>&1 || true; psql "$PGURL" -qX -c "drop database if exists $DB" >/dev/null' EXIT
PGOPTIONS='-c client_min_messages=warning' psql "$URL" -qX -v ON_ERROR_STOP=1 -f tools/demo-seed.sql >/dev/null
SECRET=$(head -c 36 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-48)
AUTHPASS=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
psql "$URL" -qX -v ON_ERROR_STOP=1 -v secret="$SECRET" -v authpass="$AUTHPASS" >/dev/null <<'SQL'
insert into auth.config values ('jwt_secret', :'secret') on conflict (key) do update set value = excluded.value;
alter role authenticator password :'authpass';
SQL
docker rm -f ph-ui-postgrest ph-ui-caddy >/dev/null 2>&1 || true
docker run -d --name ph-ui-postgrest --network host \
  -e PGRST_DB_URI="postgres://authenticator:$AUTHPASS@127.0.0.1:5432/$DB" -e PGRST_DB_SCHEMAS=ph -e PGRST_DB_ANON_ROLE=anon \
  -e PGRST_JWT_SECRET="$SECRET" -e PGRST_DB_PRE_REQUEST=auth.check_request -e PGRST_SERVER_PORT="$API" postgrest/postgrest:v12.2.3 >/dev/null
docker run -d --name ph-ui-caddy --network host -e ASKER_PORT="$WEB" -e ASKER_BIND=127.0.0.1 -e ASKER_POSTGREST="127.0.0.1:$API" \
  -e ASKER_APP_DIR=/app -v "$PWD/install/Caddyfile:/etc/caddy/Caddyfile:ro" -v "$PWD/app:/app:ro" caddy:2.8.4 >/dev/null
for i in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$WEB/rest/v1/")" = 200 ] && break; sleep 1; done
BASE="http://127.0.0.1:$WEB" DBURL="$URL" node tests/check-ui.cjs "${1:-}"
