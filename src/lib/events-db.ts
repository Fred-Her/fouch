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
