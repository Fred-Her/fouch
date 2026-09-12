import "server-only";
import { computeConsensusChange } from "@/lib/consensus-change";
import type { ConsensusChangeResult } from "@/lib/consensus-change";
import { getWinnerPicksForConsensusChange } from "@/lib/predictions-db";
import type { ParticipantDataStatus } from "@/lib/participants";

/**
 * Experiment 01 ("Your Crowd Changed"). Reuses only data FOUCH already
 * has (submission timestamps + each prediction's #1 pick) — no
 * snapshot table, no scheduled job. See FOUCH_EXPERIMENT_01.md.
 */
export async function getConsensusChangeForPrediction(
  predictionId: string,
  submittedAt: string,
  winnerParticipantId: string,
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<ConsensusChangeResult> {
  const allEligible = await getWinnerPicksForConsensusChange(eventSlug, dataStatus);
  return computeConsensusChange({ predictionId, submittedAt, winnerParticipantId }, allEligible);
}