// Receply LOCAL — end-to-end test through Chatwoot's public chat API (like a real guest on the API test inbox):
// book a room in two messages, check the database, then cancel in two messages.
//   node scripts/test.js            (paced ~40 s between messages: the OpenAI account allows ~30k tokens/minute)
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const cw = JSON.parse(fs.readFileSync(path.join(ROOT, 'secrets', 'chatwoot-local.json'), 'utf8'));
const BASE = 'http://localhost:3000/public/api/v1/inboxes/' + cw.api_inbox_identifier;
const PAUSE = Number(process.env.PAUSE || 40) * 1000;
const results = [];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const check = (name, ok, detail = '') => { results.push(ok); console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${name}${detail ? '  -- ' + String(detail).slice(0, 220) : ''}`); };
const psql = (sql) => spawnSync('docker', ['compose', 'exec', '-T', 'postgres', 'psql', '-U', 'chatwoot', '-d', 'n8n_memory', '-At', '-c', sql],
  { cwd: ROOT, encoding: 'utf8' }).stdout.trim();
async function api(method, p, body) {
  const r = await fetch(BASE + p, { method, headers: { 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
  if (!r.ok) throw new Error(method + ' ' + p + ' -> ' + r.status + ' ' + (await r.text()).slice(0, 200));
  return r.json();
}

(async () => {
  const contact = await api('POST', '/contacts', { name: 'ZZTEST Local Guest', email: 'delivered@resend.dev' });
  const conv = await api('POST', `/contacts/${contact.source_id}/conversations`, {});
  const msgs = `/contacts/${contact.source_id}/conversations/${conv.id}/messages`;
  console.log(`test conversation ${conv.id} on the API test inbox`);
  let seen = 0, last = 0;
  async function say(text, timeout = 150000) {
    const wait = PAUSE - (Date.now() - last);
    if (last && wait > 0) await sleep(wait);
    last = Date.now();
    seen = (await api('GET', msgs)).length;
    await api('POST', msgs, { content: text });
    const t0 = Date.now();
    while (Date.now() - t0 < timeout) {
      await sleep(3000);
      const all = await api('GET', msgs);
      const out = all.slice(seen).filter((m) => m.message_type === 1);
      if (out.length) { await sleep(5000); const again = (await api('GET', msgs)).slice(seen).filter((m) => m.message_type === 1);
        const reply = again.map((m) => m.content).join(' / '); console.log(`   guest: ${text}\n   AI:    ${reply.slice(0, 400)}`); return reply; }
    }
    console.log(`   guest: ${text}\n   AI:    (no reply)`); return '';
  }
  const booking = () => psql("SELECT r.status || ' | ' || r.ticket || ' | ' || coalesce(r.room_number, '-') || ' | ' || (r.calendar_event_id IS NOT NULL) FROM receply_reservations r " +
    "JOIN receply_guests g ON g.id = r.guest_id WHERE g.email = 'delivered@resend.dev' ORDER BY r.id DESC LIMIT 1");

  let reply = await say('Hi! I would like to book a room for 2 guests from 20 May 2031 to 22 May 2031. My name is Test Guest, phone 044 000 777, email delivered@resend.dev.');
  for (let i = 0; i < 3 && !booking().startsWith('held') && !/TKT-\d/.test(reply); i++) reply = await say('Any free room for 2 guests is fine.');
  check('the AI held a room and asked to confirm (nothing booked yet)', booking().startsWith('held') && !/TKT-\d/.test(reply), booking());
  reply = await say('Yes, that is all correct. Please confirm the booking.');
  const ticket = (reply.match(/TKT-\d{9}/) || [''])[0];
  check('booked on the guest\'s next message, with a ticket', !!ticket && booking().startsWith('confirmed | ' + ticket), booking());
  check('test calendar entry created', booking().endsWith('| true'), booking());
  if (ticket) {
    reply = await say(`Please cancel my booking ${ticket}.`);
    check('cancel: the booking is shown first, still active', booking().startsWith('confirmed'), booking());
    reply = await say('Yes, please cancel it.');
    check('cancelled on the guest\'s next message', booking().startsWith('cancelled'), booking());
  }
  const n = psql("SELECT count(*) FROM receply_message_log WHERE created_at > now() - interval '30 minutes'");
  check('every turn logged in the database', Number(n) >= 4, n + ' log rows');
  console.log(`\n${results.filter(Boolean).length}/${results.length} checks passed`);
})().catch((e) => { console.error('TEST FAILED: ' + e.message); process.exit(1); });
