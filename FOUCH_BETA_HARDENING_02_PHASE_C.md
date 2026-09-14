# FOUCH Beta Hardening 0.2 — Phase C: Verified Lock Cutover (Gate 1)

*Gate 1 only: the full verified-lock flow is implemented and tested in
the repository. Production has NOT been cut over — the old
`predictions_event_device_unique` constraint is still active in
production, and none of this code has been deployed. Gate 2 (the
actual cutover) requires explicit founder approval — see the end of
this document.*

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

**NOT performed.** Requires explicit founder approval for:
1. Deploying this verified-lock application code to production.
2. Applying `0006_identity_phase_c_cutover.sql` to production.
3. Both in the same controlled release window (per the frozen
   sequencing — see `FOUCH_DATABASE_MIGRATION_PLAN.md`).

Recommended cutover order once approved: verify Phase A schema present
→ verify Phase B Auth/SMTP still operational → deploy new code →
apply `0006` → immediate smoke test (steps 2-8 above, against
production) → done.