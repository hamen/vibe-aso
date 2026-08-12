# Phase 2 — App Store metadata, en-US first, then every chosen locale

Writes the five text fields — `name`, `subtitle`, `keywords`,
`promotional_text`, `description` — for en-US, then adapts them into every
locale the user chose. Files land in the standard fastlane layout
(`fastlane/metadata/<locale>/<field>.txt`) so `deliver` can push them.

## The locale set (50, verified against Apple's API)

```
ar-SA, bn-BD, ca, cs, da, de-DE, el,
en-AU, en-CA, en-GB, en-US, es-ES, es-MX,
fi, fr-CA, fr-FR, gu-IN, he, hi, hr, hu,
id, it, ja, kn-IN, ko, ml-IN, mr-IN, ms,
nl-NL, no, or-IN, pa-IN, pl, pt-BR, pt-PT,
ro, ru, sk, sl-SI, sv, ta-IN, te-IN, th,
tr, uk, ur-PK, vi, zh-Hans, zh-Hant
```

en-US is the source; the other 49 are targets. **Ask the user once** whether
they want all 49 or a subset (top markets), and reuse that answer for
screenshots and in-app strings.

**Locales Apple REJECTS despite looking plausible** — never generate these:
`fil`, `az`, `bg`, `et`, `lt`, `lv`, `sq`, `sr`, `mk`, `kk`, `mn`, `hy`,
`ka`, `is`, and bare `sl` (Slovenian is `sl-SI`). Apple wants country-suffixed
codes in several places: `sl-SI`, `bn-BD`, `ur-PK`, `ar-SA`, and all Indian
languages (`gu-IN`, `kn-IN`, `ml-IN`, `mr-IN`, `or-IN`, `pa-IN`, `ta-IN`,
`te-IN`). Chinese is `zh-Hans` / `zh-Hant`.

Pre-flight: `fastlane --version` must be ≥ 2.234.0 — earlier versions have a
stale locale list missing the Indian-subcontinent locales.

## Character limits (hard, per locale)

| Field | Limit |
|---|---|
| name | 30 |
| subtitle | 30 |
| keywords | 100 |
| promotional_text | 170 |
| description | 4000 |

Validate after writing, every locale. German, Finnish, Turkish, Hungarian,
Tamil and Malayalam explode compound words — flag any en-US name/subtitle
already over ~22 chars as a translation-length risk before generating.

## Workflow — five steps per app

### 1. Get the en-US source

If the app is already live, pull the live listing (source of truth) rather
than trusting local files: `ruby scripts/asc.rb GET
'/v1/apps/<id>/appStoreVersions?limit=1'` → version localizations, or
`fastlane deliver download_metadata`. If this is a new app, write en-US fresh
from the phase-1 keyword table: name = main keyword + brand
(`Calorie Tracker — Glow Up`), subtitle = second keyword, keyword field = the
approved list.

### 2. Source analysis — BEFORE any translation

Read the five en-US files and write down, explicitly:

- **Brand structure**: the BrandWord (proper noun — `Glow Up`) vs the
  DescriptorWord (common noun — `Calorie Tracker`). The brand stays itself;
  the descriptor is search vocabulary.
- **Domain vocabulary**: for each term of art (macros, fasting window, meal
  plan…), decide: keep English everywhere / keep English in Latin scripts
  only / translate / transliterate.
- **Idioms in body copy** ("stays out of your way", "actually works") — mark
  for meaning-translation, never literal.
- **Verbatim atoms**: iPhone, Apple Watch, iPad, all URLs, email addresses,
  EULA, numbers + units. These survive every locale untouched.

If a term is ambiguous, ask the user now — one clarifying question here is
cheap; a wrong guess replicated into 49 locales is not.

### 3. Generate all target locales in one pass

Write a small script with the full per-locale table embedded (translations
produced per the configured engine), emit all `<locale>/<field>.txt` files,
and print per-locale char counts as it writes. Never serialize behind a
single-language pilot; never pause for a per-language human review unless the
user asked for one.

**Name/subtitle rules per script family:**

- **Latin-script locales**: keep the BrandWord verbatim; translate the
  DescriptorWord into the locale's *searched* term (that's what phase 1's
  per-market research found — use it, don't re-derive from translation).
- **Non-Latin scripts** (Cyrillic, Greek, CJK, Arabic, Hebrew, Thai, Indic):
  transliterate the BrandWord into the local script, translate the
  DescriptorWord. A Latin brand string in a Devanagari listing reads as
  foreign noise.
- The keyword-led order from phase 1 holds in every locale: descriptor first,
  brand second.

**Keyword field: ADAPT, never invent.** Every locale's keyword field is a
faithful adaptation of the same en-US concept list — same concepts, local
words people actually search. Do not pad with geo terms ("calorie tracker
germany") or locale-invented extras; if a concept has no local search
equivalent, drop it and use the freed chars for the next concept on the list.

**Description/promo**: translate by meaning, keep the brand form consistent
with the name field, keep the verbatim atoms byte-identical.

### 4. Automated review — this IS the review

Check every generated file; fix and re-check what fails; report findings:

- char limits per field per locale;
- verbatim atoms survived byte-identical (a "translated" URL is a 404, a
  localized support email is a dead mailto);
- keyword-field fidelity: same concept list as en-US, no inventions;
- brand shape: BrandWord present and correctly kept/transliterated;
- spot-check the hard scripts (CJK, RTL, Indic) plus any locale the user
  reads.

### 5. Upload with `deliver`

```bash
fastlane deliver --skip-binary-upload --skip-screenshots --force
```

Gotchas that cost real time:

- **Subtitle, keywords, name and description only change with a new app
  version.** Promotional text is the one field editable in place on a live
  listing. Plan metadata changes to ride the next version.
- **Per-locale privacy policy URL is required.** Submission fails with
  per-locale "Privacy Policy URL" errors otherwise — copy the en-US
  `privacy_url.txt` into every locale dir.
- **Name collisions**: a locale's translated name may already be taken
  ("The app name you entered is already being used"). Fix that one locale by
  appending the descriptor or a distinguishing word, save the fix back to the
  local file, re-run (deliver is idempotent).
- **A version created via the API does not carry localized text forward.**
  The ASC *web UI* auto-copies name/subtitle/keywords/description to a new
  version; the *API* leaves every non-en-US locale blank. If you created the
  version programmatically (e.g. for screenshots), you MUST re-push the
  localized metadata and then verify per-locale before submitting — otherwise
  Apple fills the blanks with en-US and you ship an all-English listing over
  a localized one. Verification = read back every locale and confirm a
  non-English name and a non-zero description length.
- **Screenshots auto-fallback**: locales without their own screenshots show
  the en-US set automatically — no action needed until phase 3 uploads real
  localized ones.

## What you must NOT do

- Never invent per-locale keywords or add geo filler.
- Never include the rejected locale codes above.
- Never translate iPhone / Apple Watch / URLs / emails / EULA.
- Never mention pricing, discounts, or "free" in the description of a paid or
  paywalled app — that's a rejection class (see
  `submission-checklist.md`).
- Never exceed a char limit "just slightly" — Apple's API rejects the write.
- Never skip step 2. It is where the silent bugs die.
