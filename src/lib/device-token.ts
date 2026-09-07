const STORAGE_KEY = "fouch:device-token";

/**
 * A random, anonymous per-browser token — not tied to identity, not
 * derived from IP/fingerprinting. Used only so the server can enforce
 * "one prediction per device per event" (see the unique index in
 * 0002_predictions.sql). Clearing localStorage resets it; that's an
 * accepted tradeoff for a lightweight, non-invasive guard.
 */
export function getDeviceToken(): string {
  if (typeof window === "undefined") return "";

  try {
    const existing = window.localStorage.getItem(STORAGE_KEY);
    if (existing) return existing;

    const token = crypto.randomUUID();
    window.localStorage.setItem(STORAGE_KEY, token);
    return token;
  } catch {
    // Storage unavailable (private browsing, quota, disabled) — fall
    // back to a per-request random value. Duplicate protection is
    // simply unavailable for that session, which is an acceptable
    // degradation, not a crash.
    return crypto.randomUUID();
  }
}