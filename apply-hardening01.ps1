# Beta Hardening 0.1: Observability & Security — applies all changed files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-hardening01.ps1
$failures = @()

# Dead code removal (Beta Hardening 0.1 Part D): zero imports anywhere,
# confirmed by grep before removal.
try {
    if (Test-Path -LiteralPath "src\lib\supabase\client.ts") {
        Remove-Item -LiteralPath "src\lib\supabase\client.ts" -Force
        Write-Host "REMOVED: src\lib\supabase\client.ts (dead code, zero usages)"
    } else {
        Write-Host "SKIP:    src\lib\supabase\client.ts already absent"
    }
} catch {
    Write-Host "FAILED to remove src\lib\supabase\client.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "remove client.ts"
}

try {
    $path = "package.json"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
{
  "name": "fouch",
  "version": "0.1.0",
  "private": true,
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint",
    "test": "vitest run"
  },
  "dependencies": {
    "@supabase/supabase-js": "^2.115.0",
    "country-flag-icons": "^1.6.20",
    "lucide-react": "^1.41.0",
    "nanoid": "^6.0.1",
    "next": "^15.5.25",
    "posthog-js": "^1.430.3",
    "react": "19.0.0",
    "react-dom": "19.0.0",
    "server-only": "^0.0.1"
  },
  "devDependencies": {
    "@eslint/eslintrc": "^3.3.7",
    "@types/node": "^22.20.2",
    "@types/react": "19.0.7",
    "@types/react-dom": "19.0.3",
    "autoprefixer": "10.4.20",
    "eslint": "9.18.0",
    "eslint-config-next": "15.1.6",
    "jsdom": "^30.0.1",
    "postcss": "8.5.1",
    "tailwindcss": "3.4.17",
    "typescript": "5.7.3",
    "vitest": "^5.0.0"
  }
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     package.json"
} catch {
    Write-Host "FAILED: package.json -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "package.json"
}

