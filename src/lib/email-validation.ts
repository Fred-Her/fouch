/**
 * Beta Hardening 0.2 Phase C — minimal email validation. Deliberately
 * simple: real validation (does this address actually exist/receive
 * mail) is Supabase Auth's job via the OTP round-trip itself. This is
 * only a basic shape check before spending a Supabase Auth call.
 */

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const MAX_EMAIL_LENGTH = 254; // RFC 5321 practical limit

export function normalizeEmail(raw: string): string {
  return raw.trim().toLowerCase();
}

export function isValidEmail(raw: string): boolean {
  const normalized = normalizeEmail(raw);
  return normalized.length > 0 && normalized.length <= MAX_EMAIL_LENGTH && EMAIL_PATTERN.test(normalized);
}