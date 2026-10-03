# Receply — local demo copy

The whole Receply product running on this PC with Docker Desktop: the same Chatwoot, n8n workflows,
database rules and AI as production on the VPS — but **a demo hotel with no real guests**, its own logins
and secrets, a **test** Google Sheet and calendar, and nothing reachable from the internet.

Guests reach it on **WhatsApp only** for now (the test number, see [WhatsApp](#whatsapp)); the demo-website chat is
switched off — bring it back with `$env:WITH_WEBSITE='1'; .\scripts\setup.ps1` (then http://localhost:8080).

| Open | What it is |
|---|---|
| http://localhost:3000 | Chatwoot — the owner's inbox: every conversation live, take over any time |
| http://localhost:5556 | n8n — the 13 workflows that run the receptionist, and every execution |
| localhost:5433 | The database (DBeaver: database `n8n_memory`, user `chatwoot`, password = `POSTGRES_PASSWORD` in `.env`) |

Logins: `secrets\LOGINS.txt` (created by the setup; keep it private).
Production n8n stays at http://localhost:5555 when the SSH tunnel is open — a different system.

## Start, stop

```powershell
.\scripts\start.ps1     # starts Docker Desktop if needed, then everything
.\scripts\stop.ps1      # stops everything; all data is kept
```

First time on a PC (or after deleting the Docker volumes): `.\scripts\setup.ps1` — it is safe to run again.

## What is the same as production

- Images pinned to the exact builds production runs (Chatwoot 4.16.2, n8n 2.32.7, Postgres 15 + pgvector, Redis 7.4).
- The 13 production workflows (receptionist, the four modules, the booking/cancellation tools, email,
  Sheet Sync, reminder planner) with the same ids and logic.
- The database structure and all its rules (two-step booking, no double bookings, real room numbers...).
- The AI: OpenAI gpt-4o with the production OpenAI credential.

## What is different on purpose

| Production | Local copy |
|---|---|
| Real hotel, real guests | "Receply Demo Hotel", the 10 rooms only, no guests or history |
| The hotel's Google Sheet and calendar | "Receply LOCAL test sheet" and "Receply LOCAL test calendar" (in the same Google account) |
| WhatsApp, Instagram, website widget | The demo website widget and an API test inbox |
| Owner phone alerts on the production ntfy topic | Their own topic: `secrets\local-topic.txt` (subscribe in the ntfy app to see local alerts) |
| Public through Cloudflare | Only on this PC (127.0.0.1) |

Things that still really happen (they use the copied production credentials): calls to OpenAI, guest
emails through Resend (to whatever address the test guest gives), owner emails from the Gmail account to
the operator, and pushes to the local ntfy topic. Use test email addresses such as `delivered@resend.dev`.

## WhatsApp

The local copy can take over the WhatsApp **test number +1 555 146 8677** — the same number production uses
(Meta gives one test number per business account, and only phones registered in Meta can use it).

```powershell
.\scripts\whatsapp-local.ps1        # WhatsApp -> this PC (production's WhatsApp pauses)
.\scripts\whatsapp-production.ps1   # WhatsApp -> back to the server; stops the tunnel
python .\scripts\whatsapp-status.py # where does WhatsApp go right now?
node .\scripts\watch-whatsapp.js    # watch messages and replies arrive (with WhatsApp delivery status)
```

How it works: Meta delivers the number's messages to a **number-level webhook** (it overrides the app's Callback
URL — changing that in Meta's dashboard does nothing). The switch scripts move it between
`https://chatwoot.receply.net/webhooks/whatsapp/%2B15551468677` (production) and
`https://demo.receply.net/webhooks/whatsapp/%2B15551468677` (this PC), checking first that the target answers
Meta's verification — a failed switch changes nothing. `demo.receply.net` is the Cloudflare tunnel
`receply-local-demo` (cloudflared container, `cloudflared\config.yml`), which lets ONLY `/webhooks/whatsapp/`
through to the local Chatwoot; every other path answers 404. The local WhatsApp inbox uses the same Meta token and
verify token as production (`secrets\whatsapp-provider.json`).

Keep in mind:
- While WhatsApp is on this PC, the PC must be on, online and running Receply LOCAL, or the number goes silent.
- Switch back after the demo. Running `whatsapp-local.ps1` again later is fine.
- Editing and saving the WhatsApp inbox in production's Chatwoot makes production re-claim the number (Chatwoot
  re-sets the number-level webhook on save) — do not touch it while the number is here. The local Chatwoot tries
  the same with `http://localhost:3000`, which Meta cannot reach, so that attempt always fails harmlessly.

## Files

| Path | What |
|---|---|
| `docker-compose.yml` | The containers |
| `.env` | Local passwords and keys — generated, never commit |
| `secrets\` | Logins, the copied (encrypted) production credentials and their key, local tokens — keep private |
| `sql\00-schema.sql` | Database structure from production (no data); `sql\rooms-data.sql` the 10 rooms |
| `n8n\workflow-templates\` | The production workflows with placeholders (made by `scripts\localize.js`); the setup fills them in and imports them |
| `chatwoot\setup.rb`, `chatwoot\whatsapp.rb` | Create the Chatwoot account, inboxes, bot and webhook; the WhatsApp inbox |
| `demo-site\` | The demo hotel website |
| `scripts\` | setup / start / stop, and `localize.js` to refresh the workflows from production |

## GitHub

This folder is a git repository. `.gitignore` keeps `.env` and `secrets\` (every password, key, token and login)
off GitHub — never remove those lines; keep the repository **private**. On another PC, `git clone` gives everything
except those two: copy them over privately (USB, password manager), then run `.\scripts\setup.ps1`.

## Refresh the workflows from production

After production changes, export its workflows and run (from the n8n_claude project):
`node C:\Receply-Local\scripts\localize.js <export.json> <client.txt>` then `.\scripts\setup.ps1`.

## Start over

`docker compose down -v` deletes all local data (conversations, bookings, n8n); then `.\scripts\setup.ps1`.
The test Sheet and calendar stay in Google and are reused (delete `secrets\google-test.json` to make new ones).
