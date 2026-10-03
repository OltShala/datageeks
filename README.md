# Receply — AI hotel receptionist (local)

Receply answers a hotel's guests on **WhatsApp** with an AI receptionist: questions about rooms and services,
availability, bookings and cancellations, in Albanian, Montenegrin/Serbian or English. The hotel owner watches
every conversation live in Chatwoot and can take over at any moment. Everything in this folder runs on this PC
with Docker Desktop, for a demo hotel ("Receply Demo Hotel", 10 rooms, no real guests).

| Open | What it is |
|---|---|
| http://localhost:3000 | **Chatwoot** — the owner's inbox: every conversation live, take over any time |
| http://localhost:5556 | **n8n** — the workflows that run the receptionist, and a log of every run |
| localhost:5433 | **The database** (e.g. DBeaver: database `n8n_memory`, user `chatwoot`, password = `POSTGRES_PASSWORD` in `.env`) |

Logins for Chatwoot and n8n: `secrets\LOGINS.txt` (copy-paste the passwords).

## Start and stop

```powershell
.\scripts\start.ps1           # starts Docker Desktop if needed, then everything
.\scripts\whatsapp-local.ps1  # connects the WhatsApp number to this PC (guests can now write)
.\scripts\stop.ps1            # stops everything; all data is kept
```

First time on a PC (or after deleting the data): `.\scripts\setup.ps1` — it builds everything and is safe to
run again. Requirements: Docker Desktop, Node.js, Python 3, and the `.env` and `secrets\` from the owner.

## How a guest message is handled

1. The guest writes to the WhatsApp number **+1 555 146 8677** (a Meta test number: only phones registered in
   the Meta app can use it).
2. Meta delivers the message to `https://demo.receply.net/webhooks/whatsapp/…` — a Cloudflare tunnel
   (`cloudflared` container) to this PC that lets **only** WhatsApp's webhook through; every other path answers 404.
3. **Chatwoot** stores the message and sends it to **n8n**.
4. n8n checks whether the AI should answer (a staff member may have taken over; escalation words such as
   "human" hand the guest to the owner), then the **AI agent** (OpenAI gpt-4o) answers using its memory of the
   guest and its tools: rooms, availability, hotel information, the guest's bookings, booking, cancelling, and
   asking for the owner.
5. The reply goes back through Chatwoot to WhatsApp, and every turn is logged in the database.

### Bookings — always two guest messages

- **Prepare:** the AI checks every detail (name, phone, email, guests, dates, the room's capacity, existing
  bookings, the hotel calendar) and **holds** the room for 30 minutes. The guest sees a summary.
- **Confirm:** only the guest's **next** message can confirm. Then the booking gets a ticket, an entry in the
  calendar, a confirmation email to the guest and a notification to the owner.
- Cancelling works the same way: the AI shows the booking first and cancels only after the next message.
- The database enforces these rules itself: no double bookings, real room numbers only, no confirmation in
  the same message as the summary.

## Where the data lives

| Data | Where |
|---|---|
| Rooms, guests, bookings, conversation log, AI memory | Postgres database `n8n_memory` |
| Conversations as the owner sees them | Chatwoot (its own database `chatwoot_production`) |
| Room list the owner edits; read-only booking list | Google Sheet **"Receply LOCAL test sheet"** (synced every 10 minutes) |
| Bookings as calendar entries | Google Calendar **"Receply LOCAL test calendar"** |

Things that really happen when you test: calls to OpenAI, emails to the guest's address (use a test address
such as `delivered@resend.dev`), emails to the owner, and phone alerts on the ntfy topic in
`secrets\local-topic.txt` (subscribe to it in the ntfy app).

## WhatsApp commands

```powershell
.\scripts\whatsapp-local.ps1          # point the number to this PC (starts the tunnel)
python .\scripts\whatsapp-status.py   # where does the number point right now?
node .\scripts\watch-whatsapp.js      # watch messages and replies arrive, with delivery status
.\scripts\whatsapp-production.ps1     # release the number again and stop the tunnel
```

While the number points here, this PC must be on, online and running, or the number goes silent.

## Files

| Path | What |
|---|---|
| `docker-compose.yml` | The containers: Chatwoot (`rails`, `sidekiq`), `postgres`, `redis`, `n8n`, `cloudflared` |
| `.env` | Passwords and keys for the containers — never share |
| `secrets\` | Logins, the encrypted service credentials and their key, tokens — never share |
| `sql\00-schema.sql`, `sql\rooms-data.sql` | Database structure and rules; the 10 demo rooms |
| `n8n\workflow-templates\` | The 13 workflows; the setup fills in this PC's values and imports them |
| `chatwoot\setup.rb`, `chatwoot\whatsapp.rb` | Create the Chatwoot account, bot, webhook and the WhatsApp inbox |
| `cloudflared\config.yml` | The tunnel's rule: only `/webhooks/whatsapp/` reaches Chatwoot |
| `scripts\` | setup / start / stop, the WhatsApp commands, and `test.js` (an automatic booking test) |

## GitHub

`.gitignore` keeps `.env` and `secrets\` off GitHub — never remove those lines, keep the repository
**private**, and only update it with `git add .`, `git commit -m "…"`, `git push` (never upload a zip of the
folder: a zip includes the secrets). On another PC, copy `.env` and `secrets\` privately, then run
`.\scripts\setup.ps1`.

## Start over

`docker compose down -v` deletes all local data (conversations, bookings, n8n); then run `.\scripts\setup.ps1`.
The test Sheet and calendar stay in Google and are reused.
