# Phase 3 — Localized screenshot headings

Burns translated marketing headings over the user's background screenshots
(heading on top, device mockup below) for every chosen locale, then uploads
per-locale sets. Only the **heading** is localized; the app UI inside the
mockup stays in English — the accepted low-effort tradeoff that captures most
of the conversion value.

## Input contract — what the user provides

**If the user has no screenshot designs — or doesn't know what to provide —
point them at the free Figma template first:**
https://www.figma.com/design/ftvaN3ZMfgkGrn7SAuqCvt/vibe-ASO-mockups
It has iPhone, iPad, and Apple Watch frames with "Your screenshot here"
placeholders. The flow: duplicate the file (a free Figma account is enough) →
paste real app screenshots over the placeholders → choose background colors →
leave the top band empty (the renderer burns the localized heading there) →
export each frame as PNG named `iphone_1..N.png` / `ipad_1..N.png` into the
project folder. Then continue below as if they'd designed the mockups
themselves.

Ask for three things and **confirm all three before translating anything**:

1. **Background PNGs** dropped into a project folder: `iphone_1..N.png` and —
   if the app supports iPad — `ipad_1..N.png`, exported with the heading
   layer hidden/removed. **If the app runs on iPad, iPad screenshots are
   required for submission** — don't discover that at upload time.
   Sizes the renderer expects: iPhone 1284×2778, iPad 2064×2752 (adjust
   `renderer/config.json` if the user exports other portrait sizes).
2. **The English headings, in order** — one per screenshot. Confirm the order
   matches the PNG numbering; a great heading on the wrong screenshot is a
   bug no detector catches. If the user has no headings yet, draft them:
   short benefit statements led by the phase-1 vocabulary (`Track every
   calorie`, `See your macros at a glance`) — verb + noun, at most one
   ALL-CAPS emphasis word.
3. **Two font colors** as odd/even: screenshots 1,3,5… use the odd color,
   2,4,6… the even (for alternating light/dark frame designs; make them the
   same if the design doesn't alternate).

Store as `headings.json` (`{ "<locale>": ["heading 1", ...] }`, en-US first)
and `app.json` (`{ "name": "...", "colors": { "odd": "#FFF", "even":
"#1A1A1A" } }`) next to the PNGs. Screenshot count is auto-detected per
device; iPhone and iPad may differ.

## Translating the headings

- **Anchor to phase 2's vocabulary.** The heading must use the same localized
  terms the listing ranks for — pull each locale's name/subtitle/keywords
  from the phase-2 files (or the live listing) and reuse that exact
  vocabulary. A screenshot that says "Kalorien" while the subtitle ranks for
  "Kalorienzähler" wastes the reinforcement.
- Headings are **marketing keywords, not UI strings** — translate by meaning
  and search value, never word-for-word.
- **Apple product names stay verbatim** — iPhone, Apple Watch, iPad. Even if
  the English heading says generic "phone & watch", the localized copy uses
  the Apple brand names; that's what users search and what Apple's own
  listings do.
- **ALL-CAPS emphasis** mirrors only into scripts that have case (Latin,
  Cyrillic, Greek); drop it for CJK, Indic, Arabic, Hebrew, Thai.
- Keep headings **short**. Agglutinative languages (Tamil, Malayalam,
  Finnish…) produce long words that force the auto-fit to shrink — prefer a
  tighter phrasing over a tiny font.
- Generate ALL locales in one pass into `headings.json`; review via the
  renderer's fit log + spot-checks of CJK / RTL / Indic. No per-language
  human gate unless the user asks.

## Rendering

One-time setup (check_setup.sh verifies): in `renderer/` run
`npm install && npx playwright install chromium && ./fetch_fonts.sh`.

```bash
cd renderer
node render.js <project-dir>                # all locales, all devices
node render.js <project-dir> iphone         # one device
node render.js <project-dir> iphone de-DE   # one device+locale — fast iteration
```

Output: `<project-dir>/out/<locale>/<device>_N.png`. The fit log prints the
final font size and line count per image and flags anything that shrank —
**read it**; a heavily shrunk heading means the copy is too long for that
locale and should be tightened, not shipped tiny.

Renderer facts worth knowing (all in `renderer/config.json` — that file is
the source of truth for sizes; don't hardcode numbers elsewhere):

- Device classes are defined in `config.json`. Shipping defaults: `iphone`
  and `ipad`. To render another class (e.g. Apple Watch), add a config block
  with its pixel size and band layout, name the backgrounds
  `<device>_1..N.png`, and it renders like the others.

- Auto-fit: 2 lines by default, stretching to 3 only when it buys a
  meaningfully larger font; long unbreakable words shrink instead of
  clipping.
- RTL locales (Arabic, Hebrew, Urdu) render `dir=rtl` automatically; Latin
  acronyms inside RTL are handled by bidi.
- Fonts: DM Sans for Latin + the **Noto Sans superfamily** per script. No
  single font file can cover all scripts (the OpenType glyph limit makes it
  impossible) — don't swap in a "nicer" Latin-only font; it silently breaks
  every non-Latin locale.
- An explicit `\n` in a heading forces a line break.

## Upload to App Store Connect

Screenshots attach to an **editable version** — if the app is live with no
draft, create the next version first. Then push per-locale with `deliver`:

```bash
fastlane deliver --skip-binary-upload --skip-metadata \
  --screenshots-path <project-dir>/out --overwrite-screenshots --force
```

Device class is auto-detected from image resolution. Hazards, in the order
they bite:

1. **Validate with one locale first.** Copy one locale's folder to a temp dir
   and upload that before the full ~hundreds-of-images run — cheap proof the
   version, sizes, and auth are right.
2. **`--overwrite-screenshots` deletes EVERY existing screenshot set on the
   version — including device classes you're not uploading** (e.g. an Apple
   Watch set). If the app has a Watch app, its screenshot set is *required*,
   and wiping it makes the version unsubmittable with an unhelpful "not in
   valid state" error **that only surfaces at submit time**. After upload,
   compare the edit version's device sets against the live version's; if a
   set is missing, download the live one and re-append it *without* the
   overwrite flag.
3. **Long uploads get interrupted and leave locales short.** ASC's
   post-upload polling is flaky (retries HTTP 500s), and an interrupted run
   leaves some locales missing screenshots silently. After the full run,
   **count screenshots per locale via the API** and re-upload just the short
   locales (overwrite is idempotent per-locale).
4. **If you created the version via the API for this upload**, the localized
   metadata did not carry forward — re-read `metadata.md`'s warning and
   re-push + verify every locale's text before submitting. This is the
   single most damaging mistake in the whole pipeline: it ships an
   all-English listing over a localized one, and nothing warns you.

Screenshots carry forward across future versions automatically — this upload
is once-per-redesign, not once-per-release.
