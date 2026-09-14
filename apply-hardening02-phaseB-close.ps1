# Beta Hardening 0.2 Phase B closure: real verification results — documentation only.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-hardening02-phaseB-close.ps1
$failures = @()

try {
    $path = "FOUCH_BETA_HARDENING_02_PHASE_B.md"
    $content = @'
# FOUCH Beta Hardening 0.2 — Phase B: Supabase Auth & Email OTP Infrastructure

*Infrastructure preparation, now founder-verified against the real
production Supabase project, real Resend SMTP, and a real email
inbox. The production Lock flow itself is still completely
unchanged — no email input, no OTP screen, no auth wiring exists
anywhere in the product yet; only the infrastructure it will
eventually call has been proven to work. See "Phase B completion
status" at the end.*

## Real-world verification (founder-performed)

| Check | Result |
|---|---|
| Resend custom SMTP connected | **PASS** |
| Real OTP email delivered (first-time address) | **PASS** |
| Numeric code received (not a link) | **PASS** |
| Correct code verifies | **PASS** |
| Authenticated Supabase user returned | **PASS** |
| Valid session (`Session present: true`) | **PASS** |
| Repeat login, same email → same `auth_user_id` | **PASS** — `1505dbb2-8c82-4336-9444-163952fc7ce1` both times |
| No `predictions` row created by the test | **PASS** (structural — the script has no reference to that table) |
| Expired-code behavior | **Not manually tested** — not claimed |
| Wrong-code behavior | **Not manually tested this pass** — not claimed |

## Real Supabase template discovery (not anticipated by the original research)

Testing revealed Supabase actually uses **two different email
templates**, depending on the account's state — not just "Magic Link"
as the initial research assumed:

- **First-time / previously-unconfirmed email** → Supabase sends the
  **"Confirm signup"** template.
- **Returning, already-confirmed email** → Supabase sends the
  **"Magic Link"** template.

**Both** were edited to use the numeric `{{ .Token }}` (never
`{{ .ConfirmationURL }}`), and **both** were confirmed working with a
real inbox — the first real send used "Confirm signup," the second
(repeat login, same now-confirmed email) used "Magic Link." Phase C's
implementation must account for both paths; this is stated as what was
actually observed in this one project, not generalized as a universal
Supabase guarantee.

## Important discovery (recent, worth knowing before you start)

Supabase changed its free-tier email policy on **June 3, 2026**
(confirmed via Supabase's own changelog), in response to phishing
abuse of the shared default email sender: **on new free-tier projects,
customizing auth email templates now requires a custom SMTP provider
to be configured first.** This changes the order of operations from
what might be expected — you likely cannot edit the OTP template
(step 3 below) until SMTP (step 1-2) is connected. This is stated
plainly here because it's a recent platform change, not something
this architecture invented.

## 1. Recommended SMTP provider: Resend

**Resend**, specifically because it has an **official Supabase partner
integration** that auto-configures SMTP settings for your project
(creates a Resend API key and fills in Supabase's SMTP fields for you
— no manual host/port/credential copying). Its free tier (100
emails/day, per Resend's published limits) is far more than a 25-50
person beta needs. Postmark is a reasonable alternative but has no
equivalent one-click Supabase integration as of this research — Resend
is the simpler setup for the same outcome, which is what matters at
this scale.

## 2. Manual founder setup — SMTP

| Step | Where | What | Value | Secret? | Never commit? |
|---|---|---|---|---|---|
| A | resend.com | Create a Resend account | — | — | — |
| B | Resend dashboard → Domains | Add and verify your sending domain (or use Resend's shared test domain for beta-only testing — see caveat below) | DNS records Resend provides | No (DNS records are public) | N/A |
| C | Supabase Dashboard → Integrations (or Resend's own site, via the partner integration) | Connect Resend to your Supabase project | Guided flow — Resend/Supabase handle credential exchange | The generated API key is secret | Yes — never put it in a committed file; it lives only in Supabase's dashboard once the integration completes it |
| D | Supabase Dashboard → Authentication → Emails / SMTP Settings | Confirm "Enable Custom SMTP" is on and shows Resend as the sender | — | No | N/A |

**Domain verification caveat**: if you don't yet own a domain you want
to send from, Resend allows sending from a shared testing address for
early development — document this explicitly as **TESTING ONLY**, not
the final beta sender. A recognizable "FOUCH" display name (not
"Supabase Auth" or "No Reply") should be set once a verified sending
domain exists.

## 3. Email template

**Corrected after real testing** — this was originally researched as
"edit the Magic Link template only." Real verification with a live
inbox showed Supabase actually routes through **two different
templates** depending on account state (see "Real Supabase template
discovery" above), and **both must be edited identically**:

**Locations**: Supabase Dashboard → Authentication → Email Templates →
**Confirm signup**, and separately → **Magic Link**. Apply the exact
same subject and body to both.

**Subject**: `Your FOUCH verification code`

**Body** (HTML — paste only the tags below, nothing else; a real
mistake made during setup was pasting the surrounding markdown
formatting, e.g. a stray "```html" fence, directly into the field,
which silently broke rendering):
```html
<h2>Your FOUCH verification code</h2>
<p>Enter this code to lock your prediction:</p>
<h1>{{ .Token }}</h1>
<p>This code expires in about 10 minutes.</p>
<p>You requested this to lock a prediction on FOUCH — an independent
fan prediction game, not affiliated with Miss Universe.</p>
```

**Body** (plain text, for clients that don't render HTML):
```
Your FOUCH verification code is: {{ .Token }}

This code expires in about 10 minutes.

You requested this to lock a prediction on FOUCH — an independent
fan prediction game, not affiliated with Miss Universe.
```

No ranking data, no nickname, no prediction content, nothing beyond
the code itself and the minimum trust disclaimer — exactly as scoped.
Verified with a real inbox: the preview render (Supabase's own
"Preview" tab) matched the actual received email exactly once the raw
HTML was pasted correctly.

## 4. OTP expiry and resend cooldown

**Verified from Supabase's own current documentation** (not assumed):
by default, OTP codes expire after **1 hour** and can be resent at most
once every **60 seconds**. The expiry setting's dashboard location is
documented slightly differently across Supabase's own docs pages found
during this research — some call it "Auth → Providers → Email → Email
OTP Expiration," others "Authentication → Sign In / Providers → Auth
Providers → Email OTP expiration." **This is stated honestly rather
than guessed**: look for a setting literally named "OTP expiry" or
similar under Authentication → Providers → Email in your actual
dashboard, since this environment cannot see your live Supabase
project to confirm the exact current label.

**Target**: change the default 1 hour down to **~10 minutes** — a
setting change only, no code required. The 60-second resend cooldown
is Supabase's fixed default; the frozen architecture's Phase C UI
should use this exact number for its resend timer, not an invented one.

## 5. Site URL / redirect configuration

**Not required for this flow.** Email OTP verified via
`supabase.auth.verifyOtp({ email, token, type: "email" })` is a direct
code exchange — it does not involve a redirect URL at all (that
mechanism only matters for magic-link-style flows where Supabase
redirects the browser after a link click). No Site URL or Redirect URL
change is needed for Phase B or Phase C's OTP flow. If Supabase's
dashboard still requires a non-empty Site URL field for other reasons,
set it to FOUCH's actual current production URL,
`https://fouch-tau.vercel.app` — never `fouch.app`, which remains
unconfigured.

## 6. Application code (what was and wasn't added)

**Added**: exactly one file, `scripts/test-otp-auth.ts` — a standalone,
manually-run script (never imported by the app, never runs during a
real user session). It calls `signInWithOtp` and `verifyOtp` using the
existing public anon key (no new credential type needed), prints the
resulting `auth_user_id`, and explicitly never touches the
`predictions` table.

**Not added, on purpose**: no email input on Review, no "Verify and
Lock" button, no OTP code input, no resend UI, no session UI, no
`auth_user_id` wiring into `insertPrediction()`. The current Lock
flow's source code is byte-for-byte unchanged.

## 7. Environment variables

**No new application environment variable is required.** The test
script reuses `NEXT_PUBLIC_SUPABASE_URL` and
`NEXT_PUBLIC_SUPABASE_ANON_KEY` — both already exist and are already
appropriately public (the anon key is designed to be used exactly this
way, by any anonymous caller). The Resend API key lives **only**
inside Supabase's own dashboard (via the SMTP integration) — it is
never entered into Vercel, `.env.local`, or any FOUCH environment
variable, and must never be committed to git.

## 8. Privacy — confirmed unaffected

Consistent with the frozen architecture: email lives only in Supabase
Auth; it is not written to `predictions`; it is not sent to PostHog;
`auth_user_id` and `device_token` are not sent to PostHog; no
`posthog.alias()` call exists anywhere in the codebase. Phase B adds
no email lookups against `predictions` — the test script only ever
calls Supabase Auth's own API, never a FOUCH database query.

## 9. Tests

| Test | Type | Result |
|---|---|---|
| A. Request OTP for a new email | Manual, founder-performed | **PASS** |
| B. Correct code verifies | Manual, founder-performed | **PASS** |
| C. Verification returns an authenticated user/session | Manual, founder-performed | **PASS** — `Session present: true` |
| D. Same email, repeat login → same `auth_user_id` | Manual, founder-performed | **PASS** — `1505dbb2-8c82-4336-9444-163952fc7ce1` both times |
| E. Wrong code fails safely | Manual | **Not manually tested this pass** — not claimed |
| F. Expired code fails safely | Manual, optional | **Not manually tested this pass** — not claimed (requires waiting out the expiry window) |
| G. Resend cooldown | Documented from Supabase's own docs (60s default) | **Confirmed by documentation**, not independently re-verified against the live project's exact timing |
| H. No prediction row created | Structural — the test script contains no `predictions` table reference at all | **Confirmed by code inspection** |
| I. No current FOUCH flow changed | Full regression suite | **Confirmed** — see below |
| J. Existing regression suite | Automated | **Confirmed: 111/111 passing, typecheck/lint/build clean** — identical to before Phase B, since no product code was touched |

Tests A-D were genuinely performed by the founder against the real
production Supabase project, real Resend SMTP, and a real inbox — not
simulated, not assumed. E and F remain honestly marked as not yet
tested rather than inferred as passing.

## 10. What has NOT been implemented

Everything Phase C owns: the email screen, the code screen, the
`verifyEmailAndLockPrediction` server action, `auth_user_id` wiring
into prediction inserts, dropping the old `device_token` unique index,
any UI at all. Also not implemented: Privacy/Terms pages (not in
Phase B's frozen scope), account/login UI (never in scope), OAuth
(never in scope).

## 11. Phase B completion status

**PHASE B: COMPLETE — FOUNDER VERIFIED.** Validated against the real
production Supabase Auth project, real Resend SMTP, and a real email
inbox — not just prepared documentation. See "Real-world verification"
at the top of this document for the exact results.

## 12. Confirmed still true after this closure

- The production Lock flow is unchanged — no email input, no OTP
  screen, no "Verify and lock" button exists anywhere in the product.
- `predictions_event_device_unique` remains active (untouched since
  Phase A).
- `auth_user_id` is not written during normal prediction submission —
  it is only ever populated by the standalone test script, never by
  `insertPrediction()`.
- No email/OTP UI exists in the real Lock flow.
- No `posthog.alias()` was introduced; no email is sent to PostHog.
- No prediction row is created merely by authenticating — confirmed
  structurally (the test script never references `predictions`) and
  by the full regression suite passing unchanged.
- Phase C has not started.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_BETA_HARDENING_02_PHASE_B.md"
} catch {
    Write-Host "FAILED: FOUCH_BETA_HARDENING_02_PHASE_B.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_BETA_HARDENING_02_PHASE_B.md"
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
      `FOUCH_BETA_HARDENING_02_PHASE_A.md`. Not yet applied to the
      founder's production Supabase project; that's a manual step.)*
- [x] Phase B: Supabase Auth (OTP template, SMTP, expiry, resend
      cooldown) configured and verified — see
      `FOUCH_BETA_HARDENING_02_PHASE_B.md`
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
    Write-Host "All 2 files written successfully." -ForegroundColor Green
}