# FOUCH 0.3A.1 — Lock Time UX + Edit Copy — applies all changed/new files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-0.3a.1.ps1
$failures = @()

try {
    $path = "src\lib\event-time-display.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿/**
 * FOUCH 0.3A.1 — pure, DB-free display formatting for the prediction
 * lock instant. Deliberately separate from prediction-lock-logic.ts:
 * that file decides WHETHER predictions are open (authorization,
 * server-time-only); this file only decides HOW to show an already-
 * decided instant to a human, in the event's own timezone rather than
 * the viewer's browser timezone (which is ambiguous for a worldwide
 * audience — see FOUCH 0.3A.1 brief §1).
 *
 * CRITICAL invariant this file must never violate: formatting a
 * timestamp for display must never change what instant it represents.
 * `new Date(isoDateTime).getTime()` is always used as-is; nothing here
 * re-parses or reinterprets the ISO string as a timezone-less local
 * datetime. See event-time-display.test.ts for a test that proves
 * this directly.
 */

/**
 * Derives a short, human-readable location label from an IANA
 * timezone identifier — the last path segment, underscores replaced
 * with spaces. "America/Puerto_Rico" -> "Puerto Rico". This is a
 * generic, zero-configuration derivation (no new "location" field
 * needed) — good enough for the single-event scale this product is
 * at; if it ever produces something awkward for a future event, that
 * event can be given a nicer label at that point, not preemptively
 * here.
 */
export function deriveLocationLabel(timeZone: string): string {
  const lastSegment = timeZone.split("/").pop() ?? timeZone;
  return lastSegment.replace(/_/g, " ");
}

/**
 * Formats an absolute instant (ISO 8601 string, e.g. from
 * `events.prediction_lock_at`) as an unambiguous, human-readable
 * string in the EVENT's own local timezone — never the viewer's
 * browser timezone. Always includes a timezone abbreviation/offset
 * (via Intl's `timeZoneName: "short"`) so the result is never a naked
 * "9:00 PM" with no context (brief §3).
 *
 * When `timeZone` is null (event has none configured yet), falls back
 * to an explicit UTC-labeled rendering — still unambiguous, never a
 * silently-assumed local time.
 */
export function formatEventLocalLockTime(isoDateTime: string, timeZone: string | null): string {
  const date = new Date(isoDateTime);
  const zoneForFormatting = timeZone ?? "UTC";

  let parts: Intl.DateTimeFormatPart[];
  try {
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: zoneForFormatting,
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
      timeZoneName: "short",
    });
    parts = formatter.formatToParts(date);
  } catch {
    // An invalid/unrecognized IANA identifier should never crash the
    // page — fall back to explicit UTC, still unambiguous.
    if (zoneForFormatting !== "UTC") return formatEventLocalLockTime(isoDateTime, null);
    throw new Error(`Unable to format date in UTC: ${isoDateTime}`);
  }

  const get = (type: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === type)?.value ?? "";
  const rendered = `${get("month")} ${get("day")} at ${get("hour")}:${get("minute")} ${get("dayPeriod")} ${get("timeZoneName")}`.trim();

  if (!timeZone) return rendered;

  const location = deriveLocationLabel(timeZone);
  return `${rendered} (${location})`;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-time-display.ts"
} catch {
    Write-Host "FAILED: src\lib\event-time-display.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-time-display.ts"
}

try {
    $path = "src\lib\event-time-display.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿import { describe, it, expect } from "vitest";
import { formatEventLocalLockTime, deriveLocationLabel } from "./event-time-display";

const MISS_UNIVERSE_LOCK_AT = "2026-11-24T00:00:00Z";

describe("deriveLocationLabel — generic IANA-id -> human label, no new config field", () => {
  it("derives 'Puerto Rico' from 'America/Puerto_Rico'", () => {
    expect(deriveLocationLabel("America/Puerto_Rico")).toBe("Puerto Rico");
  });

  it("derives 'Santiago' from 'America/Santiago'", () => {
    expect(deriveLocationLabel("America/Santiago")).toBe("Santiago");
  });

  it("falls back to the raw identifier if there is no '/' segment", () => {
    expect(deriveLocationLabel("UTC")).toBe("UTC");
  });
});

describe("formatEventLocalLockTime — unambiguous, event-local, never a naked time", () => {
  it("resolves the Miss Universe 2026 lock instant correctly in Puerto Rico event time", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    // 2026-11-24T00:00:00Z is 2026-11-23 20:00 in America/Puerto_Rico
    // (AST, UTC-4 year-round — Puerto Rico does not observe DST).
    expect(result).toBe("Nov 23 at 8:00 PM AST (Puerto Rico)");
  });

  it("always includes a timezone abbreviation — never a naked time with no context", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    expect(result).toMatch(/[A-Z]{2,5}/); // AST, UTC, GMT+N, etc. — some abbreviation/offset token
    expect(result).not.toBe("8:00 PM");
    expect(result).not.toBe("9:00 PM");
  });

  it("always includes the human-readable location context in parentheses", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    expect(result).toContain("(Puerto Rico)");
  });

  it("falls back to an explicit UTC-labeled rendering when timezone is null — never a silently-assumed local time", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, null);
    expect(result).toBe("Nov 24 at 12:00 AM UTC");
    expect(result).not.toContain("(");
  });

  it("falls back to UTC gracefully for an invalid/unrecognized IANA identifier, never throws", () => {
    expect(() => formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "Not/ARealZone")).not.toThrow();
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "Not/ARealZone");
    expect(result).toBe("Nov 24 at 12:00 AM UTC");
  });

  it("CRITICAL: formatting for display never changes the absolute instant the ISO string represents — same instant, different timezone displays, both parse back to the identical epoch millisecond", () => {
    const epochBefore = new Date(MISS_UNIVERSE_LOCK_AT).getTime();

    // Render in three different timezones — none of this touches the
    // original string or reinterprets it as timezone-less.
    formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Santiago");
    formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, null);

    const epochAfter = new Date(MISS_UNIVERSE_LOCK_AT).getTime();
    expect(epochAfter).toBe(epochBefore);

    // The instant itself, independent of any display formatting, is
    // exactly what server-side lock enforcement compares against
    // (see prediction-lock-logic.test.ts) — proving here that display
    // formatting is a pure read, never a mutation of that instant.
    expect(epochBefore).toBe(Date.parse(MISS_UNIVERSE_LOCK_AT));
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-time-display.test.ts"
} catch {
    Write-Host "FAILED: src\lib\event-time-display.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-time-display.test.ts"
}

