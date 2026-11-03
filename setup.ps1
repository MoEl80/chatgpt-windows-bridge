# ChatGPT Windows Bridge - one-step setup.
# Run in this folder:  powershell -ExecutionPolicy Bypass -File setup.ps1
# It checks Node.js and Git Bash, installs dependencies, downloads/updates OpenAI's tunnel-client
# (checked against the release's SHA256SUMS.txt), creates the local secrets, asks for your
# tunnel ID and tunnel API key, writes the tunnel profile, and installs the logon task.
# Safe to run again: it keeps existing secrets unless you pass -NewSecrets.
[CmdletBinding()]
param(
  [string]$TunnelId,                       # tunnel_... from platform.openai.com -> Tunnels
  [string]$ApiKeyFile,                     # optional: file holding the restricted tunnel API key (otherwise you are asked)
  [ValidateSet('full', 'read')][string]$Mode,
  [string[]]$Roots,                        # optional allowed folders, e.g. -Roots C:\Projects,D:\Notes
  [string]$Cwd,                            # default working directory (default: your user folder)
  [ValidateRange(1024,65534)][int]$Port = 8797,
  [switch]$NewSecrets,                     # make a new secret path and bridge key
  [switch]$DownloadOnly,                   # only install dependencies and tunnel-client
  [switch]$NoTask                          # do not install/start the logon task
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'   # the PowerShell 5.1 progress bar makes downloads very slow
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$here = Split-Path -Parent $MyInvocation.MyCommand.Definition
Set-Location $here
$state = Join-Path $here '.state'
$tunnelDir = Join-Path $here 'tunnel'
$taskName = 'ChatGPT-Windows-Bridge'
function Step($m) { Write-Host "`n== $m" -ForegroundColor Cyan }
function Done($m) { Write-Host "   OK  $m" -ForegroundColor Green }
$mySid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Lock-File($path) {
  # only the current user (and SYSTEM/Administrators) can read it; folders pass the rule on to everything inside
  $rule = if ((Get-Item $path).PSIsContainer) { '(OI)(CI)F' } else { 'F' }
  & icacls.exe $path /inheritance:r /grant:r "*${mySid}:$rule" "*S-1-5-18:$rule" "*S-1-5-32-544:$rule" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "could not restrict permissions on $path" }
}
function New-Secret { $b = New-Object byte[] 32; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b); ([Convert]::ToBase64String($b)).TrimEnd('=').Replace('+', '-').Replace('/', '_') }
function Stop-RunningBridge {
  # Stop the normal scheduled cmd -> node -> tunnel-client tree before changing binaries/config.
  Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
  $logPattern = [regex]::Escape((Join-Path $here '.state\server.log'))
  Get-CimInstance Win32_Process -Filter "Name='cmd.exe'" | Where-Object { $_.CommandLine -match $logPattern } |
    ForEach-Object { & taskkill /PID $_.ProcessId /T /F | Out-Null }
  Start-Sleep -Milliseconds 500
}
function Read-SafeRoot([string]$Prompt) {
  $defaultRoot = Join-Path $env:USERPROFILE 'Documents'
  if (-not (Test-Path $defaultRoot -PathType Container)) { $defaultRoot = $env:USERPROFILE }
  $entered = Read-Host "$Prompt [$defaultRoot]"
  if ([string]::IsNullOrWhiteSpace($entered)) { $entered = $defaultRoot }
  $entered = $entered.Trim().Trim('"', "'")
  if (-not (Test-Path $entered -PathType Container)) { throw "allowed folder does not exist: $entered" }
  return (Resolve-Path $entered).Path
}

Step 'Checking requirements'
$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw 'Node.js is not installed. Install the LTS version from https://nodejs.org and run setup again.' }
$nodeMajor = [int](((& node --version) -replace '^v') -split '\.')[0]
if ($nodeMajor -lt 20) { throw "Node.js 20 or newer is needed (found $(& node --version))." }
Done "Node.js $(& node --version)"
$bashCandidates = @((Join-Path $env:ProgramFiles 'Git\bin\bash.exe'), (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'))
$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) { $bashCandidates += (Join-Path (Split-Path (Split-Path $gitCmd.Source -Parent) -Parent) 'bin\bash.exe') }
$bash = $bashCandidates | Where-Object { $_ -and (Test-Path $_ -PathType Leaf) } | Select-Object -First 1
if (-not $bash) { throw 'Git for Windows was not found. Install it from https://git-scm.com/download/win, close and reopen PowerShell, then run setup again.' }
$bash = (Resolve-Path $bash).Path
Done "Git Bash $bash"

New-Item -ItemType Directory -Force -Path $state | Out-Null
Lock-File $state
$existingTask = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existingTask) {
  Step 'Stopping the existing bridge copy'
  Stop-RunningBridge
  Done 'existing scheduled copy stopped before update'
}

