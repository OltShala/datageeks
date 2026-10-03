# Receply LOCAL — move the WhatsApp test number (+1 555 146 8677) to THIS PC, e.g. for the hackathon.
# Production's WhatsApp pauses until you run .\scripts\whatsapp-production.ps1. Run from this folder.
. "$PSScriptRoot\common.ps1"
Start-DockerDesktop
Invoke-Docker compose --profile whatsapp up -d
Wait-Url 'http://localhost:3000/api'
Wait-Url 'http://localhost:5556/healthz'
python .\scripts\whatsapp-switch.py local     # checks demo.receply.net answers Meta's verification first
if ($LASTEXITCODE -ne 0) { throw 'not switched - WhatsApp stays on production' }
python .\scripts\whatsapp-status.py
