// Watch the local WhatsApp inbox: print each incoming guest message and each reply with its delivery status.
//   node scripts/watch-whatsapp.js [minutes=15]      (exits after the first reply is delivered, or on timeout)
const { spawnSync } = require('child_process');
const path = require('path');
const ROOT = path.resolve(__dirname, '..');
const minutes = Number(process.argv[2] || 15);
const q = (sql) => spawnSync('docker', ['compose', 'exec', '-T', 'postgres', 'psql', '-U', 'chatwoot', '-d', 'chatwoot_production', '-At', '-F', '|', '-c', sql],
  { cwd: ROOT, encoding: 'utf8' }).stdout.trim();
const STATUS = { 0: 'sent', 1: 'delivered', 2: 'read', 3: 'FAILED' };
const start = q('SELECT coalesce(max(m.id), 0) FROM messages m');
let last = Number(start), replied = false;
const end = Date.now() + minutes * 60000;
console.log('watching the local WhatsApp inbox for ' + minutes + ' min...');
(async function loop() {
  while (Date.now() < end) {
    const rows = q(`SELECT m.id, m.message_type, m.status, coalesce(m.content_attributes->>'external_error', ''), replace(left(coalesce(m.content, '[media]'), 90), E'\\n', ' ')
      FROM messages m JOIN inboxes i ON i.id = m.inbox_id WHERE i.channel_type = 'Channel::Whatsapp' AND m.id > ${last} AND NOT m.private ORDER BY m.id`);
    for (const line of rows.split('\n').filter(Boolean)) {
      const [id, type, status, err, text] = line.split('|');
      last = Math.max(last, Number(id));
      if (type === '0') console.log(new Date().toLocaleTimeString() + '  guest -> ' + text);
      if (type === '1') { console.log(new Date().toLocaleTimeString() + '  AI    -> ' + text + '   [' + (STATUS[status] || status) + (err ? ': ' + err : '') + ']'); replied = true; }
    }
    if (replied) {   // give WhatsApp a few seconds to report delivery, then show the final status and stop
      await new Promise((r) => setTimeout(r, 8000));
      const st = q(`SELECT m.status, coalesce(m.content_attributes->>'external_error', '') FROM messages m JOIN inboxes i ON i.id = m.inbox_id WHERE i.channel_type = 'Channel::Whatsapp' AND m.message_type = 1 ORDER BY m.id DESC LIMIT 1`).split('|');
      console.log('last reply status: ' + (STATUS[st[0]] || st[0]) + (st[1] ? ' (' + st[1] + ')' : ''));
      return;
    }
    await new Promise((r) => setTimeout(r, 3000));
  }
  console.log('no WhatsApp message arrived in ' + minutes + ' minutes');
})();
