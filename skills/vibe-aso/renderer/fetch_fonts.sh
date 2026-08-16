#!/usr/bin/env bash
# Downloads the font set the renderer needs (DM Sans + the Noto Sans
# superfamily, one file per script) from the Google Fonts repo.
# ~55 MB total, one-time. All fonts are OFL-licensed.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)/fonts"
mkdir -p "$DIR"
BASE="https://raw.githubusercontent.com/google/fonts/main/ofl"

is_font() { # $1 = path — true if the file starts with a known sfnt magic
  [ -s "$1" ] || return 1
  case "$(head -c4 "$1" | od -An -tx1 | tr -d ' \n')" in
    00010000|4f54544f|74727565|74746366) return 0 ;;
    *) return 1 ;;
  esac
}

fetch() { # $1 = repo path, $2 = local filename
  # An interrupted download leaves a short file that is still non-empty, so
  # "cached" has to mean "starts with a font header", not "exists" — otherwise
  # a truncated TTF is cached forever and the renderer fails on it later.
  if is_font "$DIR/$2"; then echo "  ✓ $2 (cached)"; return; fi
  echo "  ↓ $2"
  # write to a temp name and rename only after the check, so an interrupted
  # run never leaves a half file in place of a good one
  curl -fsSL --retry 3 --retry-delay 2 "$BASE/$1" -o "$DIR/$2.part"
  if ! is_font "$DIR/$2.part"; then
    rm -f "$DIR/$2.part"
    echo "  ✗ $2 — download did not produce a font file" >&2
    exit 1
  fi
  mv -f "$DIR/$2.part" "$DIR/$2"
}

fetch "dmsans/DMSans%5Bopsz,wght%5D.ttf"                          "DMSans.ttf"
fetch "notosans/NotoSans%5Bwdth,wght%5D.ttf"                      "NotoSans.ttf"
fetch "notosanshebrew/NotoSansHebrew%5Bwdth,wght%5D.ttf"          "NotoSansHebrew.ttf"
fetch "notosansarabic/NotoSansArabic%5Bwdth,wght%5D.ttf"          "NotoSansArabic.ttf"
fetch "notosansdevanagari/NotoSansDevanagari%5Bwdth,wght%5D.ttf"  "NotoSansDevanagari.ttf"
fetch "notosansbengali/NotoSansBengali%5Bwdth,wght%5D.ttf"        "NotoSansBengali.ttf"
fetch "notosansgujarati/NotoSansGujarati%5Bwdth,wght%5D.ttf"      "NotoSansGujarati.ttf"
fetch "notosansgurmukhi/NotoSansGurmukhi%5Bwdth,wght%5D.ttf"      "NotoSansGurmukhi.ttf"
fetch "notosanskannada/NotoSansKannada%5Bwdth,wght%5D.ttf"        "NotoSansKannada.ttf"
fetch "notosansmalayalam/NotoSansMalayalam%5Bwdth,wght%5D.ttf"    "NotoSansMalayalam.ttf"
fetch "notosansoriya/NotoSansOriya%5Bwdth,wght%5D.ttf"            "NotoSansOriya.ttf"
fetch "notosanstamil/NotoSansTamil%5Bwdth,wght%5D.ttf"            "NotoSansTamil.ttf"
fetch "notosanstelugu/NotoSansTelugu%5Bwdth,wght%5D.ttf"          "NotoSansTelugu.ttf"
fetch "notosansthai/NotoSansThai%5Bwdth,wght%5D.ttf"              "NotoSansThai.ttf"
fetch "notosansjp/NotoSansJP%5Bwght%5D.ttf"                       "NotoSansJP.ttf"
fetch "notosanskr/NotoSansKR%5Bwght%5D.ttf"                       "NotoSansKR.ttf"
fetch "notosanssc/NotoSansSC%5Bwght%5D.ttf"                       "NotoSansSC.ttf"
fetch "notosanstc/NotoSansTC%5Bwght%5D.ttf"                       "NotoSansTC.ttf"

echo "fonts ready → $DIR"
