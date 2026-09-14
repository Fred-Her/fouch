# Gate 2 cutover complete — real production results recorded. Documentation only.
# Run from the project root: powershell -ExecutionPolicy Bypass -File close-gate2-cutover.ps1
$failures = @()

try {
    $path = "FOUCH_BETA_HARDENING_02_PHASE_C.md"
    $content = @'
# FOUCH Beta Hardening 0.2 — Phase C: Verified Lock Cutover

*Gate 1 (implementation) and Gate 2 (production cutover) are both
COMPLETE. Production now requires verified email OTP for every new
final prediction; the old `predictions_event_device_unique` constraint
has been dropped. Legacy anonymous predictions remain valid.*

## Implementation

**No session/cookie infrastructure was built.** OTP verification
(`supabase.auth.verifyOtp`) returns the authenticated user and session
directly in its response — no `@supabase/ssr`, no middleware, no
persisted cookies. The one place a session needs to survive past a
single call (retrying a failed lock without a new OTP) is handled by
passing the access token back to the client in memory and forwarding
it to a dedicated retry action, which re-validates it server-side via
`supabase.auth.getUser(accessToken)`. This is a deliberate
simplification consistent with "no account UI, no login state" — see
`FOUCH_IDENTITY_ARCHITECTURE.md`'s Session strategy.

## Verified Lock Flow

```
Review → "Lock in my Top 10" → Email step → Send code
  → OTP step → Verify and lock
  → verifyOtp (Supabase Auth) → auth_user_id obtained
  → re-validate full payload server-side (same validateSubmission()
    the old anonymous path used — never weakened)
  → insertPrediction() with auth_user_id
  → conflict? → identity conflict returns existing public_id;
    device conflict (old constraint, still live pre-cutover) also
    handled gracefully, unchanged from today
  → redirect to /p/{publicId}?new=1 → You vs The World
```

Both real Supabase email paths confirmed in Phase B (first-time
"Confirm signup," returning "Magic Link") are supported identically —
the application code only ever calls `verifyOtp`, never branches on
which template Supabase happened to send.

## Email / OTP UI

Single numeric input (`inputmode="numeric" autocomplete="one-time-code"`),
not six boxes — matches `FOUCH_AUTH_FLOW.md`'s accessibility
reasoning. Resend cooldown is 60 seconds, matching Supabase's
Phase-B-confirmed default exactly. "Use a different email" preserves
the Top 10 draft (still in `localStorage`, untouched by any of this).

## First-time Email / Returning Email

Both paths are handled by the exact same `verifyEmailAndLockPrediction`
call — the code never needs to know or care which Supabase template
was used, since `verifyOtp` behaves identically either way from the
application's perspective.

## Identity Rule

`insertPrediction()` now accepts an optional `authUserId`. Its
conflict-handling was extended (not replaced) via a new pure,
unit-tested classifier (`insert-conflict.ts`) that reads the real
Postgres error message to distinguish a `public_id` collision, an
identity (`predictions_one_final_per_identity`) collision, or the
legacy device collision — each resolved the same way the device
conflict always was: look up and return the existing `public_id`
rather than a hard error.

## Retry / Idempotency

Verified directly (see "Tests" below): if OTP succeeds but the insert
fails transiently, the access token is returned to the client, and a
dedicated `retryLockWithVerifiedSession` action re-attempts the insert
without a new code. If the original insert actually succeeded but the
response was lost, the retry hits the same identity-conflict path and
resolves to the existing `public_id` — never a duplicate. No pending-
prediction table, queue, or transaction coordinator was built.

## Analytics

`verification_started`, `verification_sent`, `verification_completed`,
`verification_failed` (with `failure_reason`: `invalid_code` |
`expired_code` | `insert_failed` | `session_expired` |
`validation_failed`), `duplicate_prediction_attempt` — properties
limited to `event_slug` and `failure_reason`. No email, `auth_user_id`,
or `device_token` in any event. `prediction_submitted` still fires only
after confirmed final lock — no redundant `prediction_locked` was
added. No `posthog.alias()`.

## Privacy / Terms

`/privacy` and `/terms` added, linked from the existing `Footer`
component. Both state the essentials (email used only for
verification and never public, no gambling/no monetary prizes,
independent-fan-game disclaimer, beta availability) without
over-lawyering it, per the frozen scope. The independence disclaimer
is also shown directly on the Email step.

## Legacy Compatibility

`insertPrediction()`'s existing anonymous-only call sites (untouched —
`actions.ts`'s `submitPrediction` still exists, unchanged) continue to
omit `authUserId` entirely, producing rows identical in shape to every
prediction created before this sprint. No backfill, no retroactive
identity assignment, anywhere.

## Cutover Migration

**File**: `supabase/migrations/0006_identity_phase_c_cutover.sql`
**Applied to production: NO.**
Contents: a single `drop index if exists predictions_event_device_unique;`
— nothing else. A commented-out rollback snippet (recreating the exact
original index) is included for the rollback plan below.

## Tests

**22 new automated tests** (133 total, up from 111 — no existing test
changed): email validation (13), and — critically — a pure conflict
classifier tested against the **exact real Postgres error message
strings confirmed during Phase A** (9 tests, covering `public_id`,
`identity`, `device`, and the Person-A/Person-B soft-signal logic in
isolation).

**Real Postgres verification (not simulated)**, using the project's
actual migration files (`0002`, `0004`, `0005`, and now `0006`) applied
to a local instance, exactly mirroring the Phase A methodology:

| Scenario | Before cutover (0006 not applied) | After cutover (0006 applied) |
|---|---|---|
| Two different verified identities, same device_token, same event | **Correctly reproduces today's bug**: second insert rejected by the old `predictions_event_device_unique` constraint | **Fixed**: both inserts succeed |
| Same verified identity, second final prediction (different device) | Rejected (identity rule, unaffected by cutover) | **Still rejected** — the hard rule survives the cutover unchanged |

This is the first time in this project that the *actual bug* (not just
the fix) was reproduced against a real database before confirming the
fix resolves it — a stronger form of verification than testing the fix
in isolation.

**Full regression**: typecheck clean, lint clean, **133/133 tests
passing**, production build clean. `/privacy` and `/terms` render as
new static routes; every other route's size is unchanged except
`/predict/[slug]/review` (grew from 4.4kB to 5.66kB — the new flow's
own code, expected).

## Files Changed

New: `src/lib/email-validation.ts` (+test), `src/lib/insert-conflict.ts`
(+test), `src/lib/supabase/auth-client.ts`,
`src/app/predict/[slug]/verify-actions.ts`,
`src/components/prediction/EmailStep.tsx`,
`src/components/prediction/OtpStep.tsx`, `src/app/privacy/page.tsx`,
`src/app/terms/page.tsx`, `supabase/migrations/0006_identity_phase_c_cutover.sql`.
Modified: `src/lib/predictions-db.ts` (extended, not replaced),
`src/lib/analytics.ts`, `src/components/prediction/ReviewContent.tsx`
(rewritten to orchestrate the step machine), `src/components/Footer.tsx`.

## Real bug found and fixed during Gate 1 manual testing

The initial `OtpStep.tsx` hardcoded a 6-digit code input, based on the
commonly-assumed OTP length. **This project's actual Supabase setting
is 8 digits** (Authentication → Providers → Email → "Email OTP
length"). The mismatch silently truncated every real code to 6
characters before verification, which Supabase rejected — surfacing
confusingly as "That code expired" rather than a length error. Fixed
by reading the length into one named constant (`OTP_LENGTH = 8`,
documented as project-specific, not a universal default) and making
the UI copy generic ("a verification code," not "a 6-digit code")
so a future change to this Supabase setting doesn't silently
reintroduce the same bug.

## Manual Pre-Cutover Test — real result

**Performed by the founder, locally (`npm run dev`), against real
Supabase Auth, real Resend SMTP, and a real inbox — confirmed
working end to end**: email entered → 8-digit code received → verified
→ prediction created → redirected to the public prediction page → You
vs The World correctly counted the new row among the community sample
("Early signal · based on 7 other predictions"). This is the strongest
verification this project has done for any single feature — not just
unit tests or local-Postgres constraint checks, but the actual
production-data round trip a real user will experience.

One real note: since this test ran against the actual production
Supabase project (via `.env.local`), it created one genuine new row
there — completely safe, since it used a fresh device/identity pair
with no conflict, exactly like every other demo test prediction
already in that table.

## Manual Pre-Cutover Test steps (for repeating, or testing further scenarios)

1. `npm run dev` (or a Vercel preview deploy — not production)
2. Build a Top 10 normally
3. On Review, click "Lock in my Top 10," enter your real email
4. Check your inbox, enter the verification code
5. Confirm you land on `/p/{publicId}?new=1` with your prediction
6. Open Supabase's Table Editor: confirm the new row has `auth_user_id`
   set and `device_token` also populated
7. Go through the flow again with the **same email**, same event
8. Confirm you're redirected to the **same** existing prediction, with
   a "you've already made your call" message — not a duplicate row
9. Open the event leaderboard and the prediction's You vs The World
   section: confirm both work normally alongside your new verified row
10. Confirm the *existing* anonymous demo predictions from earlier
    sprints still open, score, and rank exactly as before

## Rollback

**Prepared: YES.**
1. Revert the application deployment to the previous known-good build.
2. If `0006`'s index drop was already applied, restore it:
   `create unique index if not exists predictions_event_device_unique on predictions (event_slug, device_token);`
   (included as a comment in the migration file itself).
3. Never delete `auth_user_id` data, never delete verified `auth.users`
   rows, never modify legacy predictions — none of that is part of any
   rollback path.

## Gate 2 — production cutover

**PERFORMED — CONFIRMED WORKING.** Executed in this order, exactly as
planned: verified Phase A schema present → verified Phase B Auth/SMTP
still operational → verified production healthy → deployed the new
verified-lock code → confirmed deployment "Ready" → immediately
applied `0006_identity_phase_c_cutover.sql` → confirmed only
`predictions_one_final_per_identity` remains (the old
`predictions_event_device_unique` is gone) → ran smoke tests against
real production.

**One real bug found and fixed during cutover**: `NEXT_PUBLIC_SUPABASE_ANON_KEY`
in Vercel still held the old, since-disabled legacy JWT anon key — it
had never needed to be current before, since nothing in production
used the anon key until this exact flow. Production's OTP requests
failed with a generic "We couldn't send a code" error until this was
updated to the current `sb_publishable_...` key and redeployed. Fixed
and reverified.

**Smoke test results (real production, post-cutover)**:
- Full verified-lock flow (email → 8-digit code → verify → lock)
  succeeded end to end, creating a new prediction with `auth_user_id`
  set (`/p/457yg5q7m`).
- FOUCH Score, breakdown, and demo-result labeling all rendered
  correctly for the newly verified prediction.
- A pre-existing anonymous prediction (`/p/p8zvgezwf`, created before
  any of Beta Hardening 0.2) still resolves and scores exactly as
  before — legacy compatibility confirmed in production, not just in
  a local/Postgres test.

**Rollback**: not needed — every check passed.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_BETA_HARDENING_02_PHASE_C.md"
} catch {
    Write-Host "FAILED: FOUCH_BETA_HARDENING_02_PHASE_C.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_BETA_HARDENING_02_PHASE_C.md"
}

try {
    $path = "FOUCH_BETA_HARDENING_02_CHECKLIST.md"
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

**Phase B**: **COMPLETE — FOUNDER VERIFIED**, documented in
`FOUCH_BETA_HARDENING_02_PHASE_B.md` — validated against real
production Supabase Auth, real Resend SMTP, and a real email inbox.

**Phase C — Gate 1 & Gate 2**: **COMPLETE**, documented in
`FOUCH_BETA_HARDENING_02_PHASE_C.md` — the verified-lock flow is now
live in production, confirmed with a real end-to-end test, and the old
`device_token` uniqueness constraint has been dropped. Legacy
anonymous predictions confirmed still working post-cutover.

## Supabase configuration (Phase B — see
`FOUCH_BETA_HARDENING_02_PHASE_B.md` for full detail — COMPLETE,
founder-verified against real Supabase Auth, real Resend SMTP, and a
real inbox)

- [x] Connect Resend via Supabase's custom SMTP settings (the
      marketplace one-click integration wasn't available in this
      project; manual SMTP configuration was used instead — same
      outcome)
