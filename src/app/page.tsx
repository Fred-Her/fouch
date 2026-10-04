import { getI18n } from "@/lib/i18n-server";
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
  const { locale, dict } = await getI18n();
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
        <Hero dictionary={dict} eventSlug={featuredEvent?.slug ?? null} predictionsOpen={predictionsOpen} />
        {featuredEvent ? (
          <FeaturedEvent event={featuredEvent} dictionary={dict} locale={locale} />
        ) : null}
        <UpcomingEvents events={upcomingEvents} dictionary={dict} locale={locale} />
        <HowItWorks dictionary={dict} />
        <ClosingMoment eventSlug={featuredEvent?.slug ?? null} dictionary={dict} />
      </main>
      <Footer dictionary={dict} />
    </>
  );
}
