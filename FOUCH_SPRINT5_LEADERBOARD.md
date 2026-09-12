# FOUCH Sprint 5 — Event Leaderboard

## Product purpose

Answers one question: *"I got a FOUCH Score of 82 — where did I finish?"*
Strictly event-scoped. Not a global leaderboard, rating, or profile system
— see `FOUCH_SCORING_RESEARCH.md` §16 for why cross-event scores aren't
casually comparable.

## Route

`/events/[event-slug]/leaderboard` — e.g. `/events/miss-universe-2026/leaderboard`.
Accepts an optional `?from=<publicId>` query param (same convention as the
existing `?from=` attribution param) to identify the viewer's own
prediction and unlock "Your Finish."

## Eligibility

Identical filters to Sprint 3/4's `getEligiblePredictionsForComparison`
(same event, same `data_status`, `is_final = true`, exactly 10 items) —
implemented as a second, near-identical query
(`getLeaderboardRawEntries`) rather than reusing that function directly,
because that function's contract explicitly promises never to select
nickname/country for privacy reasons elsewhere. The leaderboard's whole
purpose is to show those fields publicly, so it needs its own query
rather than weakening that guarantee for everyone else.

## Ranking semantics

**Competition ranking ("1224"), not dense ranking ("1223").** A tie does
not compress the ranks below it:

```
scores: 100  99  99  99  75
ranks:    1   2   2   2   5
```

Ranking is based on the same rounded `displayScore` the UI already shows
(not hidden full-precision differences) — two rows both reading "88" are
genuinely tied. Ties are broken for **display order only** (not rank) by
`publicId`, deterministically — submission time is never used as a
tiebreaker, per the brief.

Pure, tested function: `assignCompetitionRanks()` in `src/lib/leaderboard.ts`.

## Privacy

Leaderboard rows expose **only**: nickname (or "Anonymous"), country code,
FOUCH Score, band, and the existing public prediction ID (already
shareable). Never exposed: device token, email, internal database IDs,
Supabase identifiers, analytics identifiers. Verified by inspecting
`getLeaderboardRawEntries`'s `select()` call — it lists exactly four
public columns plus prediction items, nothing else.

## Your Finish / own position

When `?from=<publicId>` resolves to an eligible, scored entry, the page
shows a "Your Finish" callout (rank, score, percentile if eligible) and
highlights that row inline if it's within the visible Top 50. If the
viewer's rank falls outside the Top 50, a small "Your neighborhood"
list (2 rows on each side) is shown instead of forcing pagination.

## Percentile

Reuses `computePercentile()` from Sprint 4's scoring engine exactly —
no second percentile formula. Same `MIN_PERCENTILE_SAMPLE = 25`
threshold, same self-exclusion, same tie handling.

## Small-sample states

| Total scored | Copy |
|---|---|
| 0 | "No scored predictions yet." |
| 1 | "First call on the board." |
| 2-4 | "The leaderboard is just getting started." |
| 5+ | Normal presentation, no special copy |

No result yet at all (not even demo) → "Leaderboard locked" state with a
"Make your call" CTA — never a fabricated empty board.

## Demo safety

The leaderboard is scoped to one `data_status` at a time
(`getEventLeaderboard(slug, dataStatus, ...)`); demo and official rows
can never appear on the same board, by construction. The page shows
"Demo leaderboard — not an official outcome" whenever `data_status ===
"demo"` (currently always true), and demo leaderboard pages are excluded
from search indexing (`robots: { index: false }`) so they can't surface
as if they were a real result.

## Performance

Ranking happens entirely server-side over the full eligible set, then
only the Top 50 (+ up to 5 neighbor rows for the viewer) are sent to the
client — never the full prediction list. At the project's current scale
(single-digit to low-hundreds of predictions per event) this is a single
pair of Supabase queries per page view; no new indexes were added since
none are needed yet at this volume. If a single event's prediction count
grows into the thousands, revisit with an actual index review — deferred
deliberately, not overlooked.

## Analytics

`leaderboard_viewed`, `leaderboard_row_clicked`, `own_rank_viewed`,
`leaderboard_from_score_clicked` — properties limited to `event_slug`,
`data_status`, `rank`, `score_band`, `leaderboard_size`,
`is_own_prediction`. No PII.

## Tests

`src/lib/leaderboard.test.ts` — 9 tests: all four required ranking
scenarios (`[95,90,85,80]→[1,2,3,4]`, `[95,90,90,80]→[1,2,2,4]`,
`[90,90,90]→[1,1,1]`, `[100,99,99,99,75]→[1,2,2,2,5]`), plus edge cases
(empty input, single entry) and `buildLeaderboard`'s tie-order/band
assignment. Combined with existing suites, the project now has **76
passing tests**. A `vitest.config.mts` was added so tests can use the
project's standard `@/...` import alias (previous test files avoided
needing it) — this is a one-time test-infrastructure fix, not a product
change.

## Known limitations

- No pagination beyond Top 50 + neighbors — acceptable at current scale,
  the natural next step if a single event's leaderboard grows very large.
- Row identity is nickname-only (+ country); FOUCH still has no
  account/profile system, so duplicate "Anonymous" or repeated nicknames
  are expected and not resolved here, as scoped.
- No dedicated leaderboard share card — the existing Result Card (score +
  band + percentile) already covers the sharing need per the brief.