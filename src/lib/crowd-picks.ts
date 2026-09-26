import "server-only";
import { getEligiblePredictionsForComparison } from "@/lib/predictions-db";
import { computeCommunityTop10 } from "@/lib/community-comparison";
import { resolveParticipantsByIds } from "@/lib/participants";
import type { ParticipantDataStatus } from "@/lib/participants";
import type { Participant } from "@/types/participant";

export interface CrowdTopPick {
  participant: Participant;
  /** % of eligible predictions that picked this participant as their
   * #1 — "who does the crowd have winning", not a Top-10-inclusion
   * rate. Rounded for display only; never re-derives a different
   * ranking than computeCommunityTop10's own points-based order. */
  pct: number;
}

export interface CrowdTopPicks {
  population: number;
  picks: CrowdTopPick[];
}

/**
 * FOUCH Home v1.1 "The Crowd" section — reuses the EXACT same
 * eligibility (getEligiblePredictionsForComparison: is_final = true,
 * scoped by event_slug + data_status, current-version-only) and
 * ranking (computeCommunityTop10, the same function You vs The World
 * uses) as the rest of the product. This is deliberately not a
 * second definition of "the crowd" — it's the same one, just without
 * a specific viewer's own prediction to compare against.
 *
 * Returns null when there's no event to show (never happens for a
 * resolved event, but keeps the caller's null-handling simple) —
 * an empty population returns `{ population: 0, picks: [] }`, which
 * the component renders as the small-sample "IT'S EARLY" state.
 */
export async function getCrowdTopPicks(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
  limit = 5,
): Promise<CrowdTopPicks> {
  const eligible = await getEligiblePredictionsForComparison(eventSlug, dataStatus);
  const population = eligible.length;

  if (population === 0) return { population: 0, picks: [] };

  const ranked = computeCommunityTop10(eligible).slice(0, limit);
  const participantsById = await resolveParticipantsByIds(
    eventSlug,
    ranked.map((entry) => entry.participantId),
  );

  const picks: CrowdTopPick[] = [];
  for (const entry of ranked) {
    const participant = participantsById.get(entry.participantId);
    if (!participant) continue; // Resolvable-by-id failure is a data anomaly, not a reason to show a blank row.
    picks.push({
      participant,
      pct: Math.round((entry.firstPlaceCount / population) * 100),
    });
  }

  return { population, picks };
}
