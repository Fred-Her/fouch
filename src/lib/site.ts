/**
 * Central source of truth for the site's absolute URL.
 *
 * Resolution order:
 * 1. NEXT_PUBLIC_SITE_URL — set this once we own a real custom domain.
 * 2. VERCEL_PROJECT_PRODUCTION_URL — Vercel's stable alias for
 *    "current production" (e.g. fouch-tau.vercel.app). Preferred over
 *    VERCEL_URL, which changes per-deployment.
 * 3. VERCEL_URL — this specific deployment's URL, as a last resort.
 * 4. localhost — local dev.
 *
 * Every check is an explicit truthy `if`, not `??` — Vercel can create
 * NEXT_PUBLIC_SITE_URL as an empty string (not undefined) when it
 * auto-detects env vars from .env.example, and `??` only falls back on
 * null/undefined, which would let an empty string slip through and
 * break `new URL("")` at build time.
 */
function resolveSiteUrl(): string {
  if (process.env.NEXT_PUBLIC_SITE_URL) {
    return process.env.NEXT_PUBLIC_SITE_URL;
  }
  if (process.env.VERCEL_PROJECT_PRODUCTION_URL) {
    return `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`;
  }
  if (process.env.VERCEL_URL) {
    return `https://${process.env.VERCEL_URL}`;
  }
  return "http://localhost:3000";
}

export const siteUrl = resolveSiteUrl();