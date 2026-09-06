"use client";

import Link from "next/link";
import type { ComponentProps } from "react";
import { track, type FouchAnalyticsEvent } from "@/lib/analytics";

interface TrackedLinkProps extends ComponentProps<typeof Link> {
  event: FouchAnalyticsEvent;
  eventProperties?: Record<string, unknown>;
}

/**
 * A normal Next.js Link that also fires an analytics event on click.
 * Isolated in its own Client Component so the rest of a section (e.g.
 * FeaturedEvent) can stay a Server Component.
 */
export function TrackedLink({ event, eventProperties, onClick, ...linkProps }: TrackedLinkProps) {
  return (
    <Link
      {...linkProps}
      onClick={(navigationEvent) => {
        track(event, eventProperties);
        onClick?.(navigationEvent);
      }}
    />
  );
}
