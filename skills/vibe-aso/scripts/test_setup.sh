#!/usr/bin/env bash
# Tests for check_setup.sh and fetch_fonts.sh.
# Run: skills/vibe-aso/scripts/test_setup.sh
#
# No framework and no network: fastlane, curl and stat are stubbed on PATH,
# and the font fixtures are built byte by byte. Everything runs against a
# throwaway HOME so a real ~/.vibe-aso is never read or written.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="$HERE/check_setup.sh"
FETCH="$HERE/../renderer/fetch_fonts.sh"
PASS=0; FAIL=0
WORK="$(mktemp -d)"
trap 'chmod -R u+rwX "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

ok()   { PASS=$((PASS+1)); echo "  ok    $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; [ -n "${2:-}" ] && echo "          $2"; }
like() { case "$1" in *"$2"*) ok "$3" ;; *) bad "$3" "expected to contain: $2" ;; esac; }
unlike() { case "$1" in *"$2"*) bad "$3" "expected NOT to contain: $2" ;; *) ok "$3" ;; esac; }

# ── fixtures ─────────────────────────────────────────────────────────────────

# A minimal but COMPLETE sfnt font: header + one table directory entry + table.
make_font() { # $1 = out path
  python3 - "$1" <<'PY'
import struct, sys
body = b"DATA" * 8                       # 32 bytes of table payload
off  = 12 + 16                           # header + one directory entry
head = struct.pack(">IHHHH", 0x00010000, 1, 16, 0, 0)
ent  = b"glyf" + struct.pack(">III", 0, off, len(body))
open(sys.argv[1], "wb").write(head + ent + body)
PY
}

# Real paths, resolved BEFORE anything is stubbed: a stub that delegates with
# `command od` would find itself again on PATH and fork-bomb.
REAL_OD="$(command -v od)"
REAL_STAT="$(command -v stat)"

stub() { # $1 = name, $2… = body — put a fake executable first on PATH
  local name="$1"; shift
  mkdir -p "$WORK/bin"
  { echo '#!/usr/bin/env bash'; printf '%s\n' "$@"; } > "$WORK/bin/$name"
  chmod +x "$WORK/bin/$name"
}

new_home() { # prints a fresh HOME with a valid config
  local h="$WORK/home.$RANDOM"
  mkdir -p "$h/.vibe-aso"
  cat > "$h/.vibe-aso/config.json" <<'EOF'
{"asc":{"key_id":"ABCDEFGHIJ","issuer_id":"0-0-0-0","p8_path":"~/.vibe-aso/AuthKey.p8"},
 "translation":{"engine":"subagents"}}
EOF
  chmod 700 "$h/.vibe-aso"; chmod 600 "$h/.vibe-aso/config.json"
  echo "$h"
}

run_check() { HOME="$1" PATH="$WORK/bin:$PATH" bash "$CHECK" 2>&1; }

echo "fetch_fonts.sh — is_font"

# is_font lives in fetch_fonts.sh; source it without running the downloads.
eval "$(sed -n '/^be()/,/^}/p;/^is_font()/,/^}/p' "$FETCH")"

make_font "$WORK/good.ttf"
is_font "$WORK/good.ttf" && ok "accepts a complete font" || bad "accepts a complete font"

# The case the guard exists for: curl writes sequentially, so an interrupted
# download keeps a valid 4-byte magic and only loses the tail.
head -c 20 "$WORK/good.ttf" > "$WORK/truncated.ttf"
is_font "$WORK/truncated.ttf" && bad "rejects a truncated font (valid magic, missing tail)" \
  || ok "rejects a truncated font (valid magic, missing tail)"

printf 'GARBAGE-not-a-font' > "$WORK/garbage.ttf"
is_font "$WORK/garbage.ttf" && bad "rejects a non-font" || ok "rejects a non-font"

: > "$WORK/empty.ttf"
is_font "$WORK/empty.ttf" && bad "rejects an empty file" || ok "rejects an empty file"

is_font "$WORK/does-not-exist.ttf" && bad "rejects a missing file" || ok "rejects a missing file"

# od implementations differ in how they pad columns; the magic parse must not
# depend on that. Feed a font through a stub od that pads with tabs.
stub od "$REAL_OD \"\$@\" | sed 's/ /\\t/g'"
PATH="$WORK/bin:$PATH" bash -c "
  eval \"\$(sed -n '/^be()/,/^}/p;/^is_font()/,/^}/p' '$FETCH')\"
  is_font '$WORK/good.ttf'" \
  && ok "tolerates tab-padded od output" || bad "tolerates tab-padded od output"
