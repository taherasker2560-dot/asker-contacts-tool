# نسخة احتياطية كل ليلة (Task Scheduler): القاعدة كلها في ملف واحد مضغوط، ونحتفظ بآخر 30 نسخة.
# لم يُختبر على ويندوز.
param(
  [string]$Dir = "D:\AskerBackups",
  [string]$PgBin = "C:\Program Files\PostgreSQL\16\bin",
  [int]$Keep = 30
)
New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$file = Join-Path $Dir ("asker_" + (Get-Date -Format "yyyy-MM-dd_HHmm") + ".dump")
& "$PgBin\pg_dump.exe" -U postgres -d asker -Fc -Z 6 -f $file
if ($LASTEXITCODE -ne 0) { Write-Error "النسخة ما اتعملتش"; exit 1 }
Get-ChildItem $Dir -Filter "asker_*.dump" | Sort-Object Name -Descending | Select-Object -Skip $Keep | Remove-Item
Write-Output "اتعملت: $file"
