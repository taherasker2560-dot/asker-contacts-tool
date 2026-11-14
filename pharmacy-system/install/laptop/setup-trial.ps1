<#
  تسطيب تجريبي لبرنامج صيدلية عسكر على اللاب (مرة واحدة). لم يُختبر على ويندوز لسه.
  بينزّل PostgreSQL وPostgREST وCaddy في $Root، يعمل القاعدة من ملفات db\، يعمل الأسرار، ويسجّل المالك.
  -ResetDb : يمسح القاعدة ويعملها من الأول (عشان نعيد النقل من فارمافلاي)، والأسرار زي ما هي.
  -OwnerPasswordFile <ملف> : كلمة سر المالك من ملف بدل ما تتكتب (لـ Claude على اللاب). الملف بيتمسح بعدها،
     والمالك يغيّرها من الإعدادات أول ما يدخل.
  التشغيل: powershell -ExecutionPolicy Bypass -File setup-trial.ps1
#>
param(
  [string]$Root = "D:\AskerTrial",
  [int]$PgPort = 5433,
  [int]$ApiPort = 3010,
  [string]$OwnerUser = "taher",
  [switch]$ResetDb,
  [string]$OwnerPasswordFile,
  [switch]$Demo,          # بيانات تجريبية (وهمية) عشان تشوف الشاشات مليانة قبل نقل فارمافلاي. بعدين: -ResetDb من غيره
  [string]$PgZipUrl = "https://get.enterprisedb.com/postgresql/postgresql-16.4-1-windows-x64-binaries.zip",
  [string]$PostgrestUrl = "https://github.com/PostgREST/postgrest/releases/download/v12.2.3/postgrest-v12.2.3-windows-x64.zip",
  [string]$CaddyUrl = "https://github.com/caddyserver/caddy/releases/download/v2.8.4/caddy_2.8.4_windows_amd64.zip"
)
. (Join-Path $PSScriptRoot "common.ps1")

foreach ($d in @($Root, $Secrets, $Conf, $Logs, (Join-Path $Root "bin"), (Join-Path $Root "downloads"))) {
  New-Item -ItemType Directory -Force -Path $d | Out-Null
}
# فولدر الأسرار لصاحب الحساب بس
icacls $Secrets /inheritance:r /grant:r "${env:USERNAME}:(OI)(CI)F" | Out-Null

