#!/usr/bin/env ruby
# Tests for asc.rb's exit contract. Run: ruby skills/vibe-aso/scripts/test_asc.rb
#
# No gems and no calls to Apple. A throwaway HTTP server on localhost stands in
# for the API, and asc.rb is pointed at it by rewriting only its host constant
# into a temp copy — everything else under test (JWT signing, method table,
# host pinning, exit codes) is the real code.
require 'socket'
require 'tmpdir'
require 'fileutils'
require 'openssl'
require 'json'

HERE = File.expand_path(__dir__)
ASC  = File.join(HERE, 'asc.rb')
PASS = []
FAIL = []

def check(name)
  ok = yield
  (ok ? PASS : FAIL) << name
  puts(ok ? "  ok    #{name}" : "  FAIL  #{name}")
rescue StandardError => e
  FAIL << name
  puts "  FAIL  #{name}\n          #{e.class}: #{e.message}"
end

# ── fixtures ─────────────────────────────────────────────────────────────────

work = Dir.mktmpdir('asc-test')
at_exit { FileUtils.remove_entry(work) if File.directory?(work) }

# A real P-256 key, so the JWT path is genuinely exercised.
key_path = File.join(work, 'AuthKey.p8')
File.write(key_path, OpenSSL::PKey::EC.generate('prime256v1').to_pem)
File.chmod(0o600, key_path)

ENV['ASC_KEY_ID']    = 'ABCDEFGHIJ'
ENV['ASC_ISSUER_ID'] = '00000000-0000-0000-0000-000000000000'
ENV['ASC_P8']        = key_path
ENV['HOME']          = work # never read a real ~/.vibe-aso

# The stand-in API. Hand-rolled on TCPServer rather than WEBrick, which left
# the stdlib in Ruby 3.0 — asc.rb's whole premise is "no gems", so its tests
# should not need one either. Each route drives one branch of the contract.
ROUTES = {
  '/ok'          => [200, 'application/json', '{"data":[{"id":"1"}]}'],
  '/notfound'    => [404, 'application/json', '{"errors":[{"status":"404"}]}'],
  '/servererror' => [500, 'text/plain', 'boom'],
  '/notjson'     => [200, 'text/plain', 'plain text']
}.freeze

seen = []
server = TCPServer.new('127.0.0.1', 0)
port = server.addr[1]
host = "127.0.0.1:#{port}" # informational

Thread.new do
  loop do
    conn = server.accept rescue break
    Thread.new(conn) do |c|
      begin
        line = c.gets or next
        req_path = line.split(' ')[1].to_s
        loop { h = c.gets; break if h.nil? || h.strip.empty? } # drain headers
        seen << req_path
        sleep 5 if req_path.start_with?('/slow') # outlives any sane deadline
        status, type, body = ROUTES[req_path.split('?').first] || [404, 'text/plain', 'no route']
        c.print "HTTP/1.1 #{status} X\r\nContent-Type: #{type}\r\n" \
                "Content-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}"
      rescue StandardError
        # a client that hangs up mid-request is expected in the timeout test
      ensure
        c.close rescue nil
      end
    end
  end
end

# asc.rb pins itself to Apple's host over TLS, which is the point of one of
# these tests. For the transport tests, copy it with the host repointed at the
# local server and TLS off. HOST stays a bare hostname (uri.host never carries
# the port), so the pinning check under test still compares like for like.
src = File.read(ASC)
point_at = lambda do |name, at_port|
  path = File.join(work, name)
  File.write(path, src
    .sub("HOST = 'api.appstoreconnect.apple.com'", "HOST = '127.0.0.1'")
    .sub('URI("https://#{HOST}#{path}")', %(URI("http://\#{HOST}:#{at_port}\#{path}")))
    .sub("uri.scheme == 'https'", "uri.scheme == 'http'")
    .sub('uri.port == 443', "uri.port == #{at_port}")
    .sub('use_ssl: true', 'use_ssl: false'))
  path
end
local = point_at.call('asc_local.rb', port)

# stdout and stderr are captured SEPARATELY: the contract under test says the
# response goes to stdout and diagnostics to stderr, which a merged stream
# cannot check.
def run(script, *args, env: {})
  rd, wr = IO.pipe
  out = IO.popen(env, ['ruby', script, *args], err: wr, &:read)
  wr.close
  err = rd.read
  rd.close
  [$?.exitstatus, out, err]
