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
}
