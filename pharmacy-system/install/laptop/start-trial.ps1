<#
  تشغيل البرنامج التجريبي على اللاب: PostgreSQL ثم PostgREST ثم Caddy.
  -Lan لو عايز تفتحه من جهاز تاني في الصيدلية (الافتراضي اللاب بس).
  لو برنامج من التلاتة شغال بس مش بيرد (أو واقف برسالة غلط)، بيتقفل ويتشغّل من جديد.
#>
param(
  [string]$Root = "D:\AskerTrial",
  [int]$PgPort = 5433,
  [int]$ApiPort = 3010,
  [int]$WebPort = 8080,
  [switch]$Lan
)
. (Join-Path $PSScriptRoot "common.ps1")
Start-Postgres
# PostgREST للويندوز محتاج LIBPQ.dll (وملفاته)، وهما في فولدر PostgreSQL اللي اتنزّل
$env:PATH = "$PgBin;$env:PATH"

function Test-Port([int]$port) {
  $c = New-Object Net.Sockets.TcpClient
  try { return $c.ConnectAsync("127.0.0.1", $port).Wait(700) -and $c.Connected } catch { return $false } finally { $c.Close() }
}
# بنقفل بس النسخ اللي من فولدر البرنامج (مش أي برنامج تاني بنفس الاسم)
function Stop-Ours([string]$name) {
  Get-Process $name -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) } |
    Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 300
}
function Tail([string]$file) {
  $p = Join-Path $Logs $file
  if (Test-Path $p) { ((Get-Content $p -Tail 6 -ErrorAction SilentlyContinue) -join "`n").Trim() } else { "" }
}

if (-not (Test-Port $ApiPort)) {
  Stop-Ours "postgrest"
  Start-Process -FilePath (Get-Exe "postgrest" "postgrest.exe") -ArgumentList "`"$Conf\postgrest.conf`"" -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $Logs "postgrest.log") -RedirectStandardError (Join-Path $Logs "postgrest.err")
}
$env:ASKER_PORT = "$WebPort"
$env:ASKER_BIND = $(if ($Lan) { "0.0.0.0" } else { "127.0.0.1" })
$env:ASKER_POSTGREST = "127.0.0.1:$ApiPort"
$env:ASKER_APP_DIR = (Join-Path $Pharmacy "app").Replace("\", "/")   # Caddy بيفهم / في المسارات
if (-not (Test-Port $WebPort)) {
  Stop-Ours "caddy"
  Start-Process -FilePath (Get-Exe "caddy" "caddy.exe") `
    -ArgumentList "run --config `"$Pharmacy\install\Caddyfile`" --adapter caddyfile" -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $Logs "caddy.log") -RedirectStandardError (Join-Path $Logs "caddy.err")
}
$url = "http://127.0.0.1:$WebPort"
for ($i = 0; $i -lt 40; $i++) {
  try { Invoke-WebRequest "$url/rest/v1/" -UseBasicParsing -TimeoutSec 2 | Out-Null; Say "البرنامج شغال: $url"; exit 0 } catch { Start-Sleep 1 }
}
# ماقامش: السبب نفسه في الرسالة (آخر سطور السجلات)
$why = @()
if (-not (Test-Port $ApiPort)) { $why += "المحرك (PostgREST) مش شغال:`n" + (Tail "postgrest.err") + "`n" + (Tail "postgrest.log") }
if (-not (Test-Port $WebPort)) { $why += "البوابة (Caddy) مش شغالة:`n" + (Tail "caddy.err") }
if (-not $why) { $why += "الاتنين شغالين بس $url/rest/v1/ مابيردش:`n" + (Tail "postgrest.log") }
throw ("البرنامج ماقامش.`n" + ($why -join "`n`n") + "`n(السجلات كلها في $Logs)")
