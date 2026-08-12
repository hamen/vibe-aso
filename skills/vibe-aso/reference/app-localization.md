# Phase 5 — In-app string localization

Localizes the strings users see *inside* the app. Sibling of phase 2 (store
metadata); this one touches the Xcode project. The framework below was
battle-tested across dozens of production apps — its core claims: **cascade
every locale in one pass, review by detectors, never by a per-language human
gate**; and most translation bugs are *domain* bugs that fluent output hides.

## Step 0 — Discover state

Inspect the project before proposing anything:

- **Already localized** (String Catalog `.xcstrings` or `.lproj` dirs with
  real translations) → this is a *top-up*: only translate what's missing or
  new, and obey the top-up rules at the bottom.
- **Partially localized** (locale dirs exist but many values equal their
  English key) → repair: fill the untranslated remainder.
- **Zero localization** (hardcoded literals everywhere) → bootstrap.

Judge "translated" by **value ≠ key**, never by "key exists" — a seeded
`"Statistics" = "Statistics";` in 30 locales is coverage, not translation.

## Locale set

Reuse the set chosen in phase 2, mapped to in-app codes (in-app uses bare
language codes where ASC wants country-suffixed ones: `de` not `de-DE`, `nl`
not `nl-NL`; Chinese stays `zh-Hans`/`zh-Hant`). The store listing promising
50 languages while the app speaks one is a bad look in reviews — align them.

## Bootstrap (zero-state projects)

1. **Prefer the project's native mechanism.** On modern Xcode that's a String
   Catalog (`Localizable.xcstrings`); the classic `<locale>.lproj/
   Localizable.strings` + a small `L10n` helper works everywhere. Match
   whatever the project already uses.
2. **Wrap user-visible literals** (`Text("…")`, `Button("…")`,
   `.navigationTitle("…")`, alerts, labels, assignments to title/message
   vars, ternaries, `return "literal"` in computed display properties, enum
   `rawValue` at display sites). Do NOT wrap: strings after `systemImage:` /
   resource/identifier parameters, SF Symbol names (`clock.fill`),
   single-word camelCase logic identifiers, log/analytics strings.
   Interpolations (`"Won \(n) points"`) convert to format strings
   (`String(format:)` / `%d`) — they can't be wrapped mechanically.
3. **Brand pass (interactive).** Some strings must stay literal in every
   language: the brand name, "<Brand> Pro" plan names, product codes. Show
   the user the candidates (navigation titles, app-name strings, plan names)
   and let them choose localize vs keep-literal. Record the decisions in a
   small per-project config file so future runs respect them.
4. **Add a language picker** in Settings if the user wants in-app override of
   the system language (optional — iOS per-app language settings cover most
   needs).
5. Harvest all keys into the English source table; build; then translate.

## Translating — engine and batching

Use the engine from `~/.vibe-aso/config.json`:

- **subagents**: spawn one subagent per locale (or per few locales), each
  given the key list + context + the rules below, returning strict JSON.
- **deepseek / openai**: batched chat-completion calls, ~80 keys per batch —
  large batches keep register consistent; small batches flip-flop grammar
  between imperative and infinitive across a list. **Check the account
  balance before a cascade** (a valid key on an empty account 402s every
  call, half an hour in).

Run locales as independent parallel jobs; each writes its own JSON; merge
after detectors pass. Chunk the shell commands per locale/batch — never one
monolithic multi-hour call.

**Every translation request carries:**

- the brand-literal list (output verbatim, never translated);
- format-specifier rules: `%@`, `%d`, `%1$d` preserved exactly, count AND
  order; never inject a specifier into a string that has literal numerals;
- "Apple Watch" stays "Apple Watch" — never bare "Watch", never a generic
  word for watch;
- frequency labels on paywalls (`Yearly`, `Monthly`, `Weekly`) translate as
  **adverbs** ("billed yearly"), never the bare noun ("Year") — the noun
  collides with duration labels elsewhere on the same screen;
- a **sense glossary** for every ambiguous domain word, and
- **enum groups** for ordered sets that render side by side.

### The sense glossary — where translation actually fails

Fluent-but-wrong survives every automated check. The model translates the
*common* sense of a word, not your app's sense: in a calorie tracker, "log"
is recording a meal (not a tree trunk, not a login), "goal" is a daily
calorie target (not a sports goal), "serving" is a food portion (not the
sports serve, not a web server). Declare each ambiguous term with its intended meaning once,
inject it into every request, and it fixes all locales at once — per-key
patching misses the locales nobody on the team reads.

Two limits, both measured on shipped apps:

- **Short keys defeat the glossary.** Two-word badge names give the model no
  context; a strong wrong prior wins. Budget a post-cascade sweep: for each
  ambiguous term, grep all locales for the *wrong* sense's word family and
  force-retranslate hits with the sense spelled out — and re-check the
  replacement against the same pattern before writing it.
