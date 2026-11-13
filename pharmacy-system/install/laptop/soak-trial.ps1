<#
  اختبار ضغط على اللاب: قاعدة لوحدها (asker_soak) بداتا متولّدة، كذا كاشير بيبيعوا في نفس الوقت، وبعدها الفحص الذاتي.
  مابيلمسش قاعدة التجربة (asker). بيتمسح في الآخر. لم يُختبر على ويندوز لسه.
  التشغيل: powershell -ExecutionPolicy Bypass -File soak-trial.ps1 -Clients 4 -Seconds 60
#>
param([string]$Root = "D:\AskerTrial", [int]$PgPort = 5433, [int]$Clients = 4, [int]$Seconds = 60)
. (Join-Path $PSScriptRoot "common.ps1")
Start-Postgres
$psql = Join-Path $PgBin "psql.exe"; $tests = Join-Path $Pharmacy "tests"
& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -q -X -c "drop database if exists asker_soak with (force)"
& (Join-Path $PgBin "createdb.exe") -h 127.0.0.1 -p $PgPort -U postgres asker_soak
try {
  Get-ChildItem (Join-Path $Pharmacy "db") -Filter "*.sql" | Where-Object { $_.Name -match '^\d\d-' } | Sort-Object Name |
    ForEach-Object { Invoke-Psql "asker_soak" $_.FullName }
  Invoke-Psql "asker_soak" (Join-Path $tests "soak-setup.sql")
  Say "$Clients كاشير لمدة $Seconds ثانية"
  $env:PGOPTIONS = "-c role=authenticated -c request.jwt.claim.sub=00000000-0000-0000-0000-0000000000c1"
  $out = & (Join-Path $PgBin "pgbench.exe") -h 127.0.0.1 -p $PgPort -U postgres -n -c $Clients -j $Clients -T $Seconds `
    -f "$(Join-Path $tests 'soak-sale.sql')@9" -f "$(Join-Path $tests 'soak-search.sql')@1" asker_soak 2>&1
  $env:PGOPTIONS = "-c client_min_messages=warning"
  $out | Select-String "number of failed|latency average|tps =" | ForEach-Object { "  " + $_.Line.Trim() }
  $res = & $psql -h 127.0.0.1 -p $PgPort -U postgres -d asker_soak -tAX -F "|" -c "select (select count(*) from ph.sales), (select max(split_part(no, '-', 3)::int) from ph.sales), (select count(*) from ph.health_check() where not ok)"
  $sales, $maxno, $bad = "$res".Trim().Split("|")
  Say "فواتير: $sales · آخر رقم: $maxno · قواعد فشلت في الفحص: $bad"
  if ($bad -ne "0" -or $sales -ne $maxno) { & $psql -h 127.0.0.1 -p $PgPort -U postgres -d asker_soak -X -c "select * from ph.health_check() where not ok"; throw "اختبار الضغط فشل" }
  Say "اختبار الضغط عدّى"
} finally {
  & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -q -X -c "drop database if exists asker_soak with (force)"
}
