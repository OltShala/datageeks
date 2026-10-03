# Receply LOCAL — add the WhatsApp test number to the local Chatwoot (idempotent):
#   docker compose exec -T rails bundle exec rails runner /app/storage/whatsapp.rb
# Reads /app/storage/wa.json ({phone_number, provider_config} copied from production: the same Meta token and the
# same webhook verify token, so moving the number between production and this copy only changes Meta's Callback
# URL). Attaches the local AI bot like production. Prints no secrets.
require 'json'

src = JSON.parse(File.read('/app/storage/wa.json'))
account = Account.find(1)
cfg = src['provider_config'].slice('api_key', 'phone_number_id', 'business_account_id', 'webhook_verify_token')

channel = Channel::Whatsapp.find_by(phone_number: src['phone_number'])
if channel
  channel.update!(provider: 'whatsapp_cloud', provider_config: cfg)
  inbox = Inbox.find_by(channel: channel)
else
  channel = Channel::Whatsapp.create!(account: account, phone_number: src['phone_number'], provider: 'whatsapp_cloud', provider_config: cfg)
  inbox = account.inboxes.create!(name: 'WhatsApp (test number)', channel: channel)
end
bot = AgentBot.find_by!(account_id: account.id, name: 'n8n AI Receptionist')
AgentBotInbox.find_or_create_by!(inbox: inbox) { |abi| abi.agent_bot = bot }
same_token = channel.provider_config['webhook_verify_token'] == cfg['webhook_verify_token']
puts "OK WhatsApp inbox #{inbox.id} for #{channel.phone_number}, AI bot attached, verify token same as production: #{same_token}"
