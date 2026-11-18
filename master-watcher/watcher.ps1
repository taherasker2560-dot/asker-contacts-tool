# مراقب فارمافلاي على الماستر - صندوق أسود + تنبيه تهنيج/إغلاق
# يشتغل في جلسة المستخدم المفتوحة (لازم عشان لقطات الشاشة). PowerShell 5.1.
#   .\watcher.ps1              تشغيل عادي
#   .\watcher.ps1 -Install     تسجيل مهمة تشتغل تلقائي عند دخول المستخدم
#   .\watcher.ps1 -Uninstall   حذف المهمة
#   .\watcher.ps1 -SelfTest    لقطة + حادثة تجريبية + تنبيه (من غير ما يلمس فارمافلاي)
param(
    [string]$ConfigPath = (Join-Path $PSScriptRoot 'config.json'),
    [string]$ProcessName,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$SelfTest
)
$ErrorActionPreference = 'Stop'
$TaskName = 'AskerMasterWatcher'

if ($Uninstall) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false; Write-Host 'تم حذف المهمة'; return }
if ($Install) {
    $arg = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
    $trg = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
    $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 99 -RestartInterval (New-TimeSpan -Minutes 1)
    $pri = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
    Register-ScheduledTask -TaskName $TaskName -Action $act -Trigger $trg -Settings $set -Principal $pri -Force | Out-Null
    Write-Host 'تم التسجيل. هيشتغل عند دخولك الجاي، أو شغّله دلوقتي: Start-ScheduledTask AskerMasterWatcher'
    return
}

$cfg = Get-Content -Raw -Encoding UTF8 $ConfigPath | ConvertFrom-Json
if ($ProcessName) { $cfg.ProcessName = $ProcessName }

$Root     = $PSScriptRoot
$FramesD  = Join-Path $Root 'frames'
$IncD     = Join-Path $Root 'incidents'
$LogF     = Join-Path $Root 'watcher.log'
$BeatF    = Join-Path $Root 'heartbeat.txt'
foreach ($d in @($FramesD, $IncD)) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }

Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Windows.Forms
Add-Type @'
using System.Runtime.InteropServices;
public static class AskerDpi { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
'@
[void][AskerDpi]::SetProcessDPIAware()

function Log([string]$m) {
    $line = '{0:yyyy-MM-dd HH:mm:ss}  {1}' -f (Get-Date), $m
    Add-Content -Path $LogF -Value $line -Encoding UTF8
    Write-Host $line
}

function Save-Frame {
    # لقطة للشاشة الرئيسية مصغّرة، بتتحفظ في frames\ باسم الوقت
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    try {
        $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
        $w = [int]($b.Width * $cfg.FrameScale); $h = [int]($b.Height * $cfg.FrameScale)
        $small = New-Object System.Drawing.Bitmap($bmp, $w, $h)
        try {
            $enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
            $ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
            $ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]$cfg.JpegQuality)
            $path = Join-Path $FramesD ('{0:yyyyMMdd_HHmmss}.jpg' -f (Get-Date))
            $small.Save($path, $enc, $ep)
            return $path
        } finally { $small.Dispose() }
    } finally { $g.Dispose(); $bmp.Dispose() }
}

function Trim-Frames {
    $all = @(Get-ChildItem -Path $FramesD -Filter *.jpg | Sort-Object Name)
    $extra = $all.Count - [int]$cfg.KeepFrames
    if ($extra -gt 0) { $all | Select-Object -First $extra | Remove-Item -Force -ErrorAction SilentlyContinue }
}

function Send-Alert([string]$text) {
    Log ('ALERT: ' + $text)
    if ($cfg.Alert.Beep) { try { [console]::Beep(1200, 400); [console]::Beep(900, 400); [console]::Beep(1200, 400) } catch {} }
    if ($cfg.Alert.TelegramBotToken -and $cfg.Alert.TelegramChatId) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $u = 'https://api.telegram.org/bot' + $cfg.Alert.TelegramBotToken + '/sendMessage'
            Invoke-RestMethod -Uri $u -Method Post -Body @{ chat_id = $cfg.Alert.TelegramChatId; text = $text } -TimeoutSec 15 | Out-Null
        } catch { Log ('telegram failed: ' + $_.Exception.Message) }
    }
    if ($cfg.Alert.WebhookUrl) {
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $body = (@{ source = 'asker-master-watcher'; text = $text; at = (Get-Date).ToString('s') } | ConvertTo-Json)
            Invoke-RestMethod -Uri $cfg.Alert.WebhookUrl -Method Post -Body ([Text.Encoding]::UTF8.GetBytes($body)) -ContentType 'application/json; charset=utf-8' -TimeoutSec 15 | Out-Null
        } catch { Log ('webhook failed: ' + $_.Exception.Message) }
    }
}