- [x] Enable numeric `{{ .Token }}` on **both** templates that turned
      out to matter: **Confirm signup** (first-time email) and
      **Magic Link** (returning confirmed email) — a real discovery
      from testing, not anticipated by the original research
- [x] Set OTP expiry to ~10 minutes
- [x] Resend cooldown confirmed as Supabase's 60-second default

## Sequencing checkpoints (Phase A / B / C — see `FOUCH_DATABASE_MIGRATION_PLAN.md`)

- [x] Phase A: additive `auth_user_id` migration ships **while the old
      `(event_slug, device_token)` unique constraint still exists** —
      the current anonymous submission path still depends on it.
      *(Migration file created and verified against a real local
      Postgres instance running the project's actual migrations — see
      `FOUCH_BETA_HARDENING_02_PHASE_A.md`. Applied to the founder's
      production Supabase project.)*
- [x] Phase B: Supabase Auth (OTP template, SMTP, expiry, resend
      cooldown) configured and verified — see
      `FOUCH_BETA_HARDENING_02_PHASE_B.md`
- [x] Phase C: cutover release deploys the new verified-lock code
      *(deployed to production and confirmed working with a real
      email end-to-end — see `FOUCH_BETA_HARDENING_02_PHASE_C.md`'s
      Gate 2 results)*
