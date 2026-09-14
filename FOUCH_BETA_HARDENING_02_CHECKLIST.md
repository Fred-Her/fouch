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