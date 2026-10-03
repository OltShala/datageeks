# Receply demo checkout

Simple payment page styled like receply.net, deployed on Vercel. Demo only: no card details, no real money.

- Page: a checkout form (reservation ID, name, email, card). Only the test cards 4242 4242 4242 4242 / 5555 5555 5555 4444 (paid) and 4000 0000 0000 0002 (declined) are accepted; card fields never leave the browser.
  Link: `/payments?ticket=TKT-123456789&room=Double%20Room&in=2026-10-12&out=2026-10-14&guests=2&amount=50&exp=<ISO time>`
  - all optional (without `ticket` the guest types the ticket ID, format TKT- + 9 digits): `ticket`, `amount`, `name`, `room`, `in`, `out`, `guests`, `cur` (default EUR),
    `hotel`, `exp` (hold expiry, shows a countdown), `wa` (WhatsApp number for "Back to WhatsApp"), `lang=sq`
- `api/pay.js` creates the confirmation ID. If the Vercel env var `PAYMENT_WEBHOOK_URL` is set (an n8n Webhook),
  it POSTs `{ ticket_id, status: paid|failed, guest_name, guest_email, confirmation_id, amount, currency, paid_at }` there first;
  n8n can reply `{ "status": "expired" }` to refuse an expired hold. Optional `PAYMENT_WEBHOOK_SECRET` is sent as
  the `X-Receply-Secret` header.

Deploy: `vercel deploy --prod` from this folder.
