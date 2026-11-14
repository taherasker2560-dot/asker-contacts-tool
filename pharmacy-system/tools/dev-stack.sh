#!/usr/bin/env bash
# البرنامج شغال على Linux للتطوير والاختبار: PostgREST + Caddy (Docker) على قاعدة موجودة (مثلًا من tools/demo.sh).
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tools/dev-stack.sh <القاعدة> [بورت الشاشات] [بورت المحرك]
#   الإيقاف: docker rm -f ph-dev-postgrest ph-dev-caddy
set -euo pipefail
cd "$(dirname "$0")/.."
PGURL="${PGURL:-postgresql:///postgres}"; DB="${1:-asker_demo}"; WEB="${2:-8090}"; API="${3:-3400}"
URL="${PGURL%/*}/$DB"
SECRET=$(head -c 36 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-48)
AUTHPASS=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
psql "$URL" -qX -v ON_ERROR_STOP=1 -v secret="$SECRET" -v authpass="$AUTHPASS" >/dev/null <<'SQL'
insert into auth.config values ('jwt_secret', :'secret') on conflict (key) do update set value = excluded.value;
alter role authenticator password :'authpass';
SQL
docker rm -f ph-dev-postgrest ph-dev-caddy >/dev/null 2>&1 || true
docker run -d --name ph-dev-postgrest --network host \
  -e PGRST_DB_URI="postgres://authenticator:$AUTHPASS@127.0.0.1:5432/$DB" -e PGRST_DB_SCHEMAS=ph -e PGRST_DB_ANON_ROLE=anon \
  -e PGRST_JWT_SECRET="$SECRET" -e PGRST_DB_PRE_REQUEST=auth.check_request -e PGRST_SERVER_PORT="$API" postgrest/postgrest:v12.2.3 >/dev/null
docker run -d --name ph-dev-caddy --network host -e ASKER_PORT="$WEB" -e ASKER_BIND=127.0.0.1 -e ASKER_POSTGREST="127.0.0.1:$API" \
  -e ASKER_APP_DIR=/app -v "$PWD/install/Caddyfile:/etc/caddy/Caddyfile:ro" -v "$PWD/app:/app:ro" caddy:2.8.4 >/dev/null
for i in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:$WEB/rest/v1/")" = 200 ] && break; sleep 1; done
echo "البرنامج: http://127.0.0.1:$WEB"
