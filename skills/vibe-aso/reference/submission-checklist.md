# Phase 6 — Submission: fill everything, verify everything, list what's manual

A new app's ASC page is almost entirely empty, and almost every field can be
set via the API. The failure mode this checklist kills is the **silent
skip** — a run that sets "the important fields", reports success, and leaves
the app blocked on something nobody mentioned. Two rules:

> **1. An item is done when a GET shows the intended value** — never when the
> PATCH returned 2xx.
> **2. Every item the API cannot set goes, explicitly, into a final "MANUAL
> STEPS REMAINING" list.** An item you didn't do is reported FAILED or
> MANUAL — never omitted.

## The checklist

**[api]** = set it AND read it back. **[manual]** = the API can't; goes in the
final list. Report all items — inapplicable ones as N/A with the reason.

| # | Surface | Who |
|---|---|---|
| 1 | App name (en-US) | [api] |
| 2 | Subtitle | [api] |
| 3 | Primary + secondary category | [api] |
| 4 | Description | [api] |
| 5 | Keywords | [api] |
| 6 | Promotional text | [api] |
| 7 | Copyright (`<year> <legal name>`) | [api] |
| 8 | Privacy Policy URL + Support URL (per locale) | [api] |
| 9 | Marketing URL (if the app has a website — per locale if the site is localized) | [api] |
| 10 | App price | [api] |
| 11 | Availability territories | [api] |
| 12 | IAPs/subscriptions + trials (if monetized) | [api] |
| 13 | Territory pricing (phase 4) | [api] |
| 14 | Age rating questionnaire | [api] + [manual] |
| 15 | App Privacy survey ("nutrition labels") | [manual] |
| 16 | Content rights declaration | [api] |
| 17 | App Review contact + demo account info | [api] |
| 18 | Release type (manual / after-approval) | [api] |
| 19 | Attach IAPs to the FIRST version | [manual] |
| 20 | IAP review screenshots | [manual] |
| 21 | App screenshots + icon | [manual] (upload via phase 3; imagery is the user's) |
| 22 | Regulated Medical Device = No (Health & Fitness apps) | [manual] |
| 23 | Final review submission | [manual] |

## The traps, in the order they bite

- **The App Privacy survey is UI-only and blocks the first submission.** The
  data-usage endpoints exist only on Apple's private web-session API — the
  public JWT API 404s on them. The user must answer the full survey in ASC →
  App Privacy and hit **Publish**. For local-only apps the honest answer is
  "Data Not Collected".
- **Age rating: send ALL attributes in one PATCH** (the API reveals missing
  required fields one error at a time — sending the full set avoids the
  loop). Even after a successful PATCH that reads back non-null, the ASC UI
  can still show **Messaging/Chat** and **User-Generated Content** as
  unanswered, which silently blocks submission — the user must open Age
  Rating in the UI and confirm no question is blank. API success here is
  necessary, not sufficient.
- **A brand-new app's FIRST version cannot attach IAPs via the API.** It is a
  web-UI step on the version page. Skip it and the app ships with nothing
  purchasable — and no error tells you.
- **IAPs sit in MISSING_METADATA until each has a review screenshot** —
  a manual upload, listed every run the app monetizes.
- **Health & Fitness category** triggers a "Regulated Medical Device?"
  question in the UI with no public API — a wellness tracker answers No, but
  a human must click it.
- **Availability territory IDs** use the inline local-ID format
  (`${AFG}`-style references) on `/v2/appAvailabilities`; a 409 "already
  exists" means it's already set — idempotent, not an error.

## Copy rules Apple actually rejects on

- **No pricing language in the description or promotional text** — no prices,
  no "free trial", no discount talk. Features and value only. This is a
  recurring metadata-rejection class (guidelines 3.1.2/5.6).
- **Don't call the app "free" anywhere in the listing if it hard-gates on a
  paywall.** "Free" copy + a paywall on first launch is a rejection.
- **No Apple product names in name/subtitle** (5.2.5) — "for Apple Watch" in
  a subtitle gets bounced; the keyword field is the place for "apple watch".
- **Don't gate App Store access behind a sentiment prompt in-app** ("Enjoying
  the app?" before the rating request) — 5.6.1.

## Review notes that prevent a rejection cycle

In App Review contact info: state whether an account is needed (if none:
`demoAccountRequired: false` + a note saying so), and that IAPs are
sandbox-testable. Reviewers who can't reach the paid surface reject blind.

## Final output — required shape

1. A table with one row per checklist item: **SET** (read-back shown) /
   **FAILED** (attempted, read-back disagrees — never reclassified as MANUAL
   to look done) / **MANUAL** / **N/A (reason)**.
2. Then, verbatim heading:

```
MANUAL STEPS REMAINING
1. App Privacy survey — ASC → App Privacy → full survey → Publish
2. Age Rating UI — confirm no blank questions (Messaging/Chat, UGC)
3. Attach IAPs to the first version (web UI, first version only)
4. IAP review screenshots
5. App screenshots + icon (if any slot is empty)
6. Regulated Medical Device = No (Health & Fitness only)
7. Submit for review
```

For a first release this list is **never empty** — an empty MANUAL list means
the run skipped something.
