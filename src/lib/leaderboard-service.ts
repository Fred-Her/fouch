import "server-only";
import { scorePrediction } from "@/lib/scoring";
import { getOfficialResult } from "@/lib/results-db";
import { getLeaderboardRawEntries } from "@/lib/predictions-db";
import { buildLeaderboard, resolveViewerContext, LEADERBOARD_TOP_N } from "@/lib/leaderboard";
import type { LeaderboardEntry, ViewerContext } from "@/lib/leaderboard";
import type { ParticipantDataStatus } from "@/lib/participants";

export interface EventLeaderboard {
  status: "no_result" | "scored";
  dataStatus: ParticipantDataStatus;
  totalCount: number;
  topEntries: LeaderboardEntry[];
  /** Present only when a viewerPublicId was given AND it resolved to
   * an eligible, scored prediction on THIS leaderboard. Absent
   * viewer context never affects `status` or `topEntries` above —
   * see resolveViewerContext() in src/lib/leaderboard.ts, which this
   * calls as a pure, separately-tested step. */
  viewer: ViewerContext | null;
}

/**
 * Builds the full event leaderboard. Ranking happens here, server-side,
 * over every eligible entry — the client only ever receives the
 * already-ranked, already-trimmed result (brief §19-21), never the raw
 * prediction list.
 *
 * Returns `{ status: "no_result" }` when there's no official/demo
 * result yet — the page renders a "leaderboard locked" state, never a
 * fabricated empty board (brief §28). This decision is made BEFORE
 * `viewerPublicId` is even read below — the leaderboard's existence
 * can never depend on who's asking (Sprint 5.1 fix).
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

  const fullPrecisionScoreByPublicId = new Map(scored.map((e) => [e.publicId, e.breakdown.score]));
  const viewer = resolveViewerContext(leaderboard, fullPrecisionScoreByPublicId, viewerPublicId);

  return {
    status: "scored",
    dataStatus,
    totalCount: leaderboard.length,
    topEntries: leaderboard.slice(0, LEADERBOARD_TOP_N),
    viewer,
  };
}