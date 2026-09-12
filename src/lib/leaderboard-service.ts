import "server-only";
import { scorePrediction, computePercentile } from "@/lib/scoring";
import type { PercentileResult } from "@/lib/scoring";
import { getOfficialResult } from "@/lib/results-db";
import { getLeaderboardRawEntries } from "@/lib/predictions-db";
import { buildLeaderboard } from "@/lib/leaderboard";
import type { LeaderboardEntry } from "@/lib/leaderboard";
import type { ParticipantDataStatus } from "@/lib/participants";

const TOP_N = 50;
/** How many rows on either side of the viewer to show when they fall
 * outside the visible Top N (Sprint 5 brief §19). */
const NEIGHBOR_WINDOW = 2;

export interface EventLeaderboard {
  status: "no_result" | "scored";
  dataStatus: ParticipantDataStatus;
  totalCount: number;
  topEntries: LeaderboardEntry[];
  /** Present only when a viewerPublicId was given and it resolved to
   * an eligible, scored prediction for this event. */
  viewer: {
    entry: LeaderboardEntry;
    /** Only populated when the viewer's rank falls outside topEntries. */
    neighbors: LeaderboardEntry[];
    percentile: PercentileResult;
  } | null;
}

/**
 * Builds the full event leaderboard. Ranking happens here, server-side,
 * over every eligible entry — the client only ever receives the
 * already-ranked, already-trimmed result (brief §19-21), never the raw
 * prediction list.
 *
 * Returns `{ status: "no_result" }` when there's no official/demo
 * result yet — the page renders a "leaderboard locked" state, never a
 * fabricated empty board (brief §28).
 */
export async function getEventLeaderboard(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
  viewerPublicId?: string,
): Promise<EventLeaderboard> {
  const official = await getOfficialResult(eventSlug, dataStatus);
  if (!official) {
    return { status: "no_result", dataStatus, totalCount: 0, topEntries: [], viewer: null };
  }

  const rawEntries = await getLeaderboardRawEntries(eventSlug, dataStatus);

  const scored = rawEntries.map((entry) => ({
    ...entry,
    breakdown: scorePrediction(entry.rankedParticipantIds, official),
  }));

  const leaderboard = buildLeaderboard(
    scored.map((entry) => ({
      publicId: entry.publicId,
      nickname: entry.nickname,
      countryCode: entry.countryCode,
      displayScore: entry.breakdown.displayScore,
    })),
  );

  const topEntries = leaderboard.slice(0, TOP_N);

  let viewer: EventLeaderboard["viewer"] = null;
  if (viewerPublicId) {
    const viewerIndex = leaderboard.findIndex((e) => e.publicId === viewerPublicId);
    if (viewerIndex !== -1) {
      const viewerEntry = leaderboard[viewerIndex]!;
      const viewerScored = scored.find((e) => e.publicId === viewerPublicId)!;
      const otherScores = scored
        .filter((e) => e.publicId !== viewerPublicId)
        .map((e) => e.breakdown.score);
      const percentile = computePercentile(viewerScored.breakdown.score, otherScores);

      const inTop = viewerIndex < TOP_N;
      const neighbors = inTop
        ? []
        : leaderboard.slice(
            Math.max(0, viewerIndex - NEIGHBOR_WINDOW),
            Math.min(leaderboard.length, viewerIndex + NEIGHBOR_WINDOW + 1),
          );

      viewer = { entry: viewerEntry, neighbors, percentile };
    }
  }

  return { status: "scored", dataStatus, totalCount: leaderboard.length, topEntries, viewer };
}