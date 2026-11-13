# إعدادات مشتركة لسكريبتات التجربة على اللاب. كل حاجة في فولدر واحد ($Root)، ومسحه = البرنامج اتشال.
# بورتات لوحدها، فمش بيلمس فارمافلاي ولا SQL Server بتاع الهَب ولا أي PostgreSQL تاني.
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$env:PGCLIENTENCODING = "UTF8"          # ملفات القاعدة عربي UTF-8
$env:PGOPTIONS = "-c client_min_messages=warning"
$Pharmacy = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path   # فولدر pharmacy-system
$PgBin    = Join-Path $Root "bin\pg\pgsql\bin"
$PgData   = Join-Path $Root "pgdata"
$Secrets  = Join-Path $Root "secrets"
$Conf     = Join-Path $Root "conf"
$Logs     = Join-Path $Root "logs"

function Say([string]$m) { Write-Host "== $m" -ForegroundColor Cyan }

function New-Secret([int]$n) {
  $chars = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789'
  $bytes = New-Object byte[] $n
  (New-Object System.Security.Cryptography.RNGCryptoServiceProvider).GetBytes($bytes)
  -join ($bytes | ForEach-Object { $chars[$_ % $chars.Length] })
}

# ملف UTF-8 من غير BOM (psql مابيحبش الـ BOM)
function Write-Utf8([string]$path, [string]$text) {
  [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $false))
}

function Invoke-Psql([string]$db, [string]$file) {
  & (Join-Path $PgBin "psql.exe") -h 127.0.0.1 -p $PgPort -U postgres -d $db -v ON_ERROR_STOP=1 -q -X -f $file
  if ($LASTEXITCODE -ne 0) { throw "psql وقف في $file" }
}

function Test-Postgres {
  $old = $ErrorActionPreference; $ErrorActionPreference = "Continue"
  & (Join-Path $PgBin "pg_ctl.exe") -D $PgData status *> $null
  $ok = ($LASTEXITCODE -eq 0); $ErrorActionPreference = $old
  return $ok
}

function Start-Postgres {
  if (-not (Test-Postgres)) {
    & (Join-Path $PgBin "pg_ctl.exe") -D $PgData -l (Join-Path $Logs "postgres.log") -o "-p $PgPort -c listen_addresses=127.0.0.1" -w start
    if ($LASTEXITCODE -ne 0) { throw "PostgreSQL ماقامش: شوف $Logs\postgres.log" }
  }
  $env:PGPASSWORD = (Get-Content (Join-Path $Secrets "postgres.txt") -Raw).Trim()
}

# تعديلات القاعدة (db\migrations): اللي لسه ماتطبقش بس، كل ملف في عملية واحدة، ومتسجل في ph.schema_migrations.
# بيوقف لو ملف اتطبق قبل كده واتعدّل بعدها. نفس قواعد tools/migrate.sh.
function Invoke-Migrations([string]$db) {
  $psql = Join-Path $PgBin "psql.exe"
  $n = 0
  foreach ($f in (Get-ChildItem (Join-Path $Pharmacy "db\migrations") -Filter "*.sql" -ErrorAction SilentlyContinue | Sort-Object Name)) {
    $v = $f.BaseName
    $sum = (Get-FileHash $f.FullName -Algorithm SHA256).Hash.ToLower()
    $old = "$(& $psql -h 127.0.0.1 -p $PgPort -U postgres -d $db -tAX -c "select coalesce(checksum, '') from ph.schema_migrations where version = '$v'")".Trim()
    if ($old) {
      if ($old -ne $sum) { throw "وقفت: $v اتطبق قبل كده والملف اتعدّل بعدها. اعمل ملف جديد بدل ما تعدّله" }
      continue
    }
    & $psql -h 127.0.0.1 -p $PgPort -U postgres -d $db -v ON_ERROR_STOP=1 -q -X -1 -f $f.FullName `
      -c "insert into ph.schema_migrations (version, checksum) values ('$v', '$sum')"
    if ($LASTEXITCODE -ne 0) { throw "فشل $v (مااتطبقش منه حاجة). لو محتاج ترجع: rollback-trial.ps1" }
    Say "اتطبق: $v"; $n++
  }
  & $psql -h 127.0.0.1 -p $PgPort -U postgres -d $db -q -X -c "notify pgrst, 'reload schema'"
  Say "تعديلات جديدة في القاعدة: $n"
}
