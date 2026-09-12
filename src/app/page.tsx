import { en } from "@/content/en";
import { getFeaturedEvent } from "@/lib/events";
import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { FeaturedEvent } from "@/components/FeaturedEvent";
import { HowItWorks } from "@/components/HowItWorks";
import { Footer } from "@/components/Footer";
import { ViewTracker } from "@/components/ViewTracker";

// Sprint 5.1: FeaturedEvent checks live result state (for the secondary
// leaderboard link) — force fresh execution so that check is never
// baked into a static build and left stale until the next deploy.
export const dynamic = "force-dynamic";

export default function Home() {
  const featuredEvent = getFeaturedEvent();

  return (
    <>
      <ViewTracker event="landing_view" />
      <Nav />
      <main>
        <Hero dictionary={en} eventSlug={featuredEvent?.slug ?? null} />
        {featuredEvent ? (
          <FeaturedEvent event={featuredEvent} dictionary={en} />
        ) : null}
        <HowItWorks dictionary={en} />
      </main>
      <Footer dictionary={en} />
    </>
  );
}