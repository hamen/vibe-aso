# Vibe ASO — a Claude Code skill

You vibe-coded the app. Now vibe the ASO.

One skill that takes an iOS app from "ready to submit" to a fully-optimized,
fully-localized App Store presence — driven from Claude Code, end to end:

1. **Keyword research** — popularity/difficulty-driven, intent-matched, per
   market. Decides what your name, subtitle, and keyword field say.
2. **Store metadata in up to 50 locales** — keyword-led name and subtitle,
   adapted (never invented) keyword fields, descriptions that translate by
   meaning. Reviewed by automated checks, not vibes.
3. **Localized screenshots** — your background mockups + translated headings
   burned in by a bundled renderer (Playwright + per-script Noto fonts, RTL
   handled, auto-fit).
4. **Worldwide pricing** — pick a model (uniform, GNI bands, Big Mac index,
   Netflix index) and it's applied per territory via the App Store Connect
   API, with read-back verification.
5. **In-app localization** — your actual UI strings, translated with a
   detector suite that catches the bugs fluent output hides (format-specifier
   drift, wrong-sense domain words, script contamination, register drift).
6. **Submission checklist** — every field the ASC API can set gets set and
   verified; everything it can't becomes an explicit manual-steps list
   instead of a silent gap.

No signup, no SaaS — you bring your own App Store Connect API key, and
translations run on Claude subagents by default (or your own DeepSeek /
OpenAI-compatible key if you prefer).

## Install

**Run these two commands in Claude Code one at a time — wait for the first to
succeed before pasting the second.**

Step 1 — register the marketplace:

```
/plugin marketplace add Kronop/vibe-aso
```

Step 2 — install the plugin:

```
/plugin install vibe-aso@vibe-aso-marketplace
```

Then `/reload-plugins` (or restart Claude Code).

Or clone directly (no plugin manager):

```bash
git clone https://github.com/Kronop/vibe-aso /tmp/vibe-aso
cp -R /tmp/vibe-aso/skills/vibe-aso ~/.claude/skills/vibe-aso
```

## Use

Open Claude Code in your app's repo and say what you want:

```
do the ASO for my app
```

…or any slice of it: "find keywords for my calorie tracker", "localize my
App Store page", "localize my screenshots", "set worldwide prices", "localize
the app itself", "get my listing ready for submission". Claude loads the
skill on its own from the description.

First run walks you through a short setup wizard:

- **App Store Connect API key** (App Store Connect → Users and Access →
  Integrations → Team Keys). Stored in `~/.vibe-aso/`, chmod 600, never in a
  repo, never printed.
- **Translation engine** — Claude subagents (default, zero setup), DeepSeek,
  or any OpenAI-compatible API.
- **Keyword data source** — an ASO tool with popularity/difficulty data
  (Astro's MCP is the best-supported), or honest degraded mode without one.

## Requirements

- macOS with Xcode command-line tools (in-app localization builds the project)
- `ruby` and `python3` (ship with macOS)
- `fastlane` ≥ 2.234.0 for metadata/screenshot upload (`brew install fastlane`)
- `node` for the screenshot renderer (one-time `npm install`,
  `npx playwright install chromium`, and a ~55 MB font download —
  `renderer/fetch_fonts.sh`)

## What it costs

Nothing beyond what you already pay: your Claude usage, and — only if you
choose the DeepSeek engine — roughly **$0.50 per app** for a full ~400-string
× 40-locale in-app cascade. The App Store Connect API is free.

## Design principles

- **Fan out, then verify.** Every localization pass covers all chosen locales
  at once and is reviewed by automated detectors + targeted spot-checks — a
  human can't review 40 languages, and reviewing one proves nothing about the
  other 39.
- **Read-back or it didn't happen.** Every API write is verified with a GET.
  Every thing the API can't do lands in an explicit manual-steps list.
- **Intent over volume.** A keyword is worth ranking for only when the person
  typing it wants *your* app.

## License

MIT. The renderer downloads Google Fonts (DM Sans, Noto Sans family) at
setup time; those are OFL-licensed and not redistributed here.
