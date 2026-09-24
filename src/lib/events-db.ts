import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { isPredictionWindowOpen, type EventLockConfig } from "@/lib/prediction-lock-logic";
import { pickFeaturedEventSlug, type FeaturedCandidate } from "@/lib/featured-event-logic";
import type { FouchEvent, EventCategory, EventStatus } from "@/types/event";

// Re-exported unchanged so every existing import site
// (`@/lib/events-db`) keeps working — the pure logic itself now lives
// in prediction-lock-logic.ts purely so it can be unit tested without
// pulling in the "server-only" guard above. See that file's comment.
export { isPredictionWindowOpen };
export type { EventLockConfig };
export { pickFeaturedEventSlug };
export type { FeaturedCandidate };

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

/**
 * FOUCH 0.3B Event Resolution Fix — `events` is now the single
 * source of truth for event metadata (name, category, status,
 * subtitle, event_date, is_featured), replacing the hardcoded array
 * that used to live in src/lib/events.ts. That file now just
 * delegates here.
 *
 * entryNounSingular/entryNounPlural (FouchEvent's two remaining
 * optional fields) have no DB column — neither existing event
 * (Miss Universe, Miss Grand) has ever set them, so they're left
 * undefined here and getEntryNoun's existing "pick"/"picks" default
 * applies exactly as before. No column was added for this: the
 * audit for this fix confirmed the `events` table already covers
 * every field either event actually uses.
 */
function toFouchEvent(row: {
  id: string;
  slug: string;
  name: string;
  category: string;
  status: string;
  event_date: string;
  hero_asset: string | null;
  is_featured: boolean;
  subtitle: string | null;
}): FouchEvent {
  return {
    id: row.id,
    slug: row.slug,
    name: row.name,
    category: row.category as EventCategory,
    status: row.status as EventStatus,
    eventDate: row.event_date,
    heroAsset: row.hero_asset ?? undefined,
    isFeatured: row.is_featured,
    subtitle: row.subtitle ?? undefined,
  };
}

const EVENT_COLUMNS = "id, slug, name, category, status, event_date, hero_asset, is_featured, subtitle";

/**
 * Resolves any event by slug from the database — Miss Universe and
 * Miss Grand alike, no hardcoded special case for either. Returns
 * null for an unknown slug (the caller's existing `notFound()`
 * handling is unchanged) or when Supabase isn't configured.
 */
export async function getEventBySlugFromDb(slug: string): Promise<FouchEvent | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase.from("events").select(EVENT_COLUMNS).eq("slug", slug).maybeSingle();

  if (error || !data) return null;
  return toFouchEvent(data);
}

/**
 * FOUCH 0.3B Home Multi-Event Rendering Fix — every event with
 * status = 'upcoming', ordered by date. The Home page uses this to
 * render the secondary "Upcoming" section, excluding whichever event
 * it already shows as Featured. This is the minimal generic query
 * needed to support more than one event on the Home at once — no
 * per-event special casing, no admin UI, just a plain SELECT.
 */
export async function getUpcomingEventsFromDb(): Promise<FouchEvent[]> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  const { data, error } = await supabase
    .from("events")
    .select(EVENT_COLUMNS)
    .eq("status", "upcoming")
    .order("event_date", { ascending: true });

  if (error || !data) return [];
  return data.map(toFouchEvent);
}

/**
 * Resolves the current featured event from the database. If more
 * than one row has is_featured = true (a data-entry mistake — see
 * this fix's report on why no DB constraint enforces "at most one"
 * yet), picks deterministically via pickFeaturedEventSlug's tie-break
 * (alphabetically first slug) rather than an arbitrary row order, by
 * mirroring that exact tie-break in the query's own ORDER BY.
 */
export async function getFeaturedEventFromDb(): Promise<FouchEvent | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("events")
    .select(EVENT_COLUMNS)
    .eq("is_featured", true)
    .order("slug", { ascending: true });

  if (error || !data || data.length === 0) return null;

  const candidates: FeaturedCandidate[] = data.map((row) => ({ slug: row.slug, isFeatured: row.is_featured }));
  const featuredSlug = pickFeaturedEventSlug(candidates);
  const chosen = data.find((row) => row.slug === featuredSlug);
  return chosen ? toFouchEvent(chosen) : null;
}
