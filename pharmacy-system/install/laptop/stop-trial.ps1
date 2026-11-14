<# إيقاف البرنامج التجريبي على اللاب (Caddy وPostgREST وPostgreSQL). لم يُختبر على ويندوز لسه. #>
param([string]$Root = "D:\AskerTrial", [int]$PgPort = 5433)
. (Join-Path $PSScriptRoot "common.ps1")
foreach ($p in @("caddy", "postgrest")) {
  Get-Process $p -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$Root*" } | Stop-Process -Force
}
& (Join-Path $PgBin "pg_ctl.exe") -D $PgData -m fast stop
Say "البرنامج وقف"
