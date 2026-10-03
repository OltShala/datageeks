# Receply LOCAL — give the WhatsApp test number back to PRODUCTION (after the hackathon), then stop the tunnel.
. "$PSScriptRoot\common.ps1"
python .\scripts\whatsapp-switch.py production   # checks chatwoot.receply.net answers Meta's verification first
if ($LASTEXITCODE -ne 0) { throw 'not switched - check production, then run this again' }
python .\scripts\whatsapp-status.py
Invoke-Docker compose --profile whatsapp stop cloudflared
Write-Host 'Tunnel stopped. WhatsApp is back on production.'
