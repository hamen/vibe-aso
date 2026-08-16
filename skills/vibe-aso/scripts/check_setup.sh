#!/usr/bin/env bash
# Vibe ASO setup check. Prints one PASS/WARN/FAIL line per prerequisite and a
# fix command for anything missing. Never prints key material.
set -uo pipefail

CFG_DIR="$HOME/.vibe-aso"
CFG="$CFG_DIR/config.json"
FAILS=0

pass() { echo "  PASS  $1"; }
warn() { echo "  WARN  $1"; }
fail() { echo "  FAIL  $1"; FAILS=$((FAILS+1)); }

perms_of() { # $1 = path -> octal mode. BSD/macOS stat first, then GNU.
  # NOTE: `stat -f` on GNU coreutils means "filesystem status": it prints a
  # block of text to stdout and THEN fails, so the two forms cannot be chained
  # with `||` — the garbage lands in the caller's variable and every
  # permission check reports a false WARN. Capture, then decide.
  local out
  if out=$(stat -f "%Lp" "$1" 2>/dev/null) && [ -n "$out" ]; then
    echo "$out"; return
  fi
  stat -c "%a" "$1" 2>/dev/null
}

json() { # $1 = jq-ish dotted path, best-effort with python3
  python3 -c "
import json,sys
try:
    cfg = json.load(open('$CFG'))
    v = cfg
    for k in '$1'.split('.'):
        v = v.get(k, None) if isinstance(v, dict) else None
    print(v if v is not None else '')
except Exception:
    print('')
" 2>/dev/null
}

echo "vibe-aso setup check"
echo

# ── config file ──────────────────────────────────────────────────────────────
if [ -f "$CFG" ]; then
  pass "config exists ($CFG)"
  perms=$(perms_of "$CFG")
  [ "$perms" = "600" ] && pass "config permissions 600" || warn "config permissions are $perms — run: chmod 600 $CFG"
else
  fail "no config at $CFG — run the setup wizard (Phase 0 in SKILL.md)"
fi

# ── App Store Connect key ────────────────────────────────────────────────────
KEY_ID="${ASC_KEY_ID:-$(json asc.key_id)}"
ISSUER_ID="${ASC_ISSUER_ID:-$(json asc.issuer_id)}"
P8="${ASC_P8:-$(json asc.p8_path)}"
P8="${P8:-$CFG_DIR/AuthKey.p8}"
P8="${P8/#\~/$HOME}"

[ -n "$KEY_ID" ]    && pass "ASC key id set"    || fail "ASC key id missing (asc.key_id in config)"
[ -n "$ISSUER_ID" ] && pass "ASC issuer id set" || fail "ASC issuer id missing (asc.issuer_id in config)"
if [ -f "$P8" ]; then
  pass "ASC private key present"
  perms=$(perms_of "$P8")
  [ "$perms" = "600" ] && pass "private key permissions 600" || warn "private key permissions are $perms — run: chmod 600 $P8"
else
  fail "ASC private key not found at $P8"
fi

# live round-trip (only if everything present)
if [ -n "$KEY_ID" ] && [ -n "$ISSUER_ID" ] && [ -f "$P8" ] && command -v ruby >/dev/null; then
  code=$(ruby "$(dirname "$0")/asc.rb" GET '/v1/apps?limit=1' 2>/dev/null | head -1)
  case "$code" in
    "HTTP 200") pass "ASC API round-trip (HTTP 200)" ;;
    "HTTP 401") fail "ASC API auth rejected (HTTP 401) — key id / issuer id / p8 don't match" ;;
    *)          warn "ASC API round-trip inconclusive ($code)" ;;
  esac
fi

