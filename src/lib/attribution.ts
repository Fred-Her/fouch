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