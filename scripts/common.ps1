# Shared helpers for the Receply LOCAL scripts (dot-sourced). Windows PowerShell 5.1 turns anything a native
# program writes to stderr into an error record — and docker compose writes its normal progress there — so the
# scripts judge success by exit codes, not by stderr.
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path $PSScriptRoot -Parent)

function Invoke-Docker {
  $out = & docker @args 2>&1
  if ($LASTEXITCODE -ne 0) { $out | ForEach-Object { Write-Host "  $_" }; throw ('docker ' + ($args -join ' ') + ' failed') }
}

function Start-DockerDesktop {
  if (& docker version --format '{{.Server.Version}}' 2>$null) { return }
  Write-Host 'Starting Docker Desktop...'
  Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
  $deadline = (Get-Date).AddMinutes(4)
  while (-not (& docker version --format '{{.Server.Version}}' 2>$null)) {
    if ((Get-Date) -gt $deadline) { throw 'Docker Desktop did not start within 4 minutes' }
    Start-Sleep -Seconds 5
  }
}

function Wait-Url([string]$url, [int]$minutes = 5) {
  $deadline = (Get-Date).AddMinutes($minutes)
  while ($true) {
    try { if ((Invoke-WebRequest $url -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200) { return } } catch { }
    if ((Get-Date) -gt $deadline) { throw "$url did not come up" }
    Start-Sleep -Seconds 3
  }
}
