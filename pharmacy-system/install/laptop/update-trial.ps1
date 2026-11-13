<#
  تحديث البرنامج التجريبي على اللاب بعد أي تعديل. لم يُختبر على ويندوز لسه.
  1) نسخة احتياطية (لو فشلت مابيكملش)  2) آخر كود من الفرع  3) تعديلات القاعدة الجديدة بس
  4) PostgREST يقرا القاعدة من جديد  5) التقرير والفحص الذاتي
  الشاشات بتتحدث لوحدها (Caddy بيقرا من فولدر الكود): اعمل Refresh في المتصفح.
#>
param(
  [string]$Root = "D:\AskerTrial",
  [int]$PgPort = 5433,
  [string]$BackupDir = "D:\AskerBackups",
  [string]$Branch = "ccr-7fcc0f51-5mtsr9",
  [switch]$NoPull      # الكود اتجاب من غير git (get.ps1 بالـ zip)
)
. (Join-Path $PSScriptRoot "common.ps1")
Start-Postgres
$repo = (Resolve-Path (Join-Path $Pharmacy "..")).Path

Say "نسخة احتياطية قبل التحديث"
& (Join-Path $Pharmacy "install\backup.ps1") -Dir $BackupDir -PgBin $PgBin -Port $PgPort -PasswordFile (Join-Path $Secrets "postgres.txt")
if ($LASTEXITCODE -ne 0) { throw "النسخة الاحتياطية فشلت: مش هحدّث" }

if ($NoPull -or -not (Test-Path (Join-Path $repo ".git"))) {
  $before = ""; Say "الكود اتجاب من غير git: مفيش سحب"
} else {
  $before = "$(git -C $repo rev-parse --short HEAD)".Trim()
  git -C $repo pull --ff-only origin $Branch
  if ($LASTEXITCODE -ne 0) { throw "git pull فشل (فيه تعديل على اللاب مااترفعش؟)" }
  $after = "$(git -C $repo rev-parse --short HEAD)".Trim()
  if ($before -eq $after) { Say "مفيش كود جديد" } else { Say "اللي اتغير ($before ← $after):"; git -C $repo log --oneline "$before..$after" }
}

Invoke-Migrations "asker"
if ($before) { Say "لو التحديث ده ماعجبكش: rollback-trial.ps1 -Commit $before" } else { Say "لو التحديث ده ماعجبكش: rollback-trial.ps1 (بيرجّع آخر نسخة احتياطية للقاعدة)" }
& (Join-Path $PSScriptRoot "desktop-icon.ps1") -Root $Root   # الأيقونة (لو اتمسحت أو أول مرة)
& (Join-Path $PSScriptRoot "start-trial.ps1") -Root $Root -PgPort $PgPort   # البرنامج يقوم (لو مش شغال) قبل الفحص
& (Join-Path $PSScriptRoot "check-trial.ps1") -Root $Root -PgPort $PgPort -BackupDir $BackupDir
exit 0   # الفحص بيعرض النتيجة ومابيوقفش التحديث
