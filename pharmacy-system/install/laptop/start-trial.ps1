<#
  تشغيل البرنامج التجريبي على اللاب: PostgreSQL ثم PostgREST ثم Caddy. لم يُختبر على ويندوز لسه.
  -Lan لو عايز تفتحه من جهاز تاني في الصيدلية (الافتراضي اللاب بس).
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
if (-not (Get-Process postgrest -ErrorAction SilentlyContinue)) {
  Start-Process -FilePath (Join-Path $Root "bin\postgrest\postgrest.exe") -ArgumentList "`"$Conf\postgrest.conf`"" -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $Logs "postgrest.log") -RedirectStandardError (Join-Path $Logs "postgrest.err")
}
$env:ASKER_PORT = "$WebPort"
$env:ASKER_BIND = $(if ($Lan) { "0.0.0.0" } else { "127.0.0.1" })
$env:ASKER_POSTGREST = "127.0.0.1:$ApiPort"
$env:ASKER_APP_DIR = (Join-Path $Pharmacy "app")
if (-not (Get-Process caddy -ErrorAction SilentlyContinue)) {
  Start-Process -FilePath (Join-Path $Root "bin\caddy\caddy.exe") `
    -ArgumentList "run --config `"$Pharmacy\install\Caddyfile`" --adapter caddyfile" -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $Logs "caddy.log") -RedirectStandardError (Join-Path $Logs "caddy.err")
}
$url = "http://127.0.0.1:$WebPort"
for ($i = 0; $i -lt 40; $i++) {
  try { Invoke-WebRequest "$url/rest/v1/" -UseBasicParsing -TimeoutSec 2 | Out-Null; Say "البرنامج شغال: $url"; exit 0 } catch { Start-Sleep 1 }
}
throw "البرنامج ماقامش: شوف $Logs"
