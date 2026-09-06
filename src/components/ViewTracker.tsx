"use client";

import { useEffect } from "react";
import { track, type FouchAnalyticsEvent } from "@/lib/analytics";

/** Fires one analytics event on mount. Renders nothing. */
export function ViewTracker({ event }: { event: FouchAnalyticsEvent }) {
  useEffect(() => {
    track(event);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}
