#!/usr/bin/env ruby
# Minimal App Store Connect API client (ES256 JWT, no gems).
#
# Credentials are read from ~/.vibe-aso/config.json ("asc" block) or, if set,
# the env vars ASC_KEY_ID / ASC_ISSUER_ID / ASC_P8 (env wins). Never prints
# the key material — only the request result.
#
# Usage: ruby asc.rb GET '/v1/apps?limit=200'
#        ruby asc.rb PATCH /v1/appInfoLocalizations/<id> '{"data":{...}}'
#
# Exit status: 0 on a 2xx; 1 on any other HTTP status, and on a usage error
# (bad method, bad path, missing credentials); 2 if the request never completed
# (timeout, DNS, TLS). On 0 and 1 the response is printed; usage errors and
# transport errors report on stderr.
require 'openssl'
require 'base64'
require 'json'
require 'net/http'
require 'uri'
require 'timeout'

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

METHODS = {
  'GET' => Net::HTTP::Get, 'POST' => Net::HTTP::Post,
  'PATCH' => Net::HTTP::Patch, 'DELETE' => Net::HTTP::Delete
}.freeze

HOST = 'api.appstoreconnect.apple.com'
# Total seconds for the request. Validated: a non-number would raise an
# unhandled ArgumentError, and 0 or a negative would mean "no limit at all" in
# Timeout.timeout — silently removing the ceiling this exists to provide.
DEADLINE = begin
  d = Integer(ENV['ASC_DEADLINE'] || 120)
  abort "ASC_DEADLINE must be a positive number of seconds, got #{d}" unless d.positive?
  d
rescue ArgumentError, TypeError
  abort "ASC_DEADLINE must be a positive number of seconds, got #{ENV['ASC_DEADLINE'].inspect}"
end

method, path, body = ARGV[0], ARGV[1], ARGV[2]
abort "usage: ruby asc.rb <GET|POST|PATCH|DELETE> <path> [json_body]" unless method && path
klass = METHODS[method.upcase] || abort("unsupported method #{method} — use one of #{METHODS.keys.join(', ')}")
begin
  uri = URI("https://#{HOST}#{path}")
rescue URI::InvalidURIError => e
  abort "bad path #{path.inspect}: #{e.message}"
end
# The path is interpolated into the URL, so it can move the request off Apple.
# "@evil.example/v1/apps" parses with host evil.example and userinfo
# api.appstoreconnect.apple.com — and the Bearer below is a LIVE signed ASC
# token. Refuse anything that did not stay on Apple's host over TLS.
# The port matters too: ":444/v1/apps" keeps the host but moves the request to
# another listener. Requiring a leading '/' rules out both that and the '@'
# form before the URL is even built.
abort "path must start with '/', got #{path.inspect}" unless path.start_with?('/')
unless uri.scheme == 'https' && uri.host == HOST && uri.port == 443 && uri.userinfo.nil?
  abort "refusing to send credentials to #{uri.scheme}://#{uri.host}:#{uri.port} — path must start with '/'"
end

req = klass.new(uri)
req['Authorization'] = "Bearer #{jwt}"
req['Content-Type']  = 'application/json'
req.body = body if body

begin
  # read_timeout bounds each individual read, not the whole exchange: a server
  # that dribbles a byte every 89s would keep this alive forever. Timeout.timeout
  # puts a ceiling on the total.
  res = Timeout.timeout(DEADLINE, nil, "request exceeded #{DEADLINE}s") do
    Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                    open_timeout: 15, read_timeout: 90, write_timeout: 90) { |h| h.request(req) }
  end
rescue StandardError => e
  # a hung connection must not hang the caller's shell forever
  warn "request failed: #{e.class}: #{e.message}"
  exit 2
end

puts "HTTP #{res.code}"
begin
  puts JSON.pretty_generate(JSON.parse(res.body)) if res.body && !res.body.empty?
rescue StandardError
  puts res.body
end

# exit non-zero on anything that is not 2xx, so a caller can chain on it
# instead of parsing this script's stdout
exit 1 unless res.is_a?(Net::HTTPSuccess)
