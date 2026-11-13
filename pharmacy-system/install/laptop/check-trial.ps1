<#
  التقرير اليومي للتجربة على اللاب: البرامج شغالة؟ القاعدة سليمة؟ فيه أخطاء في السجلات؟ النسخة الاحتياطية؟ المشاكل المفتوحة؟
  بيكتب $Root\reports\<التاريخ>.md، وبيخرج بكود 1 لو فيه حاجة حمرا (ينفع يتشغّل من Task Scheduler). لم يُختبر على ويندوز لسه.
#>
param([string]$Root = "D:\AskerTrial", [int]$PgPort = 5433, [int]$WebPort = 8080, [string]$BackupDir = "D:\AskerBackups")
. (Join-Path $PSScriptRoot "common.ps1")
$psql = Join-Path $PgBin "psql.exe"
$lines = New-Object System.Collections.Generic.List[string]
$red = 0
function Row([string]$what, [bool]$ok, [string]$detail) {
  $script:lines.Add("| $what | $(if ($ok) { 'تمام' } else { 'مشكلة' }) | $detail |")
  if (-not $ok) { $script:red++ }
}
# الاستعلام بيتكتب في ملف UTF-8 ويتقري بـ -f: ويندوز بيبعت العربي في سطر الأوامر بترميز تاني والقاعدة بترفضه
function Q([string]$sql) {
  $f = Join-Path $env:TEMP "asker-q.sql"; Write-Utf8 $f $sql
  try { & $psql -h 127.0.0.1 -p $PgPort -U postgres -d asker -tAX -F "|" -f $f } finally { Remove-Item $f -ErrorAction SilentlyContinue }
}

$lines.Add("# تقرير التجربة $(Get-Date -Format 'yyyy-MM-dd HH:mm')"); $lines.Add("")
$lines.Add("| البند | الحالة | التفاصيل |"); $lines.Add("|---|---|---|")

# 1) البرامج
$pgUp = Test-Postgres
Row "القاعدة (PostgreSQL)" $pgUp ""
Row "المحرك (PostgREST)" ([bool](Get-Process postgrest -ErrorAction SilentlyContinue)) ""
$web = $false; try { $web = (Invoke-WebRequest "http://127.0.0.1:$WebPort/rest/v1/" -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200 } catch {}
Row "البوابة والشاشات" $web "http://127.0.0.1:$WebPort"

if ($pgUp) {
  $env:PGPASSWORD = (Get-Content (Join-Path $Secrets "postgres.txt") -Raw).Trim()
  # 2) الفحص الذاتي
  foreach ($r in (Q "select check_name, ok, detail from ph.health_check()")) {
    $name, $ok, $detail = "$r".Split("|"); Row "فحص: $name" ($ok -eq "t") $detail
  }
  # 3) الحجم والمشاكل
  Row "حجم القاعدة" $true (Q "select pg_size_pretty(pg_database_size('asker'))")
  $open = Q "select coalesce(string_agg(severity || ' ' || n, '، '), 'مفيش') from (select severity, count(*) n from ph.trial_notes where status = 'open' group by 1) x"
  $blockers = Q "select count(*) from ph.trial_notes where status = 'open' and severity = 'blocker'"
  Row "مشاكل مفتوحة (trial_notes)" ("$blockers".Trim() -eq "0") $open
  Row "آخر نقل من فارمافلاي" $true (Q "select coalesce(to_char(max(finished_at), 'YYYY-MM-DD HH24:MI'), 'لسه') from ph.import_runs")
}

# 4) الأخطاء في السجلات النهارده
$today = Get-Date -Format "yyyy-MM-dd"
$pgErr = 0; $pgLog = Join-Path $Logs "postgres.log"
if (Test-Path $pgLog) { $pgErr = @(Select-String -Path $pgLog -Pattern "^$today.*(ERROR|FATAL|PANIC):" | Where-Object { $_.Line -notmatch "مش مسموح|الرصيد مايكفيش|هيعدّي حده|invalid byte sequence for encoding" }).Count }
Row "أخطاء القاعدة النهارده" ($pgErr -eq 0) "$pgErr سطر في logs\postgres.log (من غير الرفض العادي زي «الرصيد مايكفيش»)"
# Caddy بيكتب كل سجلاته (حتى العادية) في caddy.err بصيغة JSON: الغلط بس هو "level":"error"/"fatal"
$apiErr = 0
$p = Join-Path $Logs "postgrest.err"; if (Test-Path $p) { $apiErr += @(Select-String -Path $p -Pattern "FATAL|error" ).Count }
$p = Join-Path $Logs "caddy.err"; if (Test-Path $p) { $apiErr += @(Select-String -Path $p -Pattern '"level":"(error|fatal)"').Count }
Row "أخطاء المحرك والبوابة" ($apiErr -eq 0) "$apiErr سطر"

# 5) النسخة الاحتياطية والقرص
$last = Get-ChildItem $BackupDir -Filter "asker_*.dump" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Row "آخر نسخة احتياطية" ($last -and $last.LastWriteTime -gt (Get-Date).AddHours(-30)) $(if ($last) { "$($last.Name) ($([int]((Get-Date) - $last.LastWriteTime).TotalHours) ساعة)" } else { "مفيش" })
$drive = (Get-Item $Root).PSDrive
$freeGb = [math]::Round($drive.Free / 1GB, 1)
Row "المساحة الفاضية على $($drive.Name):" ($freeGb -gt 5) "$freeGb جيجا"

$dir = Join-Path $Root "reports"; New-Item -ItemType Directory -Force -Path $dir | Out-Null
$file = Join-Path $dir "$today.md"
Write-Utf8 $file (($lines -join "`r`n") + "`r`n")
$lines | ForEach-Object { Write-Host $_ }
Say "$(if ($red) { "فيه $red حاجة محتاجة تتشاف" } else { 'كله تمام' }) ← $file"
exit [int]($red -gt 0)
