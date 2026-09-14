# Fix: OTP length mismatch (project uses 8 digits, UI assumed 6) — applies changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File fix-otp-length.ps1
$failures = @()

try {
    $path = "src\components\prediction\OtpStep.tsx"
    $content = @'
"use client";

import { useEffect, useState } from "react";

/** Matches Supabase Auth's own default OTP resend cooldown, confirmed
 * in Phase B — never invent a different number here. */
const RESEND_COOLDOWN_SECONDS = 60;
/** Must match this project's actual configured "Email OTP length" in
 * Supabase (Authentication → Providers → Email) — confirmed as 8 in
 * this project, NOT the commonly-assumed 6. A mismatch here silently
 * truncates every real code and makes verification fail, misleadingly
 * reported as "expired" — a real bug found and fixed during Gate 1
 * manual testing, not a hypothetical. */
const OTP_LENGTH = 8;
/** UX guardrail only, not a security control — see
 * FOUCH_AUTH_FLOW.md's "Wrong code" state. Supabase Auth's own OTP
 * expiry/rate-limiting is the real protection. */
const MAX_UX_ATTEMPTS = 5;

export function OtpStep({
  email,
  submitting,
  errorMessage,
  wrongAttemptCount,
  onVerify,
  onResend,
  onUseDifferentEmail,
}: {
  email: string;
  submitting: boolean;
  errorMessage: string | null;
  wrongAttemptCount: number;
  onVerify: (code: string) => void;
  onResend: () => void;
  onUseDifferentEmail: () => void;
}) {
  const [code, setCode] = useState("");
  const [secondsLeft, setSecondsLeft] = useState(RESEND_COOLDOWN_SECONDS);

  useEffect(() => {
    if (secondsLeft <= 0) return;
    const timer = setInterval(() => setSecondsLeft((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(timer);
  }, [secondsLeft]);

  const lockedOut = wrongAttemptCount >= MAX_UX_ATTEMPTS;

  function handleResend() {
    setCode("");
    setSecondsLeft(RESEND_COOLDOWN_SECONDS);
    onResend();
  }

  return (
    <div className="mt-8 border-t border-border pt-6">
      <p className="font-display text-xl text-text-primary">Enter the code we sent to {email}.</p>

      <label className="mt-4 block">
        <span className="text-sm text-text-secondary">Verification code</span>
        <input
          type="text"
          inputMode="numeric"
          autoComplete="one-time-code"
          maxLength={OTP_LENGTH}
          value={code}
          onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, OTP_LENGTH))}
          disabled={lockedOut}
          className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-lg tracking-[0.3em] text-text-primary placeholder:text-text-muted focus:border-accent disabled:opacity-60"
        />
      </label>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert" aria-live="polite">
          {errorMessage}
        </p>
      ) : null}

      {lockedOut ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          Too many incorrect attempts. Request a new code.
        </p>
      ) : (
        <button
          type="button"
          disabled={submitting || code.length !== OTP_LENGTH}
          onClick={() => onVerify(code)}
          className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
        >
          {submitting ? "Verifying…" : "Verify and lock"}
        </button>
      )}

      <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm">
        {secondsLeft > 0 ? (
          <span className="text-text-muted">Resend code in 0:{String(secondsLeft).padStart(2, "0")}</span>
        ) : (
          <button type="button" onClick={handleResend} className="text-text-secondary underline hover:text-accent-strong">
            Resend code
          </button>
        )}
        <button type="button" onClick={onUseDifferentEmail} className="text-text-secondary underline hover:text-accent-strong">
          Use a different email
        </button>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\OtpStep.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\OtpStep.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\OtpStep.tsx"
}

