#!/usr/bin/env bash
# البرنامج زي ما هيتسطب في الصيدلية: Postgres + PostgREST، والطلبات عن طريق HTTP زي الكاشير والبوت بالظبط.
# بيجرب: الدخول بكلمة السر، البيع من الكاشير، مفتاح البوت وصلاحياته، الموقع من غير دخول، إلغاء المفاتيح، قفل الحساب.
# محتاج: Docker وصورة postgrest/postgrest:v12.2.3، وPostgres محلي بيقبل كلمة سر على 127.0.0.1.
# الاستخدام: PGURL=postgresql:///postgres bash pharmacy-system/tests/check-api.sh
set -euo pipefail
cd "$(dirname "$0")/.."
. tests/lib.sh
new_db ph_api
API="http://127.0.0.1:${API_PORT:-3300}"; NAME="ph-postgrest-test"
SECRET=$(head -c 36 /dev/urandom | base64 | tr -d '/+=\n' | cut -c1-48)
AUTHPASS=$(head -c 18 /dev/urandom | base64 | tr -d '/+=\n')
trap 'docker rm -f "$NAME" >/dev/null 2>&1 || true; psql "$PGURL" -qX -c "drop database if exists $DB" >/dev/null' EXIT

psql "$URL" -qX -v ON_ERROR_STOP=1 -v secret="$SECRET" -v authpass="$AUTHPASS" >/dev/null <<'SQL'
insert into auth.config values ('jwt_secret', :'secret');
alter role authenticator password :'authpass';
insert into ph.settings (pharmacy_name) values ('صيدلية تجربة');
insert into ph.branches (name) values ('الفرع');
insert into ph.locations (branch_id, name, kind, is_default_sale) values (1, 'الرئيسي', 'main', true);
insert into ph.cash_accounts (branch_id, name, kind) values (1, 'درج 1', 'drawer');
insert into ph.payment_methods values ('cash', 'كاش', 1), ('credit', 'آجل', null);
insert into ph.items (id, name_en, pack_parts, public_price) values (1259, 'PANADOL EXTRA 24 TAB', 3, 90);
insert into ph.item_stock_rules values (1259, 100, 200);
select auth.bootstrap_owner('owner', 'owner-pass-1', 'المالك') as owner_id \gset
set role authenticated;
select set_config('request.jwt.claim.sub', :'owner_id', false);
select ph.create_user('cashier', 'cashier-pass-1', 'كاشير', 'cashier');
select ph.create_user('bot', null, 'بوت النواقص', 'bot');
select ph.post_opening_stock(1::smallint, '[{"item_id":1259,"packs":10,"expiry":"2028-01-31","unit_cost":20}]');
SQL

docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --network host \
  -e PGRST_DB_URI="postgres://authenticator:$AUTHPASS@127.0.0.1:5432/$DB" -e PGRST_DB_SCHEMAS=ph -e PGRST_DB_ANON_ROLE=anon \
  -e PGRST_JWT_SECRET="$SECRET" -e PGRST_DB_PRE_REQUEST=auth.check_request -e PGRST_SERVER_PORT="${API_PORT:-3300}" \
  postgrest/postgrest:v12.2.3 >/dev/null
for i in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' "$API/")" = 200 ] && break; sleep 1; done   # PostgREST بيرد 503 لحد ما يقرا القاعدة

fails=0
check() { if [ "$1" = "$2" ]; then echo "OK   $3"; else echo "FAIL $3: طلع «$1» والمتوقع «$2»"; fails=$((fails + 1)); fi; }
# req METHOD PATH TOKEN BODY → "HTTP|body"
req() {
  local auth=(); [ -n "${3:-}" ] && auth=(-H "Authorization: Bearer $3")
  curl -s -o /tmp/ph_api_body_$$ -w '%{http_code}' -X "$1" "$API$2" "${auth[@]}" -H 'Content-Type: application/json' \
    -H 'Prefer: return=minimal' ${4:+-d "$4"} | tr -d '\n'
  printf '|%s' "$(cat /tmp/ph_api_body_$$)"
}
js() { python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))" "$1" "$2"; }

