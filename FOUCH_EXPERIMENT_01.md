# FOUCH — Experiment 01: Your Crowd Changed

**This is not Sprint 6.** A small, bounded product experiment testing one
hypothesis from `FOUCH_RETURN_LOOP_RESEARCH.md` (§17, §21). Nothing here
establishes causal retention — see "Limitations" below.

## Hypothesis

When a user sees that community support for their own winner prediction
has meaningfully changed since they submitted, is that information
interesting enough to drive additional exploration?

This experiment measures **interest/engagement**, not proven retention: a
user has to return on their own to encounter this at all — there is no
notification driving them back.

## Calculation

**THEN population**: eligible other predictions (same event, same
`data_status`, `is_final = true`, exactly 10 items) with
`submitted_at <= displayed_prediction.submitted_at`.

**NOW population**: all current eligible other predictions, same
filters, no timestamp cutoff.

Both **exclude the displayed prediction itself** (tested explicitly —
without this, a prediction's own pick inflates its own support).

```
thenSupport = (THEN predictions matching displayed's #1 pick) / THEN population × 100
nowSupport  = (NOW predictions matching displayed's #1 pick)  / NOW population  × 100
changePoints = nowSupport - thenSupport   // percentage POINTS, never relative %
```

Pure function: `computeConsensusChange()` in `src/lib/consensus-change.ts`.

## Eligibility (display gates)

```
MIN_MOVEMENT_SAMPLE = 10   // both THEN and NOW must meet this
MIN_MOVEMENT_POINTS = 5    // minimum |changePoints| to show anything
```

Below either threshold: **render nothing** — no "not enough data" message,
no disabled state, no placeholder. The section simply doesn't appear, and
the rest of the public prediction page is completely unaffected.

## Self-exclusion

Verified by a dedicated test (`consensus-change.test.ts`, "self exclusion"
case): a prediction with 0 supporters among *others* stays at 0%, even
though the displayed prediction's own matching pick is present in the
raw input array. The pure function filters it out before any counting.

## Demo/official isolation

Enforced structurally, not by convention: `getWinnerPicksForConsensusChange(eventSlug,
dataStatus)` only ever queries one `data_status` at a time. There is no
code path where a demo prediction's population could include an official
one, or vice versa — the same isolation pattern already used by You vs
The World and FOUCH Score.

## Data used — no new infrastructure

- `predictions.submitted_at` — already existed (used for immutability).
- Each prediction's #1 pick — read from `prediction_items` where
  `predicted_position = 1`, via a new lean query
  (`getWinnerPicksForConsensusChange`) that never fetches the other 9
  items of any prediction.
- **No new table. No new column. No migration. No snapshot job. No cron.**

## UI

Placed on the existing public prediction page, after You vs The World.
No new route. Not added to Home, nav, or the Leaderboard.

**Toward:**
```
YOUR CROWD CHANGED
🇨🇴 Colombia
22% → 38%
↑ +16 pts
The crowd is moving toward your call.
Based on community predictions since your call.
```

**Away:**
```
YOUR CROWD CHANGED
🇨🇴 Colombia
38% → 21%
↓ −17 pts
The crowd is moving away from your call.
Based on community predictions since your call.
```

No chart, no sparkline, no dashboard styling — plain text using FOUCH's
existing typography tokens.

## Scope discipline

Only the user's own **#1 (winner) pick** is analyzed. No Top 3/5/10
movement, no country-level rank movement ("Thailand #7→#3" — explicitly
out of scope, per the research's cold-start finding that it needs a much
larger sample), no regions, no notifications, no new page.

## Analytics

**`consensus_change_viewed`** — fires only when the section actually
renders (i.e., already eligible):
```
event_id, data_status, direction, change_points,
then_sample_bucket, now_sample_bucket
```
Sample sizes are sent as coarse buckets (`10-24`, `25-49`, `50-99`,
`100+`), never exact counts. No nickname, no public prediction ID, no
device token, no internal database ID.

**Return signal**: reuses the existing `public_prediction_viewed` event
— a second occurrence for the same public prediction ID after a
`consensus_change_viewed` fired is the evidence to look for. This
experiment does not add a new "return" event.

## Limitations

- **This does not prove the feature causes retention.** A user must
  already have returned to encounter it. It measures whether, once
  encountered, the information is real/large enough to matter, and
  provides early (not causal) evidence for a future return-loop design.
- Same-instant `submitted_at` ties are included in THEN (`<=`) —
  deterministic, but not meaningfully orderable beyond that.
- At FOUCH's current demo scale, this will likely be invisible in
  production simply because fewer than 10 eligible predictions exist yet
  — that's correct behavior, not a bug (see below).

## Success / kill criteria

Directional, not statistically proven at current sample sizes — always
report population size alongside any percentage:

- **GREEN**: ≥15% second-touch rate among predictions that were shown a
  real (≥5pt) shift → proceed toward the fuller Crowd Movement feature.
- **YELLOW**: 5–15% → signal exists but is weak; try different placement
  or copy before a full build.
- **RED**: <5%, once there's enough exposure to interpret at all → kill
  the hypothesis.

Do not make a product decision from 3, 5, or 10 exposed users.