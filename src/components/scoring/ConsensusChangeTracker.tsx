"use client";

import { useEffect } from "react";
import { track } from "@/lib/analytics";

export function ConsensusChangeTracker({
  eventSlug,
  dataStatus,
  direction,
  changePoints,
  thenSampleBucket,
  nowSampleBucket,
}: {
  eventSlug: string;
  dataStatus: string;
  direction: "toward" | "away";
  changePoints: number;
  thenSampleBucket: string;
  nowSampleBucket: string;
}) {
  useEffect(() => {
    track("consensus_change_viewed", {
      event_id: eventSlug,
      data_status: dataStatus,
      direction,
      change_points: Math.round(changePoints),
      then_sample_bucket: thenSampleBucket,
      now_sample_bucket: nowSampleBucket,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}