# ── translation engine ───────────────────────────────────────────────────────
ENGINE="$(json translation.engine)"
case "$ENGINE" in
  subagents)
    pass "translation engine: Claude subagents (no external API needed)" ;;
  deepseek|openai)
    KEY_PATH="$(json translation.api_key_path)"; KEY_PATH="${KEY_PATH/#\~/$HOME}"
    if [ -n "$KEY_PATH" ] && [ -s "$KEY_PATH" ]; then
      pass "translation engine: $ENGINE (key file present)"
      if [ "$ENGINE" = "deepseek" ]; then
        # a valid key on an empty account fails every call with HTTP 402 —
        # check the balance BEFORE a long run, not during one
        # the key goes in on stdin, never on an argv — a header passed as
        # `-H "Authorization: Bearer $(cat …)"` is readable by any local user
        # via `ps`. The key is never an argument to anything here, not even
        # to printf, so this holds whether or not printf is a shell builtin.
        bal=$({ printf 'Authorization: Bearer '; tr -d '\n' < "$KEY_PATH"; printf '\n'; } |
          curl -s -m 10 -H @- https://api.deepseek.com/user/balance 2>/dev/null)
        if echo "$bal" | grep -q '"is_available":true'; then
          pass "DeepSeek balance available"
        elif [ -n "$bal" ]; then
          fail "DeepSeek account has no available balance — top up before running a cascade"
        else
          warn "could not reach DeepSeek balance endpoint (offline?)"
        fi
      fi
    else
      fail "translation engine is $ENGINE but no key at ${KEY_PATH:-<unset>} (translation.api_key_path)"
    fi ;;
  "")
    fail "no translation engine chosen (translation.engine) — run the setup wizard" ;;
  *)
    warn "unknown translation engine '$ENGINE'" ;;
esac

# ── toolchain ────────────────────────────────────────────────────────────────
command -v ruby >/dev/null && pass "ruby present" || fail "ruby missing (needed for the ASC API client)"
command -v python3 >/dev/null && pass "python3 present" || fail "python3 missing"

if command -v fastlane >/dev/null; then
  # `fastlane --version` prints an install path, an update nag and gem
  # versions around the real answer. Grabbing the last version-shaped string
  # in that blob reports a bystander (a ruby path, the update nag, a gem) --
  # on a real 2.237.0 install it read "0.9.42" and told the user to upgrade.
  # Only the line that is exactly "fastlane <x.y.z>" is the version.
  v=$(fastlane --version 2>/dev/null | grep -oE '^fastlane [0-9]+\.[0-9]+\.[0-9]+' | head -1 | awk '{print $2}')
  major=$(echo "$v" | cut -d. -f1)
  minor=$(echo "$v" | cut -d. -f2)
  if [ -z "$v" ]; then
    warn "fastlane present but its version could not be parsed — confirm it is ≥ 2.234.0 by hand"
  elif [ "${major:-0}" -gt 2 ] || { [ "${major:-0}" -eq 2 ] && [ "${minor:-0}" -ge 234 ]; }; then
    pass "fastlane $v (locale list is current)"
  else
    warn "fastlane $v is older than 2.234.0 — its App Store locale list is missing newer locales; brew upgrade fastlane"
  fi
else
  warn "fastlane not installed — needed for metadata/screenshot upload (brew install fastlane)"
fi

# ── screenshot renderer ──────────────────────────────────────────────────────
RENDERER="$(cd "$(dirname "$0")/../renderer" 2>/dev/null && pwd)"
if [ -n "$RENDERER" ]; then
  command -v node >/dev/null && pass "node present" || warn "node missing — needed only for screenshot rendering"
  [ -d "$RENDERER/node_modules/playwright" ] && pass "renderer deps installed" || warn "renderer deps missing — run: cd $RENDERER && npm install && npx playwright install chromium"
  # Count AND validate. An interrupted download from before fetch_fonts.sh
  # grew its .part handling can leave 18 files with one truncated font: the
  # count passes, and the renderer fails on it later with no hint why.
  n_fonts=$(ls "$RENDERER/fonts/"*.ttf 2>/dev/null | wc -l | tr -d ' ')
  if [ "$n_fonts" -lt 18 ]; then
    warn "renderer fonts not fetched — run: $RENDERER/fetch_fonts.sh"
  else
    # reuse the renderer's own definition rather than restating it here
    eval "$(sed -n '/^be()/,/^}/p;/^is_font()/,/^}/p' "$RENDERER/fetch_fonts.sh")"
    damaged=""
    for f in "$RENDERER/fonts/"*.ttf; do
      is_font "$f" || damaged="$damaged $(basename "$f")"
    done
    if [ -n "$damaged" ]; then
      fail "damaged font file(s):$damaged — delete them and re-run: $RENDERER/fetch_fonts.sh"
    else
      pass "renderer fonts fetched and valid ($n_fonts files)"
    fi
  fi
fi

echo
if [ "$FAILS" -eq 0 ]; then
  echo "setup OK"
else
  echo "$FAILS check(s) failed — fix the FAIL lines above before running the pipeline"
  exit 1
fi
