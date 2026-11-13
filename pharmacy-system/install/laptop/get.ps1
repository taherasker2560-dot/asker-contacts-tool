<#
  أمر واحد للاب: بيجيب البرنامج ويسطّبه أو يحدّثه ويفتحه. لم يُختبر على ويندوز لسه.
  - أول مرة: بيجيب الكود (git لو موجود، أو zip من GitHub لو مش موجود) ← setup-trial.ps1 -Demo ← يفتح البرنامج.
  - بعد كده: نفس الأمر بيحدّث (نسخة احتياطية للقاعدة ← الكود الجديد ← تعديلات القاعدة) ← يفتح البرنامج.
  -NoDemo: أول تسطيب من غير البيانات التجريبية (هيسألك على كلمة سر المالك).
  مابيلمسش فارمافلاي ولا الهَب: الكود في $Dir والبرنامج وداتاه في $Root.
#>
param(
  [string]$Dir = "D:\asker-contacts-tool",
  [string]$Root = "D:\AskerTrial",
  [string]$Branch = "ccr-7fcc0f51-5mtsr9",
  [switch]$NoDemo
)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$repo = "https://github.com/taherasker2560-dot/asker-contacts-tool"
function Say([string]$m) { Write-Host "== $m" -ForegroundColor Cyan }
function Run([string]$script, [string[]]$more) {
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $laptop $script) @more
  if ($LASTEXITCODE -ne 0) { throw "$script وقف (شوف الرسالة اللي فوق)" }
}

$laptop = Join-Path $Dir "pharmacy-system\install\laptop"
$installed = Test-Path (Join-Path $Root "pgdata\PG_VERSION")
$git = Get-Command git -ErrorAction SilentlyContinue
$noPull = $false

# 1) الكود
if ($git -and (Test-Path (Join-Path $Dir ".git"))) {
  Say "الكود موجود ($Dir): التحديث هيجيب الجديد"
} elseif ($git -and -not (Test-Path $Dir)) {
  Say "تنزيل الكود بـ git في $Dir"
  git clone -b $Branch "$repo.git" $Dir
  if ($LASTEXITCODE -ne 0) { throw "git clone فشل" }
} else {
  # من غير git (أو فولدر مش git): آخر نسخة zip، والكود بس اللي بيتبدل.
  # أمان: لو الفولدر موجود ومش فولدر البرنامج، مانلمسوش (النسخ بيمسح أي حاجة زيادة فيه)
  if ((Test-Path $Dir) -and (Get-ChildItem $Dir -Force | Select-Object -First 1) -and -not (Test-Path (Join-Path $Dir "pharmacy-system"))) {
    throw "الفولدر $Dir فيه حاجات تانية ومش فولدر البرنامج: اختار فولدر تاني بـ -Dir"
  }
  Say "تنزيل آخر نسخة من الكود (zip)"
  $zip = Join-Path $env:TEMP "asker-code.zip"
  $tmp = Join-Path $env:TEMP "asker-code"
  Invoke-WebRequest "$repo/archive/refs/heads/$Branch.zip" -OutFile $zip -UseBasicParsing
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $src = (Get-ChildItem $tmp -Directory | Select-Object -First 1).FullName
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  robocopy $src $Dir /MIR /XD .git /NFL /NDL /NJH /NJS /NP | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "نسخ الكود فشل (robocopy $LASTEXITCODE)" }
  $global:LASTEXITCODE = 0
  $noPull = $true
}

# 2) أول مرة: تسطيب. بعد كده: تحديث
if (-not $installed) {
  Say "أول تسطيب في $Root"
  $args2 = @("-Root", $Root); if (-not $NoDemo) { $args2 += "-Demo" }
  Run "setup-trial.ps1" $args2
} else {
  Say "تحديث"
  $args2 = @("-Root", $Root, "-Branch", $Branch); if ($noPull) { $args2 += "-NoPull" }
  Run "update-trial.ps1" $args2
}

# 3) افتح البرنامج
Run "open-app.ps1" @("-Root", $Root)
Say "البرنامج اتفتح. بعد كده: أيقونة «صيدلية عسكر» على سطح المكتب أو Ctrl+Alt+A"
if (-not $installed -and -not $NoDemo) { Say "الدخول: taher وكلمة السر demo-pass-1 (بيانات تجريبية)" }
