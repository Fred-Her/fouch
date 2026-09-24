import "server-only";
import type { FouchEvent } from "@/types/event";
import { getEventBySlugFromDb, getFeaturedEventFromDb } from "@/lib/events-db";

/**
 * FOUCH 0.3B Event Resolution Fix — `events` in Supabase is now the
 * single source of truth for event metadata, replacing the
 * hardcoded array that used to live here. This file used to define
 * Miss Universe 2026 directly in TypeScript; that row already exists
 * in the database (seeded since migration 0001/0007) with every field
 * this file used to hardcode, so switching this file to read from
 * there loses nothing for Miss Universe and is what let Miss Grand
 * International 2026 — added straight to the database in 0.3B —
 * resolve correctly for the first time (previously getEventBySlug
 * returned null for it, since it was never added to this array,
 * which meant its /predict route 404'd and it could never become the
 * Home's featured event no matter what the database's own
 * `is_featured` column said).
 *
 * Both exports are now async — every existing caller already ran
 * inside an async Server Component or Server Action, so this is a
 * mechanical `await` addition at each call site, not a behavior
 * change.
 */
export async function getFeaturedEvent(): Promise<FouchEvent | null> {
  return getFeaturedEventFromDb();
}

export async function getEventBySlug(slug: string): Promise<FouchEvent | null> {
  return getEventBySlugFromDb(slug);
}

/**
 * The generic, event-agnostic term for one ranked option — "pick" by
 * default (fits the current demo country dataset), overridable per
 * event via entryNounSingular/Plural for future categories (Oscars
 * "nominee", Eurovision "entry", a verified pageant "contestant").
 */
export function getEntryNoun(event: FouchEvent, plural: boolean): string {
  if (plural) return event.entryNounPlural ?? "picks";
  return event.entryNounSingular ?? "pick";
}