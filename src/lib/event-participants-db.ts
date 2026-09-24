import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { EventParticipantStatus } from "@/lib/participant-status";

export interface EventParticipantRow {
  id: string;
  eventSlug: string;
  countryCode: string;
  countryName: string;
  contestantName: string | null;
  status: EventParticipantStatus;
  sourceUrl: string | null;
  sourceCheckedAt: string | null;
}

/**
 * All rows for an event, every status included â€” the raw material
 * both getParticipantsForEvent (filters to ACTIVE) and
 * resolveParticipantsByIds (no filter, for rendering history) build
 * on top of. Returns [] (never null) when the event has no DB-backed
 * participants at all, or when Supabase isn't configured â€” callers
 * that need to distinguish "event doesn't exist" from "event exists
 * with zero rows" do so via the `events` table itself, not this.
 */
export async function getAllEventParticipantRows(eventSlug: string): Promise<EventParticipantRow[]> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  const { data, error } = await supabase
    .from("event_participants")
    .select("id, event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at")
    .eq("event_slug", eventSlug);

  if (error || !data) return [];

  return data.map((row) => ({
    id: row.id,
    eventSlug: row.event_slug,
    countryCode: row.country_code,
    countryName: row.country_name,
    contestantName: row.contestant_name,
    status: row.status as EventParticipantStatus,
    sourceUrl: row.source_url,
    sourceCheckedAt: row.source_checked_at,
  }));
}