# 1) البرامج (zip من غير تسطيب)، وبصمة كل ملف بتتطبع عشان تتراجع
function Get-Zip([string]$url, [string]$dest) {
  if (Test-Path $dest) { return }
  $zip = Join-Path $Root ("downloads\" + [IO.Path]::GetFileName(([uri]$url).AbsolutePath))
  if (-not (Test-Path $zip)) { Say "تنزيل $url"; Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing }
  Say ("SHA256 " + (Get-FileHash $zip -Algorithm SHA256).Hash + "  " + (Split-Path $zip -Leaf))
  Expand-Archive -Path $zip -DestinationPath $dest -Force
}
Get-Zip $PgZipUrl     (Join-Path $Root "bin\pg")
Get-Zip $PostgrestUrl (Join-Path $Root "bin\postgrest")
Get-Zip $CaddyUrl     (Join-Path $Root "bin\caddy")

# 2) PostgreSQL في $Root\pgdata
if (-not (Test-Path (Join-Path $PgData "PG_VERSION"))) {
  Say "تجهيز PostgreSQL"
  $su = New-Secret 32
  Write-Utf8 (Join-Path $Secrets "postgres.txt") $su
  $pw = Join-Path $Secrets "pw.tmp"; Write-Utf8 $pw $su
  & (Join-Path $PgBin "initdb.exe") -D $PgData -U postgres -E UTF8 --no-locale -A scram-sha-256 "--pwfile=$pw"
  Remove-Item $pw
  if ($LASTEXITCODE -ne 0) { throw "initdb فشل" }
}
Start-Postgres

# 3) القاعدة
$psql = Join-Path $PgBin "psql.exe"
if ($ResetDb) {
  # سجل المشاكل بيتحفظ CSV قبل المسح
  $notes = Join-Path $Root ("reports\trial_notes_" + (Get-Date -Format "yyyy-MM-dd_HHmm") + ".csv")
  New-Item -ItemType Directory -Force -Path (Split-Path $notes) | Out-Null
  & $psql -h 127.0.0.1 -p $PgPort -U postgres -d asker -q -X -c "\copy (select * from ph.trial_notes order by id) to '$($notes.Replace('\', '/'))' with csv header"   # «/» عشان psql مايقراش \t كـ Tab
  if ($LASTEXITCODE -eq 0) { Say "سجل المشاكل اتحفظ: $notes" }
  Say "مسح القاعدة asker"
  & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -q -X -c "drop database if exists asker with (force)"
}
$exists = & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -tAX -c "select 1 from pg_database where datname = 'asker'"
# تسطيب قبل كده وقف في النص (القاعدة موجودة بس إعدادات المحرك ماتكتبتش): نعملها من الأول
if ("$exists".Trim() -eq "1" -and -not (Test-Path (Join-Path $Conf "postgrest.conf"))) {
  Say "تسطيب قبل كده ماكملش: القاعدة هتتعمل من الأول"
  & $psql -h 127.0.0.1 -p $PgPort -U postgres -d postgres -q -X -c "drop database if exists asker with (force)"
  $exists = ""
}
if ("$exists".Trim() -ne "1") {
  & (Join-Path $PgBin "createdb.exe") -h 127.0.0.1 -p $PgPort -U postgres asker
  Get-ChildItem (Join-Path $Pharmacy "db") -Filter "*.sql" | Where-Object { $_.Name -match '^\d\d-' } | Sort-Object Name |
    ForEach-Object { Say "تحميل $($_.Name)"; Invoke-Psql "asker" $_.FullName }
  Invoke-Migrations "asker"

  # 4) الأسرار (مرة واحدة، وبتتعاد استخدامها مع -ResetDb)
  $jwtFile = Join-Path $Secrets "jwt_secret.txt"; $authFile = Join-Path $Secrets "authenticator.txt"
  if (-not (Test-Path $jwtFile))  { Write-Utf8 $jwtFile  (New-Secret 48) }
  if (-not (Test-Path $authFile)) { Write-Utf8 $authFile (New-Secret 32) }
  $jwt = (Get-Content $jwtFile -Raw).Trim(); $auth = (Get-Content $authFile -Raw).Trim()

  # 5) إعدادات الصيدلية + المالك (كلمة السر بتتكتب هنا ومابتتحفظش)
  if ($Demo) {
    # البيانات التجريبية: 5 شهور وهمية + اليوزرات taher و cashier و pharmacist (كلمة السر demo-pass-1، للتجربة بس)
    $tmp = Join-Path $Secrets "init.tmp.sql"
    Write-Utf8 $tmp "insert into auth.config values ('jwt_secret', '$jwt');`nalter role authenticator password '$auth';`n"
    try { Invoke-Psql "asker" $tmp } finally { Remove-Item $tmp -ErrorAction SilentlyContinue }
    Say "تحميل البيانات التجريبية (دقيقة تقريبًا)"
    Invoke-Psql "asker" (Join-Path $Pharmacy "tools\demo-seed.sql")
  } else {
  if ($OwnerPasswordFile) {
    $plain = (Get-Content $OwnerPasswordFile -Raw -Encoding UTF8).Trim()
    Remove-Item $OwnerPasswordFile -ErrorAction SilentlyContinue
    if ($plain.Length -lt 8) { throw "كلمة سر المالك في الملف أقل من 8 حروف" }
  } else {
    $sec = Read-Host "كلمة سر المالك ($OwnerUser)، 8 حروف على الأقل" -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec))
  }
  $tmp = Join-Path $Secrets "init.tmp.sql"
  Write-Utf8 $tmp @"
insert into auth.config values ('jwt_secret', '$jwt');
alter role authenticator password '$auth';
insert into ph.settings (pharmacy_name) values ('صيدلية عسكر (تجربة)');
insert into ph.branches (name) values ('الفرع الرئيسي');
insert into ph.cash_accounts (branch_id, name, kind) values (1, 'درج 1', 'drawer'), (1, 'الخزنة', 'safe'), (1, 'فيزا', 'bank'), (1, 'محفظة', 'wallet');
insert into ph.payment_methods values ('cash', 'كاش', 1), ('card', 'فيزا', 3), ('wallet', 'محفظة', 4), ('instapay', 'InstaPay', 4), ('credit', 'آجل', null);
select auth.bootstrap_owner('$OwnerUser', '$($plain.Replace("'", "''"))', 'د. طاهر');
"@
  try { Invoke-Psql "asker" $tmp } finally { Remove-Item $tmp -ErrorAction SilentlyContinue; $plain = $null }
  }

  # 6) إعدادات PostgREST
  Write-Utf8 (Join-Path $Conf "postgrest.conf") @"
db-uri = "postgres://authenticator:$auth@127.0.0.1:$PgPort/asker"
db-schemas = "ph"
db-anon-role = "anon"
db-pre-request = "auth.check_request"
jwt-secret = "$jwt"
server-host = "127.0.0.1"
server-port = $ApiPort
"@
}
& (Join-Path $PSScriptRoot "desktop-icon.ps1") -Root $Root
Say "التسطيب خلص. دوس على أيقونة «صيدلية عسكر» على سطح المكتب (أو Ctrl+Alt+A)"
if ($Demo) { Say "بيانات تجريبية: ادخل بـ taher وكلمة السر demo-pass-1. قبل نقل داتا الصيدلية: setup-trial.ps1 -ResetDb" }
