# Phase 4 — Worldwide pricing

Sets the app's (or its IAPs'/subscriptions') price per territory. Apple gives
you ~175 territories; charging a US price everywhere leaves most of the world
unable to buy. This phase asks the user which model they want, then applies it
via the ASC API and **verifies by reading prices back**.

## Step 1 — Ask the user which model (AskUserQuestion)

1. **One price everywhere (Apple equalized)** — set the US base price; Apple
   auto-derives every territory at market exchange rates. Zero maintenance,
   no purchasing-power adjustment. Fine for a first release; most apps
   outgrow it.
2. **GNI bands (recommended)** — three bands cut on GNI per capita:
   - **Band 1 — 1.00×** of the equalized local price: US, Western Europe,
     Canada, Australia, plus high-income overrides the raw GNI cut misses —
     the Gulf states, Japan, South Korea, Singapore, Hong Kong, Taiwan.
   - **Band 2 — ~0.60×**: Eastern Europe, Turkey, Mexico, Brazil, China,
     most of Latin America.
   - **Band 3 — ~0.30×**: India, Indonesia, most of Africa and South Asia.
   The ratio multiplies Apple's *already-equalized local* price, so band 3
   lands deeper than "30% of US" — that is intended; those markets convert
   at those prices and not above.
3. **Big Mac index** — scale each territory by its Big Mac purchasing-power
   ratio. Popular idea; in practice a non-tradable food basket **misprices
   wealthy Asian markets** (Japan/Singapore/Hong Kong land far too cheap).
   If the user wants it, apply it — with that caveat stated.
4. **Netflix index** — scale by what Netflix charges locally, on the theory
   that Netflix already did the willingness-to-pay research for digital
   subscriptions. Reasonable; data goes stale and needs a source the user
   provides. GNI bands approximate the same curve with fewer moving parts.

Also confirm: does the model apply to the app price, subscriptions, lifetime
IAPs, or all three? (Usually all paid products together.)

## Step 2 — Mechanics (ASC API, via `scripts/asc.rb`)

- **App price**: `POST /v1/appPriceSchedules` with a base-territory (USA)
  price point; manual per-territory prices go into the same schedule.
- **Subscription prices**: price points per territory on the subscription,
  ALWAYS with `preserveCurrentPrice: true` — existing subscribers keep their
  price and no consent flow triggers. New subscription prices take effect
  **the next day at the earliest**: right after a run, ASC shows the old
  price with a scheduled change — that is a successful write, not a failed
  one.
- **One-time IAPs** (lifetime unlocks): price changes are immediate.
- Territory price points are discrete — for each territory pick the nearest
  available price point to `target = equalized_local × band_ratio`. Skip
  territories where no point is close rather than crashing; report them.

## Order rules that have burned real money

- **Setting a new US base price posts a fresh auto-equalized schedule that
  WIPES every per-territory override.** On any reprice: set the base price
  FIRST, then re-apply the band/index adjustments on top. Never the other
  way around.
- **Yearly and lifetime must move on the same date.** If yearly's price
  change lands a day before lifetime's, yearly briefly sits at or above
  lifetime and is strictly dominated on your own paywall.
- **Plan before writing.** Compute the full territory plan, show it (or dump
  it to a file), THEN write — a mid-run abort should leave either the old
  state or a logged, resumable position, never a half-applied mystery.

## Free trials (subscriptions)

A trial is an `introductoryOffer` of type `FREE_TRIAL` per territory. 7 days
on the weekly and yearly is the common indie default. Non-consumables cannot
carry trials. When setting trials, set them for **all** territories the sub
is available in, and verify by counting introductoryOffers back — not by the
script's own output.

## Step 3 — Verify

A 2xx is not verification. After applying:

- Sample one band-1, one band-2, one band-3 territory per product and GET the
  actual (or scheduled) price from ASC.
- For subscriptions, confirm the change is *scheduled* for tomorrow — that's
  correct — and that `preserveCurrentPrice` did its job (no pending consent
  state).
- Dump the full price state to a local file once; answer any follow-up
  ("what does India pay?") from the file, never by re-sweeping the API.
