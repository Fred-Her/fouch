export type EventCategory =
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
  /** ISO 8601 datetime. Predictions are rejected before this time, if set. */
  predictionOpenAt?: string;
  /** ISO 8601 datetime. Predictions are rejected at/after this time, if set. */
  predictionLockAt?: string;
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