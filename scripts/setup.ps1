# Receply LOCAL — first-time setup (safe to run again). Run from this folder:  .\scripts\setup.ps1
. "$PSScriptRoot\common.ps1"
Start-DockerDesktop
Invoke-Docker compose pull --quiet
node .\scripts\setup.js
if ($LASTEXITCODE -ne 0) { throw 'setup failed - see the message above' }
