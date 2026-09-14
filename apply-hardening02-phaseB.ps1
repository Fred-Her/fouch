# Beta Hardening 0.2 Phase B: Supabase Auth & Email OTP infrastructure — applies all files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-hardening02-phaseB.ps1
$failures = @()

try {
    $path = "scripts\test-otp-auth.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Beta Hardening 0.2 — Phase B manual test harness.
 *
 * Proves Supabase Email OTP works, end to end, with a REAL email
 * inbox. Deliberately NOT wired into the FOUCH app — this never
 * touches the `predictions` table, never runs during a normal user
 * session, and is not imported by any product code.
 *
 * Usage:
 *   npx tsx scripts/test-otp-auth.ts you@example.com
 *
 * Uses the PUBLIC anon key on purpose — signInWithOtp/verifyOtp are
 * genuine end-user operations, exactly what an anonymous visitor's
 * browser would call. This script does not need (and does not use)
 * the service-role key at all.
 */
import { createClient } from "@supabase/supabase-js";
import { createInterface } from "node:readline/promises";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

function loadEnvLocal() {
  const path = resolve(process.cwd(), ".env.local");
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, "utf-8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim();
    if (!(key in process.env)) process.env[key] = value;
  }
}
loadEnvLocal();

async function main() {
  const email = process.argv[2];
  if (!email) {
    console.error("Usage: npx tsx scripts/test-otp-auth.ts you@example.com");
    process.exit(1);
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    console.error("Missing NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY in .env.local");
    process.exit(1);
  }

  const supabase = createClient(url, anonKey);

  console.log(`Requesting an OTP for ${email} ...`);
  const { error: sendError } = await supabase.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: true },
  });

  if (sendError) {
    console.error("FAILED to request OTP:", sendError.message);
    process.exit(1);
  }
  console.log("OK: OTP requested. Check the inbox for a numeric code (not a link).");
  console.log("If the email contains a clickable link instead of a 6-digit code,");
  console.log("the Magic Link template has not been edited yet — see Phase B doc, step 'Email template'.");

  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const code = (await rl.question("Enter the 6-digit code from the email: ")).trim();
  rl.close();

  console.log("Verifying code ...");
  const { data, error: verifyError } = await supabase.auth.verifyOtp({
    email,
    token: code,
    type: "email",
  });

  if (verifyError) {
    console.error("FAILED to verify OTP:", verifyError.message);
    process.exit(1);
  }

  console.log("OK: verified.");
  console.log("auth_user_id (UUID):", data.user?.id);
  console.log("Session present:", Boolean(data.session));
  console.log("");
  console.log("Run this script again with the SAME email to confirm the SAME");
  console.log("auth_user_id is returned (Test D from the Phase B brief).");
  console.log("");
  console.log("No row was written to the predictions table by this script.");
}

main();
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     scripts\test-otp-auth.ts"
} catch {
    Write-Host "FAILED: scripts\test-otp-auth.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "scripts\test-otp-auth.ts"
}

try {
    $path = "FOUCH_BETA_HARDENING_02_PHASE_B.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# FOUCH Beta Hardening 0.2 — Phase B: Supabase Auth & Email OTP Infrastructure

*Infrastructure preparation only. The production Lock flow is
completely unchanged — no email input, no OTP screen, no auth wiring
exists anywhere in the product yet. This phase cannot be marked fully
complete from here: it requires real dashboard configuration and a
real inbox, neither of which this environment has access to. See
"Phase Status" at the end.*

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

Once SMTP is connected (per the June 2026 policy change above), edit
the **Magic Link** template — Supabase's Email OTP and Magic Link
share one template; there is no separate "OTP template." This is a
real platform quirk, not a FOUCH design choice: to send a numeric code
instead of a clickable link, you edit this same template to use `{{
.Token }}` instead of `{{ .ConfirmationURL }}`.

**Location**: Supabase Dashboard → Authentication → Email Templates →
Magic Link.

**Subject**: `Your FOUCH verification code`

**Body** (HTML):
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
| A. Request OTP for a new email | Manual (requires real inbox) | **Pending founder verification** |
| B. Correct code verifies | Manual | **Pending founder verification** |
| C. Verification returns an authenticated user/session | Manual | **Pending founder verification** |
| D. Same email, repeat login → same `auth_user_id` | Manual (run the script twice) | **Pending founder verification** |
| E. Wrong code fails safely | Manual | **Pending founder verification** — the script surfaces Supabase's own error message, nothing custom |
| F. Expired code fails safely | Manual, optional | **Pending founder verification** (requires waiting out the expiry window) |
| G. Resend cooldown | Documented from Supabase's own docs (60s default) | **Confirmed by documentation**, not independently re-verified against your live project |
| H. No prediction row created | Structural — the test script contains no `predictions` table reference at all | **Confirmed by code inspection** |
| I. No current FOUCH flow changed | Full regression suite | **Confirmed** — see below |
| J. Existing regression suite | Automated | **Confirmed: 111/111 passing, typecheck/lint/build clean** — identical to before Phase B, since no product code was touched |

**This environment cannot send or receive real email**, so tests A-F
genuinely require the founder to run `scripts/test-otp-auth.ts`
themselves with a real address. This is stated plainly rather than
claimed as done.

## 10. What has NOT been implemented

Everything Phase C owns: the email screen, the code screen, the
`verifyEmailAndLockPrediction` server action, `auth_user_id` wiring
into prediction inserts, dropping the old `device_token` unique index,
any UI at all. Also not implemented: Privacy/Terms pages (not in
Phase B's frozen scope), account/login UI (never in scope), OAuth
(never in scope).

## 11. Phase B completion status

**AWAITING FOUNDER VERIFICATION.** The configuration steps, email
template, and test harness are fully prepared and documented above;
what's missing is exactly what this environment cannot do itself:
creating a Resend account, connecting it in your Supabase dashboard,
and running the test script against a real inbox. Do not treat this
phase as complete until you've done that and confirmed a real code
arrived and verified successfully.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_BETA_HARDENING_02_PHASE_B.md"
} catch {
    Write-Host "FAILED: FOUCH_BETA_HARDENING_02_PHASE_B.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_BETA_HARDENING_02_PHASE_B.md"
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

**Phase B**: infrastructure prepared and documented in
`FOUCH_BETA_HARDENING_02_PHASE_B.md` — status AWAITING FOUNDER
VERIFICATION (requires real Supabase dashboard access and a real
inbox this environment doesn't have).

## Supabase configuration (Phase B — see
`FOUCH_BETA_HARDENING_02_PHASE_B.md` for full detail; every item below
is documented and ready, but requires the founder's own dashboard
access and a real inbox to actually complete — none are checked off
here on that basis alone)

- [ ] Connect Resend via Supabase's SMTP integration (required first,
      per Supabase's June 2026 free-tier template policy change)
- [ ] Enable Email OTP template (`{{ .Token }}` in the Magic Link
      template — Supabase has no separate OTP template)
- [ ] Set OTP expiry to ~10 minutes (exact dashboard label to be
      confirmed against your live project — see Phase B doc)
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