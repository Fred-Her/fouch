import { en } from "@/content/en";
import { getFeaturedEvent } from "@/lib/events";
import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { FeaturedEvent } from "@/components/FeaturedEvent";
import { HowItWorks } from "@/components/HowItWorks";
import { Footer } from "@/components/Footer";
import { ViewTracker } from "@/components/ViewTracker";

export default function Home() {
  const featuredEvent = getFeaturedEvent();

  return (
    <>
      <ViewTracker event="landing_view" />
      <Nav />
      <main>
        <Hero dictionary={en} />
        {featuredEvent ? (
          <FeaturedEvent event={featuredEvent} dictionary={en} />
        ) : null}
        <HowItWorks dictionary={en} />
      </main>
      <Footer dictionary={en} />
    </>
  );
}