rm -f "$WORK/bin/od"

echo
echo "fetch_fonts.sh — download"

# A fetch() that never replaces a good file with a bad download.
FONTDIR="$WORK/fonts"; mkdir -p "$FONTDIR"
make_font "$FONTDIR/Keep.ttf"
before=$(wc -c < "$FONTDIR/Keep.ttf")

# Run fetch() the way fetch_fonts.sh really runs it: `set -e` at top level and
# the call NOT inside a `||` list. Putting the call in a condition would switch
# `set -e` off for everything inside the function and hide exactly the bug
# this checks for.
try_fetch() { # $1 = remote path, $2 = local name — prints nothing, returns status
  bash -c '
    set -euo pipefail
    eval "$(sed -n "/^be()/,/^}/p;/^is_font()/,/^}/p;/^fetch()/,/^}/p" "$1")"
    DIR="$2"; BASE="http://example.invalid"
    fetch "$3" "$4"
  ' _ "$FETCH" "$FONTDIR" "$1" "$2" >/dev/null 2>&1
}

# 1. curl fails outright (404 / -f), writing nothing.
stub curl 'exit 22'
PATH="$WORK/bin:$PATH" try_fetch "nope/Missing.ttf" "Missing.ttf"
[ ! -e "$FONTDIR/Missing.ttf.part" ] && ok "a failed download leaves no .part behind" \
  || bad "a failed download leaves no .part behind"

# 2. The case the previous test could not see: curl writes PART of the body and
# then exits non-zero, which is what a dropped connection actually looks like.
stub curl 'while [ $# -gt 0 ]; do [ "$1" = "-o" ] && { printf "\x00\x01\x00\x00partial" > "$2"; }; shift; done; exit 18'
PATH="$WORK/bin:$PATH" try_fetch "nope/Partial.ttf" "Partial.ttf"
[ ! -e "$FONTDIR/Partial.ttf.part" ] && ok "a partial download leaves no .part behind" \
  || bad "a partial download leaves no .part behind"
[ ! -e "$FONTDIR/Partial.ttf" ] && ok "a partial download is never promoted to a real font" \
  || bad "a partial download is never promoted to a real font"

# 3. curl "succeeds" but the payload is not a font (a captive-portal HTML page).
stub curl 'while [ $# -gt 0 ]; do [ "$1" = "-o" ] && { printf "<html>login</html>" > "$2"; }; shift; done; exit 0'
PATH="$WORK/bin:$PATH" try_fetch "nope/Html.ttf" "Html.ttf"
[ ! -e "$FONTDIR/Html.ttf" ] && ok "a non-font payload is rejected, not cached" \
  || bad "a non-font payload is rejected, not cached"

[ "$(wc -c < "$FONTDIR/Keep.ttf")" = "$before" ] && ok "a failed download does not touch existing fonts" \
  || bad "a failed download does not touch existing fonts"
rm -f "$WORK/bin/curl"

# A four-byte "ttcf" file must not pass as a complete font collection.
printf 'ttcf' > "$WORK/stub.ttc"
is_font "$WORK/stub.ttc" && bad "rejects a bare ttcf header" || ok "rejects a bare ttcf header"

echo
echo "check_setup.sh — fastlane version parse"

# Real `fastlane --version` output: an install path, the version, an update
# nag, and gem versions. Taking the last version-shaped string picks a
# bystander — this is what reported 0.9.42 for a 2.237.0 install.
stub fastlane 'cat <<EOF
fastlane installation at path:
/home/u/.gem/ruby/3.4.0/gems/fastlane-2.237.0/bin/fastlane
-----------------------------
fastlane 2.237.0

# fastlane 2.238.0 is available. You are on 2.237.0.
# bundler 1.28.1, rake 0.9.42
EOF'
out=$(run_check "$(new_home)")
like "$out" "PASS  fastlane 2.237.0" "picks the real version out of noisy output"
unlike "$out" "0.9.42" "does not pick a bystander version"

stub fastlane 'echo "fastlane 2.100.0"'
out=$(run_check "$(new_home)")
like "$out" "older than 2.234.0" "still warns on a genuinely old fastlane"

stub fastlane 'echo "no version here at all"'
out=$(run_check "$(new_home)")
like "$out" "could not be parsed" "says so when the version cannot be parsed"
unlike "$out" "PASS  fastlane" "does not pass an unparseable version"
rm -f "$WORK/bin/fastlane"

