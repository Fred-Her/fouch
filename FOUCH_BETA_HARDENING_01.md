# FOUCH Beta Hardening 0.1

*Closed-scope hardening pass, not a feature sprint. Identity/auth is
explicitly deferred to Beta Hardening 0.2 — nothing here touches it.*

## 1. Scope

Five areas only, per `FOUCH_BETA_READINESS_AUDIT.md` §3/§4: real
analytics, minimal `utm_source` attribution, service-role key hygiene,
`device_token` confidentiality, and submission error handling.

## 2. Analytics Before

`track()` called `console.debug` unconditionally behind a
`NEXT_PUBLIC_ANALYTICS_ENABLED` flag that was never set anywhere in the
codebase. Every event from every sprint was collected nowhere,
confirmed by direct code inspection, not assumed from documentation.

## 3. Analytics After

`track(event, properties)` — the exact same call signature every
component already used — now calls `posthog.capture()` when configured.
No call site was changed. Best-effort by construction: every path is
wrapped so a PostHog failure (missing key, network error, ad blocker,
`init()` or `capture()` throwing) falls back to the original harmless
`console.debug`, never propagates into product code. Verified with
dedicated tests (`analytics.test.ts`) that simulate each failure mode.

No `identify()` call is ever made — every event stays on PostHog's
normal anonymous, cookie/localStorage-backed `distinct_id`. Connecting
anonymous activity to a verified identity is Beta Hardening 0.2's
decision, not made here.

## 4. PostHog Configuration

Environment variables to set in Vercel:

| Variable | Required | Notes |
|---|---|---|
| `NEXT_PUBLIC_POSTHOG_KEY` | To enable analytics | PostHog project API key — public by design (PostHog's own docs confirm this), not a secret |
| `NEXT_PUBLIC_POSTHOG_HOST` | No | Defaults to `https://us.i.posthog.com`; only set for self-hosted/EU-region |

`capture_pageview: false` and `person_profiles: "identified_only"` are
set on init — FOUCH fires its own explicit, typed pageview-equivalent
events already (`landing_view`, etc.), and anonymous beta traffic
doesn't need full PostHog "person" profiles created for it.

## 5. UTM Source

`captureUtmSource()` (`src/lib/attribution.ts`) reads `?utm_source=` from
the URL, sanitizes it (alphanumeric/`-`/`_` only, 50-char max), and
persists it in `sessionStorage` — no database column, no attribution
table, per the audit's explicit "only enough to answer where the first
25 users came from" scope. Attached to `landing_view` (via
`ViewTracker`) and to `prediction_submitted` (via `ReviewContent`),
covering the two points the brief asked for. Missing source is `null`,
never fabricated as `"direct"`.

## 6. Service-Role Security

Verified: the service-role key is referenced only in server-only files
(`src/lib/supabase/server.ts`, `scripts/set-official-result.ts`), both
marked or structurally incapable of running client-side
(`import "server-only"` in the former). `.env.local`/`.env` are
gitignored (confirmed in `.gitignore`). A repository-wide search for
JWT-shaped strings and hardcoded credentials found none committed
anywhere. **This task did not rotate the key itself** — see §11 for the
exact manual steps required, since rotation needs the founder's own
Supabase dashboard access and must be coordinated with a Vercel
environment variable update to avoid an outage.

## 7. Device Token / RLS Fix

Root cause confirmed directly in `supabase/migrations/0002_predictions.sql`:
the public-read policy (`using (true)`) is row-level — Postgres RLS
always is — and doesn't distinguish `device_token` from safe columns.
Fix (`0004_predictions_public_view.sql`): the anon SELECT policy on the
base `predictions` table is removed entirely; a new `predictions_public`
view exposes exactly 8 safe columns (`id, public_id, event_slug,
nickname, country_code, data_status, submitted_at, is_final` — never
`device_token`), granted to `anon`/`authenticated`. This changes nothing
about current behavior: every existing read already goes through
server-side functions using the service-role key, which bypasses RLS
regardless — verified by re-running the full test suite and confirming
no query in `predictions-db.ts`, `leaderboard-service.ts`,
`scoring-service.ts`, or `consensus-change-service.ts` was touched.
`getSupabaseBrowserClient()` (confirmed zero imports anywhere) was
removed outright, per the audit's own removal criteria.

## 8. Submission Error Handling

`ReviewContent.tsx`'s `handleSubmit` now wraps the `submitPrediction()`
call in try/catch. On a genuine network/server failure (not a
validation rejection — those already returned `{success:false}` and
were already handled), the user sees: *"We couldn't lock your
prediction. Your Top 10 is still saved — try again."* — the submit
button correctly re-enables (`setSubmitting(false)`), and a guard
against a rapid double-click firing two submissions was added. The
existing same-device duplicate behavior (redirect to the existing
public prediction, handled entirely server-side inside
`insertPrediction`) was not touched and is unaffected. `prediction_submitted`
still fires only after confirmed success, never on a caught failure.

## 9. Tests

**17 new tests**, all passing, added to the existing 99: 5 in
`analytics.test.ts` (no-op without a key, survives `init()` throwing,
survives `capture()` throwing, calls through with exact event/properties
when configured, never calls `identify()`), 7 in `attribution.test.ts`
(reddit, instagram, missing source, persistence across navigation,
overly-long truncation, malformed-character sanitization, overwrite on
a new source). Total project: **111/111 passing**. A DOM test
environment (`jsdom`) was added to `vitest.config.mts` since these are
the project's first tests touching `window`/`sessionStorage` — confirmed
safe for every existing pure-logic test too by re-running the full suite.

## 10. Manual Verification

**Not performed** — this task does not have access to a live PostHog
project or Vercel's environment variable dashboard. Per the brief's own
§33, this is stated plainly rather than claimed: the code is ready and
tested against simulated PostHog success/failure, but an actual
end-to-end "open the app, submit, check the PostHog dashboard" pass has
not been run, and cannot be claimed as run.

## 11. Remaining Manual Founder Actions

1. Create (or use an existing) PostHog project, and set
   `NEXT_PUBLIC_POSTHOG_KEY` (and `NEXT_PUBLIC_POSTHOG_HOST` only if not
   using PostHog's default US cloud) in Vercel's environment variables.
2. Rotate the Supabase service-role key in the Supabase dashboard
   (Project Settings → API), then update `SUPABASE_SERVICE_ROLE_KEY` in
   both Vercel's environment variables and your local `.env.local`.
3. Run the new migration (`supabase/migrations/0004_predictions_public_view.sql`)
   in the Supabase SQL editor, the same way as every previous migration.
4. After deploying, manually walk the journey in §32 of the brief
   (Home with `?utm_source=beta_test` → predict → submit → public
   prediction → You vs The World → share) and confirm the events listed
   there actually appear in your PostHog project, with `utm_source:
   "beta_test"` present on `landing_view` and `prediction_submitted`.
5. Consider also rotating `NEXT_PUBLIC_SUPABASE_ANON_KEY` out of caution
   — it was also shared in this same development conversation, even
   though nothing in the app currently uses it client-side.

## 12. Explicit Non-Goals

No identity, authentication, OTP, OAuth, or one-prediction-per-human
logic was added — that remains entirely Beta Hardening 0.2. No Terms,
Privacy pages, custom domain, feedback system, or rate limiting were
added — all correctly out of scope per the brief. No product/scoring
logic (FOUCH Score, You vs The World, leaderboard ranking, Experiment
01 thresholds) was touched.