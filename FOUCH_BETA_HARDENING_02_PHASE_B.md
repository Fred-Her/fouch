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