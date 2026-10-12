import type { Participant } from "@/types/participant";

/**
 * Where an event's roster comes from. The database is ALWAYS preferred:
 * once an event has event_participants rows, those rows are the roster
 * (status "verified"). The hardcoded demo list is only a development
 * fallback for an event with NO rows yet — which the readiness guard
 * (event-readiness.ts) treats as "Coming soon" — and a read-only
 * lookup table for historical demo predictions (ids "demo-xx").
 */
export type RosterSource = "db" | "demo" | "none";

export function chooseRosterSource(dbRowCount: number, hasDemoList: boolean): RosterSource {
  if (dbRowCount > 0) return "db";
  return hasDemoList ? "demo" : "none";
}

export const DEMO_ID_PREFIX = "demo-";

/**
 * Demo participants that a SAVED prediction references (ids "demo-xx"),
 * so an old demo prediction still renders after the event switched to
 * its real roster. They are never selectable — this only resolves ids
 * that are already stored.
 */
export function demoParticipantsForIds(ids: string[], demoList: Participant[] | undefined): Participant[] {
  if (!demoList) return [];
  const wanted = new Set(ids.filter((id) => id.startsWith(DEMO_ID_PREFIX)));
  return demoList.filter((participant) => wanted.has(participant.id));
}