- **"Only overwrite values that equal their key" can't fix wrong-sense
  values** — those *are* translated, just wrongly. Repairs need two passes:
  an identity fill AND the condemned-value scan above.

**Enum groups**: rank ladders, badge tiers, mode names that appear in one
list must not collapse onto one word ("Contender" and "Challenger" both
becoming the same local word reads as an app bug — each translation
individually fine). Declare the sets; after translating, check pairwise
distinctness per locale.

## The detector suite — this replaces the human gate

Run over every locale before anything lands; each catches a class that has
shipped as a real bug:

| Detector | Catches |
|---|---|
| same-as-key | untranslated values (whitelist true cognates: "OK", "Pro", numerals, and per-locale loanwords) |
| specifier parity | `%@`/`%d`/positional count-or-order drift vs English — a crash, not a typo. Positional reorder (`%2$d … %1$d`) is LEGAL and correct in some languages; force positional forms when order changes, don't "fix" them back |
| never-translate atoms | emails, URLs, `mailto:`, specifier-only strings — only correct value is the key itself; enforce identity at write time |
| Latin leak | non-Latin locale values holding Latin word-runs that aren't kept tokens |
| caps + punctuation parity | ALL-CAPS keys stay shouty in cased scripts; trailing terminator matches the locale's own convention — Greek's question mark is `;`, CJK uses `。/？`, Thai ends sentences with nothing; per-locale rules, never a naive "add a period" |
| enum-group collision | two members of a declared set sharing one translation |
| zh-Hans/zh-Hant script mix | Simplified/Traditional contamination — one language, two scripts, invisible to every other check. Verify with a converter (opencc): round-trip is valid for zh-Hans (`t2s` is many-to-one); for zh-Hant test characters in isolation — running the converter over whole correct Traditional text *invents* corruptions, so a round-trip count there is not a measurement |
| shipped-vocab diff | new copy inventing a second word for a term the app already ships ("splits" translated one way in onboarding, another in settings). Diff new strings against the project's existing translations for shared terms — this one check finds the bugs users actually notice |

After the cascade, three cleanup passes in order:

1. **Echo retry** — re-ask ONLY keys that came back identical to English,
   telling the model a previous pass returned them untranslated and that
   badge/feature names are nicknames, not SKUs. Loop up to 3 rounds;
   survivors are usually genuine cognates.
2. **Register harmonization** — any long list rendered together (achievement
   requirements, onboarding bullets) drifts between grammatical forms across
   batches. Send the WHOLE list in one request per locale with 6–8 of the
   app's own shipped strings as a **register anchor** ("match the address
   form of these"), never an instruction like "use the polite form" — the
   app might be informal, and uniform-but-mismatched is the same defect
   relocated. Afterwards re-check: invented trailing periods, and enum
   groups re-collapsing.
3. **Spot-read 10–15 keys in 4–5 languages** (include one CJK, one RTL). The
   detectors are necessary, not sufficient.

## Data libraries (food databases, exercise catalogs…)

Bounded in-bundle content lists (50+ items with stable IDs) get a variant
pipeline: batch ~30 items **grouped by category** (siblings disambiguate each
other — "Chicken Breast/Thigh/Tenderloin" translated together come out
distinct; alone they collapse), with a domain-specific prompt (natural
culinary/exercise names, no invented regional variants, loanwords stay
loanwords). Wire display through a computed property that looks up the
translation by ID and falls back to the English name; keep the English field
for search. Filter hallucinated keys (items not in the input) at merge.

## Top-up rules (apps that already ship translations)

1. **Never rewrite whole locale files from harvested keys.** Any key reached
   through a runtime variable (data-table IDs, catalog titles) is invisible
   to call-site harvesting, and a rewrite silently deletes its translations
   from every locale. Merge: add new keys, overwrite only an explicit
   condemned list, and assert `old_keys − new_keys = ∅` per locale before
   writing. Back up the locale dirs first.
2. **Prune dead keys before translating** — keys no Swift source references
   anymore are orphans; translating them buys screens that no longer exist.
3. **New copy inherits the shipped vocabulary.** The app already decided how
   it says its domain terms in every language; paste the app's own renderings
   into the prompt rather than letting the model pick a second word.
4. A sibling project's translations are **not** proof — they can carry seeded
   English or their own bugs. Never bulk-import values that equal their key.

## Extension targets (Watch, widgets)

Each target needs its own strings resources. If the phone sends an extension
raw English strings at runtime (e.g. a reward payload with `title:` seeds),
the extension's table must carry those keys even though no call site in the
extension references them — harvesting misses this, users see English on the
watch in every language. Check which shape the app uses.

## Build verify + ship discipline

Build every target after the merge (`xcodebuild -destination
'generic/platform=iOS' …`, plus the Watch/extension schemes — use `-scheme`,
not `-target`). Format-specifier mistakes surface here as crashes/errors.
Then **freeze strings before archiving**: any string edit after the archive
starts may or may not land in the binary — if strings change, bump the build
number and rebuild; never submit the earlier archive.
