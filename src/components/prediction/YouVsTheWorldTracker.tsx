"use client";

import { useEffect } from "react";
import { track } from "@/lib/analytics";
import type { SampleSizeBucket } from "@/lib/community-comparison";

/**
 * You vs The World itself is a Server Component (it needs server-side
 * Supabase access), so it can't call the client-only `track()`
 * directly. This tiny client component fires the view events on
 * mount and renders nothing.
 */
export function YouVsTheWorldTracker({
  eventSlug,
  dataStatus,
  bucket,
  hasSameWinner,
  hasTop3Match,
  hasBoldestPick,
  hasCommunityTop10,
}: {
  eventSlug: string;
  dataStatus: string;
  bucket: SampleSizeBucket;
  hasSameWinner: boolean;
  hasTop3Match: boolean;
  hasBoldestPick: boolean;
  hasCommunityTop10: boolean;
}) {
  useEffect(() => {
    const properties = { event_slug: eventSlug, data_status: dataStatus, comparison_population_bucket: bucket };
    track("you_vs_world_viewed", properties);
    if (hasSameWinner) track("same_winner_viewed", properties);
    if (hasTop3Match) track("top3_match_viewed", properties);
    if (hasBoldestPick) track("boldest_pick_viewed", properties);
    if (hasCommunityTop10) track("community_top10_viewed", properties);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}