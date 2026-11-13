#!/usr/bin/env bash
# (2) استرجاع نسخة فارمافلاي (.bak) على SQL Server في Docker، باسم قاعدة pf. قراية بس، مفيش حاجة بترجع لفارمافلاي.
# الاستخدام: bash restore.sh <الشغل> <ملف.bak>
#   كلمة السر بتتعمل لوحدها وبتتحفظ في <الشغل>/mssql.env (مابتتطبعش).
#   MSSQL_PID=Express افتراضي (مجاني، لحد 10 جيجا للقاعدة). لو النسخة أكبر: MSSQL_PID=Developer (للتجربة والنقل بس).
set -euo pipefail
WORK="${1:?اكتب فولدر الشغل}"; BAK="${2:?اكتب ملف .bak}"
NAME="${MSSQL_CONTAINER:-ph-mssql}"; IMAGE="${MSSQL_IMAGE:-mcr.microsoft.com/mssql/server:2022-latest}"
mkdir -p "$WORK/backup"
if [ ! -f "$WORK/mssql.env" ]; then
  umask 077
  echo "MSSQL_SA_PASSWORD=Ph$(head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n')!" > "$WORK/mssql.env"
fi
# shellcheck disable=SC1091
. "$WORK/mssql.env"
cp "$BAK" "$WORK/backup/pf.bak"; chmod a+r "$WORK/backup/pf.bak"
if ! docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" -e ACCEPT_EULA=Y -e "MSSQL_SA_PASSWORD=$MSSQL_SA_PASSWORD" -e "MSSQL_PID=${MSSQL_PID:-Express}" \
    -p 127.0.0.1:1433:1433 -v "$(cd "$WORK/backup" && pwd):/backup:ro" "$IMAGE" >/dev/null
fi
SQL=(docker exec -e "SQLCMDPASSWORD=$MSSQL_SA_PASSWORD" "$NAME" /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -b)
for i in $(seq 1 60); do "${SQL[@]}" -Q "select 1" >/dev/null 2>&1 && break; sleep 2; [ "$i" = 60 ] && { echo "SQL Server ماقامش"; docker logs --tail 20 "$NAME"; exit 1; }; done
# أسامي ملفات القاعدة جوه النسخة
mapfile -t FILES < <("${SQL[@]}" -h -1 -W -s '|' -Q "set nocount on; restore filelistonly from disk = '/backup/pf.bak'" | grep '|' | cut -d'|' -f1,3)
MOVES=""; n=0
for row in "${FILES[@]}"; do
  logical="${row%%|*}"; type="${row##*|}"; n=$((n + 1))
  ext=$([ "$type" = "L" ] && echo ldf || echo mdf)
  MOVES+=", move N'${logical}' to N'/var/opt/mssql/data/pf_${n}.${ext}'"
done
[ -n "$MOVES" ] || { echo "مش قادر أقرا ملفات النسخة"; exit 1; }
"${SQL[@]}" -Q "restore database pf from disk = '/backup/pf.bak' with replace, recovery${MOVES}" | tail -2
"${SQL[@]}" -h -1 -W -Q "set nocount on; select N'اترجعت: ' + cast(count(*) as nvarchar) + N' جدول' from pf.sys.tables"
