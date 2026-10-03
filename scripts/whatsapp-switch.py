"""Move the WhatsApp test number between production and this local copy (the number-level webhook at Meta).
   python scripts/whatsapp-switch.py local        # messages go to demo.receply.net -> this PC
   python scripts/whatsapp-switch.py production   # messages go back to chatwoot.receply.net -> the server
Meta checks the new address before switching (it must answer with the verify token), so a failed switch changes
nothing. Uses secrets/whatsapp-provider.json; prints no secrets."""
import json, pathlib, sys, urllib.parse, urllib.request, urllib.error

TARGETS = {'local': 'https://demo.receply.net/webhooks/whatsapp/%2B15551468677',
           'production': 'https://chatwoot.receply.net/webhooks/whatsapp/%2B15551468677'}
if len(sys.argv) != 2 or sys.argv[1] not in TARGETS:
    raise SystemExit('usage: python scripts/whatsapp-switch.py local|production')
root = pathlib.Path(__file__).resolve().parent.parent
pc = json.loads((root / 'secrets' / 'whatsapp-provider.json').read_text())['provider_config']
target = TARGETS[sys.argv[1]]

# 1. the target must answer Meta's verification itself first (same check Meta does)
probe = target + '?' + urllib.parse.urlencode({'hub.mode': 'subscribe', 'hub.verify_token': pc['webhook_verify_token'], 'hub.challenge': 'receply-check'})
try:   # a browser-like User-Agent: Cloudflare's bot protection on receply.net blocks Python's default one (403)
    with urllib.request.urlopen(urllib.request.Request(probe, headers={'User-Agent': 'Mozilla/5.0 (Receply switch check)'}), timeout=20) as r:
        ok = r.read().decode().strip() == 'receply-check'
except urllib.error.URLError as e:
    ok = False
    print('target not reachable:', getattr(e, 'code', '') or e.reason)
if not ok:
    raise SystemExit('NOT SWITCHED: ' + sys.argv[1] + ' does not answer the verification yet (is it running?)')

# 2. switch the number-level webhook at Meta
body = urllib.parse.urlencode({'webhook_configuration': json.dumps({'override_callback_uri': target, 'verify_token': pc['webhook_verify_token']})}).encode()
req = urllib.request.Request('https://graph.facebook.com/v21.0/' + pc['phone_number_id'], data=body, method='POST',
                             headers={'Authorization': 'Bearer ' + pc['api_key']})
try:
    with urllib.request.urlopen(req, timeout=30) as r:
        res = json.load(r)
except urllib.error.HTTPError as e:
    raise SystemExit('NOT SWITCHED: Meta answered ' + str(e.code) + ': ' + e.read().decode()[:300])
print('Meta:', 'switched' if res.get('success') else res)
print('WhatsApp +1 555 146 8677 now goes to the', 'LOCAL copy (this PC)' if sys.argv[1] == 'local' else 'PRODUCTION server')
