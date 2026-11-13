<#
  أيقونة «صيدلية عسكر» على سطح المكتب وفي قايمة Start: بتشغّل البرنامج لو مش شغال، وتفتحه في نافذة لوحده.
  وكمان Ctrl+Alt+A من أي مكان في الويندوز بيفتح البرنامج.
  -Remove بيشيل الأيقونات. setup-trial.ps1 و update-trial.ps1 بيشغّلوه لوحدهم. لم يُختبر على ويندوز لسه.
#>
param(
  [string]$Root = "D:\AskerTrial",
  [int]$WebPort = 8080,
  [string]$Hotkey = "CTRL+ALT+A",
  [switch]$Remove
)
. (Join-Path $PSScriptRoot "common.ps1")

$places = @([Environment]::GetFolderPath("Desktop"), [Environment]::GetFolderPath("Programs")) | Where-Object { $_ }
$names = @("صيدلية عسكر.lnk", "Asker Pharmacy.lnk")

if ($Remove) {
  foreach ($p in $places) { foreach ($n in $names) { Remove-Item (Join-Path $p $n) -ErrorAction SilentlyContinue } }
  Say "الأيقونات اتشالت"; exit 0
}

if (-not (Find-Browser)) { Say "تنبيه: مالقيتش Edge ولا Chrome. الأيقونة هتتعمل، بس محتاجة واحد منهم" }
$ws = New-Object -ComObject WScript.Shell
$ps = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$script = Join-Path $PSScriptRoot "open-app.ps1"
$icon = Join-Path $PSScriptRoot "asker.ico"
$i = 0
foreach ($p in $places) {
  $made = $false
  foreach ($n in $names) {   # الاسم العربي الأول، ولو الويندوز رفضه الإنجليزي
    try {
      $lnk = $ws.CreateShortcut((Join-Path $p $n))
      $lnk.TargetPath = $ps
      $lnk.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`" -Root `"$Root`" -WebPort $WebPort"
      $lnk.WorkingDirectory = $PSScriptRoot
      $lnk.IconLocation = "$icon,0"
      $lnk.Description = "برنامج صيدلية عسكر"
      $lnk.WindowStyle = 7          # من غير ما تبان نافذة PowerShell
      if ($i -eq 0 -and $Hotkey) { $lnk.Hotkey = $Hotkey }   # الاختصار على أيقونة واحدة بس عشان مايتكررش
      $lnk.Save()
      Say "اتعملت: $(Join-Path $p $n)"
      $made = $true; break
    } catch { continue }
  }
  if (-not $made) { Say "ماقدرتش أعمل أيقونة في $p" }
  $i++
}
Say "دوس على «صيدلية عسكر» على سطح المكتب، أو $Hotkey من أي مكان"
