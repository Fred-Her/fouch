"use client";

import { useEffect } from "react";
import { track } from "@/lib/analytics";
import type { ScoreBand } from "@/types/scoring";

export function FouchScoreTracker({
  eventSlug,
  scoreBand,
  percentileAvailable,
  dataStatus,
}: {
  eventSlug: string;
  scoreBand: ScoreBand;
  percentileAvailable: boolean;
  dataStatus: string;
}) {
  useEffect(() => {
    const properties = { event_slug: eventSlug, score_band: scoreBand, data_status: dataStatus };
    track("score_viewed", properties);
    track("score_breakdown_viewed", properties);
    track("result_card_generated", properties);
    if (percentileAvailable) {
      track("percentile_viewed", { ...properties, percentile_available: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}