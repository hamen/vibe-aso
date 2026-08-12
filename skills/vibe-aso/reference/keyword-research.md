# Phase 1 — Keyword research

Everything downstream (name, subtitle, keyword field, screenshot headings)
inherits from this phase. The output is small and precise:

1. **Main keyword** — leads the app name.
2. **Subtitle keyword** — the second-strongest keyword, leads the subtitle.
3. **Keyword field list** — complete phrases totalling ≤100 characters, none
   repeating what the name/subtitle already cover.
4. Per major market: whether the same terms hold, or the local language
   searches something else.

## The three surfaces keywords land on

Apple indexes three text inputs for search: the **name** (30 chars), the
**subtitle** (30 chars), and the hidden **keyword field** (100 chars). All
three are per-locale. The research phase decides what goes where; phase 2
writes it.

## Rule 1 — Lead with the keyword, not the brand

If the calorie tracker's brand is **Glow Up**, the name
`Calorie Tracker — Glow Up` beats `Glow Up — Calorie Tracker`. People type
"calorie tracker" into search; almost nobody types your brand until you're
already big. Position weight is real: the earlier a term appears in the name,
the more it counts. Brand-first naming is a vanity trade against downloads —
make it consciously if the user insists, never by default.

The subtitle takes the **second** main keyword the same way: keyword-led,
descriptive, not a slogan. `Track macros & lose weight` is a subtitle;
`Feel amazing every day` is a wasted 30 characters.

## Rule 2 — Never repeat a keyword across surfaces

Apple indexes the combination of all three surfaces; a word spent twice is
~100-char budget burned for nothing. If "calorie tracker" is in the name, the
keyword field must not contain "calorie tracker" again. A *different phrase
containing an overlapping word* is fine when it's a genuinely distinct search
("ai calorie tracker", "calorie counter") — the rule bans duplicate phrases,
not shared words. When trimming, drop the duplicate from the keyword field,
never from the name.

## Rule 3 — Relevance means intent-match, and two failure classes fake it

A keyword is relevant only when **the person typing it expects an app like
yours**. Both failure classes look attractive in a tool because their
popularity is high:

- **Too generic.** "tracker" for a calorie tracker. Huge popularity, zero
  signal — the searcher may want sleep, budget, or flight trackers. Ranking
  for it (you won't) would still convert terribly.
- **Adjacent but wrong intent.** "muscle growth" for a calorie tracker.
  Related to the *idea*, but the searcher wants workout apps. You might even
  rank; the installs won't come, and the ones that come won't stay. Ask of
  every candidate: *how many people typing this want THIS app?* If the honest
  answer is "some, indirectly" — cut it.

## Rule 4 — Popularity: the floor is a gamble

Popularity scales are a proxy, and they have a **measurement floor** (on a
5–100 scale, that floor is 5). A floor value does not mean "no traffic" — it
means *unknown, below the instrument's resolution*. One floor-value keyword in
the field is a lottery ticket; a name, subtitle, and keyword field built
mostly of floor-value keywords means the listing is invisible and you're
gambling the launch. The main keyword and subtitle keyword must have
popularity clearly above the floor. Floor-value long-tails are acceptable only
as filler after the proven terms are placed.

## Rule 5 — Difficulty: pick fights you can win

A keyword must be relevant **and winnable** — relevant-but-unwinnable is
wasted budget, winnable-but-irrelevant converts nothing.

- **New app:** anything under ~50 difficulty is winnable at some point; the
  lower the better. Put "calorie tracker" (difficulty 60+) in a brand-new
  app's name and you must understand you will *not* rank for it for a long
  time — the name slot is then a bet on the future, and the keyword field
  must carry winnable terms for the present.
- **Established app** (installs, ratings, retention): difficulty 50–70 becomes
  contestable. Authority compounds; the same subtitle that did nothing at
  launch starts ranking once the app has a few thousand installs.

An app with very few installs ranking ~1000 for a term in its own subtitle has
an **authority problem, not a keyword problem** — adding more keywords will
not fix it; installs will.

## Rule 6 — Cross-check demand with "apps using this keyword"

Good tools show how many apps carry a keyword in their name/subtitle. Many
apps betting their title on a term is *evidence people search it* — devs
converge on what works. Zero apps using a high-popularity term is a smell:
either you found a genuine gap (rare) or the metric is lying (common).

## Rule 7 — Research per market, not per translation

The keyword field is localized per locale — and so is the *research*. Germans
don't search a translation of your English keyword; they search what Germans
type ("kalorienzähler", not "kalorien tracker" — check, don't assume). For
every major market in the chosen locale set, re-run the popularity lookups on
local-language candidates. Where the tool has no data for a locale, translate
the *concepts* and say plainly that those locales are unverified.

## Two hygiene rules for the keyword field

- **Complete, readable phrases** — every entry something a human would
  actually type. No word-soup fragments ("calorie,track,count,food,diet" is
  weaker than distinct real phrases).
- **No Apple product names in name or subtitle** — "Apple Watch" in a name or
  subtitle is a metadata rejection (guideline 5.2.5). In the keyword *field*
  it's fine and valuable if the app genuinely has a Watch app: "apple watch"
  (the full phrase — that's what people type). Brand-prefix phrases rank
  separately from the bare term, so "apple watch calorie tracker" and
  "calorie tracker" are two distinct bets.

## Workflow with Astro (keyword_source: astro)

1. Work inside the app's existing entry, or create a **temporary folder/tag**
   for a not-yet-released app — keeps research separate from live tracking.
2. Seed candidates: the app's own concept list, `get_keyword_suggestions`,
   and `extract_competitors_keywords` on the 3–5 closest competitors (find
   them with `search_app_store`).
3. For every candidate record popularity, difficulty, and apps-using-it.
   Dump the table to a local file; slice follow-ups from the file.
4. Apply rules 3–6 to cut the list; sort survivors by popularity × winnability.
5. Assign: strongest surviving keyword → name; second → subtitle; the rest →
   keyword field until the 100-char budget is spent (rule 2: no repeats).
6. Per major market, re-run steps 2–4 on local-language candidates
   (`search_rankings` on the local storefront shows who's winning there).

## Workflow without a data tool (keyword_source: none)

1. Candidates from: Apple search autosuggest (type the concept, note the
   completions — they're ordered by real volume), competitor names/subtitles
   on the storefront, and the user's own understanding of the niche.
2. Apply rule 3 (intent) — it needs no tool.
3. State clearly which choices are data-backed (autosuggest order is weak but
   real evidence) and which are judgment calls. Recommend validating the main
   keyword with a real tool before committing the app *name* to it.

## Output of this phase

A short table the user signs off on — keyword, surface it's assigned to,
popularity, difficulty, and the one-line intent argument. Get explicit
approval on the **main keyword and subtitle keyword** before phase 2 spends
50 locales on them.
