﻿export type EventCategory =
  | "pageant"
  | "awards"
  | "music"
  | "reality"
  | "talent"
  | "tv";

export type EventStatus = "upcoming" | "open" | "live" | "completed";

/**
 * Category-agnostic event model. Deliberately does NOT assume
 * contestants, countries, or a Top 10 shape — those are
 * category-specific concerns for a later sprint.
 *
 * FOUCH 0.3A: this type deliberately has NO prediction open/lock
 * fields anymore. That timing now lives exclusively in Supabase
 * `events.prediction_open_at` / `prediction_lock_at` (migration
 * 0007), fetched server-side via events-db.ts's getEventLockConfig —
 * never read from this seed data. This file may still describe
 * display-only metadata (name, subtitle, hero asset) until events
 * moves fully into the database.
 */
export interface FouchEvent {
  id: string;
  slug: string;
  name: string;
  category: EventCategory;
  status: EventStatus;
  /** ISO 8601 date string. */
  eventDate: string;
  /** Path to a hero image/asset. Optional — Sprint 0 has none. */
  heroAsset?: string;
  isFeatured: boolean;
  /** Plain-language subtitle used in the UI, e.g. venue or one-line context. */
  subtitle?: string;
  /**
   * What a single ranked option is called for this event — "contestant"
   * for a verified pageant roster, "nominee" for an Oscars category,
   * "country" for a Eurovision entry, etc. Defaults to "pick" when
   * unset (see getEntryNoun), which is deliberately generic for the
   * current demo country dataset — see Sprint 3 brief section 30.
   */
  entryNounSingular?: string;
  entryNounPlural?: string;
}