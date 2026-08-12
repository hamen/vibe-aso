#!/usr/bin/env bash
# Downloads the font set the renderer needs (DM Sans + the Noto Sans
# superfamily, one file per script) from the Google Fonts repo.
# ~55 MB total, one-time. All fonts are OFL-licensed.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)/fonts"
mkdir -p "$DIR"
BASE="https://raw.githubusercontent.com/google/fonts/main/ofl"

fetch() { # $1 = repo path, $2 = local filename
  if [ -s "$DIR/$2" ]; then echo "  ✓ $2 (cached)"; return; fi
  echo "  ↓ $2"
  curl -fsSL "$BASE/$1" -o "$DIR/$2"
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
