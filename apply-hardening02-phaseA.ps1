# Beta Hardening 0.2 Phase A: identity schema foundation — applies all files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-hardening02-phaseA.ps1
$failures = @()

try {
    $path = "supabase\migrations\0005_identity_phase_a.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- Beta Hardening 0.2 — Phase A: additive identity schema foundation.
--
-- This migration changes NOTHING about current product behavior. It
-- only prepares the schema for verified identity, per the frozen
-- architecture (FOUCH_IDENTITY_ARCHITECTURE.md,
-- FOUCH_DATABASE_MIGRATION_PLAN.md). Application code is not wired to
-- this column yet — that's Phase C.
--
-- Explicitly NOT touched here: the existing
-- `predictions_event_device_unique` index on (event_slug,
-- device_token) — the current anonymous submission flow still depends
-- on it for duplicate protection, and it is only dropped in Phase C,
-- alongside the new OTP application code, per the frozen cutover
-- sequence. Also not touched: `predictions_public` (the view added in
-- Beta Hardening 0.1) — it continues to expose exactly its current 8
-- columns; `auth_user_id` is never added to it.

alter table predictions
  add column if not exists auth_user_id uuid references auth.users(id);

-- No ON DELETE behavior is specified here — this is intentionally the
-- Postgres/Supabase default (effectively "NO ACTION"), not a chosen
-- CASCADE or SET NULL. That means: attempting to delete an auth.users
-- row that still has predictions referencing it will fail with a
-- foreign-key-violation error, rather than silently deleting or
-- modifying those predictions. This satisfies "deleting an auth user
-- must not silently destroy prediction rows" without deciding the
-- actual deletion model (e.g. null out auth_user_id first, or some
-- other flow) — that decision is explicitly deferred to a later
-- phase, not made here.

-- Every existing row gets auth_user_id = NULL automatically (no
-- backfill is performed, none is needed) — legacy anonymous
-- predictions remain exactly what they are.

create unique index if not exists predictions_one_final_per_identity
  on predictions (event_slug, auth_user_id)
  where auth_user_id is not null and is_final = true;
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0005_identity_phase_a.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0005_identity_phase_a.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0005_identity_phase_a.sql"
}

