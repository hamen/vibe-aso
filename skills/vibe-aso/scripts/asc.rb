#!/usr/bin/env ruby
# Minimal App Store Connect API client (ES256 JWT, no gems).
#
# Credentials are read from ~/.vibe-aso/config.json ("asc" block) or, if set,
# the env vars ASC_KEY_ID / ASC_ISSUER_ID / ASC_P8 (env wins). Never prints
# the key material — only the request result.
#
# Usage: ruby asc.rb GET '/v1/apps?limit=200'
#        ruby asc.rb PATCH /v1/appInfoLocalizations/<id> '{"data":{...}}'
require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'

CONFIG_PATH = File.expand_path('~/.vibe-aso/config.json')

def config_asc
  return {} unless File.exist?(CONFIG_PATH)
  (JSON.parse(File.read(CONFIG_PATH))['asc'] || {})
rescue JSON::ParserError
  abort "#{CONFIG_PATH} is not valid JSON — re-run the setup wizard"
end

asc = config_asc
KEY_ID    = ENV['ASC_KEY_ID']    || asc['key_id']    || abort('missing ASC key id — run the setup wizard (see SKILL.md Phase 0)')
ISSUER_ID = ENV['ASC_ISSUER_ID'] || asc['issuer_id'] || abort('missing ASC issuer id — run the setup wizard')
P8_PATH   = File.expand_path(ENV['ASC_P8'] || asc['p8_path'] || '~/.vibe-aso/AuthKey.p8')
abort "private key not found at #{P8_PATH} — run the setup wizard" unless File.exist?(P8_PATH)

def b64(data)
  Base64.urlsafe_encode64(data).delete('=')
end

def jwt
  now = Time.now.to_i
  header  = { alg: 'ES256', kid: KEY_ID, typ: 'JWT' }
  payload = { iss: ISSUER_ID, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' }
  signing_input = "#{b64(JSON.dump(header))}.#{b64(JSON.dump(payload))}"
  key = OpenSSL::PKey::EC.new(File.read(P8_PATH))
  der = key.sign(OpenSSL::Digest::SHA256.new, signing_input)
  # DER -> raw r||s (64 bytes) for JOSE ES256
  asn = OpenSSL::ASN1.decode(der)
  r = asn.value[0].value.to_s(2).rjust(32, "\x00")
  s = asn.value[1].value.to_s(2).rjust(32, "\x00")
  "#{signing_input}.#{b64(r + s)}"
end

method, path, body = ARGV[0], ARGV[1], ARGV[2]
abort "usage: ruby asc.rb <GET|POST|PATCH|DELETE> <path> [json_body]" unless method && path
uri = URI("https://api.appstoreconnect.apple.com#{path}")
req = Object.const_get("Net::HTTP::#{method.capitalize}").new(uri)
req['Authorization'] = "Bearer #{jwt}"
req['Content-Type']  = 'application/json'
req.body = body if body
res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |h| h.request(req) }
puts "HTTP #{res.code}"
begin
  puts JSON.pretty_generate(JSON.parse(res.body)) if res.body && !res.body.empty?
rescue StandardError
  puts res.body
end
