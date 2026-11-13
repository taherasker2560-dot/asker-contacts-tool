<#
  الأيقونة اللي على سطح المكتب بتشغّل ده: لو البرنامج مش شغال يشغّله (start-trial.ps1)، وبعدين يفتحه في نافذة لوحده
  (Edge أو Chrome بخيار --app): من غير شريط عنوان ولا تابات، فالمتصفح مش بياخد أي مفتاح قبل البرنامج.
  البروفايل لوحده في $Root\browser: الجلسة والفواتير اللي مستنية الشبكة بتاعة البرنامج بس، ومفيش إضافات بتلعب في المفاتيح.
  لم يُختبر على ويندوز لسه.
#>
param(
  [string]$Root = "D:\AskerTrial",
  [int]$WebPort = 8080
)
. (Join-Path $PSScriptRoot "common.ps1")

function Show-Error([string]$m) {
  Add-Type -AssemblyName PresentationFramework
  [System.Windows.MessageBox]::Show($m, "صيدلية عسكر", "OK", "Error") | Out-Null
}

$url = "http://127.0.0.1:$WebPort/"
$up = $false
try { $up = (Invoke-WebRequest "$($url)rest/v1/" -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200 } catch {}
if (-not $up) {
  try { & (Join-Path $PSScriptRoot "start-trial.ps1") -Root $Root -WebPort $WebPort | Out-Null }
  catch { Show-Error "البرنامج ماقامش:`n$($_.Exception.Message)`n`nالتفاصيل في $Root\logs"; exit 1 }
}

$browser = Find-Browser
if (-not $browser) { Show-Error "مالقيتش Edge ولا Chrome على الجهاز ده. افتح $url من أي متصفح."; exit 1 }
$userData = Join-Path $Root "browser"
New-Item -ItemType Directory -Force -Path $userData | Out-Null
Start-Process -FilePath $browser -ArgumentList @(
  "--app=$url", "--user-data-dir=`"$userData`"", "--no-first-run", "--no-default-browser-check", "--start-maximized"
)
