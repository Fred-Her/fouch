/**
 * Minimal analytics seam.
 *
 * Intentionally NOT wired to PostHog (or any provider) yet â€” adding an
 * SDK before we know we need it is dead weight. This gives every call
 * site a single, typed function to import, so plugging in a real
 * provider later is a one-file change instead of a hunt through
 * components. Never throws, never blocks rendering, and is silent
 * when analytics isn't configured (e.g. local dev).
 *
 * Properties must never carry personally identifiable information or
 * free-text contestant/user input â€” only structural values like an
 * event slug, a count, or a position.
 */

export type FouchAnalyticsEvent =
  | "landing_view"
  | "featured_event_clicked"
  | "start_prediction"
  | "participant_selected"
  | "participant_removed"
  | "prediction_reordered"
  | "prediction_completed"
  | "prediction_reviewed";

export function track(event: FouchAnalyticsEvent, properties?: Record<string, unknown>) {
  if (typeof window === "undefined") return;
  if (!process.env.NEXT_PUBLIC_ANALYTICS_ENABLED) return;

  // Placeholder sink until a provider (e.g. PostHog) is configured behind
  // NEXT_PUBLIC_POSTHOG_KEY. Kept as a console log, not a network call,
  // so this never depends on an external analytics endpoint.
  console.debug("[fouch:analytics]", event, properties ?? {});
}