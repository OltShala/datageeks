# Receply LOCAL — stop everything (data is kept; start again with .\scripts\start.ps1).
# If WhatsApp is on this PC, give it back first: .\scripts\whatsapp-production.ps1
. "$PSScriptRoot\common.ps1"
Invoke-Docker compose --profile whatsapp stop
Write-Host 'Receply LOCAL stopped. Data is kept.'
