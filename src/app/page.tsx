import { en } from "@/content/en";
import { getFeaturedEvent, getSecondaryUpcomingEvents } from "@/lib/events";
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
  const featuredEvent = await getFeaturedEvent();
  const upcomingEvents = await getSecondaryUpcomingEvents(featuredEvent?.slug ?? null);

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
        <Hero dictionary={en} eventSlug={featuredEvent?.slug ?? null} predictionsOpen={predictionsOpen} />
        {featuredEvent ? (
          <FeaturedEvent event={featuredEvent} dictionary={en} />
        ) : null}
        <UpcomingEvents events={upcomingEvents} dictionary={en} />
        <HowItWorks dictionary={en} />
        <ClosingMoment eventSlug={featuredEvent?.slug ?? null} />
      </main>
      <Footer dictionary={en} />
    </>
  );
}
