"""Show where Meta currently delivers the WhatsApp test number's messages (read-only Graph API call).
   python scripts/whatsapp-status.py
Uses the access token in secrets/whatsapp-provider.json; prints no secrets."""
import json, pathlib, urllib.request, urllib.error

root = pathlib.Path(__file__).resolve().parent.parent
cfg = json.loads((root / 'secrets' / 'whatsapp-provider.json').read_text())
pc = cfg['provider_config']
url = ('https://graph.facebook.com/v21.0/' + pc['phone_number_id'] +
       '?fields=display_phone_number,verified_name,webhook_configuration')
req = urllib.request.Request(url, headers={'Authorization': 'Bearer ' + pc['api_key']})
try:
    with urllib.request.urlopen(req, timeout=20) as r:
        d = json.load(r)
except urllib.error.HTTPError as e:
    raise SystemExit('Meta answered ' + str(e.code) + ': ' + e.read().decode()[:300])
wc = d.get('webhook_configuration', {})
print('number:            ', d.get('display_phone_number'), '-', d.get('verified_name'))
print('app webhook:       ', wc.get('application', '(none)'))
print('number override:   ', wc.get('phone_number', '(none)'))
print('account override:  ', wc.get('whatsapp_business_account', '(none)'))
target = wc.get('phone_number') or wc.get('whatsapp_business_account') or wc.get('application') or ''
print('messages go to:    ', 'PRODUCTION (chatwoot.receply.net)' if 'chatwoot.receply.net' in target else
      'LOCAL COPY (demo.receply.net)' if 'demo.receply.net' in target else (target or 'nowhere'))
