<#
  الرجوع لنسخة احتياطية (غالبًا اللي اتعملت قبل آخر تحديث). بيمسح قاعدة التجربة الحالية ويرجّع النسخة مكانها.
  -Commit <رقم>: يرجّع الكود كمان للنسخة دي (update-trial.ps1 بيطبع الرقم). لم يُختبر على ويندوز لسه.
#>
param(
  [string]$Root = "D:\AskerTrial",
  [int]$PgPort = 5433,
  [string]$BackupDir = "D:\AskerBackups",
  [string]$File = "",
  [string]$Commit = ""
)
. (Join-Path $PSScriptRoot "common.ps1")
Start-Postgres
$dump = if ($File) { Get-Item $File } else { Get-ChildItem $BackupDir -Filter "asker_*.dump" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 }
if (-not $dump) { throw "مفيش نسخة احتياطية في $BackupDir" }
Write-Host "هرجّع $($dump.Name) ($($dump.LastWriteTime)) مكان القاعدة الحالية. أي شغل اتعمل بعدها هيروح." -ForegroundColor Yellow
if ((Read-Host "اكتب yes عشان أكمل") -ne "yes") { Say "مارجعتش حاجة"; exit 0 }

Get-Process caddy, postgrest -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Root*" } | Stop-Process -Force
$psql = Join-Path $PgBin "psql.exe"
& $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -q -X -c "drop database if exists asker with (force)"
& (Join-Path $PgBin "createdb.exe") -h 127.0.0.1 -p $PgPort -U postgres asker
& (Join-Path $PgBin "pg_restore.exe") -h 127.0.0.1 -p $PgPort -U postgres -d asker --no-owner --exit-on-error $dump.FullName
if ($LASTEXITCODE -ne 0) { throw "pg_restore فشل: النسخة في $($dump.FullName)" }
if ($Commit) {
  $repo = (Resolve-Path (Join-Path $Pharmacy "..")).Path
  git -C $repo checkout $Commit
  Say "الكود رجع لـ $Commit. لما التعديل يتصلح: git checkout ccr-7fcc0f51-5mtsr9 ثم update-trial.ps1"
}
& (Join-Path $PSScriptRoot "start-trial.ps1") -Root $Root -PgPort $PgPort
& (Join-Path $PSScriptRoot "check-trial.ps1") -Root $Root -PgPort $PgPort -BackupDir $BackupDir
