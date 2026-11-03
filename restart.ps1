# ChatGPT Windows Bridge - restart.ps1: restarts the logon task cleanly. Stop-ScheduledTask alone
# leaves the cmd -> node -> tunnel-client tree running, so kill that tree first.
param([string]$TaskName = "ChatGPT-Windows-Bridge")
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
$logPattern = [regex]::Escape((Join-Path $here '.state\server.log'))
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" | Where-Object { $_.CommandLine -match $logPattern } |
  ForEach-Object { & taskkill /PID $_.ProcessId /T /F | Out-Null }
Start-Sleep -Seconds 1
Start-ScheduledTask -TaskName $TaskName
Write-Host "Restarted '$TaskName'."
