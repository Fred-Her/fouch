# FOUCH — Open Miss Universe 2026: DB-first roster, "Make your prediction" CTAs, roster-change notice, read-only demo predictions, launch SQL.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-open-miss-universe.ps1
$failures = @()

try {
    $path = "src\app\p\[publicId]\edit\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { notFound, redirect } from "next/navigation";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { EditPredictionFlow } from "@/components/prediction/EditPredictionFlow";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { getI18n } from "@/lib/i18n-server";
import { fmt } from "@/lib/i18n";

/**
 * FOUCH 0.3A â€” the edit entry point. This route is intentionally
 * unreachable in a way that actually matters for two cases, checked
 * server-side (never just hidden in the UI, since a direct URL visit
 * bypasses any client-side hiding):
 *
 *  - legacy anonymous prediction (no verified owner) â€” there is no
 *    identity to authorize an edit against, and this sprint adds no
 *    way to claim one, so editing is simply never offered;
 *  - the event has passed prediction_lock_at â€” editing closes at
 *    lock, full stop.
 *
 * Both redirect back to the public page rather than 404 â€” the
 * prediction itself is real and viewable, only editing isn't
 * available. The actual SAVE action (verify-actions.ts) independently
 * re-checks both of these server-side again at save time â€” this
 * page's checks are only about whether to show the builder at all,
 * never the authorization boundary itself.
 */
export default async function EditPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const { locale, dict } = await getI18n();
  const record = await getPredictionWithParticipants(publicId, locale);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;

  if (!prediction.hasVerifiedOwner || prediction.dataStatus === "demo") {
    redirect(`/p/${publicId}`);
  }

  const lockConfig = await getEventLockConfig(event.slug);
  if (!isPredictionWindowOpen(lockConfig, Date.now())) {
    redirect(`/p/${publicId}`);
  }

  const participantData = await getParticipantsForEvent(event.slug, locale);
  if (!participantData) notFound();

  const requiredCount = Math.min(10, participantData.participants.length);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <div className="flex items-start justify-between gap-4">
        <h1 className="font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
        <LanguageSwitcher eventSlug={event.slug} />
      </div>
      <p className="mt-1 text-sm text-text-secondary">{fmt(dict.publicPrediction.editTitle, { n: requiredCount })}</p>

      <EditPredictionFlow
        eventSlug={event.slug}
        publicId={publicId}
        allParticipants={participantData.participants}
        initialRankedParticipants={rankedParticipants}
        requiredCount={requiredCount}
        expectedVersionNumber={prediction.currentVersionNumber}
        predictionLockAt={lockConfig?.predictionLockAt ?? null}
        predictionTimezone={lockConfig?.timezone ?? null}
      />
    </main>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\edit\page.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\edit\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\edit\page.tsx"
}

try {
    $path = "src\app\p\[publicId]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CountryFlag } from "@/components/CountryFlag";
import { siteUrl } from "@/lib/site";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getOfficialResult } from "@/lib/results-db";
import { formatContestantListUpdated } from "@/lib/event-time-display";
import { getPredictorCountryName } from "@/lib/countries";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { getI18n } from "@/lib/i18n-server";
import { fmt } from "@/lib/i18n";
import { localizePath } from "@/lib/locale";
import { PublicPredictionView } from "@/components/prediction/PublicPredictionView";
import { YouVsTheWorld } from "@/components/prediction/YouVsTheWorld";
import { FouchScore } from "@/components/scoring/FouchScore";
import { YourCrowdChanged } from "@/components/scoring/YourCrowdChanged";
import { OfficialResult } from "@/components/OfficialResult";
import { classifyPicks, buildOfficialFinish } from "@/lib/official-result-display";
import { getNextEvent } from "@/lib/next-event";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ publicId: string }>;
}): Promise<Metadata> {
  const { publicId } = await params;
  const { locale, dict } = await getI18n();
  const record = await getPredictionWithParticipants(publicId, locale);
  if (!record) return {};

  const t = dict.publicPrediction;
  const title = record.prediction.nickname
    ? fmt(t.metaTitleNamed, { name: record.prediction.nickname, event: record.event.name })
    : fmt(t.metaTitleAnon, { event: record.event.name });
  const description = t.metaDescription;
  // The Spanish page advertises its own /es URL and /es OG image; both
  // resolve to the same prediction as the unprefixed ones.
  const publicPath = localizePath(`/p/${publicId}`, locale);

  return {
    title,
    description,
    // Sprint 2 decision: public prediction pages are reachable via
    // link but intentionally not indexed â€” we don't want thousands of
    // thin user-generated pages in search results. `follow` so the
    // "Make your Top 10" CTA is still crawlable back to the real
    // product pages.
    robots: { index: false, follow: true },
    openGraph: {
      title,
      description,
      url: `${siteUrl}${publicPath}`,
      images: [`${siteUrl}${publicPath}/opengraph-image`],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
    },
  };
}

export default async function PublicPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const { locale, dict } = await getI18n();
  const record = await getPredictionWithParticipants(publicId, locale);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;
  const heading = prediction.nickname
    ? fmt(dict.publicPrediction.titleWithName, { name: prediction.nickname })
    : dict.publicPrediction.titleAnonymous;

  // Cheap existence check only (no percentile/breakdown work) â€” used
  // purely to decide share-CTA hierarchy (Sprint 4.1 Â§7-8). FouchScore
  // below independently does the full scored computation; this is a
  // second, lightweight read of the same result row, not duplicated
  // scoring logic.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);
  const hasResult = Boolean(official);
  const pickMarks = official ? classifyPicks(prediction.rankedParticipantIds, official) : undefined;
  const officialTopSize = official ? buildOfficialFinish(official).topSize : 10;

  // FOUCH 0.3A: editing is offered only for a verified prediction
  // while the event is still open â€” fetched fresh on every page view
  // from the single authoritative source, never cached/assumed.
  const lockConfig = await getEventLockConfig(event.slug);
  const isPredictionOpen = isPredictionWindowOpen(lockConfig, Date.now());
  // A demo prediction was made against placeholder data; once the event runs on
  // its real roster it stays viewable (with its banner) but is never editable.
  const isDemoPrediction = prediction.dataStatus === "demo";
  const canEdit = prediction.hasVerifiedOwner && isPredictionOpen && !isDemoPrediction;
  const showLockedNotice = prediction.hasVerifiedOwner && !isPredictionOpen && !isDemoPrediction;
  const nextEvent = isPredictionOpen ? null : await getNextEvent(event.slug, locale);

  // FOUCH 0.3B Â§13: "Contestant list updated {date}" for a real,
  // non-demo event with verified-roster provenance â€” never "Demo
  // prediction" for one of these. Null (no participant rows checked
  // yet, or a hardcoded/demo event) simply shows nothing extra here.
  const participantData = await getParticipantsForEvent(event.slug, locale);
  const sourceCheckedAt = participantData?.sourceCheckedAt ?? null;

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <div className="flex items-center justify-between">
        <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
          FOUCH
        </Link>
        <LanguageSwitcher eventSlug={event.slug} />
      </div>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-2 font-display text-xl uppercase tracking-tight text-text-primary">
        {heading}
      </p>

      {prediction.countryCode ? (
        <p className="mt-1 flex items-center gap-1.5 text-sm text-text-muted">
          <CountryFlag countryCode={prediction.countryCode} />
          {getPredictorCountryName(prediction.countryCode, locale)}
        </p>
      ) : null}

      {prediction.dataStatus === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          {dict.publicPrediction.demoBanner}
          {prediction.hasVerifiedOwner ? <span className="mt-1 block">{dict.publicPrediction.demoNoEdit}</span> : null}
        </p>
      ) : sourceCheckedAt ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          {formatContestantListUpdated(sourceCheckedAt, dict.builder.listUpdated, locale)}
        </p>
      ) : null}

      <PublicPredictionView
        eventSlug={event.slug}
        publicId={publicId}
        rankedParticipants={rankedParticipants}
        hasResult={hasResult}
        canEdit={canEdit}
        showLockedNotice={showLockedNotice}
        predictionLockAt={lockConfig?.predictionLockAt ?? null}
        predictionTimezone={lockConfig?.timezone ?? null}
        fouchScore={<FouchScore prediction={prediction} event={event} publicId={publicId} />}
        officialResultSection={
          official ? (
            <OfficialResult eventSlug={event.slug} official={official} dictionary={dict} locale={locale} />
          ) : undefined
        }
        pickMarks={pickMarks}
        officialTopSize={officialTopSize}
        predictionsClosed={!isPredictionOpen}
        nextEvent={nextEvent}
        youVsTheWorld={<YouVsTheWorld prediction={prediction} event={event} />}
        yourCrowdChanged={<YourCrowdChanged prediction={prediction} event={event} />}
      />
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\page.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\page.tsx"
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
    expect(html).not.toContain("Make your prediction");
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

