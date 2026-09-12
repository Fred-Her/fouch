"use client";

import { useEffect } from "react";
import { track } from "@/lib/analytics";

export function LeaderboardTracker({
  eventSlug,
  dataStatus,
  leaderboardSize,
  ownRank,
  ownScoreBand,
}: {
  eventSlug: string;
  dataStatus: string;
  leaderboardSize: number;
  ownRank?: number;
  ownScoreBand?: string;
}) {
  useEffect(() => {
    track("leaderboard_viewed", {
      event_slug: eventSlug,
      data_status: dataStatus,
      leaderboard_size: leaderboardSize,
      is_own_prediction: Boolean(ownRank),
    });
    if (ownRank) {
      track("own_rank_viewed", {
        event_slug: eventSlug,
        rank: ownRank,
        score_band: ownScoreBand,
      });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}