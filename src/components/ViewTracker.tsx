"use client";

import { useEffect } from "react";
import { track, type FouchAnalyticsEvent } from "@/lib/analytics";
import { captureUtmSource } from "@/lib/attribution";

/** Fires one analytics event on mount. Renders nothing. */
export function ViewTracker({ event }: { event: FouchAnalyticsEvent }) {
  useEffect(() => {
    const utmSource = captureUtmSource();
    track(event, utmSource ? { utm_source: utmSource } : undefined);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return null;
}