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
  | "consensus_change_viewed"
  | "verification_started"
  | "verification_sent"
  | "verification_completed"
  | "verification_failed"
  | "duplicate_prediction_attempt";

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