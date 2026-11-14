<#
  الأيقونة اللي على سطح المكتب بتشغّل ده: لو البرنامج مش شغال يشغّله (start-trial.ps1)، وبعدين يفتحه في نافذة لوحده
  (Edge أو Chrome بخيار --app): من غير شريط عنوان ولا تابات، فالمتصفح مش بياخد أي مفتاح قبل البرنامج.
  البروفايل لوحده في $Root\browser: الجلسة والفواتير اللي مستنية الشبكة بتاعة البرنامج بس، ومفيش إضافات بتلعب في المفاتيح.
  جلسة اللاب صلّحت نفس الفكرة واتجربت (3 ثواني والنافذة قدام)، والنسخة دي من وصفها (2026-11-14) ولسه ماتجربتش على ويندوز.
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

# النافذة بتاخد وقت تفتح (لحد 30 ثانية بعد تشغيل الجهاز) وكانت بتفتح ورا الشبابيك التانية، فكان بيبان إن الأيقونة
# مابتعملش حاجة (اتلاحظ على اللاب 2026-11-14). دلوقتي: لو مفتوحة بنجيبها قدام على طول، ولو لأ بنفتحها ونجيبها قدام.
Add-Type @"
using System; using System.Runtime.InteropServices;
public static class AskerWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
}
"@
function Find-AppWindow {
  Get-Process msedge, chrome -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -like '*صيدلية عسكر*' } | Select-Object -First 1
}
function Show-AppWindow($p) {
  $h = $p.MainWindowHandle
  if ([AskerWin]::IsIconic($h)) { [AskerWin]::ShowWindow($h, 9) | Out-Null } else { [AskerWin]::ShowWindow($h, 5) | Out-Null }   # 9 = رجّعها من التصغير، 5 = اظهر
  [AskerWin]::SetForegroundWindow($h) | Out-Null
}
$w = Find-AppWindow
if ($w) { Show-AppWindow $w; exit 0 }

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
# نستنى النافذة (لحد 60 ثانية) ونجيبها قدام
for ($i = 0; $i -lt 120; $i++) {
  Start-Sleep -Milliseconds 500
  $w = Find-AppWindow
  if ($w) { Show-AppWindow $w; break }
}