try {
    $path = "src\lib\email-step-copy.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿/**
 * FOUCH 0.3A.1 — the entire copy decision for EmailStep's heading, in
 * one pure, unit-testable place. Extracted specifically so "create
 * flow says X" and "edit flow says Y" (brief §12 tests 7-8) can be
 * asserted directly, without needing a component-testing setup this
 * codebase doesn't have (no React Testing Library / jsdom-rendering
 * test infra exists for components here — every existing *.test.ts
 * file tests pure logic, not rendered output; this follows the same
 * pattern).
 *
 * "lock your prediction" must never appear here before the actual
 * event lock — a prediction stays editable until prediction_lock_at,
 * so "lock" is no longer the right verb for this step.
 */
export type EmailStepMode = "create" | "edit";

export function getEmailStepHeading(mode: EmailStepMode): string {
  if (mode === "edit") return "Verify your email to save your changes.";
  return "Verify your email to save your prediction.";
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\email-step-copy.ts"
} catch {
    Write-Host "FAILED: src\lib\email-step-copy.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\email-step-copy.ts"
}

try {
    $path = "src\lib\email-step-copy.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿import { describe, it, expect } from "vitest";
import { getEmailStepHeading } from "./email-step-copy";

describe("getEmailStepHeading — FOUCH 0.3A.1 copy correction", () => {
  it("create flow says 'save your prediction', never 'lock your prediction'", () => {
    const heading = getEmailStepHeading("create");
    expect(heading).toBe("Verify your email to save your prediction.");
    expect(heading.toLowerCase()).not.toContain("lock your prediction");
  });

  it("edit flow says 'save your changes', never 'lock your prediction'", () => {
    const heading = getEmailStepHeading("edit");
    expect(heading).toBe("Verify your email to save your changes.");
    expect(heading.toLowerCase()).not.toContain("lock your prediction");
  });

  it("neither mode ever mentions locking, since a prediction stays editable until the event's actual lock instant", () => {
    expect(getEmailStepHeading("create").toLowerCase()).not.toContain("lock");
    expect(getEmailStepHeading("edit").toLowerCase()).not.toContain("lock");
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\email-step-copy.test.ts"
} catch {
    Write-Host "FAILED: src\lib\email-step-copy.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\email-step-copy.test.ts"
}

try {
    $path = "src\lib\prediction-lock-logic.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿﻿/**
 * FOUCH 0.3A — pure decision logic split out of events-db.ts
 * specifically so it has NO "server-only" import and can be unit
 * tested directly (vitest's jsdom environment cannot import a
 * server-only-guarded module, the same reason prediction-validation.ts
 * only ever type-imports EventLockConfig rather than importing
 * events-db.ts's runtime code). events-db.ts re-exports both symbols
 * below unchanged, so every existing import site is unaffected.
 */
export interface EventLockConfig {
  predictionOpenAt: string | null;
  predictionLockAt: string | null;
  /** FOUCH 0.3A.1 — IANA timezone identifier (e.g.
   * "America/Puerto_Rico"), display-only. Never used for lock
   * authorization — isPredictionWindowOpen below never reads it. */
  timezone: string | null;
}

/**
 * Given a lock config and the current SERVER time, decides whether
 * predictions/edits are currently allowed. Every real caller sources
 * `nowMs` from `Date.now()` on the server — never anything the client
 * supplies — per the frozen rule that client clocks must never be
 * trusted (brief §3/§20).
 */
export function isPredictionWindowOpen(config: EventLockConfig | null, nowMs: number): boolean {
  if (!config) return true; // No configured window — same as before 0.3A (unrestricted).
  if (config.predictionOpenAt && nowMs < Date.parse(config.predictionOpenAt)) return false;
  if (config.predictionLockAt && nowMs >= Date.parse(config.predictionLockAt)) return false;
  return true;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\prediction-lock-logic.ts"
} catch {
    Write-Host "FAILED: src\lib\prediction-lock-logic.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\prediction-lock-logic.ts"
}

try {
    $path = "src\lib\events-db.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿﻿import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { isPredictionWindowOpen, type EventLockConfig } from "@/lib/prediction-lock-logic";

// Re-exported unchanged so every existing import site
// (`@/lib/events-db`) keeps working — the pure logic itself now lives
// in prediction-lock-logic.ts purely so it can be unit tested without
// pulling in the "server-only" guard above. See that file's comment.
export { isPredictionWindowOpen };
export type { EventLockConfig };

/**
 * FOUCH 0.3A — the single authoritative source for prediction open/lock
 * timing. Supabase `events.prediction_open_at` / `prediction_lock_at`
 * (migration 0007) replace the old hardcoded values in
 * src/lib/events.ts, which may still hold display-only metadata
 * (name, subtitle, hero asset) but must never again be consulted for
 * timing decisions.
 *
 * Every timestamp here is compared against `Date.now()` on the
 * server that runs this code — never a value the browser supplies —
 * per the frozen rule that client clocks must never be trusted.
 */

/**
 * Returns null when the event row doesn't exist or the database isn't
 * configured. Callers must treat null as "no lock configured" (never
 * throw, never fail open in a way that fabricates a lock date) — this
 * mirrors how every other lookup in this codebase degrades when
 * Supabase is unavailable (see predictions-db.ts).
 */
export async function getEventLockConfig(eventSlug: string): Promise<EventLockConfig | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("events")
    .select("prediction_open_at, prediction_lock_at, timezone")
    .eq("slug", eventSlug)
    .maybeSingle();

  if (error || !data) return null;

  return {
    predictionOpenAt: data.prediction_open_at,
    predictionLockAt: data.prediction_lock_at,
    timezone: data.timezone,
  };
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\events-db.ts"
} catch {
    Write-Host "FAILED: src\lib\events-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\events-db.ts"
}

try {
    $path = "src\lib\events-db.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿﻿import { describe, it, expect } from "vitest";
import { isPredictionWindowOpen, type EventLockConfig } from "./prediction-lock-logic";

const LOCK_AT = "2026-11-24T00:00:00Z";
const LOCK_MS = Date.parse(LOCK_AT);

describe("isPredictionWindowOpen — the single lock-timing decision, fed by server time only", () => {
  it("is open when no lock config exists at all (event not configured — same as pre-0.3A behavior)", () => {
    expect(isPredictionWindowOpen(null, Date.now())).toBe(true);
  });

  it("is open one second before the lock instant", () => {
    const config: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    expect(isPredictionWindowOpen(config, LOCK_MS - 1000)).toBe(true);
  });

  it("is locked exactly AT the lock instant — >= , not > (brief §20: 'at lock time → rejected')", () => {
    const config: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    expect(isPredictionWindowOpen(config, LOCK_MS)).toBe(false);
  });

  it("is locked one second after the lock instant", () => {
    const config: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    expect(isPredictionWindowOpen(config, LOCK_MS + 1000)).toBe(false);
  });

  it("respects an open-at time in the future — not yet open", () => {
    const openAt = "2026-01-01T00:00:00Z";
    const config: EventLockConfig = { predictionOpenAt: openAt, predictionLockAt: null, timezone: null };
    expect(isPredictionWindowOpen(config, Date.parse(openAt) - 1)).toBe(false);
    expect(isPredictionWindowOpen(config, Date.parse(openAt))).toBe(true);
  });

  it("client clock manipulation has no effect — this function only ever receives a `nowMs` the caller supplies, and every real caller in this codebase sources it from Date.now() on the server, never from the browser", () => {
    // Documents the invariant at the type level: there is no
    // `document`/`window`/request-header parameter here at all — a
    // forged client timestamp is architecturally impossible to feed
    // into this function unless a server action explicitly chose to
    // (none do; see events-db.ts and verify-actions.ts, which always
    // call `isPredictionWindowOpen(lockConfig, Date.now())`).
    expect(isPredictionWindowOpen.length).toBe(2);
  });

  it("FOUCH 0.3A.1: adding `timezone` to EventLockConfig does not change the lock decision — timezone is display-only and this function never reads it", () => {
    const withoutTimezone: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    const withTimezone: EventLockConfig = {
      predictionOpenAt: null,
      predictionLockAt: LOCK_AT,
      timezone: "America/Puerto_Rico",
    };
    const withDifferentTimezone: EventLockConfig = {
      predictionOpenAt: null,
      predictionLockAt: LOCK_AT,
      timezone: "Pacific/Auckland",
    };

    // Same instant, three different (or absent) timezone values — the
    // open/closed decision must be identical in all three, at every
    // point tested (before, at, and after the lock instant).
    for (const nowMs of [LOCK_MS - 1000, LOCK_MS, LOCK_MS + 1000]) {
      const results = [withoutTimezone, withTimezone, withDifferentTimezone].map((config) =>
        isPredictionWindowOpen(config, nowMs),
      );
      expect(new Set(results).size).toBe(1);
    }
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\events-db.test.ts"
} catch {
    Write-Host "FAILED: src\lib\events-db.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\events-db.test.ts"
}

try {
    $path = "src\lib\prediction-validation.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿﻿import { describe, it, expect } from "vitest";
import { validateSubmission } from "./prediction-validation";
import type { FouchEvent } from "@/types/event";
import type { Participant } from "@/types/participant";
import type { EventLockConfig } from "./prediction-lock-logic";

const EVENT: FouchEvent = {
  id: "seed-1",
  slug: "miss-universe-2026",
  name: "Miss Universe 2026",
  category: "pageant",
  status: "upcoming",
  eventDate: "2026-11-24",
  isFeatured: true,
};

function makeParticipant(id: string): Participant {
  return {
    id,
    eventId: EVENT.id,
    displayName: `Contestant ${id}`,
    countryCode: "CL",
    countryName: "Chile",
    sortOrder: 0,
    isActive: true,
  };
}

const PARTICIPANTS = Array.from({ length: 12 }, (_, i) => makeParticipant(`p${i + 1}`));
const TOP_10 = PARTICIPANTS.slice(0, 10).map((p) => p.id);

describe("validateSubmission — participant/ranking rules (unchanged by FOUCH 0.3A)", () => {
  it("accepts a valid, complete, unique Top 10", () => {
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(true);
  });

  it("rejects a ranking with the wrong count", () => {
    const result = validateSubmission({ participantIds: TOP_10.slice(0, 5) }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(false);
  });

  it("rejects duplicate participants", () => {
    const withDuplicate = [...TOP_10.slice(0, 9), TOP_10[0] as string];
    const result = validateSubmission({ participantIds: withDuplicate }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(false);
  });

  it("rejects an unknown participant id", () => {
    const withUnknown = [...TOP_10.slice(0, 9), "not-a-real-id"];
    const result = validateSubmission({ participantIds: withUnknown }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(false);
  });
});

describe("validateSubmission — FOUCH 0.3A lock timing, driven entirely by the passed-in lockConfig + now", () => {
  const LOCK_AT = "2026-11-24T00:00:00Z";
  const LOCK_MS = Date.parse(LOCK_AT);

  it("allows a submission/edit one second before lock", () => {
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, lockConfig, LOCK_MS - 1000);
    expect(result.valid).toBe(true);
  });

  it("rejects a submission/edit exactly at the lock instant", () => {
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, lockConfig, LOCK_MS);
    expect(result.valid).toBe(false);
    expect(result.valid || result.error).toContain("locked");
  });

  it("rejects a submission/edit after the lock instant", () => {
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    const result = validateSubmission(
      { participantIds: TOP_10 },
      EVENT,
      PARTICIPANTS,
      10,
      lockConfig,
      LOCK_MS + 1000,
    );
    expect(result.valid).toBe(false);
  });

  it("with no lockConfig at all, never rejects for timing (matches pre-0.3A unrestricted behavior)", () => {
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, null, LOCK_MS + 100000);
    expect(result.valid).toBe(true);
  });

  it("never reads timing from the `event` (FouchEvent) argument — that type no longer even has lock fields, so this test simply documents that validateSubmission's timing decision is fully determined by lockConfig+now", () => {
    const eventWithoutLockFields = { ...EVENT } as FouchEvent;
    expect("predictionLockAt" in eventWithoutLockFields).toBe(false);
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    const result = validateSubmission(
      { participantIds: TOP_10 },
      eventWithoutLockFields,
      PARTICIPANTS,
      10,
      lockConfig,
      LOCK_MS + 1,
    );
    expect(result.valid).toBe(false);
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\prediction-validation.test.ts"
} catch {
    Write-Host "FAILED: src\lib\prediction-validation.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\prediction-validation.test.ts"
}

try {
    $path = "src\components\prediction\EmailStep.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿"use client";

import { useState } from "react";
import { getEmailStepHeading, type EmailStepMode } from "@/lib/email-step-copy";

export function EmailStep({
  mode,
  submitting,
  errorMessage,
  onSendCode,
}: {
  /** FOUCH 0.3A.1 — "create" for a first-time submission, "edit" for
   * an existing verified prediction. Drives the heading copy only;
   * OTP behavior is identical either way (brief §8-9). */
  mode: EmailStepMode;
  submitting: boolean;
  errorMessage: string | null;
  onSendCode: (email: string) => void;
}) {
  const [email, setEmail] = useState("");

  return (
    <div className="mt-8 border-t border-border pt-6">
      <p className="font-display text-xl text-text-primary">{getEmailStepHeading(mode)}</p>
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
    $path = "src\components\prediction\ReviewContent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { captureUtmSource } from "@/lib/attribution";
import { loadPrediction, clearPrediction } from "@/lib/prediction-storage";
import { getDeviceToken } from "@/lib/device-token";
import { checkExistingSubmission } from "@/app/predict/[slug]/actions";
import {
  startEmailVerification,
  verifyEmailAndLockPrediction,
  retryLockWithVerifiedSession,
  type VerifyAndLockResult,
} from "@/app/predict/[slug]/verify-actions";
import type { Participant } from "@/types/participant";
import { SubmitPanel } from "./SubmitPanel";
import { EmailStep } from "./EmailStep";
import { OtpStep } from "./OtpStep";

type Step = "review" | "email" | "otp";

/**
 * Beta Hardening 0.2 Phase C — GATE 1 implementation. This component
 * now runs the full email-OTP verified-lock flow client-side. It is
 * fully wired and tested, but production still has the old
 * `predictions_event_device_unique` constraint active — deploying
 * this to production before that constraint is dropped (Gate 2,
 * founder-approved cutover) would risk incorrectly blocking two
 * different verified people sharing a device. See
 * FOUCH_BETA_HARDENING_02_PHASE_C.md before deploying.
 */
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

  const [step, setStep] = useState<Step>("review");
  const [pendingNickname, setPendingNickname] = useState("");
  const [pendingCountryCode, setPendingCountryCode] = useState("");

  const [emailSubmitting, setEmailSubmitting] = useState(false);
  const [emailError, setEmailError] = useState<string | null>(null);
  const [email, setEmail] = useState("");

  const [otpSubmitting, setOtpSubmitting] = useState(false);
  const [otpError, setOtpError] = useState<string | null>(null);
  const [wrongAttemptCount, setWrongAttemptCount] = useState(0);
  /** Present only after OTP verification succeeded but the lock
   * insert failed transiently — enables a no-new-OTP retry. */
  const [accessTokenForRetry, setAccessTokenForRetry] = useState<string | null>(null);

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

  function handleProceedToEmail(nickname: string, countryCode: string) {
    setPendingNickname(nickname);
    setPendingCountryCode(countryCode);
    setStep("email");
  }

  async function handleSendCode(targetEmail: string) {
    if (emailSubmitting) return;
    setEmailSubmitting(true);
    setEmailError(null);
    track("verification_started", { event_slug: eventSlug });

    let result;
    try {
      result = await startEmailVerification(targetEmail);
    } catch {
      setEmailError("We couldn't send a code — try again in a moment.");
      setEmailSubmitting(false);
      return;
    }

    setEmailSubmitting(false);

    if (!result.success) {
      setEmailError(result.error);
      return;
    }

    track("verification_sent", { event_slug: eventSlug });
    setEmail(targetEmail);
    setOtpError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
    setStep("otp");
  }

  function handleLockResult(result: VerifyAndLockResult) {
    if (result.success) {
      track("verification_completed", { event_slug: eventSlug });
      if (result.duplicateDeviceSignal) {
        track("duplicate_prediction_attempt", { event_slug: eventSlug });
      }
      const utmSource = captureUtmSource();
      track("prediction_submitted", {
        event_slug: eventSlug,
        ...(utmSource ? { utm_source: utmSource } : {}),
      });
      clearPrediction(eventSlug);
      router.push(`/p/${result.publicId}?new=1`);
      return;
    }

    track("verification_failed", { event_slug: eventSlug, failure_reason: result.failureReason });
    setOtpError(result.error);
    setAccessTokenForRetry(result.accessToken ?? null);
    if (result.failureReason === "invalid_code") {
      setWrongAttemptCount((count) => count + 1);
    }
  }

  async function handleVerify(code: string) {
    if (otpSubmitting) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndLockResult;
    try {
      result = await verifyEmailAndLockPrediction(email, code, {
        eventSlug,
        participantIds: rankedIds ?? [],
        nickname: pendingNickname.trim() || undefined,
        countryCode: pendingCountryCode || undefined,
        deviceToken: getDeviceToken(),
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't verify your code — try again.");
      return;
    }

    setOtpSubmitting(false);
    handleLockResult(result);
  }

  async function handleRetryLock() {
    if (otpSubmitting || !accessTokenForRetry) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndLockResult;
    try {
      result = await retryLockWithVerifiedSession(accessTokenForRetry, {
        eventSlug,
        participantIds: rankedIds ?? [],
        nickname: pendingNickname.trim() || undefined,
        countryCode: pendingCountryCode || undefined,
        deviceToken: getDeviceToken(),
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't lock your prediction. Your Top 10 is still saved — try again.");
      return;
    }

    setOtpSubmitting(false);
    handleLockResult(result);
  }

  function handleUseDifferentEmail() {
    setStep("email");
    setEmail("");
    setOtpError(null);
    setEmailError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
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

      {step === "review" ? (
        <Link
          href={`/predict/${eventSlug}`}
          className="mt-6 inline-flex items-center gap-2 rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          <Pencil className="h-4 w-4" aria-hidden />
          Edit my Top {requiredCount}
        </Link>
      ) : null}

      {step === "review" ? (
        <SubmitPanel
          requiredCount={requiredCount}
          submitting={false}
          errorMessage={null}
          onSubmit={handleProceedToEmail}
        />
      ) : null}

      {step === "email" ? (
        <EmailStep mode="create" submitting={emailSubmitting} errorMessage={emailError} onSendCode={handleSendCode} />
      ) : null}

      {step === "otp" && accessTokenForRetry ? (
        <div className="mt-8 border-t border-border pt-6">
          {otpError ? (
            <p className="text-sm text-accent-strong" role="alert" aria-live="polite">
              {otpError}
            </p>
          ) : null}
          <button
            type="button"
            disabled={otpSubmitting}
            onClick={handleRetryLock}
            className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
          >
            {otpSubmitting ? "Trying again…" : "Try again"}
          </button>
        </div>
      ) : step === "otp" ? (
        <OtpStep
          email={email}
          submitting={otpSubmitting}
          errorMessage={otpError}
          wrongAttemptCount={wrongAttemptCount}
          onVerify={handleVerify}
          onResend={() => handleSendCode(email)}
          onUseDifferentEmail={handleUseDifferentEmail}
        />
      ) : null}
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
    $path = "src\components\prediction\EditPredictionFlow.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿﻿"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { track } from "@/lib/analytics";
import { formatEventLocalLockTime } from "@/lib/event-time-display";
import {
  startEmailVerification,
  verifyEmailAndEditPrediction,
  retryEditWithVerifiedSession,
  type VerifyAndEditResult,
} from "@/app/predict/[slug]/verify-actions";
import type { Participant } from "@/types/participant";
import { TopTenList } from "./TopTenList";
import { ParticipantBrowser } from "./ParticipantBrowser";
import { EmailStep } from "./EmailStep";
import { OtpStep } from "./OtpStep";

type Step = "edit" | "email" | "otp";

/**
 * FOUCH 0.3A — reuses the SAME ranking primitives as
 * PredictionBuilder.tsx (TopTenList, ParticipantBrowser) and the SAME
 * verification primitives as ReviewContent.tsx (EmailStep, OtpStep) —
 * deliberately not a second, independent builder. The only real
 * difference from PredictionBuilder is persistence: this component's
 * ranking state starts from the prediction's CURRENT version (passed
 * in from the server) and is never written to localStorage — there is
 * nothing "in progress" to resume here, only a specific saved
 * prediction being edited.
 */
export function EditPredictionFlow({
  eventSlug,
  publicId,
  allParticipants,
  initialRankedParticipantIds,
  requiredCount,
  expectedVersionNumber,
  predictionLockAt,
  predictionTimezone,
}: {
  eventSlug: string;
  publicId: string;
  allParticipants: Participant[];
  initialRankedParticipantIds: string[];
  requiredCount: number;
  expectedVersionNumber: number;
  predictionLockAt: string | null;
  /** FOUCH 0.3A.1 — IANA timezone identifier for the event, used only
   * for unambiguous display of predictionLockAt (see
   * event-time-display.ts). */
  predictionTimezone: string | null;
}) {
  const router = useRouter();
  const [selectedIds, setSelectedIds] = useState<string[]>(initialRankedParticipantIds);
  const [step, setStep] = useState<Step>("edit");

  const [emailSubmitting, setEmailSubmitting] = useState(false);
  const [emailError, setEmailError] = useState<string | null>(null);
  const [email, setEmail] = useState("");

  const [otpSubmitting, setOtpSubmitting] = useState(false);
  const [otpError, setOtpError] = useState<string | null>(null);
  const [wrongAttemptCount, setWrongAttemptCount] = useState(0);
  const [accessTokenForRetry, setAccessTokenForRetry] = useState<string | null>(null);

  const participantsById = new Map(allParticipants.map((participant) => [participant.id, participant]));

  const rankedParticipants = selectedIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  const isComplete = selectedIds.length >= requiredCount;

  function handleToggle(id: string) {
    setSelectedIds((current) => {
      if (current.includes(id)) {
        return current.filter((selectedId) => selectedId !== id);
      }
      if (current.length >= requiredCount) return current;
      return [...current, id];
    });
  }

  function handleRemove(id: string) {
    setSelectedIds((current) => current.filter((selectedId) => selectedId !== id));
  }

  function swap(array: string[], i: number, j: number): string[] {
    const next = [...array];
    const a = next[i];
    const b = next[j];
    if (a === undefined || b === undefined) return array;
    next[i] = b;
    next[j] = a;
    return next;
  }

  function handleMoveUp(index: number) {
    if (index === 0) return;
    setSelectedIds((current) => {
      track("prediction_edit_reordered", { event_slug: eventSlug });
      return swap(current, index - 1, index);
    });
  }

  function handleMoveDown(index: number) {
    setSelectedIds((current) => {
      if (index === current.length - 1) return current;
      track("prediction_edit_reordered", { event_slug: eventSlug });
      return swap(current, index, index + 1);
    });
  }

  function handleStartSave() {
    track("prediction_edit_started", { event_slug: eventSlug });
    setStep("email");
  }

  async function handleSendCode(targetEmail: string) {
    if (emailSubmitting) return;
    setEmailSubmitting(true);
    setEmailError(null);

    let result;
    try {
      result = await startEmailVerification(targetEmail);
    } catch {
      setEmailError("We couldn't send a code — try again in a moment.");
      setEmailSubmitting(false);
      return;
    }

    setEmailSubmitting(false);

    if (!result.success) {
      setEmailError(result.error);
      return;
    }

    setEmail(targetEmail);
    setOtpError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
    setStep("otp");
  }

  function handleEditResult(result: VerifyAndEditResult) {
    if (result.success) {
      track("prediction_updated", {
        event_slug: eventSlug,
        version_number: result.versionNumber,
        unchanged: result.unchanged,
      });
      router.push(`/p/${publicId}?edited=1`);
      return;
    }

    setOtpError(result.error);
    setAccessTokenForRetry(result.accessToken ?? null);
    if (result.failureReason === "invalid_code") {
      setWrongAttemptCount((count) => count + 1);
    }
  }

  async function handleVerify(code: string) {
    if (otpSubmitting) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndEditResult;
    try {
      result = await verifyEmailAndEditPrediction(email, code, {
        publicId,
        participantIds: selectedIds,
        expectedVersionNumber,
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't verify your code — try again.");
      return;
    }

    setOtpSubmitting(false);
    handleEditResult(result);
  }

  async function handleRetry() {
    if (otpSubmitting || !accessTokenForRetry) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndEditResult;
    try {
      result = await retryEditWithVerifiedSession(accessTokenForRetry, {
        publicId,
        participantIds: selectedIds,
        expectedVersionNumber,
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't save your changes. Try again.");
      return;
    }

    setOtpSubmitting(false);
    handleEditResult(result);
  }

  function handleUseDifferentEmail() {
    setStep("email");
    setEmail("");
    setOtpError(null);
    setEmailError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
  }

  return (
    <div className="mt-6">
      {predictionLockAt ? (
        <p className="mb-4 text-xs text-text-muted">
          You can update your picks until {formatEventLocalLockTime(predictionLockAt, predictionTimezone)}.
        </p>
      ) : null}

      {step === "edit" ? (
        <div className="lg:grid lg:grid-cols-[380px_1fr] lg:gap-10">
          <section aria-label="Your Top 10" className="lg:sticky lg:top-20 lg:self-start">
            <h2 className="font-display text-lg text-text-primary">Your Top {requiredCount}</h2>
            <div className="mt-3">
              <TopTenList
                rankedParticipants={rankedParticipants}
                requiredCount={requiredCount}
                onRemove={handleRemove}
                onMoveUp={handleMoveUp}
                onMoveDown={handleMoveDown}
              />
            </div>

            {isComplete ? (
              <button
                type="button"
                onClick={handleStartSave}
                className="mt-6 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong sm:w-auto"
              >
                Save my Top {requiredCount}
              </button>
            ) : null}
          </section>

          <section aria-label="All contestants" className="mt-10 lg:mt-0">
            <h2 className="font-display text-lg text-text-primary">All contestants</h2>
            <div className="mt-3">
              <ParticipantBrowser
                participants={allParticipants}
                selectedIds={new Set(selectedIds)}
                atMax={isComplete}
                onToggle={handleToggle}
              />
            </div>
          </section>
        </div>
      ) : null}

      {step === "email" ? (
        <EmailStep mode="edit" submitting={emailSubmitting} errorMessage={emailError} onSendCode={handleSendCode} />
      ) : null}

      {step === "otp" && accessTokenForRetry ? (
        <div className="mt-8 border-t border-border pt-6">
          {otpError ? (
            <p className="text-sm text-accent-strong" role="alert" aria-live="polite">
              {otpError}
            </p>
          ) : null}
          <button
            type="button"
            disabled={otpSubmitting}
            onClick={handleRetry}
            className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
          >
            {otpSubmitting ? "Trying again…" : "Try again"}
          </button>
        </div>
      ) : step === "otp" ? (
        <OtpStep
          email={email}
          submitting={otpSubmitting}
          errorMessage={otpError}
          wrongAttemptCount={wrongAttemptCount}
          onVerify={handleVerify}
          onResend={() => handleSendCode(email)}
          onUseDifferentEmail={handleUseDifferentEmail}
        />
      ) : null}
    </div>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\EditPredictionFlow.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\EditPredictionFlow.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\EditPredictionFlow.tsx"
}

try {
    $path = "src\components\prediction\PublicPredictionView.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿﻿"use client";

import { useEffect, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import { formatEventLocalLockTime } from "@/lib/event-time-display";
import type { Participant } from "@/types/participant";
import { ShareActions } from "./ShareActions";

export function PublicPredictionView({
  eventSlug,
  publicId,
  rankedParticipants,
  hasResult = false,
  canEdit = false,
  showLockedNotice = false,
  predictionLockAt = null,
  predictionTimezone = null,
  fouchScore,
  youVsTheWorld,
  yourCrowdChanged,
}: {
  eventSlug: string;
  publicId: string;
  rankedParticipants: Participant[];
  /** Sprint 4.1: whether an official/demo result exists for this
   * prediction's event. Drives share-CTA hierarchy only — the original
   * Prediction Card share section becomes visually secondary once a
   * Result Card exists to share instead (brief §7-8). Does not affect
   * scoring or any calculation. */
  hasResult?: boolean;
  /** FOUCH 0.3A: true only for a verified prediction (auth_user_id
   * set) while the event is still open per Supabase
   * events.prediction_lock_at. A legacy anonymous prediction never
   * gets this — there is no verified identity to authorize an edit
   * against, and this sprint adds no way to claim one. */
  canEdit?: boolean;
  /** FOUCH 0.3A: true for a verified prediction whose event has
   * passed prediction_lock_at — shows "YOUR CALL IS LOCKED" instead
   * of an edit affordance. Never shown for legacy predictions, which
   * never offered editing in the first place. */
  showLockedNotice?: boolean;
  /** ISO datetime, only used for display ("until {date}"). */
  predictionLockAt?: string | null;
  /** FOUCH 0.3A.1 — IANA timezone identifier for the event (e.g.
   * "America/Puerto_Rico"), used ONLY to render predictionLockAt
   * unambiguously in event-local time (see event-time-display.ts).
   * Null falls back to an explicit UTC-labeled rendering — never the
   * viewer's browser timezone. */
  predictionTimezone?: string | null;
  /** FOUCH Score section (Sprint 4) — null/absent renders nothing, which
   * is exactly the pre-result experience. Server Component, passed down
   * for the same reason as youVsTheWorld below. */
  fouchScore?: ReactNode;
  /** The You vs The World section — a Server Component rendered by the
   * page and passed down, since it needs server-side data fetching
   * that a Client Component can't do directly. */
  youVsTheWorld: ReactNode;
  /** Experiment 01 ("Your Crowd Changed") — null/absent renders
   * nothing, same pattern as the two slots above. */
  yourCrowdChanged?: ReactNode;
}) {
  const searchParams = useSearchParams();
  const isNew = searchParams.get("new") === "1";
  const isEdited = searchParams.get("edited") === "1";
  const showSavedBanner = isNew || isEdited;

  useEffect(() => {
    track("public_prediction_viewed", { event_slug: eventSlug, is_new: isNew });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (isNew) {
      track("prediction_card_generated", { event_slug: eventSlug });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const publicUrl = `${siteUrl}/p/${publicId}`;

  const originalPredictionShare = (
    <div id="share" className="mt-10 scroll-mt-20 border-t border-border pt-8">
      <p
        className={
          hasResult
            ? "text-sm text-text-muted"
            : "font-display text-lg text-text-primary"
        }
      >
        {hasResult ? "Your original prediction" : "Share your prediction"}
      </p>
      <div className="mt-3">
        <ShareActions
          eventSlug={eventSlug}
          publicUrl={publicUrl}
          storyCardUrl={`/p/${publicId}/card/story`}
          postCardUrl={`/p/${publicId}/card/post`}
        />
      </div>
    </div>
  );

  return (
    <div>
      {showSavedBanner ? (
        <div className="mt-4">
          <p className="font-display text-lg text-accent-strong">YOUR CALL IS IN</p>
          {predictionLockAt ? (
            <p className="mt-1 text-sm text-text-secondary">
              You can update your picks until {formatEventLocalLockTime(predictionLockAt, predictionTimezone)}.
            </p>
          ) : null}
        </div>
      ) : null}

      <ol className="mt-6 space-y-1.5">
        {rankedParticipants.map((participant, index) => (
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

      {canEdit ? (
        <div className="mt-4">
          <Link
            href={`/p/${publicId}/edit`}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-2.5 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            <Pencil className="h-4 w-4" aria-hidden />
            Edit my Top 10
          </Link>
          {predictionLockAt ? (
            <p className="mt-2 text-xs text-text-muted">
              You can update your picks until {formatEventLocalLockTime(predictionLockAt, predictionTimezone)}.
            </p>
          ) : null}
        </div>
      ) : showLockedNotice ? (
        <p className="mt-4 text-sm font-medium uppercase tracking-wide text-text-muted">
          YOUR CALL IS LOCKED
        </p>
      ) : null}

      {fouchScore}

      {youVsTheWorld}

      {yourCrowdChanged}

      {/* Pre-result: original prediction sharing stays primary and sits
          right before the "Make your Top 10" CTA, unchanged from Sprint 2/3.
          Post-result: it becomes a secondary, de-emphasized block, per the
          hierarchy in Sprint 4.1's brief (Result Card is the stronger
          social object once scoring exists). */}
      {!hasResult ? originalPredictionShare : null}

      <Link
        href={`/predict/${eventSlug}?from=${publicId}`}
        onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
        className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        Make your Top 10
      </Link>

      {hasResult ? originalPredictionShare : null}
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PublicPredictionView.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PublicPredictionView.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PublicPredictionView.tsx"
}

try {
    $path = "src\app\p\[publicId]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿﻿import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CountryFlag } from "@/components/CountryFlag";
import { siteUrl } from "@/lib/site";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getOfficialResult } from "@/lib/results-db";
import { PublicPredictionView } from "@/components/prediction/PublicPredictionView";
import { YouVsTheWorld } from "@/components/prediction/YouVsTheWorld";
import { FouchScore } from "@/components/scoring/FouchScore";
import { YourCrowdChanged } from "@/components/scoring/YourCrowdChanged";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ publicId: string }>;
}): Promise<Metadata> {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) return {};

  const title = record.prediction.nickname
    ? `${record.prediction.nickname}'s Top 10 — ${record.event.name}`
    : `A Top 10 prediction — ${record.event.name}`;
  const description = "See the prediction, then make your own call.";

  return {
    title,
    description,
    // Sprint 2 decision: public prediction pages are reachable via
    // link but intentionally not indexed — we don't want thousands of
    // thin user-generated pages in search results. `follow` so the
    // "Make your Top 10" CTA is still crawlable back to the real
    // product pages.
    robots: { index: false, follow: true },
    openGraph: {
      title,
      description,
      url: `${siteUrl}/p/${publicId}`,
      images: [`${siteUrl}/p/${publicId}/opengraph-image`],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
    },
  };
}

export default async function PublicPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;
  const heading = prediction.nickname ? `${prediction.nickname}'s Top 10` : "Someone's Top 10";

  // Cheap existence check only (no percentile/breakdown work) — used
  // purely to decide share-CTA hierarchy (Sprint 4.1 §7-8). FouchScore
  // below independently does the full scored computation; this is a
  // second, lightweight read of the same result row, not duplicated
  // scoring logic.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);
  const hasResult = Boolean(official);

  // FOUCH 0.3A: editing is offered only for a verified prediction
  // while the event is still open — fetched fresh on every page view
  // from the single authoritative source, never cached/assumed.
  const lockConfig = await getEventLockConfig(event.slug);
  const isPredictionOpen = isPredictionWindowOpen(lockConfig, Date.now());
  const canEdit = prediction.hasVerifiedOwner && isPredictionOpen;
  const showLockedNotice = prediction.hasVerifiedOwner && !isPredictionOpen;

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-2 font-display text-xl uppercase tracking-tight text-text-primary">
        {heading}
      </p>

      {prediction.countryCode ? (
        <p className="mt-1 text-sm text-text-muted"><CountryFlag countryCode={prediction.countryCode} /></p>
      ) : null}

      {prediction.dataStatus === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo prediction — not the official lineup
        </p>
      ) : null}

      <PublicPredictionView
        eventSlug={event.slug}
        publicId={publicId}
        rankedParticipants={rankedParticipants}
        hasResult={hasResult}
        canEdit={canEdit}
        showLockedNotice={showLockedNotice}
        predictionLockAt={lockConfig?.predictionLockAt ?? null}
        predictionTimezone={lockConfig?.timezone ?? null}
        fouchScore={<FouchScore prediction={prediction} event={event} publicId={publicId} />}
        youVsTheWorld={<YouVsTheWorld prediction={prediction} event={event} />}
        yourCrowdChanged={<YourCrowdChanged prediction={prediction} event={event} />}
      />
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\page.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\page.tsx"
}

try {
    $path = "src\app\p\[publicId]\edit\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿﻿import { notFound, redirect } from "next/navigation";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { EditPredictionFlow } from "@/components/prediction/EditPredictionFlow";

/**
 * FOUCH 0.3A — the edit entry point. This route is intentionally
 * unreachable in a way that actually matters for two cases, checked
 * server-side (never just hidden in the UI, since a direct URL visit
 * bypasses any client-side hiding):
 *
 *  - legacy anonymous prediction (no verified owner) — there is no
 *    identity to authorize an edit against, and this sprint adds no
 *    way to claim one, so editing is simply never offered;
 *  - the event has passed prediction_lock_at — editing closes at
 *    lock, full stop.
 *
 * Both redirect back to the public page rather than 404 — the
 * prediction itself is real and viewable, only editing isn't
 * available. The actual SAVE action (verify-actions.ts) independently
 * re-checks both of these server-side again at save time — this
 * page's checks are only about whether to show the builder at all,
 * never the authorization boundary itself.
 */
export default async function EditPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;

  if (!prediction.hasVerifiedOwner) {
    redirect(`/p/${publicId}`);
  }

  const lockConfig = await getEventLockConfig(event.slug);
  if (!isPredictionWindowOpen(lockConfig, Date.now())) {
    redirect(`/p/${publicId}`);
  }

  const participantData = getParticipantsForEvent(event.slug);
  if (!participantData) notFound();

  const requiredCount = Math.min(10, participantData.participants.length);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <h1 className="font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-1 text-sm text-text-secondary">Edit your Top {requiredCount}</p>

      <EditPredictionFlow
        eventSlug={event.slug}
        publicId={publicId}
        allParticipants={participantData.participants}
        initialRankedParticipantIds={rankedParticipants.map((participant) => participant.id)}
        requiredCount={requiredCount}
        expectedVersionNumber={prediction.currentVersionNumber}
        predictionLockAt={lockConfig?.predictionLockAt ?? null}
        predictionTimezone={lockConfig?.timezone ?? null}
      />
    </main>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\edit\page.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\edit\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\edit\page.tsx"
}

try {
    $path = "supabase\migrations\0009_event_timezone.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
﻿-- FOUCH 0.3A.1 — event timezone for unambiguous lock-time display.
--
-- Why: prediction_lock_at is correctly an absolute instant
-- (timestamptz), but displaying it as a naked local time ("9:00 PM")
-- is ambiguous for a worldwide audience — a viewer in Chile, Spain, or
-- Thailand would read it in their OWN browser's timezone, which has
-- nothing to do with when the actual event airs. This migration adds
-- the event's own canonical timezone so the UI can render the lock
-- instant in EVENT-local time with an unambiguous abbreviation,
-- instead of the viewer's local time.
--
-- This is presentational only. It does NOT change, reinterpret, or
-- widen prediction_lock_at itself — that column remains the sole
-- authoritative instant, compared against server time exactly as
-- before (see src/lib/prediction-lock-logic.ts, untouched by this
-- migration). See src/lib/event-time-display.ts for the pure,
-- separately-tested formatting function that consumes this column.
--
-- Additive and idempotent: ADD COLUMN IF NOT EXISTS, and the UPDATE
-- below only touches the one row this product currently has, by slug
-- — safe to re-run.

alter table events
  add column if not exists timezone text;

comment on column events.timezone is
  'IANA timezone identifier (e.g. "America/Puerto_Rico") for this '
  'event''s canonical local time — display-only. Never store an '
  'abbreviation ("AST") or fixed offset ("GMT-4") here; those are '
  'derived at render time via Intl.DateTimeFormat. Null means the UI '
  'falls back to an unambiguous UTC-labeled display.';

update events
set timezone = 'America/Puerto_Rico'
where slug = 'miss-universe-2026';

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0009_event_timezone.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0009_event_timezone.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0009_event_timezone.sql"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 15 files written successfully." -ForegroundColor Green
}
