<#
.SYNOPSIS
  lab.ps1 -- Windows-native launcher for the "Escape the Container" workshop.

  The exact same lab as lab.sh, for people on Windows who don't want to open
  WSL/Git Bash. Run it from a normal PowerShell window:

    .\lab.ps1 up            build + start the lab (do this once)
    .\lab.ps1 levels        list the escape levels
    .\lab.ps1 start <n>     (re)create the vulnerable container for level <n>
    .\lab.ps1 enter <n>     drop into a shell inside level <n>'s container
    .\lab.ps1 submit <n> <flag>   check a flag you captured
    .\lab.ps1 reset <n>     rebuild level <n> from scratch
    .\lab.ps1 status        show what's running
    .\lab.ps1 down          stop and wipe the whole lab

  Everything runs against a throwaway Docker-in-Docker "host".

  If you get "running scripts is disabled on this system", run once:
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
#>
[CmdletBinding()]
param(
  [Parameter(Position = 0)][string]$Command = 'help',
  [Parameter(Position = 1)][string]$Level,
  [Parameter(Position = 2, ValueFromRemainingArguments = $true)][string[]]$Rest
)

$ErrorActionPreference = 'Stop'
$Root    = $PSScriptRoot
$Build   = Join-Path $Root '.build'
$FlagsSrc = Join-Path $Root 'lab/flags'
$Answers = Join-Path $Build 'answers'
$Levels  = @('1','2','3','4','5','6','7')

function Say  { param($m) Write-Host $m }
function Ok   { param($m) Write-Host "OK  $m" -ForegroundColor Green }
function Warn { param($m) Write-Host "!   $m" -ForegroundColor Yellow }
function Die  { param($m) Write-Host "X   $m" -ForegroundColor Red; exit 1 }

function Invoke-Compose { docker compose @args }

function Assert-Docker {
  if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Die "Docker is not installed / not on PATH."
  }
  docker info *> $null
  if ($LASTEXITCODE -ne 0) { Die "Docker daemon not reachable. Is Docker Desktop running?" }
}

function Get-Title {
  param($n)
  switch ($n) {
    '1' { "Bind-mounted host path      (-v /:/mnt/host)" }
    '2' { "Mounted Docker socket       (-v /var/run/docker.sock)" }
    '3' { "Exposed Docker API over TCP (dockerd on :2375)" }
    '4' { "Privileged + host PID ns    (--privileged --pid=host)" }
    '5' { "No --privileged, just caps  (--cap-add=SYS_ADMIN,SYS_PTRACE --pid=host)" }
    '6' { "Unauth Engine API, stock container (CVE-2025-9074)" }
    '7' { "One capability only         (CAP_DAC_READ_SEARCH / open_by_handle_at)" }
  }
}

function New-Flags {
  New-Item -ItemType Directory -Force -Path $FlagsSrc, $Build | Out-Null
  Set-Content -Path $Answers -Value $null -NoNewline
  $names = @{ '1'='bind_mount'; '2'='docker_socket'; '3'='tcp_api'; '4'='privileged_pidhost'; '5'='cap_sys_admin'; '6'='unauth_engine_api'; '7'='dac_read_search' }
  foreach ($n in $Levels) {
    $rnd  = -join ((1..8) | ForEach-Object { '{0:x2}' -f (Get-Random -Maximum 256) })
    $flag = "ESD26{$($names[$n])_$rnd}"
    [IO.File]::WriteAllText((Join-Path $FlagsSrc "level$n.txt"), "$flag`n")
    Add-Content -Path $Answers -Value "$n $flag"
  }
}

function Test-HostReady {
  docker compose exec -T host docker info *> $null
  return ($LASTEXITCODE -eq 0)
}

function Wait-Engine {
  Write-Host -NoNewline "Waiting for the inner Docker engine"
  for ($i = 0; $i -lt 60; $i++) {
    if (Test-HostReady) { Write-Host ""; Ok "inner engine is up"; return }
    Write-Host -NoNewline "."
    Start-Sleep -Seconds 1
  }
  Write-Host ""
  Die "inner Docker engine did not come up in time (check: docker compose logs host)"
}

