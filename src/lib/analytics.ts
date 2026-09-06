/**
 * Minimal analytics seam for Sprint 0.
 *
 * Intentionally NOT wired to PostHog (or any provider) yet — adding the
 * SDK for three events would be dead weight before we know we need it.
 * This gives every future call site a single, typed function to import,
 * so plugging in a real provider later is a one-file change instead of
 * a hunt through components. Never throws, never blocks rendering, and
 * is silent when analytics isn't configured (e.g. local dev).
 */

export type FouchAnalyticsEvent =
  | "landing_view"
  | "featured_event_clicked"
  | "start_prediction";

export function track(event: FouchAnalyticsEvent, properties?: Record<string, unknown>) {
  if (typeof window === "undefined") return;
  if (!process.env.NEXT_PUBLIC_ANALYTICS_ENABLED) return;

  // Placeholder sink until a provider (e.g. PostHog) is configured behind
  // NEXT_PUBLIC_POSTHOG_KEY. Kept as a console log, not a network call,
  // so Sprint 0 never depends on an external analytics endpoint.
  console.debug("[fouch:analytics]", event, properties ?? {});
}