try {
    $path = "src\components\prediction\EmailStep.tsx"
    $content = @'
"use client";

import { useState } from "react";

export function EmailStep({
  submitting,
  errorMessage,
  onSendCode,
}: {
  submitting: boolean;
  errorMessage: string | null;
  onSendCode: (email: string) => void;
}) {
  const [email, setEmail] = useState("");

  return (
    <div className="mt-8 border-t border-border pt-6">
      <p className="font-display text-xl text-text-primary">Enter your email to lock your prediction.</p>
      <p className="mt-1 text-sm text-text-secondary">We&apos;ll send you a verification code — no password needed.</p>

      <label className="mt-4 block">
        <span className="text-sm text-text-secondary">Email</span>
        <input
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          placeholder="you@example.com"
          autoComplete="email"
          className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
        />
      </label>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          {errorMessage}
        </p>
      ) : null}

      <button
        type="button"
        disabled={submitting || email.trim().length === 0}
        onClick={() => onSendCode(email)}
        className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
      >
        {submitting ? "Sending…" : "Send code"}
      </button>

      <p className="mt-3 text-xs text-text-muted">
        FOUCH is an independent fan prediction game — your email is only used to verify your call,
        never shown publicly.
      </p>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\EmailStep.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\EmailStep.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\EmailStep.tsx"
}

