# نسخة احتياطية كل ليلة (Task Scheduler): القاعدة كلها في ملف واحد مضغوط، ونحتفظ بآخر 30 نسخة.
# لم يُختبر على ويندوز.
# على اللاب (التجربة): -PgBin D:\AskerTrial\bin\pg\pgsql\bin -Port 5433 -PasswordFile D:\AskerTrial\secrets\postgres.txt
param(
  [string]$Dir = "D:\AskerBackups",
  [string]$PgBin = "C:\Program Files\PostgreSQL\16\bin",
  [int]$Port = 5432,
  [string]$PasswordFile = "",
  [int]$Keep = 30
)
if ($PasswordFile) { $env:PGPASSWORD = (Get-Content $PasswordFile -Raw).Trim() }
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$file = Join-Path $Dir ("asker_" + (Get-Date -Format "yyyy-MM-dd_HHmm") + ".dump")
& "$PgBin\pg_dump.exe" -h 127.0.0.1 -p $Port -U postgres -d asker -Fc -Z 6 -f $file
if ($LASTEXITCODE -ne 0) { Write-Error "النسخة ما اتعملتش"; exit 1 }
Get-ChildItem $Dir -Filter "asker_*.dump" | Sort-Object Name -Descending | Select-Object -Skip $Keep | Remove-Item
Write-Output "اتعملت: $file"
