#!/usr/bin/env bash
# بيجرب خط النقل كله على نسخة SQL Server تجريبية: نعمل قاعدة صغيرة (عربي، أرقام عشرية، تواريخ، null) ← نسخة .bak
# ← نضغطها zip ← unpack.sh ← restore.sh ← discover.py ← copy.py ← نتأكد إن الداتا وصلت Postgres زي ما هي.
# محتاج: Docker، وصورة mcr.microsoft.com/mssql/server:2022-latest، وPython فيه requirements.txt، وPostgres محلي.
# الاستخدام: PY=python3 PGADMIN=postgresql:///postgres bash pharmacy-system/tests/check-pipeline.sh
set -euo pipefail
cd "$(dirname "$0")/.."
PY="${PY:-python3}"; PGADMIN="${PGADMIN:-postgresql:///postgres}"
WORK=$(mktemp -d); DEMO="ph-mssql-demo"; export MSSQL_CONTAINER="ph-mssql-test"
DB="ph_pipeline_$$"; PGURL="${PGADMIN%/*}/$DB"; export PGURL
cleanup() { docker rm -f "$DEMO" "$MSSQL_CONTAINER" >/dev/null 2>&1 || true; psql "$PGADMIN" -qX -c "drop database if exists $DB" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT

# 1) قاعدة SQL Server تجريبية ونسخة منها (شكل تجريبي، مش شكل فارمافلاي)
PASS="Demo$(head -c 9 /dev/urandom | od -An -tx1 | tr -d ' \n')!"
mkdir -p "$WORK/demo"; chmod 777 "$WORK/demo"
docker run -d --name "$DEMO" -e ACCEPT_EULA=Y -e "MSSQL_SA_PASSWORD=$PASS" -e MSSQL_PID=Express -v "$WORK/demo:/backup" \
  mcr.microsoft.com/mssql/server:2022-latest >/dev/null
SQL=(docker exec -e "SQLCMDPASSWORD=$PASS" "$DEMO" /opt/mssql-tools18/bin/sqlcmd -C -S localhost -U sa -b)
for i in $(seq 1 60); do "${SQL[@]}" -Q "select 1" >/dev/null 2>&1 && break; sleep 2; done
"${SQL[@]}" -Q "
create database demo;
go
use demo;
create table DemoItems (Code int primary key, NameEn nvarchar(100), NameAr nvarchar(100), Price decimal(12,2), Parts tinyint, Active bit, Guid uniqueidentifier, Pic varbinary(16));
create table DemoTickets (ID bigint primary key, TicketDate datetime, CustomerID int null, Total money, Note ntext null);
insert into DemoItems values (1060, N'AUGMENTIN 1G 14TAB', N'اوجمنتين ١ جم', 118.50, 1, 1, newid(), 0x0102), (1259, N'PANADOL EXTRA', N'بنادول اكسترا', 95, 3, 0, null, null);
insert into DemoTickets select top 25000 row_number() over (order by (select 1)), dateadd(minute, row_number() over (order by (select 1)), '2018-01-01'),
  case when row_number() over (order by (select 1)) % 5 = 0 then 7 end, 12.5, N'ملاحظة' from sys.all_objects a cross join sys.all_objects b;
backup database demo to disk = '/backup/demo.bak' with init;
" >/dev/null
docker rm -f "$DEMO" >/dev/null
( cd "$WORK/demo" && zip -q demo.zip demo.bak && rm demo.bak )
echo "OK   اتعملت نسخة تجريبية مضغوطة: $(du -h "$WORK/demo/demo.zip" | cut -f1)"

# 2) الخط نفسه
bash import/unpack.sh "$WORK/job" "$WORK/demo/demo.zip"
BAK=$(find "$WORK/job/unpacked" -iname '*.bak' | head -1)
bash import/restore.sh "$WORK/job" "$BAK"
( cd import && "$PY" discover.py "$WORK/job" )
psql "$PGADMIN" -qX -v ON_ERROR_STOP=1 -c "create database $DB"
( cd import && "$PY" copy.py "$WORK/job" )

# 3) النتيجة
grep -q 'DemoTickets' "$WORK/job/discovery.md" && grep -q '25,000' "$WORK/job/discovery.md" && echo "OK   الخريطة فيها الجداول والأعداد"
got=$(psql "$PGURL" -qXAt -c "select \"NameAr\" || '|' || \"Price\" || '|' || \"Active\" || '|' || (\"Guid\" is not null) || '|' || encode(\"Pic\", 'hex') from pf_raw.\"DemoItems\" where \"Code\" = 1060")
[ "$got" = "اوجمنتين ١ جم|118.50|true|true|0102" ] && echo "OK   العربي والعشري والـ bit والـ uuid والـ binary وصلوا زي ما هم" || { echo "FAIL $got"; exit 1; }
got=$(psql "$PGURL" -qXAt -c "select count(*) || '|' || count(\"CustomerID\") || '|' || min(\"TicketDate\") || '|' || sum(\"Total\") from pf_raw.\"DemoTickets\"")
[ "$got" = "25000|5000|2018-01-01 00:01:00|312500.0000" ] && echo "OK   25 ألف تذكرة بالـ null والتاريخ والمجموع" || { echo "FAIL $got"; exit 1; }
echo "PIPELINE OK"