echo
echo "check_setup.sh — permission probe"

H=$(new_home)
out=$(run_check "$H")
like "$out" "PASS  config permissions 600" "reports 600 correctly"

# GNU `stat -f` means "filesystem status": it prints a block of text to stdout
# and THEN fails, so a `stat -f || stat -c` chain captures the garbage.
stub stat "if [ \"\$1\" = \"-f\" ]; then echo '  File: \"x\"'; echo '  ID: deadbeef Namelen: 255'; exit 1; fi
$REAL_STAT \"\$@\""
out=$(run_check "$H")
like "$out" "PASS  config permissions 600" "GNU-style stat -f noise does not break the probe"
unlike "$out" "Namelen" "filesystem dump never reaches the message"

# BSD/macOS: stat -f works and stat -c does not exist.
stub stat 'if [ "$1" = "-f" ]; then echo 600; exit 0; fi; exit 1'
out=$(run_check "$H")
like "$out" "PASS  config permissions 600" "BSD-style stat -f is used when it works"
rm -f "$WORK/bin/stat"

H2=$(new_home); chmod 644 "$H2/.vibe-aso/config.json"
out=$(run_check "$H2")
like "$out" "config permissions are 644" "reports a genuinely wrong mode"

echo
echo "check_setup.sh — DeepSeek key handling"

H3=$(new_home)
printf 'sk-secret-key-value\n' > "$H3/.vibe-aso/deepseek-key"; chmod 600 "$H3/.vibe-aso/deepseek-key"
cat > "$H3/.vibe-aso/config.json" <<EOF
{"asc":{"key_id":"A","issuer_id":"B","p8_path":"~/.vibe-aso/AuthKey.p8"},
 "translation":{"engine":"deepseek","api_key_path":"~/.vibe-aso/deepseek-key"}}
EOF
chmod 600 "$H3/.vibe-aso/config.json"
# A curl stub that records its own argv and echoes back what it read on stdin.
stub curl 'printf "%s\n" "$@" > "$0.argv"; cat > "$0.stdin"; echo "{\"is_available\":true}"'
out=$(run_check "$H3")
like "$out" "DeepSeek balance available" "reads the balance through the stubbed curl"
unlike "$(cat "$WORK/bin/curl.argv")" "sk-secret-key-value" "key never appears in curl's argv"
like "$(cat "$WORK/bin/curl.stdin")" "sk-secret-key-value" "key is delivered on stdin instead"
rm -f "$WORK/bin/curl"

echo
echo "check_setup.sh — font validation"

# 18 files present but one truncated: the count alone reports PASS and the
# renderer then fails later with no explanation.
H4=$(new_home)
FDIR="$WORK/renderer_fonts"; mkdir -p "$FDIR"
i=0; while [ "$i" -lt 18 ]; do make_font "$FDIR/Font$i.ttf"; i=$((i+1)); done
# check_setup.sh looks next to itself, so run a copy in a matching layout
LAYOUT="$WORK/layout"; mkdir -p "$LAYOUT/scripts" "$LAYOUT/renderer"
cp "$CHECK" "$LAYOUT/scripts/"; cp "$FETCH" "$LAYOUT/renderer/"
cp -r "$FDIR" "$LAYOUT/renderer/fonts"

out=$(HOME="$H4" PATH="$WORK/bin:$PATH" bash "$LAYOUT/scripts/check_setup.sh" 2>&1)
like "$out" "renderer fonts fetched and valid (18 files)" "18 good fonts pass"

head -c 20 "$LAYOUT/renderer/fonts/Font7.ttf" > "$LAYOUT/renderer/fonts/Font7.tmp"
mv "$LAYOUT/renderer/fonts/Font7.tmp" "$LAYOUT/renderer/fonts/Font7.ttf"
out=$(HOME="$H4" PATH="$WORK/bin:$PATH" bash "$LAYOUT/scripts/check_setup.sh" 2>&1)
like "$out" "damaged font file(s): Font7.ttf" "a truncated font among 18 is reported by name"
unlike "$out" "fonts fetched and valid" "a damaged font does not pass the check"

echo
if [ "$FAIL" -eq 0 ]; then
  echo "all $PASS test(s) passed"
else
  echo "$FAIL of $((PASS+FAIL)) test(s) FAILED"
  exit 1
fi
