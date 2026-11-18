# تجربة المراقب بتهنيج حقيقي لبرنامج وهمي (HangTest.exe) من غير ما يلمس فارمافلاي.
# شغّله من نفس المجلد في PowerShell عادي (مش Admin)، وسيب نافذته مفتوحة.
$here = $PSScriptRoot
$fake = Join-Path $env:TEMP 'HangTest.exe'
Copy-Item "$PSHOME\powershell.exe" $fake -Force
$code = 'Add-Type -AssemblyName System.Windows.Forms; $f=New-Object Windows.Forms.Form; $f.Text="HangTest"; $f.Add_Shown({ Start-Sleep -Seconds 40 }); [Windows.Forms.Application]::Run($f)'
$w = Start-Process -FilePath $fake -ArgumentList @('-NoProfile','-STA','-Command',$code) -PassThru
Write-Host 'شغّلت برنامج وهمي هيتهنج بعد ثواني لمدة 40 ثانية. المراقب هيتشغّل 90 ثانية على HangTest.'
Start-Sleep -Seconds 3
$job = Start-Job -ScriptBlock { param($h) & "$h\watcher.ps1" -ProcessName 'HangTest' } -ArgumentList $here
Start-Sleep -Seconds 90
Receive-Job $job | Select-Object -Last 15
Stop-Job $job; Remove-Job $job -Force
if (-not $w.HasExited) { $w.Kill() }
Write-Host 'خلص. شوف مجلد incidents\ فيه حادثة hang ولقطات، وwatcher.log.'
