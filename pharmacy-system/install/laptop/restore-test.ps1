<#
  النسخة الاحتياطية بترجع فعلًا؟ آخر نسخة ← قاعدة لوحدها (asker_restore) ← الفحص الذاتي ← نقارن عدد الفواتير والحركات بالأصل ← نمسحها.
  مابيلمسش قاعدة التجربة. لم يُختبر على ويندوز لسه.
#>
param([string]$Root = "D:\AskerTrial", [int]$PgPort = 5433, [string]$BackupDir = "D:\AskerBackups")
. (Join-Path $PSScriptRoot "common.ps1")
Start-Postgres
$psql = Join-Path $PgBin "psql.exe"
$last = Get-ChildItem $BackupDir -Filter "asker_*.dump" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $last) { throw "مفيش نسخ في $BackupDir: شغّل backup.ps1 الأول" }
Say "برجّع $($last.Name)"
& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -q -X -c "drop database if exists asker_restore with (force)"
& (Join-Path $PgBin "createdb.exe") -h 127.0.0.1 -p $PgPort -U postgres asker_restore
try {
  & (Join-Path $PgBin "pg_restore.exe") -h 127.0.0.1 -p $PgPort -U postgres -d asker_restore --no-owner --exit-on-error $last.FullName
  if ($LASTEXITCODE -ne 0) { throw "pg_restore فشل" }
  $count = "select (select count(*) from ph.sales) || '|' || (select count(*) from ph.stock_moves) || '|' || (select count(*) from ph.party_ledger)"
  $a = (& $psql -h 127.0.0.1 -p $PgPort -U postgres -d asker_restore -tAX -c $count).Trim()
  $bad = (& $psql -h 127.0.0.1 -p $PgPort -U postgres -d asker_restore -tAX -c "select count(*) from ph.health_check() where not ok").Trim()
  Say "النسخة: فواتير|حركات مخزون|حركات حسابات = $a · قواعد فشلت = $bad"
  Say "الأصل دلوقتي: $((& $psql -h 127.0.0.1 -p $PgPort -U postgres -d asker -tAX -c $count).Trim()) (ممكن يزيد لو فيه شغل بعد النسخة)"
  if ($bad -ne "0") { throw "النسخة رجعت بس الفحص الذاتي فيه مشاكل" }
  Say "النسخة الاحتياطية بترجع سليمة"
} finally {
  & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -q -X -c "drop database if exists asker_restore with (force)"
}
