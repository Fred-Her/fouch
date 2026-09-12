import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { OfficialResultInput } from "@/types/scoring";
import type { ParticipantDataStatus } from "@/lib/participants";

/**
 * Returns the official result for an event, scoped to a specific
 * data_status. Returns null when no result exists yet (pre-result
 * state — the public page keeps its existing pre-Sprint-4 experience)
 * OR when a result exists only for a DIFFERENT data_status than the
 * one requested (research §12/§22: demo predictions must never be
 * scored against an official result, or vice versa — returning null
 * here is what enforces that, at the query itself).
 */
export async function getOfficialResult(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<OfficialResultInput | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("event_results")
    .select(
      "winner_participant_id, first_runner_up_participant_id, second_runner_up_participant_id, top5_extra_participant_ids, top10_extra_participant_ids",
    )
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .maybeSingle();

  if (error || !data) return null;

  return {
    winner: data.winner_participant_id,
    firstRunnerUp: data.first_runner_up_participant_id,
    secondRunnerUp: data.second_runner_up_participant_id,
    top5Extras: data.top5_extra_participant_ids,
    top10Extras: data.top10_extra_participant_ids,
  };
}