try {
    $path = "FOUCH_AUTH_FLOW.md"
    $content = @'
# FOUCH Auth Flow

*Every screen, state, and transition for the email-OTP lock flow.
Architecture only — no implementation yet.*

**v1.1**: clarifies that the wrong-code attempt counter is a UX
guardrail, not a security control (see the "Wrong code" state below),
and that OTP verification and the prediction insert are two sequential
facts, not one atomic database transaction (see "AUTH VERIFIED" vs
"PREDICTION LOCKED" below).
**Frozen**: after this ships, OTP verification is required for every
new final prediction — there is no anonymous locking path going
forward. Existing legacy anonymous predictions are unaffected.

## Design choice: one code input, not six boxes

The brief's phrasing ("auto advance," "paste support") implies the
common six-separate-box OTP UI. **Recommendation: use a single input**
(`inputmode="numeric"`, `autocomplete="one-time-code"`, `maxlength="6"`)
instead. This is simpler to build, trivially accessible (one label, one
field, normal tab order — no manual auto-advance JavaScript or ARIA
choreography), and is the modern standard: both iOS Safari and Android
Chrome recognize `autocomplete="one-time-code"` and offer to
autofill the code from an incoming SMS or email above the keyboard.
Paste support is automatic with a single field. This is a case of the
simpler solution being the better one, not a shortcut.

## Screen-by-screen flow

### 1. Email screen (replaces today's immediate submit)

Trigger: user clicks "Lock My Prediction" on the existing Review
screen (the Top 10 itself is unchanged, still held entirely in
`localStorage`/component state — nothing about the Builder or Review
screens changes).

```
Enter your email to lock your prediction.
We'll send you a verification code — no password needed.

[ email input ]
[ Send code ]

FOUCH is an independent fan prediction game — your email is only
used to verify your call, never shown publicly.
```

Action: `startEmailVerification(email)` → Supabase Auth
`signInWithOtp({ email })`.

- **Success** → advance to Code screen.
- **Network/server failure** → inline error, same retry pattern as
  Beta Hardening 0.1's submission fix: "We couldn't send your code —
  try again." Button re-enables, no data lost (Top 10 still local).

### 2. Code screen

```
Enter the code we sent to {email}.

[ ________ ]  (single numeric input, length matches this project's configured OTP length)

[ Verify and lock ]

Didn't get it? Resend code in 0:47
Use a different email
```

- The resend timer matches Supabase Auth's own enforced OTP-resend
  cooldown (do not invent a separate, possibly-mismatched countdown —
  see the migration plan's security notes for why).
- "Use a different email" returns to the Email screen — the Top 10
  draft is untouched (still local).

Action on submit: `verifyEmailAndLockPrediction(email, code,
predictionPayload)` — a single server action, but internally two
distinct facts, not one: **AUTH VERIFIED** (Supabase confirms the OTP
and issues a session) happens first, and **PREDICTION LOCKED** (the
row is actually inserted) is attempted immediately after, as the next
step. They normally happen seconds apart and feel like one motion to
the user — "Verify and lock" — but they are not the same database
fact, and a real (if rare) gap exists between them: see
`FOUCH_IDENTITY_ARCHITECTURE.md`'s "Verification and locking are two
facts, not one transaction" for what happens if the first succeeds and
the second transiently fails (short version: retry the lock step
directly, without a new OTP, since the session is already valid).

- **Wrong code** (not expired): *"That code didn't match. Check your
  email and try again."* Input clears, retry allowed. After 5 wrong
  attempts within one code's lifetime, show: *"Too many incorrect
  attempts. Request a new code."* and stop accepting further guesses
  against that specific code client-side.
  **v1.1 — this counter is a UX guardrail only, not a security
  control**: it lives in component state, so a refresh, a new tab, or
  incognito trivially resets it. The actual backend protection against
  brute-forcing a code is entirely Supabase Auth's own responsibility
  (OTP expiry + its built-in verification/rate-limit protections) —
  FOUCH does not build a custom server-side attempt-counter, add
  Redis, add a rate-limit table, or add a CAPTCHA for this. The
  client-side counter exists purely so a real user isn't left guessing
  indefinitely against an already-Supabase-protected endpoint; it
  contributes nothing to actual abuse resistance.
- **Expired code**: *"That code expired."* + an immediate, automatic
  fresh code request (or a clearly visible "Send a new code" button if
  auto-resend isn't desirable) — never leave the user staring at a
  dead end.
- **Verified, but this identity already has a final prediction for
  this event** (the hard rule firing): *"Looks like you've already
  made your call for this event."* + a direct link to their existing
  `/p/{public_id}` (looked up via the constraint-conflict path, same
  pattern as today's device_token duplicate handling). This is shown
  **only after** OTP succeeds — never before — see security notes on
  why revealing this earlier would be an email-enumeration risk.
- **Verified, no existing prediction** → immediately proceed to
  Success, then redirect.

### 3. Success (brief, transitional)

```
You're verified. Locking your prediction...
```

Shown only long enough to cover the final insert (typically under a
second) before redirecting to `/p/{publicId}?new=1` — the existing
public prediction page, completely unchanged.

## Additional states

**Verified, but the lock insert transiently fails** (network/database
blip *after* OTP already succeeded): *"We couldn't lock your
prediction — your Top 10 is still saved. Try again."* The retry calls
the lock step directly, reusing the already-valid Supabase session —
it does not send the user back to the Email screen or require a new
code. If the earlier attempt actually succeeded server-side but the
response was lost in transit, the retry resolves to the same
`public_id` via the unique-constraint-conflict path, never a duplicate.

**Browser refresh mid-flow** (on the Email or Code screen): since
nothing has touched FOUCH's database yet, a refresh loses only the
in-progress email/code UI state — exactly as a refresh today loses
in-progress Review-screen state. The Top 10 selections themselves
survive (still in `localStorage`). The user re-enters email and
requests a fresh code. This is an honest, disclosed limitation, not a
silent one.

**Mobile Safari specifics**: `autocomplete="one-time-code"` is
explicitly supported by Safari's QuickType bar for SMS; email-delivered
codes have more inconsistent OS-level autofill support across
platforms and versions — the single-input design degrades gracefully
either way (manual entry always works), so this isn't a hard
dependency, just a nice-to-have when the platform supports it.

**Accessibility**: single labelled input, standard tab order, error
messages associated with the input via `aria-describedby`, and errors
announced via an `aria-live` region so a screen-reader user hears
"that code didn't match" without needing to re-focus anything
manually.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_AUTH_FLOW.md"
} catch {
    Write-Host "FAILED: FOUCH_AUTH_FLOW.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_AUTH_FLOW.md"
}

try {
    $path = "FOUCH_BETA_HARDENING_02_PHASE_C.md"
    $content = @'
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

## Manual Pre-Cutover Test (founder, on a local/preview build only — never production yet)

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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_BETA_HARDENING_02_PHASE_C.md"
} catch {
    Write-Host "FAILED: FOUCH_BETA_HARDENING_02_PHASE_C.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_BETA_HARDENING_02_PHASE_C.md"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 4 files written successfully." -ForegroundColor Green
}