function New-Incident([string]$kind, [string]$detail, [datetime]$when) {
    # بيحفظ آخر لقطات الشاشة اللي كانت قبل الحادثة (= آخر شكل للفاتورة المفتوحة)
    $dir = Join-Path $IncD ('{0:yyyyMMdd_HHmmss}_{1}' -f $when, $kind)
    New-Item -ItemType Directory -Path $dir | Out-Null
    $frames = @(Get-ChildItem -Path $FramesD -Filter *.jpg | Sort-Object Name)
    foreach ($f in $frames) { Copy-Item $f.FullName -Destination $dir }
    $info = [ordered]@{ kind = $kind; detail = $detail; when = $when.ToString('s'); frames = $frames.Count; machine = $env:COMPUTERNAME }
    ($info | ConvertTo-Json) | Set-Content -Path (Join-Path $dir 'incident.json') -Encoding UTF8
    $names = @{ hang = 'فارمافلاي وقف (Not Responding)'; closed = 'فارمافلاي اتقفل/وقع من غير إغلاق عادي'; power = 'الجهاز اتقفل فجأة (احتمال قطع كهربا)'; test = 'تجربة' }
    $title = $names[$kind]; if (-not $title) { $title = $kind }
    Send-Alert ("{0} الساعة {1:HH:mm:ss}. افتح الدرج وراجع آخر بيعة. {2}`nلقطات: {3}" -f $title, $when, $detail, $dir)
    # تنظيف الحوادث القديمة
    Get-ChildItem -Path $IncD -Directory | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-[int]$cfg.KeepIncidentsDays) } | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Get-CrashEvents([datetime]$since, [string]$name) {
    # أحداث الأعطال في Application log (1000 عطل، 1001 تقرير WER، 1002 تهنيج) الخاصة بالبرنامج
    try {
        $ev = Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $since; Id = 1000, 1001, 1002 } -ErrorAction Stop
        return @($ev | Where-Object { $_.Message -match [regex]::Escape($name) })
    } catch { return @() }
}

if ($SelfTest) {
    Log 'SelfTest: لقطة + حادثة تجريبية'
    [void](Save-Frame); Trim-Frames
    New-Incident 'test' 'ده اختبار، مفيش مشكلة حقيقية.' (Get-Date)
    Log 'SelfTest خلص. شوف مجلد incidents\ وتأكد إن اللقطة بتظهر الشاشة صح.'
    return
}

# --- بداية التشغيل: لو الجهاز اتقفل فجأة من آخر نبضة ---
if (Test-Path $BeatF) {
    try {
        $last = [datetime]::Parse((Get-Content $BeatF -Raw).Trim())
        if (((Get-Date) - $last).TotalMinutes -gt 3) {
            $ev = @()
            try { $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; StartTime = $last; Id = 41, 6008 } -ErrorAction Stop) } catch {}
            if ($ev.Count -gt 0) { New-Incident 'power' ('آخر نبضة للمراقب: {0:HH:mm}. سجل Windows فيه إغلاق غير متوقع.' -f $last) $ev[0].TimeCreated }
            else { Log ('المراقب كان واقف من {0:HH:mm} (من غير إغلاق غير متوقع في السجل)' -f $last) }
        }
    } catch {}
}

Log ('بدأ المراقب. البرنامج: {0}' -f $cfg.ProcessName)
$lastFrame = [datetime]::MinValue; $lastBeat = [datetime]::MinValue
$knownPid = $null; $knownStart = $null
$hangSince = $null; $hangReported = $false

while ($true) {
    try {
        $now = Get-Date
        if (($now - $lastBeat).TotalSeconds -ge 30) { Set-Content -Path $BeatF -Value $now.ToString('s'); $lastBeat = $now }

        $p = @(Get-Process -Name $cfg.ProcessName -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
        if ($p) {
            if ($knownPid -ne $p.Id) { $knownPid = $p.Id; $knownStart = $now; $hangSince = $null; $hangReported = $false; Log ('فارمافلاي شغال PID={0}' -f $p.Id) }
            # لقطة كل كام ثانية (طول ما البرنامج شغال وسليم)
            if ($p.Responding -and (($now - $lastFrame).TotalSeconds -ge $cfg.FrameEverySeconds)) {
                [void](Save-Frame); Trim-Frames; $lastFrame = $now
            }
            # تهنيج
            if (-not $p.Responding) {
                if (-not $hangSince) { $hangSince = $now }
                if (-not $hangReported -and (($now - $hangSince).TotalSeconds -ge $cfg.HangSeconds)) {
                    New-Incident 'hang' 'اللقطات دي من قبل التهنيج.' $hangSince
                    $hangReported = $true
                }
            } else {
                if ($hangReported) { Log ('فارمافلاي فاق بعد {0:N0} ثانية' -f ($now - $hangSince).TotalSeconds) }
                $hangSince = $null; $hangReported = $false
            }
        } elseif ($knownPid) {
            # البرنامج اختفى: عطل ولا إغلاق عادي؟
            $exitAt = $now
            Log ('فارمافلاي اختفى PID={0}، بفحص السجل {1} ثانية' -f $knownPid, $cfg.ExitCheckWaitSeconds)
            Start-Sleep -Seconds ([int]$cfg.ExitCheckWaitSeconds)
            $crash = @(Get-CrashEvents $exitAt.AddMinutes(-2) $cfg.ProcessName)
            if ($hangReported) {
                Log 'اتقفل بعد تهنيج (الحادثة اتسجلت قبل كده).'
            } elseif ($crash.Count -gt 0) {
                New-Incident 'closed' ('سجل Windows: ' + (($crash[0].Message -split "`n")[0])) $exitAt
            } else {
                Log 'اتقفل من غير أعطال في السجل (غالبًا إغلاق عادي).'
            }
            $knownPid = $null; $hangSince = $null; $hangReported = $false
        }
    } catch { Log ('خطأ في الدورة: ' + $_.Exception.Message) }
    Start-Sleep -Seconds ([int]$cfg.PollSeconds)
}