end

# ── the exit contract ────────────────────────────────────────────────────────

puts 'asc.rb — exit contract'

check('2xx exits 0 and prints the status') do
  code, out = run(local, 'GET', '/ok')
  code.zero? && out.include?('HTTP 200')
end

check('2xx pretty-prints the JSON body') do
  _, out = run(local, 'GET', '/ok')
  out.include?('"data"') && out.include?("\n")
end

check('404 exits 1 but still prints the body') do
  code, out = run(local, 'GET', '/notfound')
  code == 1 && out.include?('HTTP 404') && out.include?('"errors"')
end

check('500 exits 1') { run(local, 'GET', '/servererror').first == 1 }

check('a non-JSON body is printed verbatim, not swallowed') do
  _, out = run(local, 'GET', '/notjson')
  out.include?('plain text')
end

check('connection refused exits 2, reporting on stderr') do
  code, out, err = run(point_at.call('asc_dead.rb', 1), 'GET', '/ok')
  code == 2 && err.include?('request failed') && out.empty?
end

check('a total deadline is enforced, not just a per-read timeout') do
  started = Time.now
  code, _out, err = run(local, 'GET', '/slow', env: { 'ASC_DEADLINE' => '1' })
  code == 2 && err.include?('request failed') && (Time.now - started) < 4
end

# 0 and negatives mean "no limit" to Timeout.timeout, which would silently
# remove the ceiling; a non-number would raise an unhandled ArgumentError.
check('an invalid ASC_DEADLINE is rejected instead of removing the limit') do
  ['0', '-5', 'soon', ''].all? do |bad|
    code, _out, err = run(local, 'GET', '/ok', env: { 'ASC_DEADLINE' => bad })
    code == 1 && err.include?('ASC_DEADLINE must be a positive number')
  end
end

check('a valid ASC_DEADLINE is still honoured') do
  run(local, 'GET', '/ok', env: { 'ASC_DEADLINE' => '30' }).first.zero?
end

# ── usage and safety ─────────────────────────────────────────────────────────

puts
puts 'asc.rb — usage and safety'

check('an unsupported method is rejected by name') do
  code, _out, err = run(local, 'FROB', '/ok')
  code == 1 && err.include?('unsupported method FROB')
end

check('lowercase methods are accepted') { run(local, 'get', '/ok').first.zero? }

check('a malformed path aborts cleanly, with no backtrace') do
  code, _out, err = run(local, 'GET', '//bad host')
  code == 1 && err.include?('bad path') && !err.include?('URI::InvalidURIError:')
end

check('missing arguments print usage') do
  code, _out, err = run(local)
  code == 1 && err.include?('usage: ruby asc.rb')
end

# The important one. The path is interpolated into the URL, so "@host/..."
# reparents the request onto another host — and the Authorization header is a
# live signed ASC token.
check('a path starting with @ cannot redirect the token to another host') do
  code, _out, err = run(ASC, 'GET', '@127.0.0.1:%d/v1/apps' % port)
  code == 1 && err.include?("must start with '/'") && seen.none? { |p| p.include?('/v1/apps') }
end

# ":444/v1/apps" keeps Apple's hostname but moves the request to a different
# listener, so a host-only check would wave it through.
check('a path that changes the port cannot redirect the token') do
  code, _out, err = run(ASC, 'GET', ":#{port}/v1/apps")
  code == 1 && err.include?("must start with '/'") && seen.none? { |p| p.include?('/v1/apps') }
end

check('no request reached the impostor host or port') { seen.none? { |p| p.include?('/v1/apps') } }

check('a missing private key aborts before any request') do
  code, _out, err = run(local, 'GET', '/ok', env: { 'ASC_P8' => File.join(work, 'nope.p8') })
  code == 1 && err.include?('private key not found')
end

check('the key material is never printed') do
  _, out = run(local, 'GET', '/ok')
  !out.include?('PRIVATE KEY') && !out.include?(File.read(key_path).lines[1].to_s.strip)
end

server.close

puts
if FAIL.empty?
  puts "all #{PASS.size} test(s) passed"
else
  puts "#{FAIL.size} of #{PASS.size + FAIL.size} test(s) FAILED"
  exit 1
end
