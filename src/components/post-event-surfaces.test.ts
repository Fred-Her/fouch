import { describe, it, expect, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";

vi.mock("next/navigation", () => ({ useSearchParams: () => new URLSearchParams() }));

import { I18nProvider } from "@/components/I18nProvider";
import { PredictionUnavailable } from "@/components/PredictionUnavailable";
import { ResultsLink } from "@/components/ResultsLink";
import { UpcomingEvents } from "@/components/UpcomingEvents";
import { PublicPredictionView } from "@/components/prediction/PublicPredictionView";
import { LeaderboardRow } from "@/components/scoring/LeaderboardRow";
import { en } from "@/content/en";
import { es } from "@/content/es";
import type { Participant } from "@/types/participant";
import type { FouchEvent } from "@/types/event";

const mgi = { slug: "miss-grand-international-2026", name: "Miss Grand International 2026" } as FouchEvent;
const mu = {
  id: "mu",
  slug: "miss-universe-2026",
  name: "Miss Universe 2026",
  category: "pageant",
  status: "upcoming",
  eventDate: "2026-11-24",
  isFeatured: false,
  subtitle: "José Miguel Agrelot Coliseum, San Juan, Puerto Rico",
} as FouchEvent;

const withI18n = (locale: "en" | "es", child: ReturnType<typeof createElement>) =>
  // eslint-disable-next-line react/no-children-prop
  createElement(I18nProvider, { locale, dict: locale === "es" ? es : en, children: child });

describe("Home — MGI results link (EN/ES)", () => {
  it("English: 'MGI 2026 Results → View Leaderboard' linking to the final leaderboard", () => {
    const html = renderToStaticMarkup(createElement(ResultsLink, { event: mgi, dictionary: en }));
    expect(html).toContain("MGI 2026 Results → View Leaderboard");
    expect(html).toContain('href="/events/miss-grand-international-2026/leaderboard"');
  });
  it("Spanish: 'Resultados MGI 2026 → Ver clasificación'", () => {
    const html = renderToStaticMarkup(createElement(ResultsLink, { event: mgi, dictionary: es }));
    expect(html).toContain("Resultados MGI 2026 → Ver clasificación");
  });
});

describe("Home — Up Next shows 'Coming soon' (no builder CTA) for events without an official roster", () => {
  it("coming-soon event: chip, and NO link to its builder", () => {
    const html = renderToStaticMarkup(
      createElement(UpcomingEvents, { events: [mu], dictionary: en, locale: "en", comingSoonSlugs: ["miss-universe-2026"] }),
    );
    expect(html).toContain("Coming soon");
    expect(html).not.toContain("/predict/miss-universe-2026");
    expect(html).not.toContain("Make your Top 10");
    expect(html).toContain("NOV 24 · San Juan, Puerto Rico");
  });
  it("Spanish chip", () => {
    const html = renderToStaticMarkup(
      createElement(UpcomingEvents, { events: [mu], dictionary: es, locale: "es", comingSoonSlugs: ["miss-universe-2026"] }),
    );
    expect(html).toContain("Próximamente");
  });
  it("a ready event still gets its normal CTA (comingSoonSlugs is opt-in per event)", () => {
    const html = renderToStaticMarkup(
      createElement(UpcomingEvents, { events: [mu], dictionary: en, locale: "en", comingSoonSlugs: [] }),
    );
    expect(html).toContain("/predict/miss-universe-2026");
  });
});

describe("Up Next numbering", () => {
  it("starts at 02 under a featured event, and at 01 when there is none", () => {
    const withFeatured = renderToStaticMarkup(
      createElement(UpcomingEvents, { events: [mu], dictionary: en, locale: "en", comingSoonSlugs: ["miss-universe-2026"] }),
    );
    expect(withFeatured).toContain(">02<");
    const alone = renderToStaticMarkup(
      createElement(UpcomingEvents, { events: [mu], dictionary: en, locale: "en", comingSoonSlugs: ["miss-universe-2026"], firstNumber: 1 }),
    );
    expect(alone).toContain(">01<");
    expect(alone).not.toContain(">02<");
  });
});

describe("PredictionUnavailable — closed and coming-soon states", () => {
  it("closed: explains it and links to results/leaderboard", () => {
    const html = renderToStaticMarkup(
      withI18n("en", createElement(PredictionUnavailable, { variant: "closed", eventName: mgi.name, eventSlug: mgi.slug, dictionary: en })),
    );
    expect(html).toContain("Predictions are closed");
    expect(html).toContain('href="/events/miss-grand-international-2026/leaderboard"');
  });
  it("coming soon (Spanish): no builder, no placeholder predictions", () => {
    const html = renderToStaticMarkup(
      withI18n("es", createElement(PredictionUnavailable, { variant: "coming_soon", eventName: mu.name, eventSlug: mu.slug, dictionary: es })),
    );
    expect(html).toContain("Próximamente");
    expect(html).toContain("Miss Universe 2026 llega pronto");
    expect(html).not.toContain("/leaderboard");
  });
});

describe("Public prediction after the result", () => {
  const p = (id: string, name: string, code: string, country: string, i: number): Participant => ({
    id, eventId: "e", displayName: name, countryCode: code, countryName: country, sortOrder: i, isActive: true,
  });
  const ranked = [p("TZ", "JIHAN DIMACHK", "TZ", "Tanzania", 0), p("XX", "SOMEONE ELSE", "CL", "Chile", 1)];

  const render = (locale: "en" | "es", extra: Record<string, unknown>) =>
    renderToStaticMarkup(
      withI18n(
        locale,
        createElement(PublicPredictionView, {
          eventSlug: mgi.slug,
          publicId: "abc123",
          rankedParticipants: ranked,
          hasResult: true,
          youVsTheWorld: null,
          ...extra,
        }),
      ),
    );

  it("marks each saved pick (right place / out) with an accessible label, and shows the legend with Top 11", () => {
    const html = render("en", { pickMarks: { TZ: "exact", XX: "out" }, officialTopSize: 11, predictionsClosed: true, nextEvent: null });
    expect(html).toContain('aria-label="In the right place"');
    expect(html).toContain('aria-label="Not in the Top 11"');
    expect(html).toContain("In the Top 11, different place");
  });

  it("closed event: the bottom CTA introduces Miss Universe as Coming soon (not this event's builder)", () => {
    const html = render("en", {
      predictionsClosed: true,
      nextEvent: { slug: mu.slug, name: mu.name, comingSoon: true },
    });
    expect(html).toContain("Miss Universe 2026 · Coming soon");
    expect(html).toContain('href="/predict/miss-universe-2026"');
    expect(html).not.toContain("?from=abc123");
  });

  it("Spanish closed CTA", () => {
    const html = render("es", { predictionsClosed: true, nextEvent: { slug: mu.slug, name: mu.name, comingSoon: true } });
    expect(html).toContain("Miss Universe 2026 · Próximamente");
  });

  it("open event: unchanged — the CTA still points at this event's builder", () => {
    const html = render("en", { predictionsClosed: false });
    expect(html).toContain("/predict/miss-grand-international-2026?from=abc123");
  });

  it("the original URL/public id never changes", () => {
    const html = render("en", { predictionsClosed: true, nextEvent: null });
    expect(html).toContain("/p/abc123");
  });
});

describe("Leaderboard row — no placeholder badge for entries without a country", () => {
  const entry = { publicId: "j6p7x6hef", nickname: "Alguien", countryCode: null, score: 37, band: "MISSED_IT", rank: 1 } as never;
  it("renders no 'XX' badge when the predictor left the country empty", () => {
    const html = renderToStaticMarkup(createElement(LeaderboardRow, { entry, eventSlug: "e", isViewer: false, prominent: true }));
    expect(html).not.toContain(">XX<");
    expect(html).toContain("Alguien");
  });
  it("still renders the flag when a country exists", () => {
    const withCountry = { publicId: "p", nickname: "Perez", countryCode: "CV", score: 5, band: "MISSED_IT", rank: 3 } as never;
    const html = renderToStaticMarkup(createElement(LeaderboardRow, { entry: withCountry, eventSlug: "e", isViewer: false, prominent: false }));
    expect(html).toContain("<svg");
  });
});