describe("Roster changes never silently alter a saved prediction — they warn the owner", () => {
  const rp = (id: string, name: string, active: boolean): Participant => ({
    id, eventId: "e", displayName: name, countryCode: "CL", countryName: "Chile", sortOrder: 0, isActive: active,
  });
  const ranked = [rp("a", "STILL IN", true), rp("b", "WITHDRAWN ONE", false)];
  const render = (locale: "en" | "es", extra: Record<string, unknown>) =>
    renderToStaticMarkup(
      withI18n(
        locale,
        createElement(PublicPredictionView, {
          eventSlug: mu.slug,
          publicId: "abc123",
          rankedParticipants: ranked,
          youVsTheWorld: null,
          ...extra,
        }),
      ),
    );

  it("marks the pick that left the lineup and shows the owner a notice while predictions are open", () => {
    const html = render("en", { canEdit: true });
    expect(html).toContain("No longer in the lineup");
    expect(html).toContain("One or more of your picks is no longer in the official lineup");
    expect(html).toContain("WITHDRAWN ONE");
  });
  it("Spanish copy", () => {
    const html = render("es", { canEdit: true });
    expect(html).toContain("Ya no está en la lista");
    expect(html).toContain("Edita tu predicción para reemplazarlas");
  });
  it("no owner notice once the prediction can't be edited, but the badge stays (history is preserved, never rewritten)", () => {
    const html = render("en", { canEdit: false });
    expect(html).toContain("No longer in the lineup");
    expect(html).not.toContain("One or more of your picks");
  });
  it("a prediction whose picks are all still in the lineup shows neither", () => {
    const html = renderToStaticMarkup(
      withI18n(
        "en",
        createElement(PublicPredictionView, {
          eventSlug: mu.slug,
          publicId: "abc123",
          rankedParticipants: [rp("a", "STILL IN", true)],
          canEdit: true,
          youVsTheWorld: null,
        }),
      ),
    );
    expect(html).not.toContain("No longer in the lineup");
  });
});

