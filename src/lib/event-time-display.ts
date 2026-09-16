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