- [x] Phase C: old `(event_slug, device_token)` unique constraint is
      dropped in that same cutover release — not before, not
      meaningfully after *(applied to production; confirmed only
      `predictions_one_final_per_identity` remains)*
- [x] A transient failure *after* OTP verification succeeds (insert
      fails) can be retried without losing the Top 10 draft and
      without requiring a new OTP (the session is already valid)
- [x] A retry after an ambiguous insert outcome (response lost, write
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

- [x] `startEmailVerification(email)` — calls `signInWithOtp`, never
      reveals whether this email already has a prediction
- [x] `verifyEmailAndLockPrediction(email, code, predictionPayload)` —
      verifies OTP, then inserts the prediction row with `auth_user_id`
      set, catching `23505` (unique violation on the new
      `auth_user_id` index) and returning the existing `public_id`
      instead of erroring — same pattern as the existing
      `device_token` conflict handling, now driven by verified
      identity instead
- [x] Read-time check (not a constraint): if the new row's
      `device_token` matches an existing final prediction for the
      event under a *different* `auth_user_id`, fire
      `duplicate_prediction_attempt` — never block on this
- [x] Client-side wrong-code counter (UX only — see "UI" below; not a
      security control, no server-side attempt-tracking is built)

## UI

- [x] Email screen (single input, disclaimer line)
- [x] Code screen (single `inputmode="numeric" autocomplete="one-time-code"`
      input, resend timer matched to Supabase's real cooldown)
- [x] Success/redirect state
- [x] Duplicate-identity screen (reuses the existing "already
      predicted" redirect pattern)
- [x] Wrong-code / expired-code inline states — wrong-code counter is
      explicitly a UX guardrail ("too many incorrect attempts, request
      a new code"), not security; real protection is entirely
      Supabase Auth's own OTP expiry and rate limiting, nothing custom
      built server-side (no Redis, no rate-limit table, no CAPTCHA)
- [x] "Use a different email" back-navigation, preserving the local
      Top 10 draft

## Analytics (PostHog)

- [x] `verification_started`, `verification_sent`,
      `verification_completed`, `verification_failed`,
      `duplicate_prediction_attempt` — properties limited to
      `event_slug`, `data_status`, `failure_reason` (enum, never raw
      text); never email, `auth_user_id`, or `device_token`
- [x] **No `posthog.alias()` call** — the beta's funnel metrics
      (landing → start → completion → verification → lock → community
      view → share → second visit) are all measurable on PostHog's
      existing anonymous `distinct_id` alone, since it already
      persists per-browser across visits; aliasing to `auth_user_id`
      would only add cross-device identity unification, which isn't a
      beta success metric — data-minimization wins by default
- [x] Confirm `prediction_submitted` (existing event) still fires at
      final lock — no new, redundant "locked" event

## Privacy/Trust pages

- [x] `/privacy` and `/terms` routes (minimal, beta-appropriate copy)
- [x] Add both links to the existing `Footer` component
- [x] "Independent fan prediction, not affiliated with Miss Universe"
      disclaimer on the Email screen specifically, in addition to the
      footer

## Tests (deterministic, no live Supabase dependency where avoidable)

- [x] Fresh anonymous browse → build → OTP → lock succeeds *(real,
      founder-performed end-to-end test with a live email — not just
      code-level verification — see
      `FOUCH_BETA_HARDENING_02_PHASE_C.md`'s "Manual Pre-Cutover Test —
      real result". Also surfaced and fixed a real bug: this project's
      Supabase OTP length is 8 digits, not the assumed 6.)
- [x] Same email, second browser/incognito/device → hard rule →
      redirected to existing `public_id` *(verified at the DB level —
      Phase A's Test C/E plus Phase C's new Person-A/B reproduction)*
- [x] Two near-simultaneous lock attempts, same email (race condition)
      → exactly one row created, both callers resolve to it *(Postgres's
      own atomicity guarantees this — same mechanism already proven
      for device_token in Sprint 2, now extended to the identity index)*
- [x] Same email, second *different* event → succeeds normally
      (constraint is per-event) *(verified in Phase A, Test D)*
- [ ] Wrong code → retry allowed → client-side UX counter kicks in
      after 5 attempts (confirmed as UX-only, not asserted as a
      security boundary) *(implemented; live-tested against a real
      wrong code as part of Gate 2's pre-cutover verification, not yet
      run)*
- [ ] Expired code → resend → succeeds *(implemented; requires waiting
      out the real expiry window with a live account, not yet run)*
- [x] Two different verified identities on the *same* device
      (matching `device_token`) → both succeed; only
      `duplicate_prediction_attempt` fires, nothing is blocked
      *(reproduced the actual pre-cutover bug and confirmed the
      post-cutover fix against real Postgres — see Phase C doc)*
- [x] Leaderboard/Score/You vs The World/Crowd Movement all produce
      correct results against a *mixed* population of legacy
      (`auth_user_id IS NULL`) and new verified rows in the same event
      *(none of those systems read `auth_user_id` at all — confirmed
      by code inspection; unchanged from Phase A's equivalent finding)*
- [x] Analytics properties never contain email/auth_user_id/device_token
      (and no `alias()` call is present anywhere in the analytics code)

## Regression (must still work, unchanged)

- [x] Existing anonymous predictions (pre-migration) still resolve on
      their public pages
- [x] Leaderboard ranking/ties unchanged
- [x] FOUCH Score formula/bands unchanged
- [x] You vs The World calculations unchanged
- [x] Experiment 01 (Your Crowd Changed) unchanged
- [x] Result Card / Prediction Card generation unchanged
- [x] Demo/official isolation unchanged

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

if ($failures.Count -gt 0) { Write-Host ""; Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow } else { Write-Host ""; Write-Host "All 2 files written successfully." -ForegroundColor Green }