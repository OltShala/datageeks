# Receply LOCAL — start everything (after the first-time setup). Run from this folder:  .\scripts\start.ps1
. "$PSScriptRoot\common.ps1"
Start-DockerDesktop
Invoke-Docker compose up -d
Write-Host 'Waiting for Chatwoot and n8n...'
Wait-Url 'http://localhost:3000/api'
Wait-Url 'http://localhost:5556/healthz'
Write-Host ''
Write-Host 'Receply LOCAL is running:'
Write-Host '  Chatwoot (the owner''s inbox):           http://localhost:3000'
Write-Host '  n8n (workflows):                        http://localhost:5556'
Write-Host '  Logins:                                 secrets\LOGINS.txt'
Write-Host '  WhatsApp test number to this PC:        .\scripts\whatsapp-local.ps1   (back: .\scripts\whatsapp-production.ps1)'
