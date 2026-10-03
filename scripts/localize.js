// Turn production workflow exports into LOCAL workflow templates (placeholders instead of production values).
//
//   node scripts/localize.js <production-workflows-export.json> <production-client.txt>
//
// production-client.txt is "sheet_id|calendar_id|..." for production account 1 (read-only reference values).
// Writes n8n/workflow-templates/<id>.json. Placeholders, filled by scripts/setup.js:
//   __RL_BOT_TOKEN__     the LOCAL Chatwoot bot token (replaces the live bot tokens)
//   __RL_CALENDAR_ID__   the test calendar (replaces the hotel's real calendar)
//   __RL_SHEET_ID__      the test Google Sheet (replaces the hotel's real Sheet)
//   __RL_TOPIC__         the local phone-alert topic (replaces the production alert topic)
// and https://chatwoot.receply.net -> http://localhost:3000. Refuses to write anything that still contains a
// production identifier or token.
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const [, , EXPORT, CLIENT] = process.argv;
if (!EXPORT || !CLIENT) { console.error('usage: node scripts/localize.js <export.json> <client.txt>'); process.exit(1); }
const WANT = ['Yyc46deIweJctwWCYkOmZ', 'rcpModPrepare001', 'rcpModDeliver001', 'rcpModEscalate01', 'rcpModStaffEvt01',
  'rcpToolRooms0001', 'rcpToolFindRes01', 'rcpToolPrepare01', 'yhWLLMXaUCMvHxNR', '8zoolKwu2FjTnvQ2', 'jYjHbUwfusqwTFTk',
  'rcpSheetSync0001', 'rcpReminderPlan1'];
const PROD_TOPIC = 'receply-owner-alerts-4v7q2k9xm3';
const [prodSheet, prodCal] = fs.readFileSync(CLIENT, 'utf8').trim().split('|');
if (!prodSheet || !prodCal) throw new Error('production sheet/calendar ids missing');

const all = JSON.parse(fs.readFileSync(EXPORT, 'utf8').replace(/^﻿/, ''));
const main = all.find((w) => w.id === 'Yyc46deIweJctwWCYkOmZ');
const rac = main.nodes.find((n) => n.name === 'Resolve Account Context');
const tokAssign = rac.parameters.assignments.assignments.find((a) => a.name === 'cwToken');
const prodTokens = [...new Set([...tokAssign.value.matchAll(/'([A-Za-z0-9]{20,40})'/g)].map((m) => m[1]))];
if (!prodTokens.length) throw new Error('no Chatwoot token found in Resolve Account Context');

const outDir = path.join(ROOT, 'n8n', 'workflow-templates');
fs.mkdirSync(outDir, { recursive: true });
const forbidden = [prodSheet, prodCal, PROD_TOPIC, 'chatwoot.receply.net', 'darisdervish', ...prodTokens];
for (const id of WANT) {
  const src = all.find((w) => w.id === id);
  if (!src) throw new Error('workflow ' + id + ' not in the export');
  const wf = JSON.parse(JSON.stringify(src));
  for (const k of ['shared', 'versionId', 'activeVersionId', 'pinData', 'staticData', 'tags', 'triggerCount', 'activeVersion']) delete wf[k];
  wf.active = false;
  if (id === 'Yyc46deIweJctwWCYkOmZ') {
    const a = wf.nodes.find((n) => n.name === 'Resolve Account Context').parameters.assignments.assignments.find((x) => x.name === 'cwToken');
    a.value = a.value.replace(/'[A-Za-z0-9]{20,40}'/g, "'__RL_BOT_TOKEN__'");
  }
  let s = JSON.stringify(wf);
  s = s.split(prodCal).join('__RL_CALENDAR_ID__').split(prodSheet).join('__RL_SHEET_ID__').split(PROD_TOPIC).join('__RL_TOPIC__')
    .split('https://chatwoot.receply.net').join('http://localhost:3000')
    .split('"cachedResultName":"Calendar Appointments"').join('"cachedResultName":"Receply LOCAL test calendar"')
    .split('"cachedResultName":"Excel_projektn8n"').join('"cachedResultName":"Receply LOCAL test sheet"');
  const left = forbidden.filter((f) => s.includes(f));
  if (left.length) throw new Error(id + ' still contains ' + left.length + ' production value(s) - not written');
  fs.writeFileSync(path.join(outDir, id + '.json'), JSON.stringify([JSON.parse(s)], null, 1));
  const ph = ['__RL_BOT_TOKEN__', '__RL_CALENDAR_ID__', '__RL_SHEET_ID__', '__RL_TOPIC__'].filter((p) => s.includes(p));
  console.log(`template ${id}  ${String(wf.nodes.length).padStart(2)} nodes  ${wf.name}${ph.length ? '  [' + ph.join(', ') + ']' : ''}`);
}
