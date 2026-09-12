# FOUCH Score — Implementation (Sprint 4)

This is the implementation reference. For *why* the formula is what it
is, see `FOUCH_SCORING_RESEARCH.md` (historical research — not
rewritten here).

## Architecture

```
scorePrediction(predictedRankedIds, officialResult, config)
  → pure function, src/lib/scoring.ts, no I/O
```

The engine is generic over `ScoringMode` (`STAGE_RANKING` |
`FULL_RANKING` | `CATEGORY_PICK`), but only `STAGE_RANKING` is
implemented. The other two are declared as types only
(`src/types/scoring.ts`) so a future sprint doesn't require touching
this file's shape.

## Schema

**New table**: `event_results` (migration `0003_event_results.sql`).
One row per `(event_slug, data_status)`. Winner/1st RU/2nd RU are
single participant IDs; `top5_extra_participant_ids` and
`top10_extra_participant_ids` are unordered arrays — the schema itself
makes it impossible to store an invented exact position for an
unordered stage member.

RLS: public `SELECT` (anyone with a prediction link can see whether it
scored); no `INSERT`/`UPDATE`/`DELETE` policy for anon — only the
service-role key (used exclusively by `scripts/set-official-result.ts`)
can write.

**No separate result-status state machine.** A missing row means "no
official result yet" (pre-Sprint-4 experience, unchanged). A row's
existence means "sufficient to score," because
`validateOfficialResult()` is required before any insert — this is a
deliberate simplification appropriate to the project's current scale,
not an oversight.

## Scoring config (frozen)

```ts
STAGE_RANKING_V1_CONFIG = {
  mode: "STAGE_RANKING",
  weights: { winner: 30, podium: 25, top5: 15, top10: 15, ranking: 15 },
  predictionSize: 10,
  stages: { podium: 3, top5: 5, top10: 10 },
}
```

Do not change these weights without a new research cycle (see research
§33/§34 in the validation follow-up).

## Stage-placement semantics (C2-B) — restated

Podium/Top5 credit only counts a member the user placed **within the
corresponding predicted positions** (`predictedTop10[0:3]` /
`[0:5]`) — never merely present anywhere in the Top 10. Ranking
Quality is the only order-sensitive component beyond that. See
`FOUCH_SCORING_RESEARCH.md` §22 for the full justification (this exact
question was tested against the alternative — membership-anywhere —
and rejected).

## Accepted ranges

Derived directly from the official result structure, never invented:

| Stage member | Accepted range |
|---|---|
| Winner | [1,1] |
| 1st Runner-Up | [2,2] |
| 2nd Runner-Up | [3,3] |
| Top5 extra (×2) | [4,5] |
| Top10 extra (×5) | [6,10] |

## Score bands (frozen)

| Range | Band |
|---|---|
| 0-39 | MISSED_IT |
| 40-59 | FAIR |
| 60-74 | GOOD |
| 75-89 | EXCELLENT |
| 90-100 | ELITE |

Centralized in `getScoreBand()` (`src/lib/scoring.ts`) — nothing else
compares a score to these numbers directly.

## Percentile

- **Population**: all other eligible, scored predictions for the same
  `(event_slug, data_status)` — the current prediction is always
  excluded from its own comparison, consistent with You vs The World's
  established convention.
- **Ties**: never counted as "beaten." Percentile = (count of others
  strictly below your score) / population. Two identical top scores
  both report the same, correct percentile.
- **Minimum sample**: `MIN_PERCENTILE_SAMPLE = 25` (`src/lib/scoring.ts`).
  Below that, no percentile is shown — the score and breakdown still
  render normally.

## Score calculation — dynamic, not persisted

Scores are computed on every request (`src/lib/scoring-service.ts`),
not stored. This makes "an official result correction must not create
a stale score" trivially true (there's no cache to invalidate) at the
cost of recomputing per page view. It reuses the exact same
`getEligiblePredictionsForComparison()` query You vs The World already
runs, so this doesn't add a second, duplicate data-fetching path — see
"Known limitations" below for when this trade-off should be revisited.

## Demo vs. official safety

`getOfficialResult(eventSlug, dataStatus)` only returns a result when
its `data_status` matches the one requested. A demo prediction can
never be scored against an official result, or vice versa — enforced
at the query itself, not by a downstream check that could be
forgotten. The UI additionally shows a "Demo result — not an official
outcome" label whenever `data_status === "demo"` (currently always
true for Miss Universe 2026, since the participant roster itself is
still demo data).

## How to enter a result

There is no admin UI — for this project's current scale, a reviewed
script is the safer, simpler choice.

1. Edit `RESULT` in `scripts/set-official-result.ts` (winner, runners-up,
   Top5/Top10 extras — all by participant ID).
2. Run `npx tsx scripts/set-official-result.ts` from a machine with
   `NEXT_PUBLIC_SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY` configured.
3. The script validates every participant ID and rejects duplicates or
   unknown IDs *before* writing anything (`validateOfficialResult()`).
4. Scoring activates immediately — no deploy needed, since the score is
   computed dynamically from the database.

## Public prediction page — new state

`/p/[publicId]` now conditionally renders a **FOUCH Score** section
(`src/components/scoring/FouchScore.tsx`) between the ranked prediction
and You vs The World, exactly when `getOfficialResult()` returns
non-null for that prediction's event + data_status. When it returns
null (no result yet), the page renders exactly as it did before Sprint
4 — this is strictly additive.

## Result Card

A second shareable card (`src/components/scoring/ResultCardMarkup.tsx`),
separate from the Sprint 2 Prediction Card, generated via the same
`next/og` `ImageResponse` infrastructure at `/p/[publicId]/result-card/{story,post}`.
Reuses `ShareActions` (extended with a `variant="result"` prop for
distinct analytics event names — the "prediction" variant's behavior
is unchanged) rather than a second sharing component. Uses text
country-code badges, not flag emoji — Satori/`next/og` doesn't render
Unicode flag emoji reliably (confirmed in Sprint 2), and this keeps the
Result Card consistent with the existing Prediction Card's approach.

## Tests

`src/lib/scoring.test.ts` — 31 tests, all passing:
- Reproduces the research's headline cases exactly (perfect call = 100,
  winner-only ≈ 44.33, great-field-wrong-winner ≈ 55.67 and must exceed
  winner-only, the critical runner-up-at-#9 case ≈ 1.83, buried-podium
  ≈ 30.67, near-perfect ≈ 97).
- Score band boundaries, exact (0/39/40/59/60/74/75/89/90/100).
- Percentile: below-threshold, at-threshold, ties, zero population.
- `validateOfficialResult`: accepts well-formed results, rejects
  duplicates, unknown participants, and wrong-sized stage arrays.

Combined with the existing `community-comparison.test.ts` (36 tests),
the project has **67 passing tests**. None depend on live Supabase
data.

## Known limitations

- **Dynamic (non-persisted) scoring** re-runs the full eligible-
  predictions query on every page view. Fine at hundreds to low
  thousands of predictions per event; if a single event's prediction
  count grows much larger, persisting scores (with an explicit
  recompute-on-result-change step) is the natural next iteration —
  intentionally deferred rather than built preemptively.
- **No admin UI** for entering results — a reviewed script is the
  entire "result entry" surface for now, as scoped.
- The current event's participant roster (and therefore every score
  computed against it) is demo data. Nothing about the scoring engine
  itself is Miss-Universe-specific, but this sprint did not add a
  second event to prove that in practice.