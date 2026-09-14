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