r=$(req POST /rpc/login "" '{"username":"owner","password":"wrong-pass"}')
check "${r%%|*}|$(js "${r#*|}" 'd["error"]')" "401|اسم المستخدم أو كلمة السر غلط" "كلمة سر غلط = 401"
r=$(req POST /rpc/login "" '{"username":"owner","password":"owner-pass-1"}'); OWNER=$(js "${r#*|}" 'd["token"]')
check "${r%%|*}|$(js "${r#*|}" 'd["role"]')" "200|owner" "المالك دخل وخد مفتاح 12 ساعة"
r=$(req GET "/v_stock?select=packs,units" "$OWNER")
check "$r" '200|[{"packs":10,"units":0.00}]' "المالك شايف الرصيد: 10 علب"

r=$(req POST /rpc/login "" '{"username":"cashier","password":"cashier-pass-1"}'); CASHIER=$(js "${r#*|}" 'd["token"]')
r=$(req POST /rpc/post_sale "$CASHIER" '{"p":{"client_uuid":"55555555-0000-0000-0000-000000000001","lines":[{"item_id":1259,"packs":1,"units":1}],"payments":[{"method":"cash","amount":120}]}}')
check "${r%%|*}|$(js "${r#*|}" 'd["no"][:2] + str(int(d["total"]))')" "200|S-120" "الكاشير باع علبة + شريط من الكاشير (HTTP)"
r=$(req GET "/money_moves?select=amount" "$CASHIER")
check "$r" "200|[]" "الكاشير مايشوفش حركة الخزن"

r=$(req POST /rpc/issue_bot_token "$OWNER" '{"p_username":"bot","p_days":30}'); BOT=$(js "${r#*|}" 'd["token"]')
check "${r%%|*}" "200" "المالك طلّع مفتاح للبوت"
r=$(req GET "/v_shortages?select=item_id,order_packs" "$BOT")
check "$r" '200|[{"item_id":1259,"order_packs":58}]' "البوت شايف النواقص: الرصيد 26 شريط تحت الحد 100، والطلب لحد 200 = 58 علبة"
r=$(req POST /supplier_offers "$BOT" '{"supplier_id":null,"item_id":1259,"source":"whatsapp","discount_pct":28}')
check "${r%%|*}" "400" "عرض من غير مورد مرفوض"
psql "$URL" -qX -c "insert into ph.suppliers (code, name, kind) values ('AMG', 'مخزن AMG', 'warehouse')" >/dev/null
r=$(req POST /supplier_offers "$BOT" '{"supplier_id":10000,"item_id":1259,"source":"whatsapp","discount_pct":28,"raw_text":"بنادول خصم 28"}')
check "${r%%|*}" "201" "البوت كتب عرض مورد من الواتس"
r=$(req GET "/customers?select=name" "$BOT"); check "$r" "200|[]" "البوت مايشوفش العملاء"

# البوابة (Caddy بنفس install/Caddyfile) + كود البوت بـ supabase-js زي ما هو
GW="http://127.0.0.1:${GW_PORT:-8088}"; GWNAME="ph-caddy-test"
docker rm -f "$GWNAME" >/dev/null 2>&1 || true
docker run -d --name "$GWNAME" --network host -e ASKER_LISTEN=":${GW_PORT:-8088}" -e ASKER_POSTGREST="127.0.0.1:${API_PORT:-3300}" \
  -e ASKER_APP_DIR=/app -v "$PWD/install/Caddyfile:/etc/caddy/Caddyfile:ro" -v "$PWD/app:/app:ro" caddy:2.8.4 >/dev/null
for i in $(seq 1 20); do curl -s -o /dev/null "$GW/" && break; sleep 1; done
check "$(curl -s "$GW/" | grep -c 'صيدلية عسكر' | tr -d ' ' | sed 's/^[1-9][0-9]*$/yes/')" "yes" "البوابة بتفتح شاشات البرنامج"
if [ -n "${SUPABASE_JS_DIR:-}" ]; then
  r=$(ASKER_URL="$GW" BOT_TOKEN="$BOT" NODE_PATH="$SUPABASE_JS_DIR" node tests/bot-client.cjs)
  check "$r" '{"shortages":[{"item_id":1259,"order_packs":58}],"insert":201,"customers":0,"best":[{"best_pct":27}]}' \
        "كود البوت الحالي (supabase-js) شغال على البرنامج: قرا النواقص، كتب عرض 27% (آخر عرض من نفس المورد بيكسب)، ومااتشافلوش عملاء"
else
  echo "SKIP supabase-js (حدد SUPABASE_JS_DIR)"
fi
docker rm -f "$GWNAME" >/dev/null 2>&1 || true
r=$(req POST /rpc/post_sale "$BOT" '{"p":{"client_uuid":"55555555-0000-0000-0000-000000000002","lines":[{"item_id":1259,"units":1}]}}')
check "${r%%|*}|$(js "${r#*|}" '"مش مسموح" in d["message"]')" "403|True" "البوت مايبيعش"

r=$(req GET "/items?select=id" ""); check "${r%%|*}" "401" "من غير دخول: مفيش أصناف"
r=$(req POST /rpc/store_catalog "" '{"q":"PANADOL"}')
check "${r%%|*}|$(js "${r#*|}" 'str(d[0]["available"]) + "|" + str("units" in d[0])')" "200|True|False" "الموقع: متاح من غير ما الرصيد يبان"

r=$(req POST /rpc/revoke_tokens "$OWNER" '{"p_username":"bot"}'); check "${r%%|*}" "204" "المالك لغى مفاتيح البوت"
r=$(req GET "/v_shortages?select=item_id" "$BOT")
check "${r%%|*}|$(js "${r#*|}" 'd["message"]')" "401|الدخول ده اتلغى: سجّل دخول تاني" "مفتاح البوت القديم مابقاش شغال"
r=$(req GET "/v_stock?select=packs" "${OWNER%?}x"); check "${r%%|*}" "401" "مفتاح متلعّب فيه مرفوض"

for i in 1 2 3 4 5; do req POST /rpc/login "" '{"username":"cashier","password":"nope-nope"}' >/dev/null; done
r=$(req POST /rpc/login "" '{"username":"cashier","password":"cashier-pass-1"}')
check "${r%%|*}|$(js "${r#*|}" '"مقفول" in d["error"]')" "403|True" "5 مرات غلط = الحساب اتقفل ربع ساعة حتى بكلمة السر الصح"

rm -f /tmp/ph_api_body_$$
[ "$fails" = 0 ] && echo "API OK" || { echo "$fails FAILED"; exit 1; }
