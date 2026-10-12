import "server-only";
import { getSecondaryUpcomingEvents } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { isDemoPredictionBlocked } from "@/lib/event-readiness";
import type { Locale } from "@/lib/locale";

export interface NextEventInfo {
  slug: string;
  name: string;
  /** True while the event has no official roster loaded — shown as "Coming soon", never as a builder. */
  comingSoon: boolean;
}

/** The next upcoming event after `excludeSlug`, for post-event CTAs. */
export async function getNextEvent(excludeSlug: string, locale: Locale): Promise<NextEventInfo | null> {
  const [next] = await getSecondaryUpcomingEvents(excludeSlug);
  if (!next) return null;
  const data = await getParticipantsForEvent(next.slug, locale);
  const comingSoon = !data || data.participants.length === 0 || isDemoPredictionBlocked(data.status);
  return { slug: next.slug, name: next.name, comingSoon };
}
