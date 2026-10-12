# FOUCH — MGI closing polish + stable test run (node env by default, no placeholder XX flag, Up Next numbering).
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-mgi-polish.ps1
$failures = @()

try {
    $path = "src\app\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
        <UpcomingEvents events={upcomingEvents} dictionary={dict} locale={locale} comingSoonSlugs={comingSoonSlugs}
          firstNumber={featuredEvent ? 2 : 1}
        />
        <HowItWorks dictionary={dict} />
        <ClosingMoment eventSlug={featuredEvent?.slug ?? null} dictionary={dict} />
      </main>
      <Footer dictionary={dict} />
    </>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\page.tsx"
} catch {
    Write-Host "FAILED: src\app\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\page.tsx"
}

try {
    $path = "src\components\UpcomingEvents.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { splitEventNameYear } from "@/lib/event-name-split";
import { getShortLocation } from "@/lib/event-location";
import { formatEventDayMonth } from "@/lib/event-time-display";
import type { Locale } from "@/lib/locale";
import { CinematicBackdrop } from "./CinematicBackdrop";
import { TrackedLink } from "./TrackedLink";

/**
 * FOUCH Home v1.1 Round 2 — the Home's secondary "Up Next" section, a
 * more compact "trailer" treatment than Now Predicting. Renders
 * name/date/subtitle/CTA entirely from each event's own data (via the
 * same generic splitEventNameYear FeaturedEvent uses) — no per-event
 * branching. Variant 1 of the shared cinematic backdrop gives it a
 * subtly different atmosphere from the featured section, derived only
 * from its position in the list, never from which event it is.
 */
export function UpcomingEvents({
  events,
  dictionary,
  locale = "en",
  comingSoonSlugs = [],
  firstNumber = 2,
}: {
  events: FouchEvent[];
  dictionary: Dictionary;
  locale?: Locale;
  /** Slugs with no official roster yet: shown as "Coming soon", no CTA. */
  comingSoonSlugs?: string[];
  /** Section number of the first event: 2 when a featured event is shown above (01), otherwise 1. */
  firstNumber?: number;
}) {
  if (events.length === 0) return null;

  return (
    <>
      {events.map((event, index) => {
        const { primary, year } = splitEventNameYear(event.name);
        const dayMonth = formatEventDayMonth(event.eventDate, locale);

        return (
          <section key={event.slug} className="relative overflow-hidden py-8 sm:py-11">
            <CinematicBackdrop variant={1} />
            <div className="relative mx-auto max-w-content px-6">
              <div className="flex flex-wrap items-end justify-between gap-6">
                <div>
                  <div className="flex items-center gap-3">
                    <span className="font-display text-sm text-accent-strong/70">
                      {String(index + firstNumber).padStart(2, "0")}
                    </span>
                    <span className="h-px w-8 bg-border-strong" aria-hidden />
                    <span className="text-xs font-medium uppercase tracking-[0.25em] text-text-secondary">
                      {dictionary.featuredEvent.eyebrowUpcoming}
                    </span>
                  </div>

                  <h3 className="mt-3 font-display leading-[0.95] text-text-primary">
                    <span className="block text-xl sm:text-2xl">{primary}</span>
                    {year ? (
                      <span className="block text-4xl font-semibold tracking-tight sm:text-5xl">{year}</span>
                    ) : null}
                  </h3>

                  <p className="mt-2 text-sm uppercase tracking-[0.15em] text-text-muted">
                    {dayMonth} · {getShortLocation(event.subtitle ?? "")}
                  </p>
                </div>

                {comingSoonSlugs.includes(event.slug) ? (
                  <span className="inline-flex shrink-0 items-center gap-2 rounded border border-border-strong px-5 py-3 text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
                    <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-text-muted" />
                    {dictionary.homeResults.comingSoonChip}
                  </span>
                ) : (
                <TrackedLink
                  href={`/predict/${event.slug}`}
                  event="featured_event_clicked"
                  eventProperties={{ slug: event.slug, source: "upcoming_secondary" }}
                  className="group inline-flex shrink-0 items-center gap-2 rounded bg-accent px-6 py-3.5 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
                >
                  {dictionary.featuredEvent.cta}
                  <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
                </TrackedLink>
                )}
              </div>
            </div>
          </section>
        );
      })}
    </>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\UpcomingEvents.tsx"
} catch {
    Write-Host "FAILED: src\components\UpcomingEvents.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\UpcomingEvents.tsx"
}

try {
    $path = "src\components\post-event-surfaces.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\post-event-surfaces.test.ts"
} catch {
    Write-Host "FAILED: src\components\post-event-surfaces.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\post-event-surfaces.test.ts"
}

try {
    $path = "src\components\scoring\LeaderboardRow.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { CountryFlag } from "@/components/CountryFlag";
import { TrackedLink } from "@/components/TrackedLink";
import type { LeaderboardEntry } from "@/lib/leaderboard";

export function LeaderboardRow({
  entry,
  eventSlug,
  isViewer,
  prominent,
  youLabel = "You",
}: {
  entry: LeaderboardEntry;
  eventSlug: string;
  isViewer: boolean;
  /** Top 3 get slightly stronger typography — restrained, no medals. */
  prominent: boolean;
  /** Localized "You" marker (i18n v1). */
  youLabel?: string;
}) {
  return (
    <TrackedLink
      href={`/p/${entry.publicId}`}
      event="leaderboard_row_clicked"
      eventProperties={{ event_slug: eventSlug, rank: entry.rank, score_band: entry.band }}
      className={`flex items-center gap-3 rounded border px-4 py-3 transition-colors hover:border-accent ${
        isViewer ? "border-accent bg-accent/10" : "border-border bg-surface"
      }`}
    >
      <span
        className={`font-display shrink-0 text-accent-strong ${prominent ? "w-10 text-3xl" : "w-8 text-base"}`}
      >
        {String(entry.rank).padStart(2, "0")}
      </span>
      {entry.countryCode ? (
        <CountryFlag countryCode={entry.countryCode} className={prominent ? "text-2xl" : "text-lg"} />
      ) : null}
      <span className={`flex-1 truncate text-text-primary ${prominent ? "text-lg" : "text-sm"}`}>
        {entry.nickname || "Anonymous"}
        {isViewer ? <span className="ml-2 text-xs uppercase tracking-wide text-accent-strong">{youLabel}</span> : null}
      </span>
      <span className={`font-display text-text-primary ${prominent ? "text-2xl" : "text-base"}`}>
        {entry.score}
      </span>
    </TrackedLink>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\LeaderboardRow.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\LeaderboardRow.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\LeaderboardRow.tsx"
}

try {
    $path = "src\lib\analytics-locale.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from "vitest";

describe("analytics — locale property on every event (i18n v1)", () => {
  const originalKey = process.env.NEXT_PUBLIC_POSTHOG_KEY;
  afterEach(() => {
    if (originalKey === undefined) delete process.env.NEXT_PUBLIC_POSTHOG_KEY;
    else process.env.NEXT_PUBLIC_POSTHOG_KEY = originalKey;
    vi.resetModules();
    vi.restoreAllMocks();
  });

  async function setup() {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    const captureSpy = vi.fn();
    vi.doMock("posthog-js", () => ({ default: { init: vi.fn(), capture: captureSpy } }));
    const analytics = await import("./analytics");
    return { ...analytics, captureSpy };
  }

  it("attaches locale to the funnel events once the UI language is known", async () => {
    const { track, setAnalyticsLocale, captureSpy } = await setup();
    setAnalyticsLocale("es");
    for (const event of [
      "landing_view",
      "start_prediction",
      "prediction_completed",
      "verification_sent",
      "prediction_submitted",
      "you_vs_world_viewed",
      "share_clicked",
      "instagram_story_clicked",
    ] as const) {
      track(event, { event_slug: "miss-grand-international-2026" });
      expect(captureSpy).toHaveBeenLastCalledWith(event, {
        locale: "es",
        event_slug: "miss-grand-international-2026",
      });
    }
  });

  it("existing event names are unchanged and still fire with their original properties plus locale", async () => {
    const { track, setAnalyticsLocale, captureSpy } = await setup();
    setAnalyticsLocale("en");
    track("prediction_submitted", { event_slug: "e", utm_source: "whatsapp" });
    expect(captureSpy).toHaveBeenCalledWith("prediction_submitted", {
      locale: "en",
      event_slug: "e",
      utm_source: "whatsapp",
    });
  });

  it("language_changed carries from_locale, to_locale, page and event_slug", async () => {
    const { track, setAnalyticsLocale, captureSpy } = await setup();
    setAnalyticsLocale("en");
    track("language_changed", {
      from_locale: "en",
      to_locale: "es",
      page: "/predict/miss-grand-international-2026",
      event_slug: "miss-grand-international-2026",
    });
    expect(captureSpy).toHaveBeenCalledWith("language_changed", {
      locale: "en",
      from_locale: "en",
      to_locale: "es",
      page: "/predict/miss-grand-international-2026",
      event_slug: "miss-grand-international-2026",
    });
  });

  it("no locale property is added before a locale is set (existing behavior untouched)", async () => {
    const { track, captureSpy } = await setup();
    track("landing_view", { utm_source: "x" });
    expect(captureSpy).toHaveBeenCalledWith("landing_view", { utm_source: "x" });
  });

  it("an explicit locale in the call's own properties wins", async () => {
    const { track, setAnalyticsLocale, captureSpy } = await setup();
    setAnalyticsLocale("es");
    track("landing_view", { locale: "en" });
    expect(captureSpy).toHaveBeenCalledWith("landing_view", { locale: "en" });
  });

  it("still never sends private identifiers (locale is the only addition)", async () => {
    const { track, setAnalyticsLocale, captureSpy } = await setup();
    setAnalyticsLocale("es");
    track("instagram_story_clicked", {
      event_slug: "e",
      prediction_public_id: "abc123",
      device_type: "mobile",
      share_method: "native_share",
    });
    const props = captureSpy.mock.calls[0]?.[1] as Record<string, unknown>;
    expect(Object.keys(props).sort()).toEqual(
      ["device_type", "event_slug", "locale", "prediction_public_id", "share_method"].sort(),
    );
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\analytics-locale.test.ts"
} catch {
    Write-Host "FAILED: src\lib\analytics-locale.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\analytics-locale.test.ts"
}

try {
    $path = "src\lib\analytics.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
// @vitest-environment jsdom
import { describe, it, expect, vi, afterEach } from "vitest";

describe("track() — Beta Hardening 0.1: analytics must never break the product", () => {
  const originalKey = process.env.NEXT_PUBLIC_POSTHOG_KEY;

  afterEach(() => {
    if (originalKey === undefined) delete process.env.NEXT_PUBLIC_POSTHOG_KEY;
    else process.env.NEXT_PUBLIC_POSTHOG_KEY = originalKey;
    vi.resetModules();
    vi.restoreAllMocks();
  });

  it("does not throw when no PostHog key is configured (falls back silently)", async () => {
    delete process.env.NEXT_PUBLIC_POSTHOG_KEY;
    vi.resetModules();
    const { track } = await import("./analytics");
    const debugSpy = vi.spyOn(console, "debug").mockImplementation(() => {});

    expect(() => track("landing_view", { utm_source: "reddit" })).not.toThrow();
    expect(debugSpy).toHaveBeenCalledWith("[fouch:analytics]", "landing_view", { utm_source: "reddit" });
  });

  it("does not throw even if posthog.init itself throws", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    vi.doMock("posthog-js", () => ({
      default: {
        init: () => {
          throw new Error("network unavailable");
        },
        capture: vi.fn(),
      },
    }));
    const { track } = await import("./analytics");

    expect(() => track("prediction_submitted", { event_slug: "miss-universe-2026" })).not.toThrow();
  });

  it("does not throw even if posthog.capture itself throws (ad blocker, etc.)", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    vi.doMock("posthog-js", () => ({
      default: {
        init: vi.fn(),
        capture: () => {
          throw new Error("blocked by client");
        },
      },
    }));
    const { track } = await import("./analytics");

    expect(() => track("prediction_submitted", { event_slug: "miss-universe-2026" })).not.toThrow();
  });

  it("calls posthog.capture with the exact event name and properties when configured", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    const captureSpy = vi.fn();
    vi.doMock("posthog-js", () => ({
      default: { init: vi.fn(), capture: captureSpy },
    }));
    const { track } = await import("./analytics");

    track("score_viewed", { event_slug: "miss-universe-2026", score_band: "EXCELLENT" });

    expect(captureSpy).toHaveBeenCalledWith("score_viewed", {
      event_slug: "miss-universe-2026",
      score_band: "EXCELLENT",
    });
  });

  it("never calls posthog.identify — stays on anonymous distinct_id semantics", async () => {
    process.env.NEXT_PUBLIC_POSTHOG_KEY = "test-key";
    vi.resetModules();
    const identifySpy = vi.fn();
    vi.doMock("posthog-js", () => ({
      default: { init: vi.fn(), capture: vi.fn(), identify: identifySpy },
    }));
    const { track } = await import("./analytics");

    track("public_prediction_viewed", { event_slug: "miss-universe-2026" });

    expect(identifySpy).not.toHaveBeenCalled();
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\analytics.test.ts"
} catch {
    Write-Host "FAILED: src\lib\analytics.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\analytics.test.ts"
}

try {
    $path = "src\lib\attribution.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
// @vitest-environment jsdom
import { describe, it, expect, beforeEach } from "vitest";
import { captureUtmSource } from "./attribution";

function setUrl(search: string) {
  window.history.pushState({}, "", `/${search}`);
}

describe("captureUtmSource", () => {
  beforeEach(() => {
    window.sessionStorage.clear();
    setUrl("");
  });

  it("captures a simple source (reddit)", () => {
    setUrl("?utm_source=reddit");
    expect(captureUtmSource()).toBe("reddit");
  });

  it("captures another simple source (instagram)", () => {
    setUrl("?utm_source=instagram");
    expect(captureUtmSource()).toBe("instagram");
  });

  it("returns null with no utm_source and nothing previously captured", () => {
    setUrl("");
    expect(captureUtmSource()).toBeNull();
  });

  it("persists across calls within the same session even after the param is gone", () => {
    setUrl("?utm_source=missosology");
    expect(captureUtmSource()).toBe("missosology");
    setUrl(""); // simulate navigating to a page with no query string
    expect(captureUtmSource()).toBe("missosology");
  });

  it("sanitizes an overly long source by truncating", () => {
    const long = "a".repeat(200);
    setUrl(`?utm_source=${long}`);
    const result = captureUtmSource();
    expect(result).not.toBeNull();
    expect(result!.length).toBeLessThanOrEqual(50);
  });

  it("sanitizes malformed characters out of the source", () => {
    setUrl(`?utm_source=${encodeURIComponent("<script>alert(1)</script>")}`);
    const result = captureUtmSource();
    expect(result).not.toContain("<");
    expect(result).not.toContain(">");
  });

  it("a new utm_source overwrites a previously captured one", () => {
    setUrl("?utm_source=reddit");
    captureUtmSource();
    setUrl("?utm_source=creator");
    expect(captureUtmSource()).toBe("creator");
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\attribution.test.ts"
} catch {
    Write-Host "FAILED: src\lib\attribution.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\attribution.test.ts"
}

try {
    $path = "vitest.config.mts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { defineConfig } from "vitest/config";

// Vitest doesn't read tsconfig "paths" automatically. Previous test
// files avoided this by only using relative imports; leaderboard.ts
// needs the project's standard "@/..." alias (src/lib/scoring), so
// this maps it the same way Next.js already does via tsconfig.json.
//
// environment: "jsdom" — Beta Hardening 0.1 added tests that touch
// `window`/`sessionStorage` (attribution.ts, analytics.ts). jsdom is a
// safe superset for the existing pure-Node tests too (scoring,
// leaderboard, community-comparison never reference window).
// i18n v1: the app's tsconfig uses "jsx": "preserve" (Next compiles JSX
// itself), which Vite can't parse. Enabling the automatic JSX runtime for
// tests ONLY lets the localized share-card markup be rendered and
// asserted directly. It does not touch the Next.js build.
export default defineConfig({
  oxc: { jsx: { runtime: "automatic" } },
  test: {
    // Most tests are pure logic or static markup and need no DOM. Booting
    // a jsdom window for every file made the suite slow enough on a busy
    // machine to trip vitest's 5s default on module-import-heavy tests, so
    // the default is node and the few files that touch window/sessionStorage
    // opt in with `// @vitest-environment jsdom`.
    environment: "node",
    // Cold module transforms (posthog-js) can be slow on a loaded machine;
    // a generous ceiling removes the false timeout without weakening any
    // assertion.
    testTimeout: 30000,
    hookTimeout: 30000,
  },
  resolve: {
    alias: {
      "@": new URL("./src", import.meta.url).pathname,
    },
  },
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     vitest.config.mts"
} catch {
    Write-Host "FAILED: vitest.config.mts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "vitest.config.mts"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 8 files written successfully." -ForegroundColor Green
}