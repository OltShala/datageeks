// Receply LOCAL — first-time setup (idempotent: safe to run again). Run from PowerShell:  .\scripts\setup.ps1
// Needs Docker Desktop running and Node.js. Every step checks whether it is already done.
// Logins it creates are written to secrets\LOGINS.txt (never printed).
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const ROOT = path.resolve(__dirname, '..');
const SEC = path.join(ROOT, 'secrets');
const env = Object.fromEntries(fs.readFileSync(path.join(ROOT, '.env'), 'utf8').split(/\r?\n/)
  .filter((l) => /^[A-Z_]+=/.test(l)).map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1)]));
const WORKFLOWS = ['rcpModPrepare001', 'rcpModDeliver001', 'rcpModEscalate01', 'rcpModStaffEvt01', 'rcpToolRooms0001',
  'rcpToolFindRes01', 'rcpToolPrepare01', 'jYjHbUwfusqwTFTk', 'yhWLLMXaUCMvHxNR', '8zoolKwu2FjTnvQ2', 'rcpSheetSync0001',
  'rcpReminderPlan1', 'Yyc46deIweJctwWCYkOmZ'];
const CRED = { calendar: { id: '8wAB0uxntdU6yfvs', name: 'Google Calendar account' }, sheets: { id: '2VVltbj0a8vgsnP5', name: 'Google Sheets account' } };

