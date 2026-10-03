# Receply LOCAL — one-time Chatwoot setup (idempotent), run with:
#   docker compose exec -T -e ADMIN_EMAIL=... -e ADMIN_PASSWORD=... rails bundle exec rails runner /app/storage/setup.rb
#
# Mirrors production account 1: an account, a website inbox (the demo hotel site) and an API inbox for tests, the
# account-scoped agent bot "n8n AI Receptionist" on both inboxes (its token is what n8n replies with), and the
# account webhook that sends new messages and status changes to n8n. Writes the ids and tokens n8n needs to
# /app/storage/receply-local.json (copied out by setup.ps1; never printed).
require 'json'

email = ENV.fetch('ADMIN_EMAIL')
password = ENV.fetch('ADMIN_PASSWORD')

user = User.find_or_initialize_by(email: email)
if user.new_record?
  user.name = 'Receply Admin'
  user.password = password
  user.password_confirmation = password
  user.skip_confirmation!
  user.save!
end

account = Account.find_by(id: 1) || Account.create!(name: 'Receply Demo Hotel')
account.update!(name: 'Receply Demo Hotel') unless account.name == 'Receply Demo Hotel'
AccountUser.find_or_create_by!(account: account, user: user) { |au| au.role = :administrator }

# The demo-website chat only when asked for (WITH_WEBSITE=1, see scripts\website-on.ps1): WhatsApp only for now.
web = account.inboxes.find_by(name: 'Demo hotel website')
if !web && ENV['WITH_WEBSITE'] == '1'
  ch = Channel::WebWidget.create!(account: account, website_url: 'http://localhost:8080', widget_color: '#1F4E5F',
                                  welcome_title: 'Hi, welcome to Receply Demo Hotel',
                                  welcome_tagline: 'Ask about rooms, prices or a booking. We reply in seconds, day and night.')
  web = account.inboxes.create!(name: 'Demo hotel website', channel: ch)
end

api = account.inboxes.find_by(name: 'Test channel (API)')
unless api
  ch = Channel::Api.create!(account: account)
  api = account.inboxes.create!(name: 'Test channel (API)', channel: ch)
end

bot = AgentBot.find_by(account_id: account.id, name: 'n8n AI Receptionist') ||
      AgentBot.create!(account_id: account.id, name: 'n8n AI Receptionist', description: 'Replies through the Receply n8n workflows')
[web, api].compact.each do |inbox|
  AgentBotInbox.find_or_create_by!(inbox: inbox) { |abi| abi.agent_bot = bot }
end
token = (bot.access_token || bot.create_access_token!).token

hook = account.webhooks.find_or_initialize_by(url: 'http://n8n:5678/webhook/chatwoot-webhook')
hook.subscriptions = %w[message_created conversation_status_changed]
hook.save!

# The installation is set up: show the login page, not the first-time "installation onboarding" screen (creating
# the admin through that screen is what normally clears this flag; here the script creates the admin).
::Redis::Alfred.delete('CHATWOOT_INSTALLATION_ONBOARDING')

out = { account_id: account.id, user_email: email, website_inbox_id: web&.id, website_token: web&.channel&.website_token,
        api_inbox_id: api.id, api_inbox_identifier: api.channel.identifier, bot_id: bot.id, bot_token: token }
File.write('/app/storage/receply-local.json', JSON.generate(out))
puts "OK account #{account.id}, website inbox #{web ? web.id : 'none (WhatsApp only)'}, API inbox #{api.id}, bot #{bot.id}, webhook #{hook.id}"