describe("Primary CTA copy (EN/ES)", () => {
  it("English: 'Make your prediction' on the hero and the featured event", () => {
    expect(en.hero.cta).toBe("Make your prediction");
    expect(en.featuredEvent.cta).toBe("Make your prediction");
  });
  it("Spanish: 'Haz tu predicción'", () => {
    expect(es.hero.cta).toBe("Haz tu predicción");
    expect(es.featuredEvent.cta).toBe("Haz tu predicción");
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
    $path = "src\components\prediction\PublicPredictionView.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, type ReactNode } from "react";
import { useSearchParams } from "next/navigation";
import Link from "next/link";
import { Pencil, Check, Minus, X } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import { formatEventLocalLockTime } from "@/lib/event-time-display";
import type { Participant } from "@/types/participant";
import type { PickMark } from "@/lib/official-result-display";
import { ShareActions } from "./ShareActions";
import { useI18n } from "@/components/I18nProvider";
import { fmt } from "@/lib/i18n";
import { localizePath } from "@/lib/locale";

export function PublicPredictionView({
  eventSlug,
  publicId,
  rankedParticipants,
  hasResult = false,
  canEdit = false,
  showLockedNotice = false,
  predictionLockAt = null,
  predictionTimezone = null,
  fouchScore,
  officialResultSection,
  pickMarks,
  officialTopSize = 10,
  predictionsClosed = false,
  nextEvent = null,
  youVsTheWorld,
  yourCrowdChanged,
}: {
  eventSlug: string;
  publicId: string;
  rankedParticipants: Participant[];
  /** Sprint 4.1: whether an official/demo result exists for this
   * prediction's event. Drives share-CTA hierarchy only — the original
   * Prediction Card share section becomes visually secondary once a
   * Result Card exists to share instead (brief §7-8). Does not affect
   * scoring or any calculation. */
  hasResult?: boolean;
  /** FOUCH 0.3A: true only for a verified prediction (auth_user_id
   * set) while the event is still open per Supabase
   * events.prediction_lock_at. A legacy anonymous prediction never
   * gets this — there is no verified identity to authorize an edit
   * against, and this sprint adds no way to claim one. */
  canEdit?: boolean;
  /** FOUCH 0.3A: true for a verified prediction whose event has
   * passed prediction_lock_at — shows "YOUR CALL IS LOCKED" instead
   * of an edit affordance. Never shown for legacy predictions, which
   * never offered editing in the first place. */
  showLockedNotice?: boolean;
  /** ISO datetime, only used for display ("until {date}"). */
  predictionLockAt?: string | null;
  /** FOUCH 0.3A.1 — IANA timezone identifier for the event (e.g.
   * "America/Puerto_Rico"), used ONLY to render predictionLockAt
   * unambiguously in event-local time (see event-time-display.ts).
   * Null falls back to an explicit UTC-labeled rendering — never the
   * viewer's browser timezone. */
  predictionTimezone?: string | null;
  /** FOUCH Score section (Sprint 4) — null/absent renders nothing, which
   * is exactly the pre-result experience. Server Component, passed down
   * for the same reason as youVsTheWorld below. */
  fouchScore?: ReactNode;
  /** Post-event: the official finish (Server Component), rendered
   * right after the score. Absent before a result exists. */
  officialResultSection?: ReactNode;
  /** Post-event: how each of the user's saved picks landed, keyed by
   * participant id — display only, derived from the same ranges the
   * score uses. Absent before a result exists. */
  pickMarks?: Record<string, PickMark>;
  /** 10 for a conventional Top 10, 11 for a tied Top 11 (labels only). */
  officialTopSize?: number;
  /** True once the event's prediction window has ended: the bottom CTA
   * stops pointing at this (closed) event's builder. */
  predictionsClosed?: boolean;
  /** The next event to introduce after this one, if any. */
  nextEvent?: { slug: string; name: string; comingSoon: boolean } | null;
  /** The You vs The World section — a Server Component rendered by the
   * page and passed down, since it needs server-side data fetching
   * that a Client Component can't do directly. */
  youVsTheWorld: ReactNode;
  /** Experiment 01 ("Your Crowd Changed") — null/absent renders
   * nothing, same pattern as the two slots above. */
  yourCrowdChanged?: ReactNode;
}) {
  const searchParams = useSearchParams();
  const { locale, dict } = useI18n();
  const pt = dict.publicPrediction;
  const ut = dict.unavailable;
  const isNew = searchParams.get("new") === "1";
  const isEdited = searchParams.get("edited") === "1";
  const showSavedBanner = isNew || isEdited;

  useEffect(() => {
    track("public_prediction_viewed", { event_slug: eventSlug, is_new: isNew });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (isNew) {
      track("prediction_card_generated", { event_slug: eventSlug });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // A shared link carries the language: a Spanish sharer's link opens
  // in Spanish. /es/p/x and /p/x are the SAME prediction.
  const publicPath = localizePath(`/p/${publicId}`, locale);
  const publicUrl = `${siteUrl}${publicPath}`;

  const originalPredictionShare = (
    <div id="share" className="mt-10 scroll-mt-20 border-t border-border pt-8">
      <p
        className={
          hasResult
            ? "text-sm text-text-muted"
            : "font-display text-lg text-text-primary"
        }
      >
        {hasResult ? pt.originalPrediction : pt.shareHeading}
      </p>
      <div className="mt-3">
        <ShareActions
          eventSlug={eventSlug}
          publicId={publicId}
          publicUrl={publicUrl}
          storyCardUrl={`${publicPath}/card/story`}
          postCardUrl={`${publicPath}/card/post`}
        />
      </div>
    </div>
  );

  return (
    <div>
      {showSavedBanner ? (
        <div className="mt-4">
          <p className="font-display text-lg text-accent-strong">{pt.callIsIn}</p>
          {predictionLockAt ? (
            <p className="mt-1 text-sm text-text-secondary">
              {fmt(pt.updateUntil, { when: formatEventLocalLockTime(predictionLockAt, predictionTimezone, locale) })}
            </p>
          ) : null}
        </div>
      ) : null}

      <ol className="mt-6 space-y-1.5">
        {rankedParticipants.map((participant, index) => (
          <li
            key={participant.id}
            className="flex items-center gap-3 rounded border border-border bg-surface px-4 py-3"
          >
            <span className="font-display w-7 shrink-0 text-base text-accent-strong">
              {String(index + 1).padStart(2, "0")}
            </span>
            <CountryFlag countryCode={participant.countryCode} className="text-xl" />
            <span className="truncate text-sm text-text-primary">
              {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
            </span>
            {!participant.isActive ? (
              <span className="shrink-0 rounded border border-border-strong px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-accent-strong">
                {pt.pickUnavailableBadge}
              </span>
            ) : null}
            {pickMarks ? <PickMarkIcon mark={pickMarks[participant.id]} topSize={officialTopSize} /> : null}
          </li>
        ))}
      </ol>

      {pickMarks ? (
        <ul className="mt-3 flex flex-wrap gap-x-5 gap-y-1 text-xs text-text-muted">
          <li className="inline-flex items-center gap-1.5">
            <Check className="h-3.5 w-3.5 text-accent-strong" aria-hidden />
            {dict.results.markExact}
          </li>
          <li className="inline-flex items-center gap-1.5">
            <Minus className="h-3.5 w-3.5" aria-hidden />
            {fmt(dict.results.markIn, { n: officialTopSize })}
          </li>
          <li className="inline-flex items-center gap-1.5">
            <X className="h-3.5 w-3.5" aria-hidden />
            {fmt(dict.results.markOut, { n: officialTopSize })}
          </li>
        </ul>
      ) : null}

      {canEdit && rankedParticipants.some((participant) => !participant.isActive) ? (
        <p role="status" className="mt-4 rounded border border-accent/40 bg-accent/10 px-4 py-3 text-sm text-text-primary">
          {pt.pickUnavailableNotice}
        </p>
      ) : null}

      {canEdit ? (
        <div className="mt-4">
          <Link
            href={`/p/${publicId}/edit`}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-2.5 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            <Pencil className="h-4 w-4" aria-hidden />
            {pt.editCta}
          </Link>
          {predictionLockAt ? (
            <p className="mt-2 text-xs text-text-muted">
              {fmt(pt.updateUntil, { when: formatEventLocalLockTime(predictionLockAt, predictionTimezone, locale) })}
            </p>
          ) : null}
        </div>
      ) : showLockedNotice ? (
        <p className="mt-4 text-sm font-medium uppercase tracking-wide text-text-muted">
          {pt.callLocked}
        </p>
      ) : null}

      {fouchScore}

      {officialResultSection}

      {youVsTheWorld}

      {yourCrowdChanged}

      {/* Pre-result: original prediction sharing stays primary and sits
          right before the "Make your Top 10" CTA, unchanged from Sprint 2/3.
          Post-result: it becomes a secondary, de-emphasized block, per the
          hierarchy in Sprint 4.1's brief (Result Card is the stronger
          social object once scoring exists). */}
      {!hasResult ? originalPredictionShare : null}

      {predictionsClosed ? (
        nextEvent ? (
          <Link
            href={`/predict/${nextEvent.slug}`}
            onClick={() => track("public_prediction_cta_clicked", { event_slug: nextEvent.slug })}
            className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            {nextEvent.comingSoon ? fmt(ut.nextEventCta, { event: nextEvent.name }) : pt.makeYourTop}
          </Link>
        ) : null
      ) : (
        <Link
          href={`/predict/${eventSlug}?from=${publicId}`}
          onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
          className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
        >
          {pt.makeYourTop}
        </Link>
      )}

      {hasResult ? originalPredictionShare : null}
    </div>
  );
}
/** Per-pick result marker. Icon + accessible label (never color alone). */
function PickMarkIcon({ mark, topSize }: { mark: PickMark | undefined; topSize: number }) {
  const { dict } = useI18n();
  if (!mark) return null;
  if (mark === "exact") {
    const label = dict.results.markExact;
    return (
      <span title={label} aria-label={label} className="shrink-0 text-accent-strong">
        <Check className="h-4 w-4" aria-hidden />
      </span>
    );
  }
  if (mark === "in_top") {
    const label = fmt(dict.results.markIn, { n: topSize });
    return (
      <span title={label} aria-label={label} className="shrink-0 text-text-secondary">
        <Minus className="h-4 w-4" aria-hidden />
      </span>
    );
  }
  const label = fmt(dict.results.markOut, { n: topSize });
  return (
    <span title={label} aria-label={label} className="shrink-0 text-text-muted">
      <X className="h-4 w-4" aria-hidden />
    </span>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PublicPredictionView.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PublicPredictionView.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PublicPredictionView.tsx"
}

try {
    $path = "src\content\en.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
export const en = {
  meta: {
    title: "FOUCH — Entertainment Predictions",
    description:
      "Predict entertainment's biggest moments and see how your picks compare with the world.",
  },
  nav: { wordmark: "FOUCH", language: "Language" },
  hero: {
    eyebrow: "Entertainment Predictions",
    headlineLines: ["Make", "your", "call."],
    subhead: "Predict it. See what the crowd thinks. Prove you called it.",
    cta: "Make your prediction",
    predictionsOpen: "Predictions Open",
    predictLabel: "Predict",
    predictHint: "Build your Top 10",
    competeLabel: "Compete",
    competeHint: "See what the crowd thinks",
    proveLabel: "Prove it",
  },
  featuredEvent: {
    eyebrowUpcoming: "Upcoming",
    eyebrowNow: "Now Predicting",
    eyebrowClosed: "Predictions Closed",
    prompt: "Who makes your Top 10?",
    cta: "Make your prediction",
    viewLeaderboard: "View leaderboard →",
  },
  crowd: {
    title: "The Crowd",
    earlyTitle: "It's early.",
    earlyBody: "The first calls are coming in. Make yours before the crowd starts taking shape.",
    earlyCta: "Make your call →",
    question: "Who does the crowd have winning?",
    viewAll: "View all →",
    basedOn: "Based on {n} predictions",
  },
  howItWorks: {
    title: "How it works",
    steps: [
      { title: "Predict", body: "Build your ranking." },
      { title: "Compete", body: "See how your picks compare." },
      { title: "Prove it", body: "Get scored when the results are in." },
    ],
    you: "You",
    crowd: "Crowd",
    excellent: "Excellent",
    exampleScore: "Example score",
  },
  closing: {
    lineOne: "Everyone has a take.",
    lineTwo: "FOUCH keeps the receipts.",
    tagline: "Predict · Compete · Prove it",
    cta: "Make your call",
  },
  eventPage: {
    back: "Back to Fouch",
    comingSoon: "The prediction builder for this event opens soon.",
  },
  footer: {
    tagline: "Entertainment predictions.",
    disclaimer:
      "FOUCH is an independent entertainment prediction game. Not affiliated with or endorsed by the events, organizations, or participants featured on the platform.",
    privacy: "Privacy",
    terms: "Terms",
  },
  builder: {
    metaTitle: "Build your Top 10 — {event}",
    metaDescription: "Choose the 10 contestants you think will go furthest.",
    backToFouch: "Back to Fouch",
    backToBuilder: "Back to builder",
    noParticipants: "No participants are available for this event yet. Check back soon.",
    buildTitle: "Build your Top {n}",
    buildHint: "Choose the {n} contestants you think will go furthest.",
    yourTop: "Your Top {n}",
    topReady: "Your Top {n} is ready.",
    reviewCta: "Review my prediction",
    allContestants: "All contestants",
    selectedCount: "{count} / {total} selected",
    searchPlaceholder: "Search countries...",
    searchAria: "Search countries",
    selected: "Selected",
    noMatch: "No countries match “{query}”.",
    emptyList: "Tap a country below to give it position 01.",
    replaceBadge: "Replace",
    replaceTitle: "No longer available — remove and pick a current contestant to save changes.",
    replaceHint: "Replace the contestant marked \"Replace\" with a current one to save your changes.",
    moveUpAria: "Move {name} up, currently position {pos} of {total}",
    moveDownAria: "Move {name} down, currently position {pos} of {total}",
    removeAria: "Remove {name} from your Top {total}",
    demoNote: "Demo participant data — not the official lineup",
    listUpdated: "Contestant list updated {date}",
  },
  review: {
    metaTitle: "Your Top 10 — {event}",
    yourTop: "Your Top {n}",
    incomplete: "We don't have a complete prediction for this event yet on this device.",
    buildCta: "Build your Top {n}",
    editCta: "Edit my Top {n}",
    nickname: "Nickname",
    country: "Country",
    optional: "Optional",
    optionalNote:
      "Optional — shown publicly with your prediction. You can update your picks until predictions close.",
    saving: "Saving…",
    saveCta: "Save my Top {n}",
    tryAgain: "Try again",
    tryingAgain: "Trying again…",
  },
  auth: {
    headingCreate: "Verify your email to save your prediction.",
    headingEdit: "Verify your email to save your changes.",
    subheading: "We'll send you a verification code — no password needed.",
    emailLabel: "Email",
    emailPlaceholder: "you@example.com",
    sending: "Sending…",
    sendCode: "Send code",
    privacyNote:
      "FOUCH is an independent fan prediction game — your email is only used to verify your call, never shown publicly.",
    enterCode: "Enter the code we sent to {email}.",
    codeLabel: "Verification code",
    tooManyAttempts: "Too many incorrect attempts. Request a new code.",
    verifying: "Verifying…",
    verifyCta: "Verify and lock",
    resendCode: "Resend code",
    resendIn: "Resend code in 0:{s}",
    differentEmail: "Use a different email",
    sendFailed: "We couldn't send a code — try again in a moment.",
    verifyFailed: "We couldn't verify your code — try again.",
    lockFailed: "We couldn't save your prediction. Your Top 10 is still saved — try again.",
    editFailed: "We couldn't save your changes. Try again.",
  },
  publicPrediction: {
    titleWithName: "{name}'s Top 10",
    titleAnonymous: "Someone's Top 10",
    metaTitleNamed: "{name}'s Top 10 — {event}",
    metaTitleAnon: "A Top 10 prediction — {event}",
    metaDescription: "See the prediction, then make your own call.",
    demoBanner: "Demo prediction — not the official lineup",
    callIsIn: "YOUR CALL IS IN",
    updateUntil: "You can update your picks until {when}.",
    callLocked: "YOUR CALL IS LOCKED",
    editCta: "Edit my Top 10",
    shareHeading: "Share your call",
    originalPrediction: "Your original prediction",
    makeYourTop: "Make your Top 10",
    pickUnavailableBadge: "No longer in the lineup",
    pickUnavailableNotice:
      "One or more of your picks is no longer in the official lineup. Edit your prediction to replace them before predictions lock.",
    demoNoEdit: "This was a demo prediction and can no longer be edited.",
    editTitle: "Edit your Top {n}",
  },
  share: {
    story: "Story",
    post: "Post",
    instagramStory: "Instagram Story",
    preparing: "Preparing…",
    share: "Share",
    saveImage: "Save image",
    copyLink: "Copy link",
    copied: "Copied",
    copyPredictionLink: "Copy prediction link",
    storyReady: "Your Story is ready",
    storyReadyMobile: "Image saved. Open Instagram → Story → choose the image.",
    storyReadyDesktop: "Open Instagram on your phone and add the saved image to your Story.",
    shareTitle: "My Fouch prediction",
    predictionCardAlt: "Your Fouch prediction card",
    resultCardAlt: "Your Fouch result card",
    shareResult: "Share your result",
    cardHeadline: "MAKE YOUR CALL.",
    cardFooter: "WHO YOU GOT?",
    cardDemo: "DEMO",
    cardWinner: "Winner",
    cardCorrect: "Correct",
    cardMissed: "Missed",
    cardPodium: "Podium",
    cardTop5: "Top 5",
    cardTop10: "Top 10",
    cardTopPct: "TOP {n}%",
    cardWorldwide: "WORLDWIDE",
    cardBeatIt: "THINK YOU COULD BEAT IT?",
    ogHeadingNamed: "{name}'s Top 10",
    ogHeadingAnon: "A Top 10 prediction",
  },
  community: {
    youVsWorld: "You vs the World",
    demoNote: "Demo community data — not official {noun}",
    earlyTitle: "You're early.",
    earlyBody: "Be the first to set the pace.",
    forming: "The crowd is just forming — {n} other {noun} in so far.",
    nounOne: "prediction",
    nounMany: "predictions",
    earlySignal: "Early signal · based on {n} other predictions",
    sameWinner: "Same winner",
    nobodySameCall: "nobody else made the same call.",
    sameWinnerCount: "{count} of {total} other predictions agree.",
    sameWinnerPct: "{pct} of the world agrees. Based on {total} other predictions.",
    top3Match: "Top 3 match",
    youShare: "You share {n} of your top 3 with the world.",
    picked: "{ratio} picked",
    avgPos: "avg #{n}",
    basedOnOne: "Based on {n} other prediction.",
    basedOnMany: "Based on {n} other predictions.",
    boldest: "Your boldest call",
    boldestCount: "Only {count} of {total} other predictions have this in their top 10.",
    boldestPct: "Only {pct} of other predictions have this in their top 10.",
    worldTop10: "The world's top 10",
    worldTop10Hint: "Ranked by how high each pick appears across predictions.",
    shareStandsOut: "Your call stands out.",
    shareWrong: "Think the world is wrong?",
    shareCta: "Share your call",
    crowdChanged: "Your crowd changed",
    crowdMovingToward: "The crowd is moving toward your call.",
    crowdMovingAway: "The crowd is moving away from your call.",
    crowdBasedOn: "Based on community predictions since your call.",
    pts: "pts",
  },
  score: {
    title: "Fouch score",
    demoResult: "Demo result — not an official outcome",
    bands: {
      MISSED_IT: "Missed it",
      FAIR: "Fair call",
      GOOD: "Good call",
      EXCELLENT: "Excellent call",
      ELITE: "Elite call",
    },
    winner: "Winner",
    correct: "Correct",
    missed: "✗ Missed — your pick:",
    actual: "Actual:",
    podium: "Podium",
    top5: "Top 5",
    top10: "Top 10",
    ranking: "Ranking",
    closeness: "How close your picks were to the official finish.",
    seeFinish: "See where you finished",
    beat: "You beat {pct}% of {noun} for this event, based on {n} other predictions.",
    worldUnlocks: "World ranking unlocks at {n} predictions.",
  },
  leaderboard: {
    back: "FOUCH",
    title: "Event leaderboard",
    subtitle: "See who called it best.",
    demoNote: "Demo leaderboard — not an official outcome",
    locked: "Leaderboard locked",
    makeCall: "Make your call",
    none: "No scored predictions yet.",
    first: "First call on the board.",
    starting: "The leaderboard is just getting started.",
    yourFinish: "Your finish",
    topPct: "Top {n}%",
    neighborhood: "Your neighborhood",
    you: "You",
    lockedBody: "Results will appear here once {event} has been scored.",
    rankOf: "#{rank} of {total}",
    scoreLine: "Fouch score {score}",
    worldUnlocks: "World ranking unlocks at {n} predictions.",
    metaTitle: "{event} Predictions Leaderboard | FOUCH",
    metaDemo: "A demo FOUCH predictions leaderboard — not an official result.",
    metaLive: "See how FOUCH predictions ranked after the result.",
  },
  results: {
    heading: "Official result",
    winner: "Winner",
    firstRunnerUp: "1st runner-up",
    secondRunnerUp: "2nd runner-up",
    top5Group: "Top 5 (positions 4–5)",
    remainingGroup: "Rest of the Top {n} (tied — no order)",
    tiedNote: "The competition announced a Top {n}. Tied finalists are shown without invented positions.",
    yourPicks: "How your picks landed",
    markExact: "In the right place",
    markIn: "In the Top {n}, different place",
    markOut: "Not in the Top {n}",
    howScoreWorks: "How your score works",
    scoreExplain:
      "Winner {winner} + Podium {podium} + Top 5 {top5} + Top 10 {top10} + Ranking {ranking} = 100. Every tied finalist counts exactly the same.",
  },
  unavailable: {
    closedTitle: "Predictions are closed",
    closedBody: "The prediction window for this event has ended. Your original call is safe — see how it landed.",
    viewResults: "View results and leaderboard →",
    comingSoonLabel: "Coming soon",
    comingSoonTitle: "{event} is coming soon",
    comingSoonBody:
      "We're loading the official contestant list. Predictions open as soon as it's confirmed — never with placeholder data.",
    backHome: "Back to FOUCH",
    nextEventCta: "{event} · Coming soon",
    nextUp: "Next up",
  },
  homeResults: {
    link: "{event} Results → View Leaderboard",
    comingSoonChip: "Coming soon",
  },
  lock: {
    notOpen: "Predictions for this event haven't opened yet.",
    locked: "Predictions for this event are locked.",
  },
  errors: {
    generic: "Something went wrong. Try again.",
  },
};

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\content\en.ts"
} catch {
    Write-Host "FAILED: src\content\en.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\content\en.ts"
}

try {
    $path = "src\content\es.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Dictionary } from "./types";

/**
 * Neutral conversational Latin American Spanish — no country-specific
 * slang. Typed as Dictionary, so any key missing here fails the
 * typecheck. Brand name FOUCH and official event/contestant names are
 * never translated.
 */
export const es: Dictionary = {
  meta: {
    title: "FOUCH — Predicciones de entretenimiento",
    description:
      "Predice los grandes momentos del entretenimiento y descubre cómo se comparan tus elecciones con las del mundo.",
  },
  nav: { wordmark: "FOUCH", language: "Idioma" },
  hero: {
    eyebrow: "Predicciones de entretenimiento",
    headlineLines: ["Haz", "tu", "predicción."],
    subhead: "Predice. Descubre qué piensa la comunidad. Demuestra que acertaste.",
    cta: "Haz tu predicción",
    predictionsOpen: "Predicciones abiertas",
    predictLabel: "Predice",
    predictHint: "Arma tu Top 10",
    competeLabel: "Compite",
    competeHint: "Mira qué piensa la comunidad",
    proveLabel: "Demuéstralo",
  },
  featuredEvent: {
    eyebrowUpcoming: "Próximamente",
    eyebrowNow: "Predicciones abiertas",
    eyebrowClosed: "Predicciones cerradas",
    prompt: "¿Quiénes están en tu Top 10?",
    cta: "Haz tu predicción",
    viewLeaderboard: "Ver clasificación →",
  },
  crowd: {
    title: "La comunidad",
    earlyTitle: "Es temprano.",
    earlyBody: "Están llegando las primeras predicciones. Haz la tuya antes de que la comunidad tome forma.",
    earlyCta: "Haz tu predicción →",
    question: "¿A quién ve ganando la comunidad?",
    viewAll: "Ver todo →",
    basedOn: "Basado en {n} predicciones",
  },
  howItWorks: {
    title: "Cómo funciona",
    steps: [
      { title: "Predice", body: "Arma tu ranking." },
      { title: "Compite", body: "Mira cómo se comparan tus elecciones." },
      { title: "Demuéstralo", body: "Recibe tu puntaje cuando salgan los resultados." },
    ],
    you: "Tú",
    crowd: "Comunidad",
    excellent: "Excelente",
    exampleScore: "Puntaje de ejemplo",
  },
  closing: {
    lineOne: "Todos tienen una opinión.",
    lineTwo: "FOUCH guarda el comprobante.",
    tagline: "Predice · Compite · Demuéstralo",
    cta: "Haz tu predicción",
  },
  eventPage: {
    back: "Volver a Fouch",
    comingSoon: "El armador de predicciones de este evento abre pronto.",
  },
  footer: {
    tagline: "Predicciones de entretenimiento.",
    disclaimer:
      "FOUCH es un juego independiente de predicciones de entretenimiento. No está afiliado ni respaldado por los eventos, organizaciones o participantes que aparecen en la plataforma.",
    privacy: "Privacidad",
    terms: "Términos",
  },
  builder: {
    metaTitle: "Arma tu Top 10 — {event}",
    metaDescription: "Elige a las 10 participantes que crees que llegarán más lejos.",
    backToFouch: "Volver a Fouch",
    backToBuilder: "Volver al armador",
    noParticipants: "Todavía no hay participantes disponibles para este evento. Vuelve pronto.",
    buildTitle: "Arma tu Top {n}",
    buildHint: "Elige a las {n} participantes que crees que llegarán más lejos.",
    yourTop: "Tu Top {n}",
    topReady: "Tu Top {n} está listo.",
    reviewCta: "Revisar mi predicción",
    allContestants: "Todas las participantes",
    selectedCount: "{count} / {total} elegidas",
    searchPlaceholder: "Buscar países...",
    searchAria: "Buscar países",
    selected: "Elegida",
    noMatch: "Ningún país coincide con “{query}”.",
    emptyList: "Toca un país abajo para darle la posición 01.",
    replaceBadge: "Reemplazar",
    replaceTitle: "Ya no está disponible — quítala y elige a una participante vigente para guardar los cambios.",
    replaceHint: "Reemplaza a la participante marcada como \"Reemplazar\" por una vigente para guardar tus cambios.",
    moveUpAria: "Subir a {name}, actualmente en la posición {pos} de {total}",
    moveDownAria: "Bajar a {name}, actualmente en la posición {pos} de {total}",
    removeAria: "Quitar a {name} de tu Top {total}",
    demoNote: "Datos de participantes de demostración — no es la lista oficial",
    listUpdated: "Lista de participantes actualizada el {date}",
  },
  review: {
    metaTitle: "Tu Top 10 — {event}",
    yourTop: "Tu Top {n}",
    incomplete: "Todavía no tenemos una predicción completa para este evento en este dispositivo.",
    buildCta: "Arma tu Top {n}",
    editCta: "Editar mi Top {n}",
    nickname: "Apodo",
    country: "País",
    optional: "Opcional",
    optionalNote:
      "Opcional — se muestra públicamente junto a tu predicción. Puedes actualizar tus elecciones hasta que cierren las predicciones.",
    saving: "Guardando…",
    saveCta: "Guardar mi Top {n}",
    tryAgain: "Intentar de nuevo",
    tryingAgain: "Intentando de nuevo…",
  },
  auth: {
    headingCreate: "Verifica tu correo para guardar tu predicción.",
    headingEdit: "Verifica tu correo para guardar tus cambios.",
    subheading: "Te enviaremos un código de verificación — sin contraseñas.",
    emailLabel: "Correo electrónico",
    emailPlaceholder: "tu@ejemplo.com",
    sending: "Enviando…",
    sendCode: "Enviar código",
    privacyNote:
      "FOUCH es un juego independiente de predicciones entre fans — tu correo solo se usa para verificar tu predicción y nunca se muestra públicamente.",
    enterCode: "Ingresa el código que enviamos a {email}.",
    codeLabel: "Código de verificación",
    tooManyAttempts: "Demasiados intentos incorrectos. Solicita un código nuevo.",
    verifying: "Verificando…",
    verifyCta: "Verificar y guardar",
    resendCode: "Reenviar código",
    resendIn: "Reenviar código en 0:{s}",
    differentEmail: "Usar otro correo",
    sendFailed: "No pudimos enviar el código — inténtalo de nuevo en un momento.",
    verifyFailed: "No pudimos verificar tu código — inténtalo de nuevo.",
    lockFailed: "No pudimos guardar tu predicción. Tu Top 10 sigue guardado — inténtalo de nuevo.",
    editFailed: "No pudimos guardar tus cambios. Inténtalo de nuevo.",
  },
  publicPrediction: {
    titleWithName: "El Top 10 de {name}",
    titleAnonymous: "El Top 10 de alguien",
    metaTitleNamed: "El Top 10 de {name} — {event}",
    metaTitleAnon: "Una predicción Top 10 — {event}",
    metaDescription: "Mira la predicción y luego haz la tuya.",
    demoBanner: "Predicción de demostración — no es la lista oficial",
    callIsIn: "TU PREDICCIÓN ESTÁ REGISTRADA",
    updateUntil: "Puedes actualizar tus elecciones hasta el {when}.",
    callLocked: "TU PREDICCIÓN ESTÁ BLOQUEADA",
    editCta: "Editar mi Top 10",
    shareHeading: "Comparte tu predicción",
    originalPrediction: "Tu predicción original",
    makeYourTop: "Arma tu Top 10",
    pickUnavailableBadge: "Ya no está en la lista",
    pickUnavailableNotice:
      "Una o más de tus elecciones ya no están en la lista oficial. Edita tu predicción para reemplazarlas antes de que cierren las predicciones.",
    demoNoEdit: "Esta era una predicción de demostración y ya no se puede editar.",
    editTitle: "Edita tu Top {n}",
  },
  share: {
    story: "Historia",
    post: "Publicación",
    instagramStory: "Historia de Instagram",
    preparing: "Preparando…",
    share: "Compartir",
    saveImage: "Guardar imagen",
    copyLink: "Copiar enlace",
    copied: "Copiado",
    copyPredictionLink: "Copiar enlace de la predicción",
    storyReady: "Tu historia está lista",
    storyReadyMobile: "Imagen guardada. Abre Instagram → Historia → elige la imagen.",
    storyReadyDesktop: "Abre Instagram en tu teléfono y agrega la imagen guardada a tu historia.",
    shareTitle: "Mi predicción en Fouch",
    predictionCardAlt: "Tu tarjeta de predicción de Fouch",
    resultCardAlt: "Tu tarjeta de resultado de Fouch",
    shareResult: "Comparte tu resultado",
    cardHeadline: "HAZ TU PREDICCIÓN.",
    cardFooter: "¿CUÁL ES EL TUYO?",
    cardDemo: "DEMO",
    cardWinner: "Ganadora",
    cardCorrect: "Acertaste",
    cardMissed: "Fallaste",
    cardPodium: "Podio",
    cardTop5: "Top 5",
    cardTop10: "Top 10",
    cardTopPct: "TOP {n}%",
    cardWorldwide: "A NIVEL MUNDIAL",
    cardBeatIt: "¿CREES QUE PUEDES SUPERARLO?",
    ogHeadingNamed: "El Top 10 de {name}",
    ogHeadingAnon: "Una predicción Top 10",
  },
  community: {
    youVsWorld: "Tú vs el mundo",
    demoNote: "Datos de comunidad de demostración — no son {noun} oficiales",
    earlyTitle: "Llegaste temprano.",
    earlyBody: "Sé la primera persona en marcar el ritmo.",
    forming: "La comunidad apenas se está formando — {n} {noun} más por ahora.",
    nounOne: "predicción",
    nounMany: "predicciones",
    earlySignal: "Señal temprana · basada en {n} predicciones más",
    sameWinner: "Misma ganadora",
    nobodySameCall: "nadie más hizo la misma predicción.",
    sameWinnerCount: "{count} de {total} predicciones más coinciden.",
    sameWinnerPct: "El {pct} del mundo coincide. Basado en {total} predicciones más.",
    top3Match: "Coincidencia en el Top 3",
    youShare: "Compartes {n} de tu Top 3 con el mundo.",
    picked: "{ratio} la eligió",
    avgPos: "prom. #{n}",
    basedOnOne: "Basado en {n} predicción más.",
    basedOnMany: "Basado en {n} predicciones más.",
    boldest: "Tu elección más arriesgada",
    boldestCount: "Solo {count} de {total} predicciones más la tienen en su top 10.",
    boldestPct: "Solo el {pct} de las demás predicciones la tiene en su top 10.",
    worldTop10: "El top 10 del mundo",
    worldTop10Hint: "Ordenado según qué tan alto aparece cada elección en las predicciones.",
    shareStandsOut: "Tu predicción destaca.",
    shareWrong: "¿Crees que el mundo se equivoca?",
    shareCta: "Comparte tu predicción",
    crowdChanged: "Tu comunidad cambió",
    crowdMovingToward: "La comunidad se está acercando a tu predicción.",
    crowdMovingAway: "La comunidad se está alejando de tu predicción.",
    crowdBasedOn: "Basado en las predicciones de la comunidad desde la tuya.",
    pts: "pts",
  },
  score: {
    title: "Puntaje Fouch",
    demoResult: "Resultado de demostración — no es un resultado oficial",
    bands: {
      MISSED_IT: "No acertaste",
      FAIR: "Predicción aceptable",
      GOOD: "Buena predicción",
      EXCELLENT: "Excelente predicción",
      ELITE: "Predicción de élite",
    },
    winner: "Ganadora",
    correct: "Correcto",
    missed: "✗ Fallaste — tu elección:",
    actual: "Real:",
    podium: "Podio",
    top5: "Top 5",
    top10: "Top 10",
    ranking: "Ranking",
    closeness: "Qué tan cerca estuvieron tus elecciones del resultado oficial.",
    seeFinish: "Mira dónde quedaste",
    beat: "Superaste al {pct}% de las {noun} de este evento, según {n} predicciones más.",
    worldUnlocks: "El ranking mundial se desbloquea con {n} predicciones.",
  },
  leaderboard: {
    back: "FOUCH",
    title: "Clasificación del evento",
    subtitle: "Mira quién acertó mejor.",
    demoNote: "Clasificación de demostración — no es un resultado oficial",
    locked: "Clasificación bloqueada",
    makeCall: "Haz tu predicción",
    none: "Todavía no hay predicciones con puntaje.",
    first: "La primera predicción en la tabla.",
    starting: "La clasificación apenas está comenzando.",
    yourFinish: "Tu resultado",
    topPct: "Top {n}%",
    neighborhood: "Tu zona de la tabla",
    you: "Tú",
    lockedBody: "Los resultados aparecerán aquí cuando {event} haya sido puntuado.",
    rankOf: "#{rank} de {total}",
    scoreLine: "Puntaje Fouch {score}",
    worldUnlocks: "El ranking mundial se desbloquea con {n} predicciones.",
    metaTitle: "Clasificación de predicciones de {event} | FOUCH",
    metaDemo: "Una clasificación de demostración de predicciones de FOUCH — no es un resultado oficial.",
    metaLive: "Mira cómo quedaron las predicciones de FOUCH tras el resultado.",
  },
  results: {
    heading: "Resultado oficial",
    winner: "Ganadora",
    firstRunnerUp: "1ª finalista",
    secondRunnerUp: "2ª finalista",
    top5Group: "Top 5 (posiciones 4–5)",
    remainingGroup: "Resto del Top {n} (empatadas — sin orden)",
    tiedNote: "El concurso anunció un Top {n}. Las finalistas empatadas se muestran sin posiciones inventadas.",
    yourPicks: "Cómo quedaron tus elecciones",
    markExact: "En el lugar correcto",
    markIn: "En el Top {n}, en otro lugar",
    markOut: "Fuera del Top {n}",
    howScoreWorks: "Cómo funciona tu puntaje",
    scoreExplain:
      "Ganadora {winner} + Podio {podium} + Top 5 {top5} + Top 10 {top10} + Ranking {ranking} = 100. Todas las finalistas empatadas cuentan exactamente igual.",
  },
  unavailable: {
    closedTitle: "Las predicciones están cerradas",
    closedBody: "La ventana de predicciones de este evento terminó. Tu predicción original está a salvo — mira cómo quedó.",
    viewResults: "Ver resultados y clasificación →",
    comingSoonLabel: "Próximamente",
    comingSoonTitle: "{event} llega pronto",
    comingSoonBody:
      "Estamos cargando la lista oficial de participantes. Las predicciones abrirán apenas esté confirmada — nunca con datos de prueba.",
    backHome: "Volver a FOUCH",
    nextEventCta: "{event} · Próximamente",
    nextUp: "Lo que sigue",
  },
  homeResults: {
    link: "Resultados {event} → Ver clasificación",
    comingSoonChip: "Próximamente",
  },
  lock: {
    notOpen: "Las predicciones de este evento todavía no han abierto.",
    locked: "Las predicciones de este evento están cerradas.",
  },
  errors: {
    generic: "Algo salió mal. Inténtalo de nuevo.",
  },
};

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\content\es.ts"
} catch {
    Write-Host "FAILED: src\content\es.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\content\es.ts"
}

try {
    $path = "src\lib\participants.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import type { Participant } from "@/types/participant";
import { isSelectableStatus } from "@/lib/participant-status";
import { localizeParticipant as localize } from "@/lib/participant-locale";
import { chooseRosterSource, demoParticipantsForIds } from "@/lib/participant-sources";
import type { Locale } from "@/lib/locale";
import { getAllEventParticipantRows, type EventParticipantRow } from "@/lib/event-participants-db";

/**
 * DEMO / DEVELOPMENT DATA â€” NOT the official Miss Universe 2026 lineup.
 *
 * The full, verified list of national delegates for Miss Universe 2026
 * is not yet finalized/confirmed by the organization at the time of
 * writing. Rather than invent an official-looking roster, this is a
 * clearly-marked demo set of real countries, used only to test the
 * Top 10 mechanic. See `getParticipantsForEvent`'s returned `status`
 * field â€” the UI must surface "Demo participant data" whenever it is
 * "demo", and this must never be presented as the official lineup.
 */
const demoCountries: Array<{ code: string; name: string }> = [
  { code: "AR", name: "Argentina" },
  { code: "AU", name: "Australia" },
  { code: "BR", name: "Brazil" },
  { code: "CA", name: "Canada" },
  { code: "CL", name: "Chile" },
  { code: "CO", name: "Colombia" },
  { code: "DO", name: "Dominican Republic" },
  { code: "ES", name: "Spain" },
  { code: "FR", name: "France" },
  { code: "IN", name: "India" },
  { code: "ID", name: "Indonesia" },
  { code: "IT", name: "Italy" },
  { code: "JM", name: "Jamaica" },
  { code: "JP", name: "Japan" },
  { code: "KE", name: "Kenya" },
  { code: "KR", name: "South Korea" },
  { code: "MX", name: "Mexico" },
  { code: "NG", name: "Nigeria" },
  { code: "PE", name: "Peru" },
  { code: "PH", name: "Philippines" },
  { code: "PR", name: "Puerto Rico" },
  { code: "TH", name: "Thailand" },
  { code: "VE", name: "Venezuela" },
  { code: "VN", name: "Vietnam" },
  { code: "ZA", name: "South Africa" },
].sort((a, b) => a.name.localeCompare(b.name));

const missUniverse2026Participants: Participant[] = demoCountries.map((country, index) => ({
  id: `demo-${country.code.toLowerCase()}`,
  eventId: "seed-miss-universe-2026",
  displayName: country.name,
  countryCode: country.code,
  countryName: country.name,
  sortOrder: index,
  isActive: true,
}));

const participantsByEventSlug: Record<string, Participant[]> = {
  "miss-universe-2026": missUniverse2026Participants,
};

export type ParticipantDataStatus = "demo" | "verified";

export interface ParticipantsForEvent {
  status: ParticipantDataStatus;
  participants: Participant[];
  /** FOUCH 0.3B Â§13: the most recent `source_checked_at` across this
   * event's ACTIVE participants, for the "Contestant list updated
   * {date}" copy â€” never used for a "demo" event (always null there;
   * Miss Universe's hardcoded seed has no provenance concept at all).
   * Null for a verified event with no source-checked participants
   * yet (e.g. Miss Grand before its roster import â€” see
   * FOUCH_EVENT_PARTICIPANTS_IMPORT.md). */
  sourceCheckedAt: string | null;
}

function toParticipant(row: EventParticipantRow): Participant {
  return {
    // Stable identity (0.3B Â§6): the DB row's own uuid, never derived
    // from name/position/status/country â€” see migration 0010.
    id: row.id,
    eventId: row.eventSlug,
    // A PENDING row has no confirmed contestant_name yet â€” never
    // invented here; fall back to the country name itself so the UI
    // has something displayable without fabricating a person's name.
    displayName: row.contestantName ?? row.countryName,
    countryCode: row.countryCode,
    countryName: row.countryName,
    sortOrder: 0,
    isActive: isSelectableStatus(row.status),
  };
}

/**
 * The active/selectable roster for building a NEW Top 10 (or a new
 * version of an edited one) â€” exactly the same contract this function
 * has always had: only ever returns participants a person may
 * currently choose. Every existing caller (builder, review,
 * validateSubmission's activeParticipants, edit's requiredCount) can
 * keep assuming that, unchanged â€” the only difference from before
 * 0.3B is that resolving a database-driven event's roster requires an
 * await now.
 *
 * PENDING/WITHDRAWN/REPLACED participants are deliberately excluded
 * here â€” see resolveParticipantsByIds below for the separate,
 * status-blind lookup that historical rendering needs instead.
 */
export async function getParticipantsForEvent(slug: string, locale: Locale = "en"): Promise<ParticipantsForEvent | null> {
  const hardcoded = participantsByEventSlug[slug];
  const rows = await getAllEventParticipantRows(slug);

  // Database first: an event with real roster rows ALWAYS uses them. The
  // hardcoded demo list only applies while an event has no rows at all.
  const source = chooseRosterSource(rows.length, Boolean(hardcoded));
  if (source === "demo" && hardcoded) {
    return {
      status: "demo",
      participants: hardcoded.filter((participant) => participant.isActive).map((p) => localize(p, locale)),
      sourceCheckedAt: null,
    };
  }
  if (source === "none") return null;

  const active = rows.filter((row) => isSelectableStatus(row.status));
  const sourceCheckedAt = active.reduce<string | null>((latest, row) => {
    if (!row.sourceCheckedAt) return latest;
    if (!latest || row.sourceCheckedAt > latest) return row.sourceCheckedAt;
    return latest;
  }, null);

  return {
    status: "verified",
    participants: active.map((row) => localize(toParticipant(row), locale)),
    sourceCheckedAt,
  };
}

/**
 * Resolves a specific set of participant IDs to display info
 * REGARDLESS of current status â€” the one place historical rendering
 * (a saved prediction's ranking, its share card, its winner pick for
 * scoring/consensus) must go through instead of
 * getParticipantsForEvent above. A WITHDRAWN or REPLACED participant
 * still resolves here with its real name/country (isActive: false),
 * exactly so an existing prediction never silently loses an entry
 * just because that country's delegate later changed (brief Â§7).
 *
 * For Miss Universe's hardcoded roster this is equivalent to the
 * active-only lookup (every hardcoded entry is always active), so
 * behavior there is unchanged.
 */
export async function resolveParticipantsByIds(
  eventSlug: string,
  participantIds: string[],
  locale: Locale = "en",
): Promise<Map<string, Participant>> {
  const idSet = new Set(participantIds);
  const rows = await getAllEventParticipantRows(eventSlug);
  const map = new Map<string, Participant>();
  for (const row of rows) {
    if (idSet.has(row.id)) map.set(row.id, localize(toParticipant(row), locale));
  }

  // Historical demo predictions (ids "demo-xx") must keep rendering after
  // the event moved to its real roster. Resolve-only: never selectable.
  for (const demo of demoParticipantsForIds(participantIds, participantsByEventSlug[eventSlug])) {
    if (!map.has(demo.id)) map.set(demo.id, localize(demo, locale));
  }
  return map;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participants.ts"
} catch {
    Write-Host "FAILED: src\lib\participants.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participants.ts"
}

try {
    $path = "src\lib\participant-sources.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { chooseRosterSource, demoParticipantsForIds, DEMO_ID_PREFIX } from "./participant-sources";
import type { Participant } from "@/types/participant";

const demo = (code: string): Participant => ({
  id: `demo-${code}`,
  eventId: "seed",
  displayName: code,
  countryCode: code.toUpperCase(),
  countryName: code,
  sortOrder: 0,
  isActive: true,
});
const demoList = [demo("ar"), demo("cl"), demo("ve")];

describe("chooseRosterSource — the database always wins", () => {
  it("an event with roster rows uses the database, even when a demo list exists (Miss Universe after the roster load)", () => {
    expect(chooseRosterSource(24, true)).toBe("db");
  });
  it("an event with NO rows falls back to the demo list only if one exists (Miss Universe before the roster load -> Coming soon)", () => {
    expect(chooseRosterSource(0, true)).toBe("demo");
  });
  it("an event with no rows and no demo list has no roster at all", () => {
    expect(chooseRosterSource(0, false)).toBe("none");
  });
  it("a single row is enough to switch to the database (no placeholder padding)", () => {
    expect(chooseRosterSource(1, true)).toBe("db");
  });
});

describe("demoParticipantsForIds — historical demo predictions keep rendering", () => {
  it("resolves only the demo ids a saved prediction references", () => {
    const found = demoParticipantsForIds(["demo-ar", "demo-ve", "demo-zz"], demoList);
    expect(found.map((p) => p.id)).toEqual(["demo-ar", "demo-ve"]);
  });
  it("never resolves a real (uuid) participant id from the demo list", () => {
    expect(demoParticipantsForIds(["e2a5991c-cafd-4a42-a5a4-e46b6719a914"], demoList)).toEqual([]);
  });
  it("an event with no demo list resolves nothing", () => {
    expect(demoParticipantsForIds(["demo-ar"], undefined)).toEqual([]);
  });
  it("uses the documented demo id prefix", () => {
    expect(DEMO_ID_PREFIX).toBe("demo-");
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participant-sources.test.ts"
} catch {
    Write-Host "FAILED: src\lib\participant-sources.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participant-sources.test.ts"
}

try {
    $path = "src\lib\participant-sources.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Participant } from "@/types/participant";

/**
 * Where an event's roster comes from. The database is ALWAYS preferred:
 * once an event has event_participants rows, those rows are the roster
 * (status "verified"). The hardcoded demo list is only a development
 * fallback for an event with NO rows yet — which the readiness guard
 * (event-readiness.ts) treats as "Coming soon" — and a read-only
 * lookup table for historical demo predictions (ids "demo-xx").
 */
export type RosterSource = "db" | "demo" | "none";

export function chooseRosterSource(dbRowCount: number, hasDemoList: boolean): RosterSource {
  if (dbRowCount > 0) return "db";
  return hasDemoList ? "demo" : "none";
}

export const DEMO_ID_PREFIX = "demo-";

/**
 * Demo participants that a SAVED prediction references (ids "demo-xx"),
 * so an old demo prediction still renders after the event switched to
 * its real roster. They are never selectable — this only resolves ids
 * that are already stored.
 */
export function demoParticipantsForIds(ids: string[], demoList: Participant[] | undefined): Participant[] {
  if (!demoList) return [];
  const wanted = new Set(ids.filter((id) => id.startsWith(DEMO_ID_PREFIX)));
  return demoList.filter((participant) => wanted.has(participant.id));
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participant-sources.ts"
} catch {
    Write-Host "FAILED: src\lib\participant-sources.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participant-sources.ts"
}

try {
    $path = "supabase\imports\miss-universe-2026-affected-predictions.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- FOUCH — Miss Universe 2026: predictions affected by a roster change (READ-ONLY).
--
-- Lists every FINAL prediction whose CURRENT version contains a participant that is no longer
-- selectable (WITHDRAWN or REPLACED). It changes nothing: saved predictions are never edited or
-- remapped. Owners see a "No longer in the lineup" badge and a notice on their public page and
-- must replace the pick themselves (editing creates a new immutable version) before the lock.
--
-- Run it after any withdraw/replace so you know exactly who is affected and can reach out.

select p.public_id,
       p.nickname,
       i.predicted_position as position,
       ep.country_code,
       ep.contestant_name as pick_that_left,
       ep.status          as roster_status,
       (select ep2.contestant_name
          from event_participants ep2
         where ep2.event_slug = ep.event_slug
           and ep2.country_code = ep.country_code
           and ep2.status = 'ACTIVE') as current_delegate_for_that_country
from predictions p
join prediction_items i
  on i.version_id = p.current_version_id
join event_participants ep
  on ep.id::text = i.participant_id
 and ep.event_slug = p.event_slug
where p.event_slug = 'miss-universe-2026'
  and p.is_final = true
  and p.data_status = 'verified'
  and ep.status in ('WITHDRAWN', 'REPLACED')
order by p.public_id, i.predicted_position;

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\imports\miss-universe-2026-affected-predictions.sql"
} catch {
    Write-Host "FAILED: supabase\imports\miss-universe-2026-affected-predictions.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\imports\miss-universe-2026-affected-predictions.sql"
}

try {
    $path = "supabase\imports\miss-universe-2026-roster-and-lock.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- FOUCH — Miss Universe 2026: load the VERIFIED launch roster, set the prediction lock, and open the event.
--
-- Run ONCE in the Supabase SQL Editor (production), AFTER the code deploy that makes the event
-- database-driven (until this runs, Miss Universe stays "Coming soon"). Plain data load, not a
-- schema migration. It never touches predictions, prediction versions, scoring, or Miss Grand.
--
-- ROSTER: 24 delegates, each named by El Nuevo Día's October 2026 candidate coverage AND by at
-- least one other independent, current source (see `notes`). Matched by country_code. The other
-- ~57 delegates cited only by Wikipedia (a pre-September snapshot) are added LATER, one verified
-- batch at a time, with the workflow in FOUCH_EVENT_PARTICIPANTS_IMPORT.md (e.g. Argentina had
-- already changed delegates since that snapshot). Thailand is HELD: its participation is disputed
-- inside the Miss Universe Organization (9 Oct 2026). No placeholders are inserted for any
-- missing country.
--
-- LOCK: the Grand Final is Tue 24 Nov 2026, 8:00 PM Puerto Rico time (America/Puerto_Rico, UTC-4;
-- official venue/ticketing page + Ticketera). The lock is one hour earlier — 7:00 PM AST =
-- 2026-11-24 23:00:00+00 — the same policy used for Miss Grand. It replaces the provisional value
-- 2026-11-24 00:00:00+00 and refuses to run if the lock was already changed by someone else.
-- prediction_open_at stays NULL (predictions open immediately).
--
-- The script ABORTS (writing nothing) if the event row is missing, if the event already has roster
-- rows, or if the lock is no longer the provisional value.

begin;

do $$
begin
  if not exists (select 1 from events where slug = 'miss-universe-2026') then
    raise exception 'Event row miss-universe-2026 not found. Nothing was written.';
  end if;

  if exists (select 1 from event_participants where event_slug = 'miss-universe-2026') then
    raise exception 'miss-universe-2026 already has roster rows — this is the INITIAL load only. Use the add/withdraw/replace workflow instead. Nothing was written.';
  end if;

  if not exists (
    select 1 from events
    where slug = 'miss-universe-2026' and prediction_lock_at = '2026-11-24 00:00:00+00'
  ) then
    raise exception 'prediction_lock_at is no longer the provisional 2026-11-24 00:00:00+00 — refusing to overwrite. Nothing was written.';
  end if;
end $$;

insert into event_participants
  (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at, notes)
values
  ('miss-universe-2026', 'AR', 'Argentina', 'DAIANA PEREYRA', 'ACTIVE', 'https://www.hola.com/us/celebrities/20260921924564/miss-argentina-organization-replaces-tamara-rogouski-miss-universe-final/', '2026-10-12 00:00:00+00', 'Replaced Tamara Rogouski (withdrew 15-16 Sep 2026). Official Miss Universe Argentina communiqué; Telemundo, La Nación, Hola, Canal 12 Misiones.'),
  ('miss-universe-2026', 'AU', 'Australia', 'CAITLIN WORTHINGTON', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Gold Coast Magazine, 26 Aug 2026.'),
  ('miss-universe-2026', 'BZ', 'Belize', 'CALEIGH-ROSE WEST', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Breaking Belize News, 16 Aug 2026.'),
  ('miss-universe-2026', 'BO', 'Bolivia', 'VALERIA MENA', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Red Uno de Bolivia, 26 Jul 2026.'),
  ('miss-universe-2026', 'BR', 'Brazil', 'MARCELLA KOZINSKI', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: R7, 26 Jul 2026.'),
  ('miss-universe-2026', 'BG', 'Bulgaria', 'ANNA MARIA BABAU', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Town.bg, 21 Jul 2026.'),
  ('miss-universe-2026', 'CL', 'Chile', 'DOMINGA LÓPEZ', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: BioBioChile, 3 Aug 2026.'),
  ('miss-universe-2026', 'CR', 'Costa Rica', 'MARÍA ALEJANDRA ACOSTA', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Known as Mariale Acosta. Also: CRHoy; La Teja, 5 Jun 2026.'),
  ('miss-universe-2026', 'CU', 'Cuba', 'MIA DIO', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Legal name Mia Angelina Donadio Cancio. Also: El Nuevo Día (Miss Universe Cuba 2026).'),
  ('miss-universe-2026', 'CW', 'Curaçao', 'BIANTY GOMPERTS', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: NoticiaCla, 27 Jul 2026.'),
  ('miss-universe-2026', 'DO', 'Dominican Republic', 'MELISSA NÚÑEZ', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: El Nacional RD, 30 Jul 2026.'),
  ('miss-universe-2026', 'EC', 'Ecuador', 'DALIA BUCARAM', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Primicias, 15 Aug 2026.'),
  ('miss-universe-2026', 'EG', 'Egypt', 'SONIA GERGIS', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: CinemaBravo, 16 Aug 2026.'),
  ('miss-universe-2026', 'GT', 'Guatemala', 'MARÍA ADELINA CASTILLO', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Prensa Libre, 8 Aug 2026.'),
  ('miss-universe-2026', 'IN', 'India', 'KAZIAH LIZ MEJO', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: India TV, 24 Aug 2026.'),
  ('miss-universe-2026', 'KE', 'Kenya', 'JEAN OJIRO', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Kenya Times, 28 Jul 2026.'),
  ('miss-universe-2026', 'MX', 'Mexico', 'MARÍA VARGAS', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Hola, 30 Aug 2026 (crowned Miss Universe México 2026).'),
  ('miss-universe-2026', 'PY', 'Paraguay', 'GRETHA MATIAUDA', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: La Tribuna (PY), 26 Mar 2026.'),
  ('miss-universe-2026', 'PE', 'Peru', 'LUREN MÁRQUEZ', 'ACTIVE', 'https://www.hola.com/us-es/celebrities/20260817918486/luren-marquez-miss-universe-peru-recupera-titulo/', '2026-10-12 00:00:00+00', 'Dismissed 13 Aug 2026, reinstated 15 Aug 2026 (América TV, RPP, El Nuevo Día, Hola).'),
  ('miss-universe-2026', 'PH', 'Philippines', 'BEA MILLAN-WINDORSKI', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Listed by El Nuevo Día as Beatrice Millan-Windorski. Also: GMA News, 23 Jul 2026.'),
  ('miss-universe-2026', 'PR', 'Puerto Rico', 'JENNIFER BARRETO', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Hola, 9 Oct 2026.'),
  ('miss-universe-2026', 'ES', 'Spain', 'SUSANA MEDINA', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Listed by El Nuevo Día as Susana Lucía Medina. Also: Puerto de la Cruz, 19 Jul 2026.'),
  ('miss-universe-2026', 'US', 'United States', 'JUSTUS KELLEY', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: El Nuevo Día, 11 Oct 2026.'),
  ('miss-universe-2026', 'VE', 'Venezuela', 'CLARA VEGAS', 'ACTIVE', 'https://www.elnuevodia.com/entretenimiento/farandula/fotogalerias/miss-universe-2026-conoce-a-las-candidatas-que-van-por-la-corona-universal/', '2026-10-12 00:00:00+00', 'Also: Hola, 7 Sep 2026.');

do $$
declare n int;
begin
  select count(*) into n from event_participants
  where event_slug = 'miss-universe-2026' and status = 'ACTIVE';
  if n <> 24 then
    raise exception 'Expected 24 ACTIVE delegates after the load, found %. Rolling back.', n;
  end if;
end $$;

update events
set prediction_lock_at = '2026-11-24 23:00:00+00',
    is_featured = true
where slug = 'miss-universe-2026';

-- Verification (read this output before trusting the load):
select slug, status, is_featured, prediction_open_at, prediction_lock_at, timezone
from events order by slug;

select count(*) filter (where status = 'ACTIVE') as active_delegates,
       count(*) filter (where status <> 'ACTIVE') as non_active_rows
from event_participants where event_slug = 'miss-universe-2026';

commit;

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\imports\miss-universe-2026-roster-and-lock.sql"
} catch {
    Write-Host "FAILED: supabase\imports\miss-universe-2026-roster-and-lock.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\imports\miss-universe-2026-roster-and-lock.sql"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 11 files written successfully." -ForegroundColor Green
}