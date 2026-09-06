import type { FouchEvent } from "@/types/event";

/**
 * SEED DATA — Sprint 0.
 *
 * This is real, verifiable public information (event name, date, venue),
 * not a database yet. There are no participant counts, popularity
 * numbers, or "trending" claims here — Fouch does not fabricate social
 * proof. Once Supabase is wired up (see src/lib/supabase), this file's
 * shape becomes the seed for the `events` table and this function can
 * be swapped for a real query without touching the components that
 * consume it.
 */
const events: FouchEvent[] = [
  {
    id: "seed-miss-universe-2026",
    slug: "miss-universe-2026",
    name: "Miss Universe 2026",
    category: "pageant",
    status: "upcoming",
    eventDate: "2026-11-24",
    isFeatured: true,
    subtitle: "José Miguel Agrelot Coliseum, San Juan, Puerto Rico",
  },
];

export function getFeaturedEvent(): FouchEvent | null {
  return events.find((event) => event.isFeatured) ?? null;
}

export function getEventBySlug(slug: string): FouchEvent | null {
  return events.find((event) => event.slug === slug) ?? null;
}