try {
    $path = "FOUCH_BETA_HARDENING_02_PHASE_A.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# FOUCH Beta Hardening 0.2 — Phase A Implementation Note

*Additive database foundation only. No application behavior changed.
Verified against a real local Postgres instance running the actual,
unmodified project migrations — not just read for syntax.*

## Migration

**File**: `supabase/migrations/0005_identity_phase_a.sql`

**Changes**:
1. `alter table predictions add column if not exists auth_user_id uuid
   references auth.users(id);` — nullable, no default, no backfill.
2. `create unique index if not exists predictions_one_final_per_identity
   on predictions (event_slug, auth_user_id) where auth_user_id is not
   null and is_final = true;`

Nothing else. No other column, table, or view was touched.

## Identity Constraint

Exact rule, confirmed working against real Postgres:
`UNIQUE (event_slug, auth_user_id) WHERE auth_user_id IS NOT NULL AND
is_final = true`.

## Device Token Constraint

**Status: unchanged, confirmed active.** The existing
`predictions_event_device_unique` index on `(event_slug, device_token)`
— found to exactly match its documented definition, no discrepancy —
was not dropped, altered, renamed, or weakened. Verified directly: a
duplicate `(event_slug, device_token)` insert was rejected by this
exact constraint during testing, unchanged.

## Foreign Key Behavior

`auth_user_id` references `auth.users(id)` with Postgres/Supabase's
plain default (no `ON DELETE` clause specified — not `CASCADE`, not
`SET NULL`). **Verified directly**: attempting to delete an
`auth.users` row that still has predictions referencing it fails with
a foreign-key-violation error, and the referencing predictions remain
completely untouched. This satisfies "deleting an auth user must not
silently destroy prediction rows" without deciding the actual
deletion-model behavior (e.g. null the column first) — that decision
is deferred, not made here.

## Public View

**Status: unchanged.** `predictions_public` was not recreated (no
change was required). Confirmed by direct inspection of
`information_schema.columns`: exactly 8 columns — `id, public_id,
event_slug, nickname, country_code, data_status, submitted_at,
is_final`. Neither `auth_user_id` nor `device_token` is present.

## Legacy Predictions

**Status: unaffected, no backfill.** Every row inserted without an
explicit `auth_user_id` gets `NULL` automatically. Multiple `NULL`
rows for the same event coexist freely (the partial index's `WHERE
auth_user_id IS NOT NULL` clause means it never evaluates them).

## Tests

All of the following were run as real SQL against a local PostgreSQL
16 instance, using the project's actual, unmodified migration files
(`0002_predictions.sql`, `0004_predictions_public_view.sql`,
`0005_identity_phase_a.sql`) applied in sequence, plus a minimal
`auth.users` stub table (matching Supabase's own always-present `auth`
schema) — not a syntax read, not a mock:

| Case | Result |
|---|---|
| A. Legacy row, no `auth_user_id` | Inserted fine, `auth_user_id` is `NULL`, `is_final = true` |
| B. Duplicate `device_token` for the same event | **Rejected** by `predictions_event_device_unique` (unchanged, still active) |
| C. Same `auth_user_id`, same event, second final prediction | **Rejected** by `predictions_one_final_per_identity` |
| D. Same `auth_user_id`, different event | **Allowed** |
| E. Two different verified identities, same event, sharing a device (the Person A/Person B case) | **Both allowed** — the exact scenario the identity architecture was designed to fix |
| F. Multiple `NULL`-identity rows, same event | **Allowed** (3 confirmed coexisting) |
| G. `predictions_public` column list | Exactly the pre-existing 8 safe columns; `auth_user_id`/`device_token` absent |
| FK deletion safety | Deleting a referenced `auth.users` row **fails loudly**; predictions untouched |

**Full project regression suite**: typecheck clean, lint clean,
**111/111 tests passing** (identical count to before this migration —
no application code was touched, so no test count change was
expected), production build clean with an unchanged route list.

## Files Changed

- `supabase/migrations/0005_identity_phase_a.sql` (new)
- `FOUCH_BETA_HARDENING_02_PHASE_A.md` (this file, new)
- `FOUCH_BETA_HARDENING_02_CHECKLIST.md` (Phase A items marked complete only)

No application source file was modified.

## Manual Founder Steps

1. Open `supabase/migrations/0005_identity_phase_a.sql`, copy its
   contents.
2. Run it in Supabase's SQL Editor (same process as every previous
   migration).
3. Confirm the column exists: in the SQL Editor, `select
   column_name from information_schema.columns where table_name =
   'predictions' and column_name = 'auth_user_id';` should return one row.
4. Confirm the new index exists: `select indexname from pg_indexes
   where tablename = 'predictions' and indexname =
   'predictions_one_final_per_identity';` should return one row.
5. Confirm the old index is still there too: same query with
   `indexname = 'predictions_event_device_unique'` should also return
   one row.
6. Make one normal prediction through the existing, completely
   unchanged Lock flow — it should work exactly as it does today.

## Implementation Status

PHASE A: COMPLETE. Migration file created and verified against a real
Postgres instance running the project's actual migrations — not yet
applied to the founder's production Supabase project (that's manual
step 1-2 above).
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_BETA_HARDENING_02_PHASE_A.md"
} catch {
    Write-Host "FAILED: FOUCH_BETA_HARDENING_02_PHASE_A.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_BETA_HARDENING_02_PHASE_A.md"
}

try {
    $path = "FOUCH_BETA_HARDENING_02_CHECKLIST.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# FOUCH Beta Hardening 0.2 — Implementation Checklist

*For use only after the architecture in `FOUCH_IDENTITY_ARCHITECTURE.md`,
`FOUCH_AUTH_FLOW.md`, and `FOUCH_DATABASE_MIGRATION_PLAN.md` is
reviewed and approved. Nothing on this list has been built yet.*

**v1.1**: reflects the frozen `device_token`-drop sequencing (now
explicit Phase A / B / C checkpoints), the decision to skip
`posthog.alias()`, the wrong-code counter's UX-only framing, and the
verify-then-lock retry semantics for a transient post-verification
failure.

## Supabase configuration (do first — no code depends on this being
done in any particular order relative to the schema migration, but it
has the longest external lead time, e.g. SMTP provider setup)

- [ ] Enable Email OTP template (`{{ .Token }}`), not magic link
- [ ] Connect a custom SMTP provider (Resend/Postmark) — do not rely
      on Supabase's built-in sender at beta scale
- [ ] Set OTP expiry to ~10 minutes
- [ ] Note Supabase's actual OTP resend cooldown for the UI timer

## Sequencing checkpoints (Phase A / B / C — see `FOUCH_DATABASE_MIGRATION_PLAN.md`)

- [x] Phase A: additive `auth_user_id` migration ships **while the old
      `(event_slug, device_token)` unique constraint still exists** —
      the current anonymous submission path still depends on it.
      *(Migration file created and verified against a real local
      Postgres instance running the project's actual migrations — see
      `FOUCH_BETA_HARDENING_02_PHASE_A.md`. Not yet applied to the
      founder's production Supabase project; that's a manual step.)*
- [ ] Phase B: Supabase Auth (OTP template, SMTP, expiry, resend
      cooldown) configured and verified
- [ ] Phase C: cutover release deploys the new verified-lock code
- [ ] Phase C: old `(event_slug, device_token)` unique constraint is
      dropped in that same cutover release — not before, not
      meaningfully after
- [ ] A transient failure *after* OTP verification succeeds (insert
      fails) can be retried without losing the Top 10 draft and
      without requiring a new OTP (the session is already valid)
- [ ] A retry after an ambiguous insert outcome (response lost, write
      possibly succeeded) resolves safely to the existing `public_id`
      via the unique-constraint-conflict path — never a duplicate

## Schema

- [x] Add `auth_user_id uuid references auth.users(id)` (nullable) to
      `predictions` — *done in Phase A, see
      `FOUCH_BETA_HARDENING_02_PHASE_A.md`*
- [x] Add partial unique index `(event_slug, auth_user_id) where
      auth_user_id is not null and is_final = true`
- [x] Confirm `predictions_public` view is unchanged (still excludes
      `auth_user_id`, alongside `device_token`) — *verified in Phase A*

## Server actions

- [ ] `startEmailVerification(email)` — calls `signInWithOtp`, never
      reveals whether this email already has a prediction
- [ ] `verifyEmailAndLockPrediction(email, code, predictionPayload)` —
      verifies OTP, then inserts the prediction row with `auth_user_id`
      set, catching `23505` (unique violation on the new
      `auth_user_id` index) and returning the existing `public_id`
      instead of erroring — same pattern as the existing
      `device_token` conflict handling, now driven by verified
      identity instead
- [ ] Read-time check (not a constraint): if the new row's
      `device_token` matches an existing final prediction for the
      event under a *different* `auth_user_id`, fire
      `duplicate_prediction_attempt` — never block on this
- [ ] Client-side wrong-code counter (UX only — see "UI" below; not a
      security control, no server-side attempt-tracking is built)

## UI

- [ ] Email screen (single input, disclaimer line)
- [ ] Code screen (single `inputmode="numeric" autocomplete="one-time-code"`
      input, resend timer matched to Supabase's real cooldown)
- [ ] Success/redirect state
- [ ] Duplicate-identity screen (reuses the existing "already
      predicted" redirect pattern)
- [ ] Wrong-code / expired-code inline states — wrong-code counter is
      explicitly a UX guardrail ("too many incorrect attempts, request
      a new code"), not security; real protection is entirely
      Supabase Auth's own OTP expiry and rate limiting, nothing custom
      built server-side (no Redis, no rate-limit table, no CAPTCHA)
- [ ] "Use a different email" back-navigation, preserving the local
      Top 10 draft

## Analytics (PostHog)

- [ ] `verification_started`, `verification_sent`,
      `verification_completed`, `verification_failed`,
      `duplicate_prediction_attempt` — properties limited to
      `event_slug`, `data_status`, `failure_reason` (enum, never raw
      text); never email, `auth_user_id`, or `device_token`
- [ ] **No `posthog.alias()` call** — the beta's funnel metrics
      (landing → start → completion → verification → lock → community
      view → share → second visit) are all measurable on PostHog's
      existing anonymous `distinct_id` alone, since it already
      persists per-browser across visits; aliasing to `auth_user_id`
      would only add cross-device identity unification, which isn't a
      beta success metric — data-minimization wins by default
- [ ] Confirm `prediction_submitted` (existing event) still fires at
      final lock — no new, redundant "locked" event

## Privacy/Trust pages

- [ ] `/privacy` and `/terms` routes (minimal, beta-appropriate copy)
- [ ] Add both links to the existing `Footer` component
- [ ] "Independent fan prediction, not affiliated with Miss Universe"
      disclaimer on the Email screen specifically, in addition to the
      footer

## Tests (deterministic, no live Supabase dependency where avoidable)

- [ ] Fresh anonymous browse → build → OTP → lock succeeds
- [ ] Same email, second browser/incognito/device → hard rule →
      redirected to existing `public_id`
- [ ] Two near-simultaneous lock attempts, same email (race condition)
      → exactly one row created, both callers resolve to it
- [ ] Same email, second *different* event → succeeds normally
      (constraint is per-event)
- [ ] Wrong code → retry allowed → client-side UX counter kicks in
      after 5 attempts (confirmed as UX-only, not asserted as a
      security boundary)
- [ ] Expired code → resend → succeeds
- [ ] Two different verified identities on the *same* device
      (matching `device_token`) → both succeed; only
      `duplicate_prediction_attempt` fires, nothing is blocked
- [ ] Leaderboard/Score/You vs The World/Crowd Movement all produce
      correct results against a *mixed* population of legacy
      (`auth_user_id IS NULL`) and new verified rows in the same event
- [ ] Analytics properties never contain email/auth_user_id/device_token
      (and no `alias()` call is present anywhere in the analytics code)

## Regression (must still work, unchanged)

- [ ] Existing anonymous predictions (pre-migration) still resolve on
      their public pages
- [ ] Leaderboard ranking/ties unchanged
- [ ] FOUCH Score formula/bands unchanged
- [ ] You vs The World calculations unchanged
- [ ] Experiment 01 (Your Crowd Changed) unchanged
- [ ] Result Card / Prediction Card generation unchanged
- [ ] Demo/official isolation unchanged

## Explicitly not in this checklist

Profiles, account menus, login/logout UI, password auth, notifications,
creator pages, leagues, followers, AI predictions, Sprint 6 — all out
of scope, per the architecture brief.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_BETA_HARDENING_02_CHECKLIST.md"
} catch {
    Write-Host "FAILED: FOUCH_BETA_HARDENING_02_CHECKLIST.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_BETA_HARDENING_02_CHECKLIST.md"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 3 files written successfully." -ForegroundColor Green
}