Step 'Installing dependencies (npm ci)'
& npm ci --no-audit --no-fund
if ($LASTEXITCODE -ne 0) { throw 'npm ci failed' }
Done 'node_modules ready'

Step 'Checking OpenAI tunnel-client'
$exe = Join-Path $tunnelDir 'tunnel-client.exe'
$versionFile = Join-Path $tunnelDir '.installed-version'
$headers = @{ 'User-Agent' = 'chatgpt-windows-bridge-setup' }
$rel = Invoke-RestMethod -Headers $headers -Uri 'https://api.github.com/repos/openai/tunnel-client/releases/latest'
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$zipAsset = $rel.assets | Where-Object { $_.name -match "^tunnel-client-v[\d.]+-windows-$arch\.zip$" } | Select-Object -First 1
$sumAsset = $rel.assets | Where-Object { $_.name -eq 'SHA256SUMS.txt' } | Select-Object -First 1
if (-not $zipAsset -or -not $sumAsset) { throw "release $($rel.tag_name) has no windows-$arch zip or SHA256SUMS.txt" }
$installedVersion = if (Test-Path $versionFile) { (Get-Content $versionFile -Raw).Trim() } else { '' }
$needTunnelUpdate = -not (Test-Path $exe -PathType Leaf) -or $installedVersion -ne $rel.tag_name
if ($needTunnelUpdate) {
  $updateDir = Join-Path $state ('.tunnel-update-' + [Guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Force -Path $updateDir | Out-Null
  try {
    $zip = Join-Path $updateDir $zipAsset.name
    $sums = Join-Path $updateDir 'SHA256SUMS.txt'
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $zipAsset.browser_download_url -OutFile $zip
    Invoke-WebRequest -UseBasicParsing -Headers $headers -Uri $sumAsset.browser_download_url -OutFile $sums
    $line = Get-Content $sums | Where-Object { $_ -match "\s\*?$([regex]::Escape($zipAsset.name))$" } | Select-Object -First 1
    if (-not $line) { throw "$($zipAsset.name) is not listed in SHA256SUMS.txt" }
    $want = ($line -split '\s+')[0].ToLower()
    $have = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
    if ($want -ne $have) { throw "checksum mismatch for $($zipAsset.name): expected $want, got $have" }
    $extractDir = Join-Path $updateDir 'extract'
    Expand-Archive -Path $zip -DestinationPath $extractDir -Force
    $newExe = Get-ChildItem $extractDir -Filter 'tunnel-client.exe' -File -Recurse | Select-Object -First 1
    if (-not $newExe) { throw "tunnel-client.exe not found after extracting $($zipAsset.name)" }
    New-Item -ItemType Directory -Force -Path $tunnelDir | Out-Null
    $stagedExe = Join-Path $tunnelDir 'tunnel-client.exe.new'
    $backupExe = Join-Path $tunnelDir 'tunnel-client.exe.old'
    Copy-Item $newExe.FullName $stagedExe -Force
    Remove-Item $backupExe -Force -ErrorAction SilentlyContinue
    if (Test-Path $exe) { Move-Item $exe $backupExe -Force }
    try {
      Move-Item $stagedExe $exe -Force
      [System.IO.File]::WriteAllText($versionFile, $rel.tag_name, $utf8NoBom)
      Remove-Item $backupExe -Force -ErrorAction SilentlyContinue
    } catch {
      Remove-Item $stagedExe -Force -ErrorAction SilentlyContinue
      if ((-not (Test-Path $exe)) -and (Test-Path $backupExe)) { Move-Item $backupExe $exe -Force }
      throw
    }
    Done "$($rel.tag_name) windows-$arch installed, archive sha256 $have verified"
  } finally {
    Remove-Item $updateDir -Recurse -Force -ErrorAction SilentlyContinue
  }
} else {
  Done "already current: $installedVersion windows-$arch"
}
if ($DownloadOnly) {
  if ($existingTask) { Start-ScheduledTask -TaskName $taskName; Done 'existing bridge task restarted' }
  Write-Host "`nDownload-only run finished."
  exit 0
}

Step 'Creating local secrets'
foreach ($name in 'token', 'bridge-key') {
  $f = Join-Path $state $name
  if ($NewSecrets -or -not (Test-Path $f)) { Set-Content -Path $f -Value (New-Secret) -Encoding ascii -NoNewline; Done "created .state\$name" }
  else { Done ".state\$name kept" }
}
$token = (Get-Content (Join-Path $state 'token') -Raw).Trim()

Step 'Tunnel ID and API key'
$profilePath = Join-Path $state 'tunnel-client.yaml'
if (-not $TunnelId -and (Test-Path $profilePath)) {
  $m = Select-String -Path $profilePath -Pattern 'tunnel_id:\s*"?(tunnel_([a-z]{4}_)?[a-z0-9]{32})' | Select-Object -First 1
  if ($m) { $TunnelId = $m.Matches[0].Groups[1].Value; Done 'using tunnel ID from the existing profile' }
}
$tries = 0
while (-not ($TunnelId -match '^tunnel_[A-Za-z0-9_]{8,}$')) {
  if ($TunnelId) { Write-Warning "'$TunnelId' does not look like a tunnel ID. It starts with tunnel_ (copy it from platform.openai.com -> Tunnels)." }
  if (++$tries -gt 3) { throw 'No valid tunnel ID entered. Run setup.ps1 again when you have it.' }
  $TunnelId = (Read-Host 'Paste your tunnel ID (platform.openai.com -> Tunnels, starts with tunnel_)').Trim().Trim('"', "'")
}
$keyPath = Join-Path $state 'control-plane-api-key'
if ($ApiKeyFile) {
  $apiKey = (Get-Content $ApiKeyFile -Raw).Trim()
} elseif (Test-Path $keyPath) {
  $apiKey = (Get-Content $keyPath -Raw).Trim(); Done 'tunnel API key kept'
} else {
  Write-Host '   Paste the restricted API key and press Enter. Nothing appears on screen while you paste - that is normal.'
  $sec = Read-Host 'API key (Tunnels: Read + Use only)' -AsSecureString
  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
  try { $apiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr).Trim() }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}
if (-not ($apiKey -match '^sk-[A-Za-z0-9_-]{20,}$')) { throw 'that does not look like an OpenAI API key (it should start with sk-)' }
Set-Content -Path $keyPath -Value $apiKey -Encoding ascii -NoNewline
Done 'API key saved to .state\control-plane-api-key (only your user can read it)'

$yaml = @"
config_version: 1
control_plane:
  base_url: "https://api.openai.com"
  tunnel_id: "$TunnelId"
  api_key: "env:CONTROL_PLANE_API_KEY"
health:
  listen_addr: "127.0.0.1:$($Port + 1)"
admin_ui:
  open_browser: false
log:
  level: info
  format: json
mcp:
  server_urls:
    - channel: main
      url: "http://127.0.0.1:$Port/$token/mcp"
"@
Set-Content -Path $profilePath -Value $yaml -Encoding ascii
Done 'wrote .state\tunnel-client.yaml'

Step 'Settings (config.json)'
$cfgPath = Join-Path $here 'config.json'
$freshConfig = -not (Test-Path $cfgPath)
$cfg = [ordered]@{}
if (-not $freshConfig) { (Get-Content $cfgPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $cfg[$_.Name] = $_.Value } }

# Fresh interactive installs no longer silently choose full access to the whole PC.
if ($freshConfig -and -not $Mode -and -not $PSBoundParameters.ContainsKey('Roots')) {
  Write-Host @"
Choose the bridge access level:
  1. Read-only, one folder (recommended)
  2. Full tools, one folder for file tools/default cwd (run is still an unrestricted Windows-user shell)
  3. Full tools, whole Windows user account (advanced)
"@
  $choice = ''
  while ($choice -notin @('1','2','3')) { $choice = (Read-Host 'Choose 1, 2 or 3').Trim() }
  switch ($choice) {
    '1' {
      $chosenRoot = Read-SafeRoot 'Folder ChatGPT may read'
      $cfg['mode'] = 'read'; $cfg['roots'] = @($chosenRoot); $cfg['cwd'] = $chosenRoot
    }
    '2' {
      $chosenRoot = Read-SafeRoot 'Folder for direct file tools and default working directory'
      $cfg['mode'] = 'full'; $cfg['roots'] = @($chosenRoot); $cfg['cwd'] = $chosenRoot
      Write-Warning 'Full-mode run is not sandboxed by Roots; shell commands can reach anything your Windows user can reach.'
    }
    '3' {
      $cfg['mode'] = 'full'; $cfg['roots'] = @(); $cfg['cwd'] = $env:USERPROFILE
      Write-Warning 'Advanced mode selected: ChatGPT shell commands run with your normal Windows-user permissions.'
    }
  }
}

$cfg['port'] = $Port
if ($Mode) { $cfg['mode'] = $Mode } elseif (-not $cfg.Contains('mode')) { $cfg['mode'] = 'full' }
if ($PSBoundParameters.ContainsKey('Roots')) {
  # "-Roots C:\a,D:\b" arrives as one string under -File, so split on , and ;
  $list = @($Roots | ForEach-Object { $_ -split '[,;]' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
  foreach ($r in $list) { if (-not (Test-Path $r -PathType Container)) { throw "allowed folder does not exist: $r" } }
  $cfg['roots'] = @($list | ForEach-Object { (Resolve-Path $_).Path })
} elseif (-not $cfg.Contains('roots')) { $cfg['roots'] = @() }
if ($Cwd) {
  if (-not (Test-Path $Cwd -PathType Container)) { throw "working directory does not exist: $Cwd" }
  $cfg['cwd'] = (Resolve-Path $Cwd).Path
} elseif (@($cfg['roots']).Count -and -not $cfg.Contains('cwd')) { $cfg['cwd'] = @($cfg['roots'])[0] }
elseif (-not $cfg.Contains('cwd')) { $cfg['cwd'] = $env:USERPROFILE }
$cfg['bash'] = $bash
# write without a byte-order mark: Node's JSON.parse rejects one (PowerShell 5.1 '-Encoding utf8' adds it)
[System.IO.File]::WriteAllText($cfgPath, ($cfg | ConvertTo-Json), $utf8NoBom)
Done ("mode=$($cfg['mode'])  roots=" + $(if (@($cfg['roots']).Count) { @($cfg['roots']) -join '; ' } else { '(whole PC)' }))

Step 'Self-test (local, temporary port and secrets)'
& node test.mjs
if ($LASTEXITCODE -ne 0) { throw 'self-test failed' }
Done 'self-test passed'

if ($NoTask) {
  if ($existingTask) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $here 'run-server.vbs') -ErrorAction SilentlyContinue
    Done 'existing logon task removed because -NoTask was requested'
  }
} else {
  Step 'Installing the logon task'
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $here 'install-task.ps1') -Port $Port
  if ($LASTEXITCODE -ne 0) { throw 'install-task.ps1 failed' }
  Step 'Checking that the bridge is running'
  $ok = $false
  for ($i = 0; $i -lt 20; $i++) { Start-Sleep -Seconds 1; try { if ((Invoke-WebRequest -UseBasicParsing -TimeoutSec 2 "http://127.0.0.1:$Port/healthz").StatusCode -eq 200) { $ok = $true; break } } catch {} }
  if (-not $ok) { throw "the bridge did not answer on port $Port. Setup is not complete; inspect .state\server.log" }
  Done "server answering on port $Port"
}

Step 'Checking the tunnel connection with tunnel-client doctor'
$env:CONTROL_PLANE_API_KEY = $apiKey
try {
  & $exe doctor --config $profilePath
  $doctorCode = $LASTEXITCODE
} finally {
  Remove-Item Env:\CONTROL_PLANE_API_KEY -ErrorAction SilentlyContinue
}
if ($doctorCode -ne 0) { throw 'tunnel-client doctor reported a problem. Setup is not complete; check the lines above and .state\tunnel.log.' }
Done 'doctor passed'

Write-Host @"

All set. Last step, in ChatGPT (web, if custom MCP is available for your account/workspace):
  1. Plugins -> + -> Add custom MCP server
  2. Name it (e.g. "My PC"), Connection: Tunnel, pick your tunnel
  3. Authentication: No authentication (tunnel/workspace permissions still control access)
  4. Tick "I understand and want to continue", Create, then Install
  5. In a chat, type @ and pick your plugin, e.g. "@My PC run hostname"

Health: http://127.0.0.1:$Port/healthz   tunnel: http://127.0.0.1:$($Port + 1)/ui
"@ -ForegroundColor Green