function Cmd-Up {
  Assert-Docker
  Say "Generating fresh, unique flags for this run..."
  New-Flags
  Say "Building the vulnerable image on your machine..."
  docker build -q -t vuln:latest (Join-Path $Root 'lab/vulnerable') | Out-Null
  Say "Saving it for offline load into the lab..."
  docker save vuln:latest -o (Join-Path $Build 'vuln.tar')
  Say "Building + starting the DinD host..."
  docker compose up -d --build
  Wait-Engine
  Say "Loading the vulnerable image into the lab engine..."
  # .build is bind-mounted read-only at /mnt/build inside the host (see
  # docker-compose.yml), so the saved image tar loads directly -- no stdin pipe
  # (which PowerShell corrupts) and no `docker cp` (which dind's mount ns hides).
  docker compose exec -T host docker load -i /mnt/build/vuln.tar | Out-Null
  Ok "lab is ready"
  Write-Host ""
  Cmd-Levels
  Write-Host ""
  Say "Next:  .\lab.ps1 enter 1   then try to escape and read the flag."
}

function Cmd-Levels {
  Say "Escape levels:"
  foreach ($n in $Levels) { "  $n  $(Get-Title $n)" }
}

function Cmd-Start {
  param($n)
  if (-not $n) { Die "usage: lab.ps1 start <level>" }
  Assert-Docker
  if (-not (Test-HostReady)) { Die "lab is not running -- run '.\lab.ps1 up' first." }
  docker compose exec -T host /opt/lab/launch.sh $n
}

function Cmd-Enter {
  param($n)
  if (-not $n) { Die "usage: lab.ps1 enter <level>" }
  Assert-Docker
  if (-not (Test-HostReady)) { Die "lab is not running -- run '.\lab.ps1 up' first." }
  $running = docker compose exec -T host docker inspect -f '{{.State.Running}}' "level$n" 2>$null
  if ($running -notmatch 'true') { docker compose exec -T host /opt/lab/launch.sh $n }
  Say "Entering level $n. Goal: escape this container and read /flags/level$n.txt on the host."
  Say "Type 'exit' to leave."
  docker compose exec host docker exec -it "level$n" /bin/bash
}

function Cmd-Reset {
  param($n)
  if (-not $n) { Die "usage: lab.ps1 reset <level>" }
  Assert-Docker
  docker compose exec -T host docker rm -f "level$n" 2>$null | Out-Null
  Cmd-Start $n
  Ok "level $n reset"
}

function Cmd-Submit {
  param($n, $flagParts)
  $got = ($flagParts -join ' ').Trim()
  if (-not $n -or -not $got) { Die "usage: lab.ps1 submit <level> <flag>" }
  if (-not (Test-Path $Answers)) { Die "no answers file -- run '.\lab.ps1 up' first." }
  $want = $null
  foreach ($line in Get-Content $Answers) {
    $parts = $line -split ' ', 2
    if ($parts[0] -eq $n) { $want = $parts[1].Trim() }
  }
  if (-not $want) { Die "unknown level: $n" }
  if ($got -eq $want) { Ok "Correct! Level $n captured: $want" }
  else { Die "Not quite. That flag doesn't match level $n. Keep going!" }
}

function Cmd-Status {
  Assert-Docker
  if (Test-HostReady) {
    Ok "lab host is up"
    docker compose exec -T host docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'
  } else {
    Warn "lab host is not running"
  }
}

function Cmd-Down {
  Assert-Docker
  docker compose down -v
  Ok "lab stopped and wiped"
}

function Show-Help {
  Get-Content (Join-Path $Root 'lab.ps1') |
    Where-Object { $_ -match '^\s+\.\\lab\.ps1' } |
    ForEach-Object { $_.Trim() }
}

Push-Location $Root
try {
  switch ($Command) {
    'up'     { Cmd-Up }
    'levels' { Cmd-Levels }
    'start'  { Cmd-Start $Level }
    'enter'  { Cmd-Enter $Level }
    'reset'  { Cmd-Reset $Level }
    'submit' { Cmd-Submit $Level $Rest }
    'status' { Cmd-Status }
    'down'   { Cmd-Down }
    default  { Show-Help }
  }
}
finally {
  Pop-Location
}
