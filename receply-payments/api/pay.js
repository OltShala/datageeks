// Demo payment processor for /payments.
//
// The browser never decides the confirmation ID: it is created here, after the "payment" goes through.
// If PAYMENT_WEBHOOK_URL is set (an n8n Webhook node), the result is sent there so n8n can mark the
// reservation confirmed, update the calendar and message the guest. n8n may answer with
// { "status": "expired" } to refuse a hold that is no longer valid, or with its own confirmation_id.
// Without the variable the page still works on its own (pure demo mode).
const crypto = require('crypto');

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    res.setHeader('Allow', 'POST');
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const body = typeof req.body === 'string' ? safeJson(req.body) : req.body || {};
  const ticketId = String(body.ticket_id || '').trim().toUpperCase();
  if (!/^TKT-\d{9}$/.test(ticketId)) {
    return res.status(400).json({ error: 'Invalid ticket ID' });
  }

  const guestName = String(body.guest_name || '').trim().slice(0, 100);
  const guestEmail = String(body.guest_email || '').trim().slice(0, 200);
  if (guestName.length < 2) return res.status(400).json({ error: 'Invalid name' });
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(guestEmail)) return res.status(400).json({ error: 'Invalid email' });

  // Card details never reach this function — the page only reports the outcome of the demo test card.
  const status = body.result === 'decline' ? 'failed' : 'paid';
  const now = new Date();
  const payload = {
    ticket_id: ticketId,
    status,
    guest_name: guestName,
    guest_email: guestEmail,
    confirmation_id: status === 'paid' ? confirmationId(now) : null,
    amount: typeof body.amount === 'number' ? body.amount : null,
    currency: typeof body.currency === 'string' ? body.currency.slice(0, 3) : 'EUR',
    paid_at: status === 'paid' ? now.toISOString() : null,
    provider: 'receply-demo',
  };

  const hook = process.env.PAYMENT_WEBHOOK_URL;
  if (hook) {
    try {
      const r = await fetch(hook, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(process.env.PAYMENT_WEBHOOK_SECRET ? { 'X-Receply-Key': process.env.PAYMENT_WEBHOOK_SECRET } : {}),
        },
        body: JSON.stringify(payload),
        signal: AbortSignal.timeout(15000),
      });
      if (!r.ok) return res.status(502).json({ error: 'Booking system unavailable' });
      const answer = safeJson(await r.text());
      if (answer.status === 'expired') return res.json({ status: 'expired' });
      if (status === 'paid' && typeof answer.confirmation_id === 'string' && answer.confirmation_id) {
        payload.confirmation_id = answer.confirmation_id;
      }
    } catch (e) {
      return res.status(502).json({ error: 'Booking system unavailable' });
    }
  }

  return res.json({ status: payload.status, confirmation_id: payload.confirmation_id, demo: !hook });
};

function confirmationId(d) {
  const ymd = d.toISOString().slice(0, 10).replace(/-/g, '');
  return 'PAY-' + ymd + '-' + crypto.randomBytes(3).toString('hex').toUpperCase();
}

function safeJson(s) {
  try { return JSON.parse(s) || {}; } catch (e) { return {}; }
}