const log = (m) => console.log('  ' + m);
const step = (m) => console.log('\n== ' + m);
function dc(args, input) {
  const r = spawnSync('docker', ['compose', ...args], { cwd: ROOT, encoding: 'utf8', input, maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0) throw new Error('docker compose ' + args.slice(0, 4).join(' ') + ' failed: ' + ((r.stderr || '') + (r.stdout || '')).slice(-600));
  return r.stdout || '';
}
const psql = (db, sql) => dc(['exec', '-T', 'postgres', 'psql', '-U', 'chatwoot', '-d', db, '-v', 'ON_ERROR_STOP=1', '-At', '-c', sql]).trim();
const psqlStdin = (db, text) => dc(['exec', '-T', 'postgres', 'psql', '-U', 'chatwoot', '-d', db, '-v', 'ON_ERROR_STOP=1', '-q'], text);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function waitFor(what, fn, seconds = 240) {
  const end = Date.now() + seconds * 1000;
  while (Date.now() < end) { try { if (await fn()) return; } catch (e) { /* not yet */ } await sleep(3000); }
  throw new Error('timed out waiting for ' + what);
}
const http = async (url, opts) => { const r = await fetch(url, opts); return { status: r.status, text: await r.text() }; };
const secret = (n) => crypto.randomBytes(n).toString('base64url');
function firstJson(s) {
  const i = s.indexOf('{');
  if (i < 0) throw new Error('no JSON in output: ' + s.slice(-300));
  let depth = 0, inStr = false, esc = false;
  for (let k = i; k < s.length; k++) {
    const c = s[k];
    if (inStr) { if (esc) esc = false; else if (c === '\\') esc = true; else if (c === '"') inStr = false; continue; }
    if (c === '"') inStr = true; else if (c === '{') depth++; else if (c === '}' && --depth === 0) return JSON.parse(s.slice(i, k + 1));
  }
  throw new Error('unterminated JSON in output');
}
function n8nImport(kind, obj, name) {
  const tmp = path.join(SEC, '.tmp-' + name);
  fs.writeFileSync(tmp, JSON.stringify(obj));
  try {
    dc(['cp', tmp, 'n8n:/home/node/.n8n/' + name]);
    const out = dc(['exec', '-T', 'n8n', 'n8n', 'import:' + kind, '--input=/home/node/.n8n/' + name]);
    if (!/Successfully imported/i.test(out)) throw new Error('import:' + kind + ' did not confirm: ' + out.slice(-300));
  } finally {
    fs.rmSync(tmp, { force: true });
    try { dc(['exec', '-T', 'n8n', 'rm', '-f', '/home/node/.n8n/' + name]); } catch (e) { /* ignore */ }
  }
}
function n8nExecute(id) {
  const out = dc(['exec', '-T', '-e', 'N8N_RUNNERS_BROKER_PORT=5691', 'n8n', 'n8n', 'execute', '--id=' + id, '--rawOutput']);
  return firstJson(out);
}

function googleSetupWorkflow(sourceSheet) {
  const httpNode = (name, x, cred, method, url, body) => ({
    id: 'g-' + name.replace(/\W/g, ''), name, type: 'n8n-nodes-base.httpRequest', typeVersion: 4.2, position: [x, 0],
    credentials: cred === 'calendar' ? { googleCalendarOAuth2Api: CRED.calendar } : { googleSheetsOAuth2Api: CRED.sheets },
    parameters: { method, url, authentication: 'predefinedCredentialType',
      nodeCredentialType: cred === 'calendar' ? 'googleCalendarOAuth2Api' : 'googleSheetsOAuth2Api',
      ...(body ? { sendBody: true, specifyBody: 'json', jsonBody: body } : {}), options: {} } });
  const ranges = 'ranges=' + encodeURIComponent('RoomInformation!A1:Z200') + '&ranges=' + encodeURIComponent("'Hotel Services Information'!A1:Z200");
  const nodes = [
    { id: 'g-run', name: 'Run', type: 'n8n-nodes-base.manualTrigger', typeVersion: 1, position: [0, 0], parameters: {} },
    httpNode('Create Calendar', 220, 'calendar', 'POST', 'https://www.googleapis.com/calendar/v3/calendars',
      JSON.stringify({ summary: 'Receply LOCAL test calendar', timeZone: 'Europe/Belgrade', description: 'Test calendar of the local Receply demo copy. Safe to delete.' })),
    httpNode('Read Source', 440, 'sheets', 'GET', 'https://sheets.googleapis.com/v4/spreadsheets/' + sourceSheet + '/values:batchGet?' + ranges),
    httpNode('Create Sheet', 660, 'sheets', 'POST', 'https://sheets.googleapis.com/v4/spreadsheets',
      JSON.stringify({ properties: { title: 'Receply LOCAL test sheet', timeZone: 'Europe/Belgrade' },
        sheets: [{ properties: { sheetId: 0, title: 'Hotel Services Information' } }, { properties: { sheetId: 1, title: 'RoomInformation' } }] })),
    httpNode('Fill Sheet', 880, 'sheets', 'POST', "={{ 'https://sheets.googleapis.com/v4/spreadsheets/' + $json.spreadsheetId + '/values:batchUpdate' }}",
      "={{ JSON.stringify({ valueInputOption: 'RAW', data: [ { range: 'RoomInformation!A1', values: $('Read Source').first().json.valueRanges[0].values || [] }, { range: \"'Hotel Services Information'!A1\", values: $('Read Source').first().json.valueRanges[1].values || [] } ] }) }}"),
    { id: 'g-result', name: 'Result', type: 'n8n-nodes-base.code', typeVersion: 2, position: [1100, 0], parameters: { jsCode:
      "const v = $('Read Source').first().json.valueRanges;\nreturn [{ json: { calendarId: $('Create Calendar').first().json.id, sheetId: $('Create Sheet').first().json.spreadsheetId, roomRows: (v[0].values || []).length, infoRows: (v[1].values || []).length } }];" } },
  ];
  const connections = {};
  for (let i = 0; i < nodes.length - 1; i++) connections[nodes[i].name] = { main: [[{ node: nodes[i + 1].name, type: 'main', index: 0 }]] };
  return { id: 'rlGoogleSetup001', name: 'Receply LOCAL — one-time: create the test calendar and Sheet', active: false,
    settings: { executionOrder: 'v1' }, nodes, connections };
}

(async () => {
  step('1. Containers: database and cache');
  dc(['up', '-d', 'postgres', 'redis']);
  await waitFor('Postgres', async () => /accepting/.test(dc(['exec', '-T', 'postgres', 'pg_isready', '-U', 'chatwoot'])));
  log('Postgres ready');

  step('2. Receply database (n8n_memory): structure from production, no data');
  if (psql('chatwoot_production', "SELECT count(*) FROM pg_database WHERE datname = 'n8n_memory'") === '0') {
    psql('chatwoot_production', 'CREATE DATABASE n8n_memory');
    log('database n8n_memory created');
  }
  if (psql('n8n_memory', "SELECT count(*) FROM pg_tables WHERE tablename = 'receply_clients'") === '0') {
    psqlStdin('n8n_memory', fs.readFileSync(path.join(ROOT, 'sql', '00-schema.sql'), 'utf8'));
    log('schema applied (' + psql('n8n_memory', "SELECT count(*) FROM pg_tables WHERE schemaname = 'public'") + ' tables)');
  } else log('schema already there');

  step('3. Chatwoot');
  if (psql('chatwoot_production', "SELECT count(*) FROM pg_tables WHERE tablename = 'accounts'") === '0') {
    log('preparing the Chatwoot database (first time, 1-3 minutes)...');
    dc(['run', '--rm', 'rails', 'bundle', 'exec', 'rails', 'db:chatwoot_prepare']);
  }
  dc(['up', '-d', 'rails', 'sidekiq']);
  await waitFor('Chatwoot on http://localhost:3000', async () => (await http('http://localhost:3000/api')).status === 200, 420);
  log('Chatwoot answering on http://localhost:3000');
  const loginsPath = path.join(SEC, 'logins.json');
  const logins = fs.existsSync(loginsPath) ? JSON.parse(fs.readFileSync(loginsPath, 'utf8')) : {
    chatwoot: { url: 'http://localhost:3000', email: 'oltshala@gmail.com', password: 'Rcp-' + secret(12) + '!7a' },
    n8n: { url: 'http://localhost:5556', email: 'oltshala@gmail.com', password: 'Rcp-' + secret(12) + '!7A' },
  };
  fs.writeFileSync(loginsPath, JSON.stringify(logins, null, 1));
  fs.writeFileSync(path.join(SEC, 'LOGINS.txt'), [
    'Receply LOCAL — logins for this PC only (generated by setup; keep private).', '',
    'Chatwoot (inbox, conversations):  ' + logins.chatwoot.url, '  email:    ' + logins.chatwoot.email, '  password: ' + logins.chatwoot.password, '',
    'n8n (workflows, executions):      ' + logins.n8n.url, '  email:    ' + logins.n8n.email, '  password: ' + logins.n8n.password, '',
    'Database (DBeaver): localhost:5433, database n8n_memory, user chatwoot, password = POSTGRES_PASSWORD in .env', ''].join('\r\n'));
  dc(['cp', path.join(ROOT, 'chatwoot', 'setup.rb'), 'rails:/app/storage/setup.rb']);
  const cwOut = dc(['exec', '-T', '-e', 'ADMIN_EMAIL=' + logins.chatwoot.email, '-e', 'ADMIN_PASSWORD=' + logins.chatwoot.password,
    '-e', 'WITH_WEBSITE=' + (process.env.WITH_WEBSITE === '1' ? '1' : '0'), 'rails', 'bundle', 'exec', 'rails', 'runner', '/app/storage/setup.rb']);
  log((cwOut.match(/OK account.*/) || ['Chatwoot setup ran'])[0]);
  dc(['cp', 'rails:/app/storage/receply-local.json', path.join(SEC, 'chatwoot-local.json')]);
  dc(['exec', '-T', 'rails', 'rm', '-f', '/app/storage/receply-local.json', '/app/storage/setup.rb']);
  const cw = JSON.parse(fs.readFileSync(path.join(SEC, 'chatwoot-local.json'), 'utf8'));

  step('4. n8n');
  dc(['up', '-d', 'n8n']);
  let settings;
  await waitFor('n8n on http://localhost:5556', async () => {   // healthz answers before the REST API is ready
    const r = await http('http://localhost:5556/rest/settings');
    try { settings = JSON.parse(r.text); return r.status === 200 && !!settings.data; } catch (e) { return false; }
  });
  if (settings.data && settings.data.userManagement && settings.data.userManagement.showSetupOnFirstLoad) {
    const r = await http('http://localhost:5556/rest/owner/setup', { method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: logins.n8n.email, firstName: 'Receply', lastName: 'Local', password: logins.n8n.password }) });
    log(r.status === 200 ? 'n8n owner login created (see secrets\\LOGINS.txt)' : 'n8n owner not created (' + r.status + ') - set it up on first visit');
  } else log('n8n owner already set up');
  const creds = JSON.parse(fs.readFileSync(path.join(SEC, 'credentials-encrypted.json'), 'utf8'));
  creds.push({ id: 'HlCBJZWnzlU5fYpY', name: 'Chatwoot Postgres (n8n_memory)', type: 'postgres',
    data: { host: 'postgres', database: 'n8n_memory', user: 'chatwoot', password: env.POSTGRES_PASSWORD, port: 5432, ssl: 'disable',
      allowUnauthorizedCerts: false, sshTunnel: false, maxConnections: 100 } });
  n8nImport('credentials', creds, 'rl-creds.json');
  log(creds.length + ' credentials in place (OpenAI, Google Calendar/Sheets, Gmail, Resend: copied encrypted from production; Postgres: local)');

  step('5. Test calendar and test Google Sheet (never the hotel\'s real ones)');
  const gPath = path.join(SEC, 'google-test.json');
  if (!fs.existsSync(gPath)) {
    n8nImport('workflow', [googleSetupWorkflow(fs.readFileSync(path.join(SEC, 'source-sheet-id.txt'), 'utf8').trim())], 'rl-google.json');
    const run = n8nExecute('rlGoogleSetup001');
    const rd = run.data.resultData;
    if (rd.error) throw new Error('creating the test calendar/Sheet failed: ' + (rd.error.message || JSON.stringify(rd.error)).slice(0, 300));
    const res = rd.runData.Result[0].data.main[0][0].json;
    if (!res.calendarId || !res.sheetId) throw new Error('test calendar/Sheet not created: ' + JSON.stringify(res));
    fs.writeFileSync(gPath, JSON.stringify({ calendarId: res.calendarId, calendarName: 'Receply LOCAL test calendar', sheetId: res.sheetId, sheetName: 'Receply LOCAL test sheet' }, null, 1));
    log('created: test calendar + test Sheet (copied ' + res.roomRows + ' room rows and ' + res.infoRows + ' hotel-information rows from the hotel Sheet, read-only)');
  } else log('already created earlier');
  const g = JSON.parse(fs.readFileSync(gPath, 'utf8'));
  const topicPath = path.join(SEC, 'local-topic.txt');
  if (!fs.existsSync(topicPath)) fs.writeFileSync(topicPath, 'receply-local-' + crypto.randomBytes(5).toString('hex'));
  const topic = fs.readFileSync(topicPath, 'utf8').trim();

  step('6. Workflows (local copies of the 13 production workflows)');
  for (const id of WORKFLOWS) {   // filled in memory only: the filled copies hold the local bot token
    let s = fs.readFileSync(path.join(ROOT, 'n8n', 'workflow-templates', id + '.json'), 'utf8');
    s = s.split('__RL_BOT_TOKEN__').join(cw.bot_token).split('__RL_CALENDAR_ID__').join(g.calendarId)
      .split('__RL_SHEET_ID__').join(g.sheetId).split('__RL_TOPIC__').join(topic);
    if (/__RL_[A-Z_]+__/.test(s)) throw new Error(id + ': placeholder left');
    n8nImport('workflow', JSON.parse(s), 'rl-wf.json');
  }
  log(WORKFLOWS.length + ' workflows imported');
  for (const id of WORKFLOWS) dc(['exec', '-T', 'n8n', 'n8n', 'publish:workflow', '--id=' + id]);
  log('all 13 published (switched on)');

  step('7. The demo hotel in the Receply database');
  const ps = JSON.parse(fs.readFileSync(path.join(SEC, 'prod-settings.json'), 'utf8'));
  psql('n8n_memory', `INSERT INTO receply_clients (account_id, business_name, vertical, sheet_id, calendar_id, workflow_id, webhook_path, timezone,
      office_open, office_close, office_days, owner_email, alert_topic, next_booking_no, public_name)
    VALUES (${Number(cw.account_id)}, 'Receply Demo Hotel (local)', 'hotel', '${g.sheetId}', '${g.calendarId}', 'Yyc46deIweJctwWCYkOmZ', 'chatwoot-webhook',
      '${ps.timezone}', '${ps.office_open}', '${ps.office_close}', '${ps.office_days}', NULL, '${topic}', 1, 'Receply Demo Hotel')
    ON CONFLICT (account_id) DO UPDATE SET sheet_id = EXCLUDED.sheet_id, calendar_id = EXCLUDED.calendar_id, alert_topic = EXCLUDED.alert_topic,
      business_name = EXCLUDED.business_name, public_name = EXCLUDED.public_name`);
  if (psql('n8n_memory', 'SELECT count(*) FROM receply_rooms') === '0') psqlStdin('n8n_memory', fs.readFileSync(path.join(ROOT, 'sql', 'rooms-data.sql'), 'utf8'));
  log('demo hotel registered with ' + psql('n8n_memory', 'SELECT count(*) FROM receply_rooms') + ' rooms');

  step('8. Restart n8n (activates the webhook and schedules) and the demo hotel website');
  dc(['restart', 'n8n']);
  await waitFor('n8n after restart', async () => (await http('http://localhost:5556/healthz')).status === 200);
  await waitFor('the main workflow to activate', async () => /Activated workflow .*Yyc46deIweJctwWCYkOmZ/.test(dc(['logs', 'n8n', '--since', '5m'])), 120);
  if (cw.website_token) {   // the demo-website chat exists only when set up with WITH_WEBSITE=1 (WhatsApp only for now)
    const tpl = fs.readFileSync(path.join(ROOT, 'demo-site', 'index.template.html'), 'utf8');
    fs.writeFileSync(path.join(ROOT, 'demo-site', 'index.html'), tpl.split('__RL_WEBSITE_TOKEN__').join(cw.website_token));
    dc(['--profile', 'website', 'up', '-d', 'website']);
  }
  try { const sync = n8nExecute('rcpSheetSync0001'); log('Sheet Sync ran: ' + (sync.data.resultData.error ? 'ERROR ' + sync.data.resultData.error.message : 'ok')); } catch (e) { log('Sheet Sync first run: ' + e.message.slice(0, 160)); }

  console.log('\nDONE. Receply runs locally:\n' +
    (cw.website_token ? '  Demo hotel website (chat with the AI):  http://localhost:8080\n' : '  Guests reach it on WhatsApp:            .\\scripts\\whatsapp-local.ps1\n') +
    '  Chatwoot (the owner\'s inbox):           http://localhost:3000\n' +
    '  n8n (workflows):                        http://localhost:5556\n' +
    '  Logins:                                 ' + path.join(SEC, 'LOGINS.txt') + '\n' +
    '  Phone alerts (ntfy app, subscribe to):  ' + topic);
})().catch((e) => { console.error('\nSETUP FAILED: ' + e.message); process.exit(1); });
