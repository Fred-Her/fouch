import { getI18n } from "@/lib/i18n-server";
import { getFeaturedEvent, getSecondaryUpcomingEvents, getLatestCompletedEvent } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { getOfficialResult } from "@/lib/results-db";
import { isDemoPredictionBlocked } from "@/lib/event-readiness";
import { ResultsLink } from "@/components/ResultsLink";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { FeaturedEvent } from "@/components/FeaturedEvent";
import { UpcomingEvents } from "@/components/UpcomingEvents";
import { HowItWorks } from "@/components/HowItWorks";
import { ClosingMoment } from "@/components/ClosingMoment";
import { Footer } from "@/components/Footer";
import { ViewTracker } from "@/components/ViewTracker";

// Sprint 5.1: FeaturedEvent checks live result state (for the secondary
// leaderboard link) — force fresh execution so that check is never
// baked into a static build and left stale until the next deploy.
export const dynamic = "force-dynamic";

export default async function Home() {
  const { locale, dict } = await getI18n();
  const rawFeaturedEvent = await getFeaturedEvent();
  let featuredEvent = rawFeaturedEvent;
  let upcomingEvents = await getSecondaryUpcomingEvents(rawFeaturedEvent?.slug ?? null);

  // A "featured" event without an official roster must never present a
  // prediction CTA: it moves to Up Next as "Coming soon" instead.
  if (rawFeaturedEvent) {
    const featuredData = await getParticipantsForEvent(rawFeaturedEvent.slug, locale);
    if (!featuredData || featuredData.participants.length === 0 || isDemoPredictionBlocked(featuredData.status)) {
      featuredEvent = null;
      upcomingEvents = [rawFeaturedEvent, ...upcomingEvents].sort((a, b) => a.eventDate.localeCompare(b.eventDate));
    }
  }

  // Upcoming events with no official roster yet are shown as "Coming
  // soon" — never as a builder over placeholder data.
  const comingSoonSlugs: string[] = [];
  for (const upcoming of upcomingEvents) {
    const data = await getParticipantsForEvent(upcoming.slug, locale);
    if (!data || data.participants.length === 0 || isDemoPredictionBlocked(data.status)) {
      comingSoonSlugs.push(upcoming.slug);
    }
  }

  // The latest completed event links to its final leaderboard — only
  // once an official result actually exists for it.
  let resultsEvent = null;
  const completedEvent = await getLatestCompletedEvent();
  if (completedEvent) {
    const completedData = await getParticipantsForEvent(completedEvent.slug, locale);
    if (completedData && (await getOfficialResult(completedEvent.slug, completedData.status))) {
      resultsEvent = completedEvent;
    }
  }

  // Home v1.1: the Hero's "Predictions Open" badge reflects the same
  // real lock-window check every other prediction-open decision in
  // the app uses — never inferred from event.status.
  const featuredLockConfig = featuredEvent ? await getEventLockConfig(featuredEvent.slug) : null;
  const predictionsOpen = featuredEvent ? isPredictionWindowOpen(featuredLockConfig, Date.now()) : false;

  return (
    <>
      <ViewTracker event="landing_view" />
      <Nav />
      <main>
        <Hero dictionary={dict} eventSlug={featuredEvent?.slug ?? null} predictionsOpen={predictionsOpen} />
        {resultsEvent ? <ResultsLink event={resultsEvent} dictionary={dict} /> : null}
        {featuredEvent ? (
          <FeaturedEvent event={featuredEvent} dictionary={dict} locale={locale} />
        ) : null}
        <UpcomingEvents events={upcomingEvents} dictionary={dict} locale={locale} comingSoonSlugs={comingSoonSlugs} />
        <HowItWorks dictionary={dict} />
        <ClosingMoment eventSlug={featuredEvent?.slug ?? null} dictionary={dict} />
      </main>
      <Footer dictionary={dict} />
    </>
  );
}