try {
    $path = "src\lib\attribution.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Beta Hardening 0.1 — minimal attribution. Captures ONLY `utm_source`,
 * persisted via sessionStorage so it survives the same browser session
 * from landing through submission, without a database column or an
 * attribution table. Answers exactly one question: "where did our
 * first beta users come from?" — nothing more.
 */

const STORAGE_KEY = "fouch:utm_source";
const MAX_LENGTH = 50;

function sanitize(raw: string): string | null {
  const trimmed = raw.slice(0, MAX_LENGTH).replace(/[^a-zA-Z0-9_-]/g, "");
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Call on any page. If the current URL has a `utm_source`, captures and
 * persists it (overwriting any previously stored value — first touch
 * within a session is not specially protected, which is fine for a
 * beta-scale "where did they come from" question). Otherwise returns
 * whatever was previously captured this session, or null if there
 * isn't one (organic/direct traffic — never fabricated as "direct").
 */
export function captureUtmSource(): string | null {
  if (typeof window === "undefined") return null;

  try {
    const params = new URLSearchParams(window.location.search);
    const raw = params.get("utm_source");
    if (raw) {
      const clean = sanitize(raw);
      if (clean) {
        window.sessionStorage.setItem(STORAGE_KEY, clean);
        return clean;
      }
    }
    return window.sessionStorage.getItem(STORAGE_KEY);
  } catch {
    // sessionStorage unavailable (private browsing, disabled) — no
    // attribution for this session, not a crash.
    return null;
  }
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\attribution.ts"
} catch {
    Write-Host "FAILED: src\lib\attribution.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\attribution.ts"
}

try {
    $path = "src\lib\attribution.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect, beforeEach } from "vitest";
import { captureUtmSource } from "./attribution";

function setUrl(search: string) {
  window.history.pushState({}, "", `/${search}`);
}

describe("captureUtmSource", () => {
  beforeEach(() => {
    window.sessionStorage.clear();
    setUrl("");
  });

  it("captures a simple source (reddit)", () => {
    setUrl("?utm_source=reddit");
    expect(captureUtmSource()).toBe("reddit");
  });

  it("captures another simple source (instagram)", () => {
    setUrl("?utm_source=instagram");
    expect(captureUtmSource()).toBe("instagram");
  });

  it("returns null with no utm_source and nothing previously captured", () => {
    setUrl("");
    expect(captureUtmSource()).toBeNull();
  });

  it("persists across calls within the same session even after the param is gone", () => {
    setUrl("?utm_source=missosology");
    expect(captureUtmSource()).toBe("missosology");
    setUrl(""); // simulate navigating to a page with no query string
    expect(captureUtmSource()).toBe("missosology");
  });

  it("sanitizes an overly long source by truncating", () => {
    const long = "a".repeat(200);
    setUrl(`?utm_source=${long}`);
    const result = captureUtmSource();
    expect(result).not.toBeNull();
    expect(result!.length).toBeLessThanOrEqual(50);
  });

  it("sanitizes malformed characters out of the source", () => {
    setUrl(`?utm_source=${encodeURIComponent("<script>alert(1)</script>")}`);
    const result = captureUtmSource();
    expect(result).not.toContain("<");
    expect(result).not.toContain(">");
  });

  it("a new utm_source overwrites a previously captured one", () => {
    setUrl("?utm_source=reddit");
    captureUtmSource();
    setUrl("?utm_source=creator");
    expect(captureUtmSource()).toBe("creator");
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\attribution.test.ts"
} catch {
    Write-Host "FAILED: src\lib\attribution.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\attribution.test.ts"
}

try {
    $path = "src\lib\analytics.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect, vi, afterEach } from "vitest";

describe("track() — Beta Hardening 0.1: analytics must never break the product", () => {
  const originalKey = process.env.NEXT_PUBLIC_POSTHOG_KEY;

  afterEach(() => {
    if (originalKey === undefined) delete process.env.NEXT_PUBLIC_POSTHOG_KEY;
    else process.env.NEXT_PUBLIC_POSTHOG_KEY = originalKey;
    vi.resetModules();
    vi.restoreAllMocks();
  });

  it("does not throw when no PostHog key is configured (falls back silently)", async () => {
    delete process.env.NEXT_PUBLIC_POSTHOG_KEY;
    vi.resetModules();
    const { track } = await import("./analytics");
    const debugSpy = vi.spyOn(console, "debug").mockImplementation(() => {});

    expect(() => track("landing_view", { utm_source: "reddit" })).not.toThrow();
    expect(debugSpy).toHaveBeenCalledWith("[fouch:analytics]", "landing_view", { utm_source: "reddit" });
  });

  it("does not throw even if posthog.init itself throws", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    vi.doMock("posthog-js", () => ({
      default: {
        init: () => {
          throw new Error("network unavailable");
        },
        capture: vi.fn(),
      },
    }));
    const { track } = await import("./analytics");

    expect(() => track("prediction_submitted", { event_slug: "miss-universe-2026" })).not.toThrow();
  });

  it("does not throw even if posthog.capture itself throws (ad blocker, etc.)", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    vi.doMock("posthog-js", () => ({
      default: {
        init: vi.fn(),
        capture: () => {
          throw new Error("blocked by client");
        },
      },
    }));
    const { track } = await import("./analytics");

    expect(() => track("prediction_submitted", { event_slug: "miss-universe-2026" })).not.toThrow();
  });

  it("calls posthog.capture with the exact event name and properties when configured", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    const captureSpy = vi.fn();
    vi.doMock("posthog-js", () => ({
      default: { init: vi.fn(), capture: captureSpy },
    }));
    const { track } = await import("./analytics");

    track("score_viewed", { event_slug: "miss-universe-2026", score_band: "EXCELLENT" });

    expect(captureSpy).toHaveBeenCalledWith("score_viewed", {
      event_slug: "miss-universe-2026",
      score_band: "EXCELLENT",
    });
  });

  it("never calls posthog.identify — stays on anonymous distinct_id semantics", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    const identifySpy = vi.fn();
    vi.doMock("posthog-js", () => ({
      default: { init: vi.fn(), capture: vi.fn(), identify: identifySpy },
    }));
    const { track } = await import("./analytics");

    track("public_prediction_viewed", { event_slug: "miss-universe-2026" });

    expect(identifySpy).not.toHaveBeenCalled();
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\analytics.test.ts"
} catch {
    Write-Host "FAILED: src\lib\analytics.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\analytics.test.ts"
}

try {
    $path = "supabase\migrations\0004_predictions_public_view.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- Beta Hardening 0.1 — device_token confidentiality fix.
--
-- Root cause (found in the beta readiness audit): the `predictions`
-- table's public-read RLS policy was `using (true)` — row-level, which
-- Postgres RLS always is. It does not, and cannot, restrict which
-- COLUMNS are visible. That meant `device_token` (meant to be a
-- private anti-abuse signal, never a public field) was technically
-- readable by anyone holding the anon key, even though no current
-- application code takes that path (all real reads go through
-- server-side functions using the service-role key, which bypasses
-- RLS entirely and only ever forwards safe fields to the client — see
-- PredictionRecord in src/lib/predictions-db.ts, which has no
-- device_token field at all).
--
-- Fix: remove anon's SELECT policy on the base table, and replace it
-- with a column-restricted view containing only the fields the
-- product actually needs to be public. This doesn't change any
-- current behavior (nothing today queries the base table via the anon
-- key) — it closes the gap for good, structurally, rather than
-- relying on "nothing happens to import the browser client."
--
-- Mechanism: a Postgres view without `security_invoker` runs with its
-- OWNER's privileges when queried, not the querying role's — so this
-- view can still read the base table (RLS is bypassed for the view's
-- own internal query) while anon/authenticated are granted SELECT on
-- the view itself via a normal object-privilege grant, not RLS. Anon
-- querying the base table directly now gets nothing (no policy left);
-- anon querying predictions_public gets exactly the 8 safe columns
-- below, never device_token.

drop policy if exists "predictions are publicly readable" on predictions;

create or replace view predictions_public
as
select
  id,
  public_id,
  event_slug,
  nickname,
  country_code,
  data_status,
  submitted_at,
  is_final
from predictions;

grant select on predictions_public to anon, authenticated;

-- prediction_items and event_results were also reviewed: neither
-- contains anything sensitive (participant IDs, positions, published
-- result data), so their existing `using (true)` public-read policies
-- are correct as-is and are not changed here.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0004_predictions_public_view.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0004_predictions_public_view.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0004_predictions_public_view.sql"
}

try {
    $path = "FOUCH_BETA_HARDENING_01.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_BETA_HARDENING_01.md"
} catch {
    Write-Host "FAILED: FOUCH_BETA_HARDENING_01.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_BETA_HARDENING_01.md"
}

try {
    $path = "src\lib\analytics.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Analytics seam — Beta Hardening 0.1.
 *
 * Every call site still imports the same `track(event, properties)`
 * function as before; only the transport underneath changed, from a
 * console.debug stub to real PostHog capture. The contract is
 * unchanged on purpose so no component needed to be touched.
 *
 * Configuration (set in Vercel):
 *   NEXT_PUBLIC_POSTHOG_KEY  — PostHog project API key (public by
 *     design — PostHog's own docs confirm this key is meant to be
 *     browser-visible; it is not a secret).
 *   NEXT_PUBLIC_POSTHOG_HOST — defaults to https://us.i.posthog.com
 *     if unset; only needed for a self-hosted or EU-region instance.
 *
 * Without NEXT_PUBLIC_POSTHOG_KEY configured, track() falls back to
 * the original console.debug behavior — nothing crashes, nothing is
 * silently required. Analytics is always best-effort: every call is
 * wrapped so a PostHog failure (network, ad blocker, misconfiguration)
 * can never throw into product code. Prediction submission, sharing,
 * and every public page must keep working exactly the same whether or
 * not analytics succeeds.
 *
 * Properties must never carry personally identifiable information or
 * free-text nickname/contestant input — only structural values like
 * an event slug, a count, a position, or a share method. This function
 * also never calls posthog.identify() — every event stays on
 * PostHog's normal anonymous, cookie/localStorage-backed distinct_id.
 * Connecting anonymous activity to a verified identity is explicitly
 * deferred to Beta Hardening 0.2.
 */

import posthog from "posthog-js";

let posthogReady = false;

function ensurePostHogInitialized(): boolean {
  if (typeof window === "undefined") return false;

  const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;
  if (!key) return false;

  if (!posthogReady) {
    try {
      posthog.init(key, {
        api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST || "https://us.i.posthog.com",
        // Beta-appropriate defaults: no automatic pageview capture (we
        // fire explicit, typed events already, e.g. landing_view), and
        // no full "person" profile creation for anonymous beta traffic
        // — keeps this cheap and avoids modeling identity we haven't
        // decided on yet (that's Beta Hardening 0.2).
        capture_pageview: false,
        person_profiles: "identified_only",
      });
      posthogReady = true;
    } catch {
      return false;
    }
  }

  return true;
}

export type FouchAnalyticsEvent =
  | "landing_view"
  | "featured_event_clicked"
  | "start_prediction"
  | "participant_selected"
  | "participant_removed"
  | "prediction_reordered"
  | "prediction_completed"
  | "prediction_reviewed"
  | "prediction_submit_started"
  | "prediction_submitted"
  | "prediction_card_generated"
  | "share_clicked"
  | "native_share_opened"
  | "copy_link_clicked"
  | "image_downloaded"
  | "public_prediction_viewed"
  | "public_prediction_cta_clicked"
  | "you_vs_world_viewed"
  | "same_winner_viewed"
  | "top3_match_viewed"
  | "boldest_pick_viewed"
  | "community_top10_viewed"
  | "community_share_clicked"
  | "score_viewed"
  | "score_breakdown_viewed"
  | "percentile_viewed"
  | "result_card_generated"
  | "result_card_shared"
  | "result_card_saved"
  | "result_share_link_copied"
  | "leaderboard_viewed"
  | "leaderboard_row_clicked"
  | "own_rank_viewed"
  | "leaderboard_from_score_clicked"
  | "consensus_change_viewed";

export function track(event: FouchAnalyticsEvent, properties?: Record<string, unknown>) {
  if (typeof window === "undefined") return;

  try {
    if (ensurePostHogInitialized()) {
      posthog.capture(event, properties);
      return;
    }
  } catch {
    // Analytics must never break the product — fall through to the
    // silent/dev-visible fallback below rather than propagate.
  }

  // No PostHog key configured (or init/capture failed): preserve the
  // original, harmless console.debug behavior rather than losing
  // visibility entirely during local development or misconfiguration.
  console.debug("[fouch:analytics]", event, properties ?? {});
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\analytics.ts"
} catch {
    Write-Host "FAILED: src\lib\analytics.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\analytics.ts"
}

try {
    $path = "src\components\ViewTracker.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect } from "react";
import { track, type FouchAnalyticsEvent } from "@/lib/analytics";
import { captureUtmSource } from "@/lib/attribution";

/** Fires one analytics event on mount. Renders nothing. */
export function ViewTracker({ event }: { event: FouchAnalyticsEvent }) {
  useEffect(() => {
    const utmSource = captureUtmSource();
    track(event, utmSource ? { utm_source: utmSource } : undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\ViewTracker.tsx"
} catch {
    Write-Host "FAILED: src\components\ViewTracker.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\ViewTracker.tsx"
}

try {
    $path = "src\components\prediction\ReviewContent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { captureUtmSource } from "@/lib/attribution";
import { loadPrediction, clearPrediction } from "@/lib/prediction-storage";
import { getDeviceToken } from "@/lib/device-token";
import { checkExistingSubmission, submitPrediction } from "@/app/predict/[slug]/actions";
import type { Participant } from "@/types/participant";
import { SubmitPanel } from "./SubmitPanel";

export function ReviewContent({
  eventSlug,
  participants,
  requiredCount,
}: {
  eventSlug: string;
  participants: Participant[];
  requiredCount: number;
}) {
  const router = useRouter();
  const [rankedIds, setRankedIds] = useState<string[] | null>(null);
  const [checkingExisting, setCheckingExisting] = useState(true);
  const [submitting, setSubmitting] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    const validIds = new Set(participants.map((participant) => participant.id));
    setRankedIds(loadPrediction(eventSlug, validIds));

    // A submitted prediction is immutable — if this device already has
    // one for this event, go straight to it instead of showing the
    // submit form again.
    const deviceToken = getDeviceToken();
    checkExistingSubmission(eventSlug, deviceToken)
      .then((existing) => {
        if (existing) {
          router.replace(`/p/${existing.publicId}`);
          return;
        }
        setCheckingExisting(false);
      })
      .catch(() => setCheckingExisting(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const participantsById = new Map(participants.map((participant) => [participant.id, participant]));
  const ranked = (rankedIds ?? [])
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  useEffect(() => {
    if (rankedIds !== null && ranked.length >= requiredCount) {
      track("prediction_reviewed", { event_slug: eventSlug });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rankedIds]);

  async function handleSubmit(nickname: string, countryCode: string) {
    // Guard against a rapid double-click firing two submissions before
    // React re-renders the disabled button.
    if (submitting) return;

    setSubmitting(true);
    setErrorMessage(null);
    const utmSource = captureUtmSource();
    track("prediction_submit_started", { event_slug: eventSlug });

    let result;
    try {
      const deviceToken = getDeviceToken();
      result = await submitPrediction({
        eventSlug,
        participantIds: rankedIds ?? [],
        nickname: nickname.trim() || undefined,
        countryCode: countryCode || undefined,
        deviceToken,
      });
    } catch {
      // Network/server failure reaching the Server Action itself (not a
      // validation rejection — those return {success:false} normally,
      // handled below). The local Top 10 draft is untouched either way
      // (clearPrediction only runs on confirmed success, further down).
      setErrorMessage("We couldn't lock your prediction. Your Top 10 is still saved — try again.");
      setSubmitting(false);
      return;
    }

    if (!result.success) {
      setErrorMessage(result.error);
      setSubmitting(false);
      return;
    }

    // Fires only after confirmed success — never on a caught failure above.
    track("prediction_submitted", { event_slug: eventSlug, ...(utmSource ? { utm_source: utmSource } : {}) });
    clearPrediction(eventSlug);
    router.push(`/p/${result.publicId}?new=1`);
  }

  // Avoid a flash of the form before we know whether this device
  // already has a locked-in prediction.
  if (rankedIds === null || checkingExisting) return null;

  if (ranked.length < requiredCount) {
    return (
      <div>
        <p className="text-text-secondary">
          We don&apos;t have a complete prediction for this event yet on this device.
        </p>
        <Link
          href={`/predict/${eventSlug}`}
          className="mt-4 inline-flex items-center gap-2 rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
        >
          Build your Top {requiredCount}
        </Link>
      </div>
    );
  }

  return (
    <div>
      <ol className="space-y-1.5">
        {ranked.map((participant, index) => (
          <li
            key={participant.id}
            className="flex items-center gap-3 rounded border border-border bg-surface px-4 py-3"
          >
            <span className="font-display w-7 shrink-0 text-base text-accent-strong">
              {String(index + 1).padStart(2, "0")}
            </span>
            <CountryFlag countryCode={participant.countryCode} className="text-xl" />
            <span className="text-sm text-text-primary">{participant.displayName}</span>
          </li>
        ))}
      </ol>

      <Link
        href={`/predict/${eventSlug}`}
        className="mt-6 inline-flex items-center gap-2 rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
      >
        <Pencil className="h-4 w-4" aria-hidden />
        Edit my Top {requiredCount}
      </Link>

      <SubmitPanel
        requiredCount={requiredCount}
        submitting={submitting}
        errorMessage={errorMessage}
        onSubmit={handleSubmit}
      />
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ReviewContent.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ReviewContent.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ReviewContent.tsx"
}

try {
    $path = "vitest.config.mts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { defineConfig } from "vitest/config";

// Vitest doesn't read tsconfig "paths" automatically. Previous test
// files avoided this by only using relative imports; leaderboard.ts
// needs the project's standard "@/..." alias (src/lib/scoring), so
// this maps it the same way Next.js already does via tsconfig.json.
//
// environment: "jsdom" — Beta Hardening 0.1 added tests that touch
// `window`/`sessionStorage` (attribution.ts, analytics.ts). jsdom is a
// safe superset for the existing pure-Node tests too (scoring,
// leaderboard, community-comparison never reference window).
export default defineConfig({
  test: {
    environment: "jsdom",
  },
  resolve: {
    alias: {
      "@": new URL("./src", import.meta.url).pathname,
    },
  },
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     vitest.config.mts"
} catch {
    Write-Host "FAILED: vitest.config.mts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "vitest.config.mts"
}

try {
    $path = "README.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# Fouch

Fouch is a worldwide social entertainment-prediction platform. The core
loop is **Predict → Compete → Score → Share**. The initial wedge is
pageants, but the architecture and brand are deliberately
category-agnostic — future categories include Eurovision, the Oscars,
the Grammys, and other entertainment competitions.

This repository is currently at **Sprint 0 / Foundation**: the public
homepage and technical foundation, not the product itself.

## Stack

- [Next.js](https://nextjs.org) (App Router) + TypeScript
- [Tailwind CSS](https://tailwindcss.com)
- [Supabase](https://supabase.com) / PostgreSQL (prepared, not yet load-bearing — see below)
- [Vercel](https://vercel.com) for hosting

## Prerequisites

- Node.js 20+
- npm

## Local setup

```bash
npm install
cp .env.example .env.local   # fill in values if you have them — see below
npm run dev
```

Open http://localhost:3000.

**Nothing in `.env.local` is required to run Sprint 0.** The homepage
reads from a typed seed event in `src/lib/events.ts`, not from
Supabase, so the app runs with zero configuration.

## Environment variables

See `.env.example` for the full list. Summary:

| Variable | Required for Sprint 0? | Notes |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | No | Public Supabase project URL. |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | No | Public anon key, safe for the browser. |
| `SUPABASE_SERVICE_ROLE_KEY` | No | **Server-only.** Never prefix with `NEXT_PUBLIC_`. Only imported from `src/lib/supabase/server.ts`, which is marked `server-only`. |
| `NEXT_PUBLIC_SITE_URL` | No (has a fallback) | Used for absolute URLs in metadata, OG, sitemap, robots. |
| `NEXT_PUBLIC_POSTHOG_KEY` | No | PostHog project API key. Without it, analytics falls back to a harmless console.debug — see `src/lib/analytics.ts`. |
| `NEXT_PUBLIC_POSTHOG_HOST` | No | Defaults to `https://us.i.posthog.com`; only needed for a self-hosted or EU-region PostHog instance. |

## Supabase setup (when you're ready to use it)

1. Create a Supabase project.
2. Run the migration in `supabase/migrations/0001_init.sql` (via the
   Supabase SQL editor, or the Supabase CLI: `supabase db push`).
3. Copy the project URL and anon key into `.env.local`.

The `events` table this migration creates is **not yet read by the
app** — Sprint 0 intentionally uses static seed data so the homepage
has zero external dependencies. Swapping `src/lib/events.ts` for a
Supabase query is future work, and the function signatures
(`getFeaturedEvent`, `getEventBySlug`) are already shaped so that swap
doesn't touch any component.

## Commands

```bash
npm run dev        # local development
npm run lint        # ESLint
npx tsc --noEmit    # TypeScript check
npm run build       # production build
npm run start        # run the production build locally
```

## Deployment

Deployed on Vercel. Connect this repository in the Vercel dashboard
(or `vercel --prod` from the CLI) — no project-specific build
configuration is required beyond the environment variables above (all
optional for Sprint 0).

## Sprint 0 scope

**Built:**
- Next.js + TypeScript + Tailwind foundation
- Design tokens (background, surface, text hierarchy, border, accent,
  success, warning) in `src/app/globals.css`
- Homepage: nav, hero ("Make your call."), one honestly-represented
  featured event (Miss Universe 2026, real public date/venue — no
  fabricated prediction counts or popularity stats), "how it works"
- `/events/[slug]` — minimal, honest "coming soon" page for the
  featured event, so the CTA has somewhere real to go
- SEO foundation: metadata, OpenGraph image, Twitter card, robots.txt,
  sitemap.xml, generated favicon
- Category-agnostic `Event` type and seed data
- Supabase client scaffolding (browser + server) and one migration for
  `events` — not yet wired to the UI
- Analytics seam (`src/lib/analytics.ts`) with three event names
  defined, no provider installed yet
- i18n foundation: all UI copy lives in `src/content/{en,es,pt}.ts`
  behind a shared `Dictionary` type. **Only English is live** — es/pt
  are translated and structurally ready, not yet routed.

**Deliberately deferred (not built):**
Authentication, login/signup, user profiles, the Prediction Builder,
drag-and-drop ranking, the scoring engine, leaderboards, AI
predictions, private leagues, friend battles, badges, achievements,
notifications, payments, admin dashboard, real-time infrastructure,
the full Prediction Card sharing system, and regional/community
analytics. These are later sprints.

## Next recommended step

Sprint 1: build the Prediction Builder (Top 10 ranking flow) for the
featured event, with local-only state first and persistence to
Supabase second.
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     README.md"
} catch {
    Write-Host "FAILED: README.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "README.md"
}

# package.json specifically must never keep a BOM (Node's JSON.parse
# doesn't strip it) -- strip it immediately after writing, every time.
try {
    $pkgContent = Get-Content -LiteralPath "package.json" -Raw
    [System.IO.File]::WriteAllText("$PWD\package.json", $pkgContent, (New-Object System.Text.UTF8Encoding $false))
    Write-Host "OK:     package.json (BOM stripped)"
} catch {
    Write-Host "FAILED to strip BOM from package.json -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "package.json (BOM strip)"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) issue(s) found." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 11 files written successfully (plus 1 removed)." -ForegroundColor Green
}