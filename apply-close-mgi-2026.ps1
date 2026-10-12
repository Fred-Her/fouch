# FOUCH — Close Miss Grand International 2026: official result (tied Top 11), post-event experience, Coming soon guard.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-close-mgi-2026.ps1
$failures = @()

try {
    $path = ".env.example"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# Copy this file to .env.local and fill in real values.
# Never commit .env.local â€” it's already in .gitignore.

# --- Supabase --------------------------------------------------------
# Public â€” safe to expose to the browser.
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
# Server-only â€” NEVER prefix with NEXT_PUBLIC_, never import outside
# src/lib/supabase/server.ts.
SUPABASE_SERVICE_ROLE_KEY=

# --- Site --------------------------------------------------------------
# Only set this once we own a real custom domain. Until then, leave it
# unset â€” src/lib/site.ts automatically falls back to Vercel's stable
# production URL (e.g. fouch-tau.vercel.app), so metadata/OG/sitemap
# never incorrectly point at a domain we don't control.
NEXT_PUBLIC_SITE_URL=

# --- Analytics (optional, future) --------------------------------------
# Leave unset locally. Analytics silently no-ops when absent.
NEXT_PUBLIC_ANALYTICS_ENABLED=
NEXT_PUBLIC_POSTHOG_KEY=
NEXT_PUBLIC_POSTHOG_HOST=

# --- Demo data guard (local development only) --------------------------
# Predictions are blocked (UI shows "Coming soon", server rejects) for any
# event whose roster is still demo/placeholder data — currently Miss
# Universe 2026. Set this to "true" ONLY in your local .env.local to keep
# testing the builder with the demo roster. NEVER set it in production.
ALLOW_DEMO_PREDICTIONS=

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     .env.example"
} catch {
    Write-Host "FAILED: .env.example -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += ".env.example"
}

try {
    $path = "src\app\events\[slug]\leaderboard\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getEventBySlug, getEntryNoun } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLeaderboard } from "@/lib/leaderboard-service";
import { MIN_PERCENTILE_SAMPLE } from "@/lib/scoring";
import { LeaderboardRow } from "@/components/scoring/LeaderboardRow";
import { LeaderboardTracker } from "@/components/scoring/LeaderboardTracker";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { getI18n } from "@/lib/i18n-server";
import { fmt } from "@/lib/i18n";
import { getNextEvent } from "@/lib/next-event";

// Sprint 5.1: this route reads Supabase state that changes independently
// of any URL parameter (a new prediction being scored, a result being
// entered) â€” force fresh server execution on every request rather than
// risk this being treated as a cacheable static/ISR route.
export const dynamic = "force-dynamic";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
  if (!event) return {};
  const { locale, dict } = await getI18n();
  const lb = dict.leaderboard;

  const participantData = await getParticipantsForEvent(slug, locale);
  const isDemo = participantData?.status === "demo";

  return {
    title: fmt(lb.metaTitle, { event: event.name }),
    description: isDemo ? lb.metaDemo : lb.metaLive,
    // Demo leaderboards should never be indexed as if they were real â€”
    // same non-indexing posture as public prediction pages (Sprint 2).
    robots: isDemo ? { index: false, follow: true } : undefined,
  };
}

export default async function EventLeaderboardPage({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ from?: string }>;
}) {
  const { slug } = await params;
  const { from } = await searchParams;
  const { locale, dict } = await getI18n();
  const lb = dict.leaderboard;

  const event = await getEventBySlug(slug);
  if (!event) notFound();

  const participantData = await getParticipantsForEvent(slug, locale);
  if (!participantData) notFound();

  const leaderboard = await getEventLeaderboard(slug, participantData.status, from);
  const nextEvent = await getNextEvent(slug, locale);
  const pluralNoun = getEntryNoun(event, true);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <div className="flex items-center justify-between">
        <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
          {lb.back}
        </Link>
        <LanguageSwitcher eventSlug={slug} />
      </div>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-1 font-display text-xl uppercase tracking-tight text-text-primary">
        {lb.title}
      </p>
      <p className="mt-2 text-sm text-text-secondary">{lb.subtitle}</p>

      {participantData.status === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          {lb.demoNote}
        </p>
      ) : null}

      {leaderboard.status === "no_result" ? (
        <div className="mt-10 rounded border border-border bg-surface p-6">
          <p className="font-display text-xl text-text-primary">{lb.locked}</p>
          <p className="mt-2 text-sm text-text-secondary">
            {fmt(lb.lockedBody, { event: event.name })}
          </p>
          <Link
            href={`/predict/${slug}`}
            className="mt-5 inline-flex items-center justify-center rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            {lb.makeCall}
          </Link>
        </div>
      ) : (
        <div className="mt-8">
          <LeaderboardTracker
            eventSlug={slug}
            dataStatus={leaderboard.dataStatus}
            leaderboardSize={leaderboard.totalCount}
            ownRank={leaderboard.viewer?.entry.rank}
            ownScoreBand={leaderboard.viewer?.entry.band}
          />

          {leaderboard.totalCount === 0 ? (
            <p className="text-sm text-text-muted">{lb.none}</p>
          ) : leaderboard.totalCount === 1 ? (
            <p className="text-sm text-text-muted">{lb.first}</p>
          ) : leaderboard.totalCount <= 4 ? (
            <p className="text-sm text-text-muted">{lb.starting}</p>
          ) : null}

          {leaderboard.viewer ? (
            <div className="mt-6 rounded border border-accent/40 bg-accent/10 p-5">
              <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-secondary">
                {lb.yourFinish}
              </p>
              <p className="mt-2 font-display text-4xl text-accent-strong">
                {fmt(lb.rankOf, { rank: leaderboard.viewer.entry.rank, total: leaderboard.totalCount })}
              </p>
              <p className="mt-1 text-sm text-text-secondary">
                {fmt(lb.scoreLine, { score: leaderboard.viewer.entry.score })}
                {leaderboard.viewer.percentile.percentile !== null
                  ? ` · ${fmt(lb.topPct, { n: Math.max(1, Math.round(100 - leaderboard.viewer.percentile.percentile)) })}`
                  : ""}
              </p>
              {leaderboard.viewer.percentile.percentile === null ? (
                <p className="mt-1 text-xs text-text-muted">
                  {fmt(lb.worldUnlocks, { n: MIN_PERCENTILE_SAMPLE })}
                </p>
              ) : null}
            </div>
          ) : null}

          {leaderboard.topEntries.length > 0 ? (
            <ol className="mt-8 space-y-2">
              {leaderboard.topEntries.map((entry) => (
                <li key={entry.publicId}>
                  <LeaderboardRow
                    entry={entry}
                    eventSlug={slug}
                    isViewer={entry.publicId === from}
                    prominent={entry.rank <= 3}
                    youLabel={lb.you}
                  />
                </li>
              ))}
            </ol>
          ) : null}

          {leaderboard.viewer && leaderboard.viewer.neighbors.length > 0 ? (
            <div className="mt-8 border-t border-border pt-6">
              <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">
                {lb.neighborhood}
              </p>
              <ol className="mt-3 space-y-2">
                {leaderboard.viewer.neighbors.map((entry) => (
                  <li key={entry.publicId}>
                    <LeaderboardRow
                      entry={entry}
                      eventSlug={slug}
                      isViewer={entry.publicId === from}
                      prominent={false}
                      youLabel={lb.you}
                    />
                  </li>
                ))}
              </ol>
            </div>
          ) : null}

          <p className="mt-6 text-xs text-text-muted">
            Showing the top {Math.min(50, leaderboard.totalCount)} {pluralNoun === "picks" ? "predictions" : pluralNoun}
            {leaderboard.totalCount > 50 ? ` of ${leaderboard.totalCount}` : ""}.
          </p>
        </div>
      )}

      {nextEvent ? (
        <div className="mt-12 border-t border-border pt-8">
          <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">{dict.unavailable.nextUp}</p>
          <Link
            href={`/predict/${nextEvent.slug}`}
            className="mt-3 inline-flex items-center justify-center rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            {nextEvent.comingSoon ? fmt(dict.unavailable.nextEventCta, { event: nextEvent.name }) : nextEvent.name}
          </Link>
        </div>
      ) : null}
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\events\[slug]\leaderboard\page.tsx"
} catch {
    Write-Host "FAILED: src\app\events\[slug]\leaderboard\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\events\[slug]\leaderboard\page.tsx"
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
  const canEdit = prediction.hasVerifiedOwner && isPredictionOpen;
  const showLockedNotice = prediction.hasVerifiedOwner && !isPredictionOpen;
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
        <UpcomingEvents events={upcomingEvents} dictionary={dict} locale={locale} comingSoonSlugs={comingSoonSlugs} />
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
    $path = "src\app\predict\[slug]\actions.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use server";

import { getEventBySlug } from "@/lib/events";
import { getEventLockConfig } from "@/lib/events-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { validateSubmission } from "@/lib/prediction-validation";
import { insertPrediction, getPredictionByDeviceToken } from "@/lib/predictions-db";
import { isDemoPredictionBlocked } from "@/lib/event-readiness";

export interface SubmitPredictionInput {
  eventSlug: string;
  participantIds: string[];
  nickname?: string;
  countryCode?: string;
  deviceToken: string;
}

export type SubmitPredictionResult =
  | { success: true; publicId: string }
  | { success: false; error: string };

export async function submitPrediction(
  input: SubmitPredictionInput,
): Promise<SubmitPredictionResult> {
  const event = await getEventBySlug(input.eventSlug);
  if (!event) {
    return { success: false, error: "This event doesn't exist." };
  }

  const participantData = await getParticipantsForEvent(input.eventSlug);
  if (!participantData) {
    return { success: false, error: "This event has no contestants configured." };
  }

  if (isDemoPredictionBlocked(participantData.status)) {
    return { success: false, error: "Predictions for this event aren't open yet." };
  }

  const requiredCount = Math.min(10, participantData.participants.length);

  // FOUCH 0.3A: lock/open timing comes from Supabase (single
  // authoritative source), fetched fresh on every submission attempt
  // â€” never cached, never trusted from the client.
  const lockConfig = await getEventLockConfig(input.eventSlug);

  const validation = validateSubmission(
    {
      participantIds: input.participantIds,
      nickname: input.nickname,
      countryCode: input.countryCode,
    },
    event,
    participantData.participants,
    requiredCount,
    lockConfig,
  );

  if (!validation.valid) {
    return { success: false, error: validation.error };
  }

  if (!input.deviceToken || typeof input.deviceToken !== "string") {
    return { success: false, error: "Missing device token." };
  }

  const result = await insertPrediction({
    eventSlug: input.eventSlug,
    participantIds: validation.data.participantIds,
    nickname: validation.data.nickname,
    countryCode: validation.data.countryCode,
    dataStatus: participantData.status,
    deviceToken: input.deviceToken,
  });

  if (!result.success) {
    return { success: false, error: result.error };
  }

  return { success: true, publicId: result.publicId };
}

/**
 * Checks whether this device already has a submitted prediction for
 * this event, so the Review screen can redirect straight to the
 * existing public prediction instead of showing the submit form again
 * â€” a submitted prediction is immutable in Sprint 2.
 */
export async function checkExistingSubmission(
  eventSlug: string,
  deviceToken: string,
): Promise<{ publicId: string } | null> {
  if (!deviceToken) return null;
  const existing = await getPredictionByDeviceToken(eventSlug, deviceToken);
  return existing ? { publicId: existing.publicId } : null;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\actions.ts"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\actions.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\actions.ts"
}

try {
    $path = "src\app\predict\[slug]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { formatContestantListUpdated } from "@/lib/event-time-display";
import { PredictionBuilder } from "@/components/prediction/PredictionBuilder";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { getI18n } from "@/lib/i18n-server";
import { fmt } from "@/lib/i18n";
import { PredictionUnavailable } from "@/components/PredictionUnavailable";
import { isDemoPredictionBlocked } from "@/lib/event-readiness";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
  if (!event) return {};
  const { dict } = await getI18n();

  return {
    title: fmt(dict.builder.metaTitle, { event: event.name }),
    description: dict.builder.metaDescription,
  };
}

const REQUIRED_SELECTIONS = 10;

export default async function PredictPage({
  params,
  searchParams,
}: {
  params: Promise<{ slug: string }>;
  searchParams: Promise<{ from?: string }>;
}) {
  const { slug } = await params;
  const { from } = await searchParams;
  const { locale, dict } = await getI18n();
  const t = dict.builder;
  const event = await getEventBySlug(slug);
  if (!event) notFound();

  const participantData = await getParticipantsForEvent(slug, locale);
  if (!participantData || participantData.participants.length === 0) {
    return (
      <main className="mx-auto max-w-content px-6 py-16">
        <Link
          href="/"
          className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          {t.backToFouch}
        </Link>
        <p className="mt-8 text-text-secondary">
          {t.noParticipants}
        </p>
      </main>
    );
  }

  const lockConfig = await getEventLockConfig(slug);
  if (isDemoPredictionBlocked(participantData.status)) {
    return <PredictionUnavailable variant="coming_soon" eventName={event.name} eventSlug={slug} dictionary={dict} />;
  }
  if (!isPredictionWindowOpen(lockConfig, Date.now())) {
    return <PredictionUnavailable variant="closed" eventName={event.name} eventSlug={slug} dictionary={dict} />;
  }

  const { status, participants, sourceCheckedAt } = participantData;
  const requiredCount = Math.min(REQUIRED_SELECTIONS, participants.length);

  return (
    <main>
      <div className="mx-auto max-w-content px-6 pt-8">
        <div className="flex items-center justify-between">
          <Link
            href="/"
            className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
          >
            <ArrowLeft className="h-4 w-4" aria-hidden />
            {t.backToFouch}
          </Link>
          <LanguageSwitcher eventSlug={slug} />
        </div>

        <p className="mt-6 font-display text-sm tracking-[0.2em] text-text-muted">FOUCH</p>
        <h1 className="mt-1 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
        <p className="mt-3 font-display text-xl uppercase tracking-tight text-text-primary">
          {fmt(t.buildTitle, { n: requiredCount })}
        </p>
        <p className="mt-2 max-w-md text-sm text-text-secondary">
          {fmt(t.buildHint, { n: requiredCount })}
        </p>

        {status === "demo" ? (
          <p className="mt-4 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
            {t.demoNote}
          </p>
        ) : sourceCheckedAt ? (
          <p className="mt-4 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
            {formatContestantListUpdated(sourceCheckedAt, t.listUpdated, locale)}
          </p>
        ) : null}
      </div>

      <div className="mt-8">
        <PredictionBuilder
          eventSlug={slug}
          participants={participants}
          requiredCount={requiredCount}
          sourcePredictionId={from}
        />
      </div>
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\page.tsx"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\page.tsx"
}

try {
    $path = "src\app\predict\[slug]\review\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { ReviewContent } from "@/components/prediction/ReviewContent";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { getI18n } from "@/lib/i18n-server";
import { fmt } from "@/lib/i18n";
import { PredictionUnavailable } from "@/components/PredictionUnavailable";
import { isDemoPredictionBlocked } from "@/lib/event-readiness";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
  if (!event) return {};
  const { dict } = await getI18n();

  return { title: fmt(dict.review.metaTitle, { event: event.name }) };
}

const REQUIRED_SELECTIONS = 10;

export default async function ReviewPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const { locale, dict } = await getI18n();
  const event = await getEventBySlug(slug);
  if (!event) notFound();

  const participantData = await getParticipantsForEvent(slug, locale);
  if (!participantData || participantData.participants.length === 0) notFound();

  const lockConfig = await getEventLockConfig(slug);
  if (isDemoPredictionBlocked(participantData.status)) {
    return <PredictionUnavailable variant="coming_soon" eventName={event.name} eventSlug={slug} dictionary={dict} />;
  }
  if (!isPredictionWindowOpen(lockConfig, Date.now())) {
    return <PredictionUnavailable variant="closed" eventName={event.name} eventSlug={slug} dictionary={dict} />;
  }

  const requiredCount = Math.min(REQUIRED_SELECTIONS, participantData.participants.length);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <div className="flex items-center justify-between">
        <Link
          href={`/predict/${slug}`}
          className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          {dict.builder.backToBuilder}
        </Link>
        <LanguageSwitcher eventSlug={slug} />
      </div>

      <p className="mt-6 font-display text-sm tracking-[0.2em] text-text-muted">FOUCH</p>
      <h1 className="mt-1 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-3 font-display text-xl uppercase tracking-tight text-text-primary">
        {fmt(dict.review.yourTop, { n: requiredCount })}
      </p>

      <div className="mt-8">
        <ReviewContent
          eventSlug={slug}
          participants={participantData.participants}
          requiredCount={requiredCount}
        />
      </div>
    </main>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\review\page.tsx"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\review\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\review\page.tsx"
}

try {
    $path = "src\app\predict\[slug]\verify-actions.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use server";

import { getEventBySlug } from "@/lib/events";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { validateSubmission } from "@/lib/prediction-validation";
import {
  insertPrediction,
  getDeviceTokenIdentity,
  getPredictionForEdit,
  createPredictionVersion,
  type InsertPredictionResult,
} from "@/lib/predictions-db";
import { isDeviceIdentityMismatch } from "@/lib/insert-conflict";
import { isAuthorizedToEdit } from "@/lib/prediction-version-logic";
import { normalizeEmail, isValidEmail } from "@/lib/email-validation";
import { getSupabaseAuthClient } from "@/lib/supabase/auth-client";
import { isDemoPredictionBlocked } from "@/lib/event-readiness";

/**
 * Beta Hardening 0.2 Phase C â€” the verified-lock flow.
 *
 * GATE 1 + GATE 2 CLOSED: this file is wired into ReviewContent.tsx's
 * real Lock button, and the old `predictions_event_device_unique`
 * constraint has been dropped in production (migration 0006). See
 * FOUCH_BETA_HARDENING_02_PHASE_C.md for the completed cutover
 * procedure. device_token is now purely the soft, non-blocking signal
 * described in FOUCH_IDENTITY_ARCHITECTURE.md.
 */

export type StartVerificationResult = { success: true } | { success: false; error: string };

/**
 * Requests an OTP for the given email. Never reveals whether the
 * email already exists as a user, or already has a prediction for
 * this event â€” that check only happens AFTER verification succeeds
 * (see verifyEmailAndLockPrediction), specifically to avoid an
 * email-enumeration leak at this earlier, unauthenticated step.
 */
export async function startEmailVerification(email: string): Promise<StartVerificationResult> {
  const normalized = normalizeEmail(email);
  if (!isValidEmail(normalized)) {
    return { success: false, error: "That doesn't look like a valid email address." };
  }

  const supabase = getSupabaseAuthClient();
  if (!supabase) {
    return { success: false, error: "Verification isn't available right now — try again shortly." };
  }

  const { error } = await supabase.auth.signInWithOtp({
    email: normalized,
    options: { shouldCreateUser: true },
  });

  if (error) {
    // Supabase's own message here is already safe/generic (rate-limit,
    // transient failure) â€” never surface raw error internals, but no
    // need to further genericize what Supabase itself already returns
    // as a user-facing string.
    return { success: false, error: "We couldn't send a code — try again in a moment." };
  }

  return { success: true };
}

export interface LockPredictionPayload {
  eventSlug: string;
  participantIds: string[];
  nickname?: string;
  countryCode?: string;
  deviceToken: string;
}

export type VerifyAndLockFailureReason =
  | "invalid_code"
  | "expired_code"
  | "insert_failed"
  | "session_expired"
  | "validation_failed";

export type VerifyAndLockResult =
  | { success: true; publicId: string; duplicateDeviceSignal: boolean }
  | {
      success: false;
      error: string;
      failureReason: VerifyAndLockFailureReason;
      /** Present only when OTP verification itself succeeded but the
       * insert failed transiently â€” lets the client retry the lock
       * step alone, without a new OTP (frozen retry semantics). */
      accessToken?: string;
    };

/** Shared by verifyEmailAndLockPrediction and retryLockWithVerifiedSession
 * â€” re-validates the entire payload server-side (never weaker than the
 * existing anonymous submitPrediction() path) and attempts the insert
 * with the now-known auth_user_id. */
async function validateAndLock(
  authUserId: string,
  payload: LockPredictionPayload,
): Promise<VerifyAndLockResult> {
  const event = await getEventBySlug(payload.eventSlug);
  if (!event) {
    return { success: false, error: "This event doesn't exist.", failureReason: "validation_failed" };
  }

  const participantData = await getParticipantsForEvent(payload.eventSlug);
  if (!participantData) {
    return {
      success: false,
      error: "This event has no contestants configured.",
      failureReason: "validation_failed",
    };
  }

  if (isDemoPredictionBlocked(participantData.status)) {
    return {
      success: false,
      error: "Predictions for this event aren't open yet.",
      failureReason: "validation_failed",
    };
  }

  const requiredCount = Math.min(10, participantData.participants.length);

  // FOUCH 0.3A: fetched fresh on every lock/edit attempt from
  // Supabase, the single authoritative source â€” never from
  // src/lib/events.ts, never from anything the client supplies.
  const lockConfig = await getEventLockConfig(payload.eventSlug);

  const validation = validateSubmission(
    { participantIds: payload.participantIds, nickname: payload.nickname, countryCode: payload.countryCode },
    event,
    participantData.participants,
    requiredCount,
    lockConfig,
  );

  if (!validation.valid) {
    return { success: false, error: validation.error, failureReason: "validation_failed" };
  }

  if (!payload.deviceToken || typeof payload.deviceToken !== "string") {
    return { success: false, error: "Missing device token.", failureReason: "validation_failed" };
  }

  // Soft signal only â€” computed BEFORE the insert (so it reflects
  // whoever already holds this device, if anyone), never blocks.
  const existingOnDevice = await getDeviceTokenIdentity(payload.eventSlug, payload.deviceToken);
  const duplicateDeviceSignal = isDeviceIdentityMismatch(existingOnDevice, {
    deviceToken: payload.deviceToken,
    authUserId,
  });

  let result: InsertPredictionResult;
  try {
    result = await insertPrediction({
      eventSlug: payload.eventSlug,
      participantIds: validation.data.participantIds,
      nickname: validation.data.nickname,
      countryCode: validation.data.countryCode,
      dataStatus: participantData.status,
      deviceToken: payload.deviceToken,
      authUserId,
    });
  } catch {
    return {
      success: false,
      error: "We couldn't lock your prediction. Your Top 10 is still saved — try again.",
      failureReason: "insert_failed",
    };
  }

  if (!result.success) {
    return { success: false, error: result.error, failureReason: "insert_failed" };
  }

  return { success: true, publicId: result.publicId, duplicateDeviceSignal };
}

/**
 * The main verified-lock entry point: verifies the OTP, then
 * immediately attempts the lock as the next step in the same
 * user-facing action â€” sequential, not one shared database
 * transaction (see FOUCH_IDENTITY_ARCHITECTURE.md).
 */
export async function verifyEmailAndLockPrediction(
  email: string,
  code: string,
  payload: LockPredictionPayload,
): Promise<VerifyAndLockResult> {
  const normalized = normalizeEmail(email);

  const supabase = getSupabaseAuthClient();
  if (!supabase) {
    return {
      success: false,
      error: "Verification isn't available right now — try again shortly.",
      failureReason: "invalid_code",
    };
  }

  const { data, error } = await supabase.auth.verifyOtp({
    email: normalized,
    token: code,
    type: "email",
  });

  if (error || !data.user) {
    const message = error?.message.toLowerCase() ?? "";
    const failureReason: VerifyAndLockFailureReason = message.includes("expired")
      ? "expired_code"
      : "invalid_code";
    const userMessage =
      failureReason === "expired_code"
        ? "That code expired."
        : "That code didn't match. Check your email and try again.";
    return { success: false, error: userMessage, failureReason };
  }

  const result = await validateAndLock(data.user.id, payload);

  // Only offer a no-new-OTP retry when verification itself succeeded
  // (we have a real session) but the LOCK step is what failed.
  if (!result.success && result.failureReason === "insert_failed" && data.session) {
    return { ...result, accessToken: data.session.access_token };
  }

  return result;
}

/**
 * Retries only the lock step after a transient insert failure,
 * reusing the access token obtained during the original OTP
 * verification â€” never requires a new code, per the frozen retry
 * semantics. Validates the token server-side via Supabase Auth itself
 * (getUser) rather than trusting anything the client asserts.
 */
export async function retryLockWithVerifiedSession(
  accessToken: string,
  payload: LockPredictionPayload,
): Promise<VerifyAndLockResult> {
  const supabase = getSupabaseAuthClient();
  if (!supabase) {
    return {
      success: false,
      error: "Verification isn't available right now — try again shortly.",
      failureReason: "session_expired",
    };
  }

  const { data, error } = await supabase.auth.getUser(accessToken);

  if (error || !data.user) {
    return {
      success: false,
      error: "Your verification expired — please request a new code.",
      failureReason: "session_expired",
    };
  }

  const result = await validateAndLock(data.user.id, payload);

  if (!result.success && result.failureReason === "insert_failed") {
    return { ...result, accessToken };
  }

  return result;
}

/* ------------------------------------------------------------------
 * FOUCH 0.3A â€” Editable Predictions.
 *
 * Deliberately mirrors the Lock flow above almost exactly: same
 * email â†’ OTP â†’ verify shape, same accessToken-based retry-without-
 * new-code semantics, because the identity architecture is frozen
 * (Beta Hardening 0.2 rules are unchanged, see brief Â§3). The only
 * new thing editing needs on top of that is OWNERSHIP authorization
 * â€” see validateAndEdit below.
 *
 * Legacy scope (explicit product decision, not inferred): a
 * prediction with auth_user_id = null has no verified identity to
 * authorize an edit against, and this sprint introduces no mechanism
 * to retroactively claim one via nickname, device_token, a
 * later-entered email, public_id, or anything else. Such predictions
 * remain fully public/readable/scoreable forever, exactly as today â€”
 * they are simply never editable. The UI never even offers "EDIT MY
 * TOP 10" for them (see PublicPredictionPage), but the server check
 * below is the actual authorization boundary, not the UI.
 * ------------------------------------------------------------------ */

export interface EditPredictionPayload {
  publicId: string;
  participantIds: string[];
  /** The version_number the client read just before opening the edit
   * builder â€” used as an optimistic-concurrency check, see
   * createPredictionVersion() in predictions-db.ts. */
  expectedVersionNumber: number;
}

export type VerifyAndEditFailureReason =
  | "invalid_code"
  | "expired_code"
  | "not_found"
  | "not_owner"
  | "locked"
  | "validation_failed"
  | "conflict"
  | "edit_failed"
  | "session_expired";

export type VerifyAndEditResult =
  | { success: true; publicId: string; versionNumber: number; unchanged: boolean }
  | {
      success: false;
      error: string;
      failureReason: VerifyAndEditFailureReason;
      /** Present only when OTP verification itself succeeded but the
       * save step failed transiently â€” lets the client retry the save
       * step alone, without a new OTP (same frozen retry semantics as
       * the lock flow). Never present for not_owner/locked/conflict â€”
       * those are never worth retrying with the same input. */
      accessToken?: string;
    };

/**
 * Shared by verifyEmailAndEditPrediction and
 * retryEditWithVerifiedSession. Every authorization and timing check
 * here is independent server-side state â€” nothing the client supplies
 * (publicId aside, which only selects WHICH prediction, never
 * authorizes anything on its own) is trusted for identity or timing.
 */
async function validateAndEdit(
  authUserId: string,
  payload: EditPredictionPayload,
): Promise<VerifyAndEditResult> {
  const editable = await getPredictionForEdit(payload.publicId);
  if (!editable) {
    return { success: false, error: "We couldn't find that prediction.", failureReason: "not_found" };
  }

  // The critical authorization check (brief Â§10-11, reconfirmed for
  // legacy scope): the verified auth_user_id from THIS session must
  // match the prediction's stored auth_user_id exactly. See
  // isAuthorizedToEdit's own doc for why this single, pure check is
  // the entire ownership rule â€” no nickname/device_token/public_id/
  // email-based claiming exists anywhere in this codebase.
  if (!isAuthorizedToEdit(editable.authUserId, authUserId)) {
    return {
      success: false,
      error: "This isn't your prediction.",
      failureReason: "not_owner",
    };
  }

  const event = await getEventBySlug(editable.eventSlug);
  if (!event) {
    return { success: false, error: "This event doesn't exist.", failureReason: "validation_failed" };
  }

  const participantData = await getParticipantsForEvent(editable.eventSlug);
  if (!participantData) {
    return {
      success: false,
      error: "This event has no contestants configured.",
      failureReason: "validation_failed",
    };
  }

  const requiredCount = Math.min(10, participantData.participants.length);

  // Re-fetched fresh, right now, from Supabase â€” the one and only
  // authoritative source. Never trust that the event was still open
  // when the edit page loaded; only whether it's open THIS instant.
  const lockConfig = await getEventLockConfig(editable.eventSlug);
  if (!isPredictionWindowOpen(lockConfig, Date.now())) {
    return {
      success: false,
      error: "Predictions for this event are locked.",
      failureReason: "locked",
    };
  }

  const validation = validateSubmission(
    { participantIds: payload.participantIds },
    event,
    participantData.participants,
    requiredCount,
    lockConfig,
  );

  if (!validation.valid) {
    return { success: false, error: validation.error, failureReason: "validation_failed" };
  }

  let result;
  try {
    result = await createPredictionVersion({
      predictionPublicId: editable.publicId,
      participantIds: validation.data.participantIds,
      expectedVersionNumber: payload.expectedVersionNumber,
      currentRankedParticipantIds: editable.currentRankedParticipantIds,
    });
  } catch {
    return {
      success: false,
      error: "We couldn't save your changes. Your Top 10 is still what it was — try again.",
      failureReason: "edit_failed",
    };
  }

  if (!result.success) {
    const failureReason: VerifyAndEditFailureReason = result.error.startsWith("Your prediction changed")
      ? "conflict"
      : "edit_failed";
    return { success: false, error: result.error, failureReason };
  }

  return {
    success: true,
    publicId: result.publicId,
    versionNumber: result.versionNumber,
    unchanged: result.unchanged,
  };
}

/**
 * The main verified-edit entry point â€” verifies the OTP, then
 * immediately attempts the edit as the next step in the same
 * user-facing action, exactly mirroring verifyEmailAndLockPrediction.
 */
export async function verifyEmailAndEditPrediction(
  email: string,
  code: string,
  payload: EditPredictionPayload,
): Promise<VerifyAndEditResult> {
  const normalized = normalizeEmail(email);

  const supabase = getSupabaseAuthClient();
  if (!supabase) {
    return {
      success: false,
      error: "Verification isn't available right now — try again shortly.",
      failureReason: "invalid_code",
    };
  }

  const { data, error } = await supabase.auth.verifyOtp({
    email: normalized,
    token: code,
    type: "email",
  });

  if (error || !data.user) {
    const message = error?.message.toLowerCase() ?? "";
    const failureReason: VerifyAndEditFailureReason = message.includes("expired")
      ? "expired_code"
      : "invalid_code";
    const userMessage =
      failureReason === "expired_code"
        ? "That code expired."
        : "That code didn't match. Check your email and try again.";
    return { success: false, error: userMessage, failureReason };
  }

  const result = await validateAndEdit(data.user.id, payload);

  // Only offer a no-new-OTP retry when verification itself succeeded
  // (we have a real session) but the SAVE step is what failed
  // transiently â€” never for not_owner/locked/conflict/validation,
  // none of which a bare retry with the same input would fix.
  if (!result.success && result.failureReason === "edit_failed" && data.session) {
    return { ...result, accessToken: data.session.access_token };
  }

  return result;
}

/**
 * Retries only the save step after a transient failure, reusing the
 * access token from the original OTP verification â€” mirrors
 * retryLockWithVerifiedSession exactly.
 */
export async function retryEditWithVerifiedSession(
  accessToken: string,
  payload: EditPredictionPayload,
): Promise<VerifyAndEditResult> {
  const supabase = getSupabaseAuthClient();
  if (!supabase) {
    return {
      success: false,
      error: "Verification isn't available right now — try again shortly.",
      failureReason: "session_expired",
    };
  }

  const { data, error } = await supabase.auth.getUser(accessToken);

  if (error || !data.user) {
    return {
      success: false,
      error: "Your verification expired — please request a new code.",
      failureReason: "session_expired",
    };
  }

  const result = await validateAndEdit(data.user.id, payload);

  if (!result.success && result.failureReason === "edit_failed") {
    return { ...result, accessToken };
  }

  return result;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\predict\[slug]\verify-actions.ts"
} catch {
    Write-Host "FAILED: src\app\predict\[slug]\verify-actions.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\predict\[slug]\verify-actions.ts"
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
}: {
  events: FouchEvent[];
  dictionary: Dictionary;
  locale?: Locale;
  /** Slugs with no official roster yet: shown as "Coming soon", no CTA. */
  comingSoonSlugs?: string[];
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
                      {String(index + 2).padStart(2, "0")}
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
    cta: "Start predicting",
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
    cta: "Make your Top 10",
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
    cta: "Empieza a predecir",
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
    cta: "Arma tu Top 10",
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
    $path = "src\lib\event-name-split.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { splitEventNameYear, getEventShortLabel } from "./event-name-split";

describe("splitEventNameYear — generic, never a specific-event hardcode", () => {
  it("splits 'Miss Universe 2026' into 'Miss Universe' + '2026'", () => {
    expect(splitEventNameYear("Miss Universe 2026")).toEqual({ primary: "Miss Universe", year: "2026" });
  });

  it("splits 'Miss Grand International 2026' into 'Miss Grand International' + '2026' — same function, no per-event branch", () => {
    expect(splitEventNameYear("Miss Grand International 2026")).toEqual({
      primary: "Miss Grand International",
      year: "2026",
    });
  });

  it("falls back to the whole name with no year when there is no trailing 4-digit token", () => {
    expect(splitEventNameYear("The Oscars")).toEqual({ primary: "The Oscars", year: null });
  });

  it("does not split on a non-4-digit trailing number", () => {
    expect(splitEventNameYear("Top 10")).toEqual({ primary: "Top 10", year: null });
  });
});

describe("getEventShortLabel — generic, never keyed to one event", () => {
  it("abbreviates three-or-more-word names", () => {
    expect(getEventShortLabel("Miss Grand International 2026")).toBe("MGI 2026");
  });
  it("keeps short names in full", () => {
    expect(getEventShortLabel("Miss Universe 2026")).toBe("Miss Universe 2026");
    expect(getEventShortLabel("Eurovision")).toBe("Eurovision");
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-name-split.test.ts"
} catch {
    Write-Host "FAILED: src\lib\event-name-split.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-name-split.test.ts"
}

try {
    $path = "src\lib\event-name-split.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * FOUCH 0.3B Home Multi-Event Rendering Fix — the FeaturedEvent card's
 * two-line typography ("MISS UNIVERSE" / "2026") used to be two
 * literal hardcoded strings, which meant every event rendered as
 * "Miss Universe 2026" regardless of which event was actually
 * featured. This is the generic, event-agnostic replacement: split
 * any event.name into a "primary" line and a trailing "year" line
 * purely by pattern (a trailing 4-digit token), never by matching a
 * specific event's name. The next event added to the `events` table
 * needs zero changes here.
 */
export function splitEventNameYear(name: string): { primary: string; year: string | null } {
  const match = name.trim().match(/^(.*\S)\s+(\d{4})$/);
  if (!match) return { primary: name.trim(), year: null };
  const primary = match[1] ?? name.trim();
  const year = match[2] ?? null;
  return { primary, year };
}

/**
 * Compact label for tight spots (e.g. the Home results link):
 * "Miss Grand International 2026" -> "MGI 2026". Only abbreviates
 * names of three or more words; shorter names ("Miss Universe 2026")
 * are returned in full. Pure and generic — never keyed to one event.
 */
export function getEventShortLabel(name: string): string {
  const { primary, year } = splitEventNameYear(name);
  const words = primary.split(/\s+/).filter(Boolean);
  if (words.length < 3) return name.trim();
  const initials = words.map((word) => word.charAt(0).toUpperCase()).join("");
  return year ? `${initials} ${year}` : initials;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-name-split.ts"
} catch {
    Write-Host "FAILED: src\lib\event-name-split.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-name-split.ts"
}

try {
    $path = "src\lib\events-db.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { isPredictionWindowOpen, type EventLockConfig } from "@/lib/prediction-lock-logic";
import { pickFeaturedEventSlug, type FeaturedCandidate } from "@/lib/featured-event-logic";
import type { FouchEvent, EventCategory, EventStatus } from "@/types/event";

// Re-exported unchanged so every existing import site
// (`@/lib/events-db`) keeps working — the pure logic itself now lives
// in prediction-lock-logic.ts purely so it can be unit tested without
// pulling in the "server-only" guard above. See that file's comment.
export { isPredictionWindowOpen };
export type { EventLockConfig };
export { pickFeaturedEventSlug };
export type { FeaturedCandidate };

/**
 * FOUCH 0.3A — the single authoritative source for prediction open/lock
 * timing. Supabase `events.prediction_open_at` / `prediction_lock_at`
 * (migration 0007) replace the old hardcoded values in
 * src/lib/events.ts, which may still hold display-only metadata
 * (name, subtitle, hero asset) but must never again be consulted for
 * timing decisions.
 *
 * Every timestamp here is compared against `Date.now()` on the
 * server that runs this code — never a value the browser supplies —
 * per the frozen rule that client clocks must never be trusted.
 */

/**
 * Returns null when the event row doesn't exist or the database isn't
 * configured. Callers must treat null as "no lock configured" (never
 * throw, never fail open in a way that fabricates a lock date) — this
 * mirrors how every other lookup in this codebase degrades when
 * Supabase is unavailable (see predictions-db.ts).
 */
export async function getEventLockConfig(eventSlug: string): Promise<EventLockConfig | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("events")
    .select("prediction_open_at, prediction_lock_at, timezone")
    .eq("slug", eventSlug)
    .maybeSingle();

  if (error || !data) return null;

  return {
    predictionOpenAt: data.prediction_open_at,
    predictionLockAt: data.prediction_lock_at,
    timezone: data.timezone,
  };
}

/**
 * FOUCH 0.3B Event Resolution Fix — `events` is now the single
 * source of truth for event metadata (name, category, status,
 * subtitle, event_date, is_featured), replacing the hardcoded array
 * that used to live in src/lib/events.ts. That file now just
 * delegates here.
 *
 * entryNounSingular/entryNounPlural (FouchEvent's two remaining
 * optional fields) have no DB column — neither existing event
 * (Miss Universe, Miss Grand) has ever set them, so they're left
 * undefined here and getEntryNoun's existing "pick"/"picks" default
 * applies exactly as before. No column was added for this: the
 * audit for this fix confirmed the `events` table already covers
 * every field either event actually uses.
 */
function toFouchEvent(row: {
  id: string;
  slug: string;
  name: string;
  category: string;
  status: string;
  event_date: string;
  hero_asset: string | null;
  is_featured: boolean;
  subtitle: string | null;
}): FouchEvent {
  return {
    id: row.id,
    slug: row.slug,
    name: row.name,
    category: row.category as EventCategory,
    status: row.status as EventStatus,
    eventDate: row.event_date,
    heroAsset: row.hero_asset ?? undefined,
    isFeatured: row.is_featured,
    subtitle: row.subtitle ?? undefined,
  };
}

const EVENT_COLUMNS = "id, slug, name, category, status, event_date, hero_asset, is_featured, subtitle";

/**
 * Resolves any event by slug from the database — Miss Universe and
 * Miss Grand alike, no hardcoded special case for either. Returns
 * null for an unknown slug (the caller's existing `notFound()`
 * handling is unchanged) or when Supabase isn't configured.
 */
export async function getEventBySlugFromDb(slug: string): Promise<FouchEvent | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase.from("events").select(EVENT_COLUMNS).eq("slug", slug).maybeSingle();

  if (error || !data) return null;
  return toFouchEvent(data);
}

/**
 * FOUCH 0.3B Home Multi-Event Rendering Fix — every event with
 * status = 'upcoming', ordered by date. The Home page uses this to
 * render the secondary "Upcoming" section, excluding whichever event
 * it already shows as Featured. This is the minimal generic query
 * needed to support more than one event on the Home at once — no
 * per-event special casing, no admin UI, just a plain SELECT.
 */
export async function getUpcomingEventsFromDb(): Promise<FouchEvent[]> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  const { data, error } = await supabase
    .from("events")
    .select(EVENT_COLUMNS)
    .eq("status", "upcoming")
    .order("event_date", { ascending: true });

  if (error || !data) return [];
  return data.map(toFouchEvent);
}

/**
 * Resolves the current featured event from the database. If more
 * than one row has is_featured = true (a data-entry mistake — see
 * this fix's report on why no DB constraint enforces "at most one"
 * yet), picks deterministically via pickFeaturedEventSlug's tie-break
 * (alphabetically first slug) rather than an arbitrary row order, by
 * mirroring that exact tie-break in the query's own ORDER BY.
 */
export async function getFeaturedEventFromDb(): Promise<FouchEvent | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("events")
    .select(EVENT_COLUMNS)
    .eq("is_featured", true)
    .order("slug", { ascending: true });

  if (error || !data || data.length === 0) return null;

  const candidates: FeaturedCandidate[] = data.map((row) => ({ slug: row.slug, isFeatured: row.is_featured }));
  const featuredSlug = pickFeaturedEventSlug(candidates);
  const chosen = data.find((row) => row.slug === featuredSlug);
  return chosen ? toFouchEvent(chosen) : null;
}

/**
 * The most recently completed event (status = 'completed'), used by
 * the Home to link to its final results/leaderboard. Generic — never
 * keyed to a specific event.
 */
export async function getLatestCompletedEventFromDb(): Promise<FouchEvent | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("events")
    .select(EVENT_COLUMNS)
    .eq("status", "completed")
    .order("event_date", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (error || !data) return null;
  return toFouchEvent(data);
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\events-db.ts"
} catch {
    Write-Host "FAILED: src\lib\events-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\events-db.ts"
}

try {
    $path = "src\lib\events.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import type { FouchEvent } from "@/types/event";
import {
  getEventBySlugFromDb,
  getFeaturedEventFromDb,
  getLatestCompletedEventFromDb,
  getUpcomingEventsFromDb,
} from "@/lib/events-db";

/**
 * FOUCH 0.3B Event Resolution Fix — `events` in Supabase is now the
 * single source of truth for event metadata, replacing the
 * hardcoded array that used to live here. This file used to define
 * Miss Universe 2026 directly in TypeScript; that row already exists
 * in the database (seeded since migration 0001/0007) with every field
 * this file used to hardcode, so switching this file to read from
 * there loses nothing for Miss Universe and is what let Miss Grand
 * International 2026 — added straight to the database in 0.3B —
 * resolve correctly for the first time (previously getEventBySlug
 * returned null for it, since it was never added to this array,
 * which meant its /predict route 404'd and it could never become the
 * Home's featured event no matter what the database's own
 * `is_featured` column said).
 *
 * Both exports are now async — every existing caller already ran
 * inside an async Server Component or Server Action, so this is a
 * mechanical `await` addition at each call site, not a behavior
 * change.
 */
export async function getFeaturedEvent(): Promise<FouchEvent | null> {
  return getFeaturedEventFromDb();
}

export async function getEventBySlug(slug: string): Promise<FouchEvent | null> {
  return getEventBySlugFromDb(slug);
}

/**
 * FOUCH 0.3B Home Multi-Event Rendering Fix — every upcoming event
 * EXCEPT the one already shown as Featured, for the Home's secondary
 * "Upcoming" section. Purely a filter on top of getUpcomingEventsFromDb
 * — no separate query, no per-event logic.
 */
export async function getSecondaryUpcomingEvents(excludeSlug: string | null): Promise<FouchEvent[]> {
  const events = await getUpcomingEventsFromDb();
  return events.filter((event) => event.slug !== excludeSlug);
}

/**
 * The generic, event-agnostic term for one ranked option — "pick" by
 * default (fits the current demo country dataset), overridable per
 * event via entryNounSingular/Plural for future categories (Oscars
 * "nominee", Eurovision "entry", a verified pageant "contestant").
 */
export function getEntryNoun(event: FouchEvent, plural: boolean): string {
  if (plural) return event.entryNounPlural ?? "picks";
  return event.entryNounSingular ?? "pick";
}
/** Most recent completed event, for the Home's "results" link. */
export async function getLatestCompletedEvent(): Promise<FouchEvent | null> {
  return getLatestCompletedEventFromDb();
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\events.ts"
} catch {
    Write-Host "FAILED: src\lib\events.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\events.ts"
}

try {
    $path = "src\lib\leaderboard-service.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { scorePrediction } from "@/lib/scoring";
import { getOfficialResult } from "@/lib/results-db";
import { getLeaderboardRawEntries } from "@/lib/predictions-db";
import { buildLeaderboard, resolveViewerContext, LEADERBOARD_TOP_N } from "@/lib/leaderboard";
import type { LeaderboardEntry, ViewerContext } from "@/lib/leaderboard";
import type { ParticipantDataStatus } from "@/lib/participants";
import { applyLeaderboardExclusions } from "@/lib/leaderboard-exclusions";

export interface EventLeaderboard {
  status: "no_result" | "scored";
  dataStatus: ParticipantDataStatus;
  totalCount: number;
  topEntries: LeaderboardEntry[];
  /** Present only when a viewerPublicId was given AND it resolved to
   * an eligible, scored prediction on THIS leaderboard. Absent
   * viewer context never affects `status` or `topEntries` above —
   * see resolveViewerContext() in src/lib/leaderboard.ts, which this
   * calls as a pure, separately-tested step. */
  viewer: ViewerContext | null;
}

/**
 * Builds the full event leaderboard. Ranking happens here, server-side,
 * over every eligible entry — the client only ever receives the
 * already-ranked, already-trimmed result (brief §19-21), never the raw
 * prediction list.
 *
 * Returns `{ status: "no_result" }` when there's no official/demo
 * result yet — the page renders a "leaderboard locked" state, never a
 * fabricated empty board (brief §28). This decision is made BEFORE
 * `viewerPublicId` is even read below — the leaderboard's existence
 * can never depend on who's asking (Sprint 5.1 fix).
 */
export async function getEventLeaderboard(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
  viewerPublicId?: string,
): Promise<EventLeaderboard> {
  const official = await getOfficialResult(eventSlug, dataStatus);
  if (!official) {
    return { status: "no_result", dataStatus, totalCount: 0, topEntries: [], viewer: null };
  }

  const rawEntries = applyLeaderboardExclusions(
    await getLeaderboardRawEntries(eventSlug, dataStatus),
    eventSlug,
  );

  const scored = rawEntries.map((entry) => ({
    ...entry,
    breakdown: scorePrediction(entry.rankedParticipantIds, official),
  }));

  const leaderboard = buildLeaderboard(
    scored.map((entry) => ({
      publicId: entry.publicId,
      nickname: entry.nickname,
      countryCode: entry.countryCode,
      displayScore: entry.breakdown.displayScore,
    })),
  );

  const fullPrecisionScoreByPublicId = new Map(scored.map((e) => [e.publicId, e.breakdown.score]));
  const viewer = resolveViewerContext(leaderboard, fullPrecisionScoreByPublicId, viewerPublicId);

  return {
    status: "scored",
    dataStatus,
    totalCount: leaderboard.length,
    topEntries: leaderboard.slice(0, LEADERBOARD_TOP_N),
    viewer,
  };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\leaderboard-service.ts"
} catch {
    Write-Host "FAILED: src\lib\leaderboard-service.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\leaderboard-service.ts"
}

try {
    $path = "src\lib\official-result-validation.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { OfficialResultInput } from "@/types/scoring";
import type { Participant } from "@/types/participant";

export type OfficialResultValidation = { valid: true } | { valid: false; error: string };

/**
 * Validates an official result BEFORE it's accepted (research §24).
 * Rejects invalid structures outright — never silently corrects them.
 */
export function validateOfficialResult(
  result: OfficialResultInput,
  activeParticipants: Participant[],
): OfficialResultValidation {
  if (result.top5Extras.length !== 2) {
    return { valid: false, error: "top5Extras must contain exactly 2 participants." };
  }
  // A conventional Top 10 has exactly 5 unordered finalists beyond the
  // Top 5. Some competitions announce a TIED Top 11 instead (Miss Grand
  // International 2026: six equal 5th runners-up). The tied finalists
  // are stored as published — unordered, with no invented positions —
  // so 5 or 6 are both valid. Anything else is still rejected outright.
  if (result.top10Extras.length !== 5 && result.top10Extras.length !== 6) {
    return {
      valid: false,
      error: "top10Extras must contain 5 participants (or 6 when the official result is a tied Top 11).",
    };
  }

  const allIds = [
    result.winner,
    result.firstRunnerUp,
    result.secondRunnerUp,
    ...result.top5Extras,
    ...result.top10Extras,
  ];

  if (new Set(allIds).size !== allIds.length) {
    return { valid: false, error: "Duplicate participant appears more than once in the result." };
  }

  const validIds = new Set(activeParticipants.map((p) => p.id));
  const unknown = allIds.filter((id) => !validIds.has(id));
  if (unknown.length > 0) {
    return { valid: false, error: `Unknown or inactive participant(s): ${unknown.join(", ")}` };
  }

  // Nested-stage consistency is implied by construction (winner/RU1/RU2 are
  // disjoint from top5Extras/top10Extras by the duplicate check above), but
  // stated explicitly per research §24's "podium belongs to Top5, Top5
  // belongs to Top10" requirement — true here by definition of the sets.

  return { valid: true };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\official-result-validation.ts"
} catch {
    Write-Host "FAILED: src\lib\official-result-validation.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\official-result-validation.ts"
}

try {
    $path = "src\lib\scoring.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import {
  scorePrediction,
  getScoreBand,
  computePercentile,
  MIN_PERCENTILE_SAMPLE,
  STAGE_RANKING_V1_CONFIG,
} from "./scoring";
import { validateOfficialResult } from "./official-result-validation";
import type { OfficialResultInput } from "@/types/scoring";
import type { Participant } from "@/types/participant";

// Ranks 1-24 as string IDs, matching the research's abstraction exactly.
const R = (n: number) => `r${n}`;
const OFFICIAL: OfficialResultInput = {
  winner: R(1),
  firstRunnerUp: R(2),
  secondRunnerUp: R(3),
  top5Extras: [R(4), R(5)],
  top10Extras: [R(6), R(7), R(8), R(9), R(10)],
};

function ids(nums: number[]): string[] {
  return nums.map(R);
}

describe("scorePrediction — reproduces FOUCH_SCORING_RESEARCH.md cases exactly", () => {
  it("1. Perfect call -> 100", () => {
    const result = scorePrediction(ids([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), OFFICIAL);
    expect(result.score).toBeCloseTo(100, 5);
    expect(result.displayScore).toBe(100);
    expect(result.band).toBe("ELITE");
  });

  it("2. Winner only, rest poor -> ~44.33", () => {
    const result = scorePrediction(ids([1, 15, 16, 17, 18, 19, 20, 21, 22, 23]), OFFICIAL);
    expect(result.score).toBeCloseTo(44.33, 1);
    expect(result.components.winner.hit).toBe(true);
  });

  it("3. Great field, wrong winner -> ~55.67 (must exceed 'winner only')", () => {
    const winnerOnly = scorePrediction(ids([1, 15, 16, 17, 18, 19, 20, 21, 22, 23]), OFFICIAL);
    const greatField = scorePrediction(ids([11, 2, 3, 4, 5, 6, 7, 8, 9, 10]), OFFICIAL);
    expect(greatField.score).toBeCloseTo(55.67, 1);
    // The exact test that sank the original C1 formula — must never regress.
    expect(greatField.score).toBeGreaterThan(winnerOnly.score);
  });

  it("4. Runner-up predicted #2 -> strong contribution", () => {
    const result = scorePrediction(ids([15, 2, 16, 17, 18, 19, 20, 21, 22, 23]), OFFICIAL);
    expect(result.score).toBeCloseTo(14.33, 1);
    expect(result.components.podium.hits).toBe(1);
  });

  it("5. Runner-up predicted #9 -> ~1.83 (stage-placement semantics: NO podium credit)", () => {
    const result = scorePrediction(ids([15, 16, 17, 18, 19, 20, 21, 22, 2, 23]), OFFICIAL);
    expect(result.score).toBeCloseTo(1.83, 1);
    expect(result.components.podium.hits).toBe(0); // C2-B: not in predicted[0:3]
  });

  it("6. 10/10 correct but podium buried at #8-10 -> ~30.67", () => {
    const result = scorePrediction(ids([4, 5, 6, 7, 8, 9, 10, 1, 2, 3]), OFFICIAL);
    expect(result.score).toBeCloseTo(30.67, 1);
    expect(result.components.podium.hits).toBe(0); // winner/RU1/RU2 are at positions 8-10, not 1-3
    expect(result.components.top10.hits).toBe(10);
  });

  it("7. Near perfect -> ~97", () => {
    const result = scorePrediction(ids([1, 2, 3, 4, 5, 6, 7, 8, 9, 15]), OFFICIAL);
    expect(result.score).toBeCloseTo(97, 1);
    expect(result.band).toBe("ELITE");
  });

  it("13a. Top5-only member at #4 or #5 receives no distance penalty", () => {
    const at4 = scorePrediction(ids([11, 12, 13, 4, 16, 17, 18, 19, 20, 21]), OFFICIAL);
    const at5 = scorePrediction(ids([11, 12, 13, 16, 4, 17, 18, 19, 20, 21]), OFFICIAL);
    // Ranking credit for this one member should be full (1/10 share) either way.
    expect(at4.components.ranking.earned).toBeCloseTo(at5.components.ranking.earned, 5);
  });

  it("13b. Top10-only member anywhere in #6-#10 receives no distance penalty", () => {
    const positions = [6, 7, 8, 9, 10];
    const scores = positions.map((pos) => {
      const base = [11, 12, 13, 14, 16, 17, 18, 19, 20, 21];
      base[pos - 1] = 8;
      return scorePrediction(ids(base), OFFICIAL).components.ranking.earned;
    });
    // All five placements are within the accepted [6,10] band -> identical ranking credit.
    const [first, ...rest] = scores;
    for (const s of rest) expect(s).toBeCloseTo(first!, 5);
  });
});

describe("getScoreBand — exact boundaries (research §13, restated §22)", () => {
  it.each([
    [0, "MISSED_IT"],
    [39, "MISSED_IT"],
    [40, "FAIR"],
    [59, "FAIR"],
    [60, "GOOD"],
    [74, "GOOD"],
    [75, "EXCELLENT"],
    [89, "EXCELLENT"],
    [90, "ELITE"],
    [100, "ELITE"],
  ])("displayScore %i -> %s", (score, expected) => {
    expect(getScoreBand(score)).toBe(expected);
  });
});

describe("computePercentile", () => {
  it("hides percentile below MIN_PERCENTILE_SAMPLE (24 others)", () => {
    const others = Array.from({ length: MIN_PERCENTILE_SAMPLE - 1 }, () => 50);
    const result = computePercentile(80, others);
    expect(result.population).toBe(24);
    expect(result.percentile).toBeNull();
  });

  it("shows percentile at exactly MIN_PERCENTILE_SAMPLE (25 others)", () => {
    const others = Array.from({ length: MIN_PERCENTILE_SAMPLE }, () => 50);
    const result = computePercentile(80, others);
    expect(result.population).toBe(25);
    expect(result.percentile).toBe(100); // beats all 25
  });

  it("ties never count as 'beaten' (two identical top scores both read the same percentile)", () => {
    const others = [...Array.from({ length: 24 }, () => 50), 80]; // 25 others, one tied at 80
    const result = computePercentile(80, others);
    expect(result.percentile).toBe((24 / 25) * 100); // beats the 24 at 50, not the tied 80
  });

  it("0 comparison predictions -> no percentile, no division by zero", () => {
    const result = computePercentile(80, []);
    expect(result.population).toBe(0);
    expect(result.percentile).toBeNull();
  });

  it("excludes self from the population by construction (caller passes only OTHER scores)", () => {
    // computePercentile takes an already-self-excluded array — this test
    // documents that contract rather than re-deriving it.
    const others = Array.from({ length: 30 }, () => 10);
    const result = computePercentile(10, others);
    expect(result.percentile).toBe(0); // beats none — everyone else tied at the same score
  });
});

describe("validateOfficialResult", () => {
  const participants: Participant[] = Array.from({ length: 24 }, (_, i) => ({
    id: R(i + 1),
    eventId: "e",
    displayName: `Country ${i + 1}`,
    countryCode: "XX",
    countryName: `Country ${i + 1}`,
    sortOrder: i,
    isActive: true,
  }));

  it("accepts a well-formed result", () => {
    expect(validateOfficialResult(OFFICIAL, participants).valid).toBe(true);
  });

  it("rejects a result with a duplicated participant", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, secondRunnerUp: OFFICIAL.winner };
    const result = validateOfficialResult(bad, participants);
    expect(result.valid).toBe(false);
  });

  it("rejects a result referencing an unknown/inactive participant", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, winner: "not-a-real-id" };
    const result = validateOfficialResult(bad, participants);
    expect(result.valid).toBe(false);
  });

  it("rejects top5Extras with the wrong size", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, top5Extras: [R(4)] };
    expect(validateOfficialResult(bad, participants).valid).toBe(false);
  });

  it("rejects top10Extras with the wrong size (neither 5 nor 6)", () => {
    const bad: OfficialResultInput = { ...OFFICIAL, top10Extras: [R(6), R(7)] };
    expect(validateOfficialResult(bad, participants).valid).toBe(false);
  });
});

describe("STAGE_RANKING_V1_CONFIG — frozen weights sanity check", () => {
  it("weights sum to 100", () => {
    const w = STAGE_RANKING_V1_CONFIG.weights;
    expect(w.winner + w.podium + w.top5 + w.top10 + w.ranking).toBe(100);
  });

  it("matches the frozen research formula exactly", () => {
    expect(STAGE_RANKING_V1_CONFIG.weights).toEqual({
      winner: 30,
      podium: 25,
      top5: 15,
      top10: 15,
      ranking: 15,
    });
  });
});
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\scoring.test.ts"
} catch {
    Write-Host "FAILED: src\lib\scoring.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\scoring.test.ts"
}

try {
    $path = "src\lib\scoring.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type {
  OfficialResultInput,
  ScoreBand,
  ScoreBreakdown,
  StageRankingConfig,
} from "@/types/scoring";

/**
 * FOUCH SCORE v1.0 — frozen. Source of truth: FOUCH_SCORING_RESEARCH.md
 * §19 (formula) and §22 (C2-B stage-placement semantics, validated
 * against the C2-A membership alternative and rejected it explicitly).
 *
 * DO NOT change these weights, DO NOT switch Podium/Top5 to
 * membership-anywhere semantics, without a new research cycle.
 */
export const STAGE_RANKING_V1_CONFIG: StageRankingConfig = {
  mode: "STAGE_RANKING",
  weights: { winner: 30, podium: 25, top5: 15, top10: 15, ranking: 15 },
  predictionSize: 10,
  stages: { podium: 3, top5: 5, top10: 10 },
};

/**
 * Score bands — frozen (FOUCH_SCORING_RESEARCH.md §13, re-confirmed §22).
 * Centralized here on purpose: nothing else in the app should compare a
 * score to 40/60/75/90 directly.
 */
export function getScoreBand(displayScore: number): ScoreBand {
  if (displayScore >= 90) return "ELITE";
  if (displayScore >= 75) return "EXCELLENT";
  if (displayScore >= 60) return "GOOD";
  if (displayScore >= 40) return "FAIR";
  return "MISSED_IT";
}

/**
 * Derives each official stage member's accepted position range directly
 * from the published result structure — never an invented exact
 * position for an unordered Top5/Top10 extra (research §3, §5).
 */
export function getAcceptedRanges(official: OfficialResultInput): Map<string, [number, number]> {
  const ranges = new Map<string, [number, number]>();
  ranges.set(official.winner, [1, 1]);
  ranges.set(official.firstRunnerUp, [2, 2]);
  ranges.set(official.secondRunnerUp, [3, 3]);
  for (const id of official.top5Extras) ranges.set(id, [4, 5]);
  for (const id of official.top10Extras) ranges.set(id, [6, 10]);
  return ranges;
}

function podiumSet(official: OfficialResultInput): Set<string> {
  return new Set([official.winner, official.firstRunnerUp, official.secondRunnerUp]);
}
function top5Set(official: OfficialResultInput): Set<string> {
  return new Set([...podiumSet(official), ...official.top5Extras]);
}
function top10Set(official: OfficialResultInput): Set<string> {
  return new Set([...top5Set(official), ...official.top10Extras]);
}

/**
 * FOUCH SCORE v1.0 — STAGE_RANKING. Pure function, no I/O. Implements
 * the frozen formula exactly, with C2-B (stage-placement) semantics:
 * Podium/Top5 credit only counts a member placed within the
 * corresponding predicted positions (0:3 / 0:5) — never merely present
 * somewhere in the Top 10. See FOUCH_SCORING_RESEARCH.md §22 for why.
 */
export function scorePrediction(
  predictedRankedIds: string[],
  official: OfficialResultInput,
  config: StageRankingConfig = STAGE_RANKING_V1_CONFIG,
): ScoreBreakdown {
  const { weights, stages } = config;
  const podium = podiumSet(official);
  const top5 = top5Set(official);
  const top10 = top10Set(official);
  const acceptedRanges = getAcceptedRanges(official);

  const winnerHit = predictedRankedIds[0] === official.winner;
  const winnerComponent = { earned: winnerHit ? weights.winner : 0, max: weights.winner, hit: winnerHit };

  function stageComponent(predictedSlice: string[], officialSet: Set<string>, weight: number, total: number) {
    const hits = predictedSlice.filter((id) => officialSet.has(id)).length;
    return { hits, total, earned: (hits / total) * weight, max: weight };
  }

  const podiumComponent = stageComponent(predictedRankedIds.slice(0, stages.podium), podium, weights.podium, 3);
  const top5Component = stageComponent(predictedRankedIds.slice(0, stages.top5), top5, weights.top5, 5);
  const top10Component = stageComponent(
    predictedRankedIds.slice(0, stages.top10),
    top10,
    weights.top10,
    10,
  );

  let rankingRaw = 0;
  for (const memberId of top10) {
    const predictedPosition = predictedRankedIds.indexOf(memberId) + 1; // 0 if absent
    if (predictedPosition === 0) continue;
    const range = acceptedRanges.get(memberId);
    if (!range) continue;
    const [lo, hi] = range;
    const distance = Math.max(lo - predictedPosition, predictedPosition - hi, 0);
    rankingRaw += Math.max(0, 1 - distance / 9);
  }
  const rankingComponent = { earned: (rankingRaw / 10) * weights.ranking, max: weights.ranking };

  const score =
    winnerComponent.earned +
    podiumComponent.earned +
    top5Component.earned +
    top10Component.earned +
    rankingComponent.earned;

  const displayScore = Math.round(score);

  return {
    score,
    displayScore,
    band: getScoreBand(displayScore),
    components: {
      winner: winnerComponent,
      podium: podiumComponent,
      top5: top5Component,
      top10: top10Component,
      ranking: rankingComponent,
    },
  };
}

// ---------------------------------------------------------------------
// Percentile
// ---------------------------------------------------------------------

/** Never show a percentile claim below this many OTHER eligible, scored
 * predictions for the same event — research §14/§22, restated here as
 * the one place this number lives. */
export const MIN_PERCENTILE_SAMPLE = 25;

export interface PercentileResult {
  /** Number of other eligible predictions this was compared against. */
  population: number;
  /** "You beat N% of other predictions" — null below MIN_PERCENTILE_SAMPLE. */
  percentile: number | null;
}

/**
 * Percentile semantics (explicit, per research §15): "the current
 * prediction" is always EXCLUDED from its own comparison population —
 * consistent with the self-exclusion rule already used by You vs The
 * World (Sprint 3). Ties never count as "beaten": percentile is the
 * fraction of the other population with a STRICTLY lower score, so two
 * identical top scores both correctly show the same percentile rather
 * than one inflating past the other.
 */
export function computePercentile(selfScore: number, otherScores: number[]): PercentileResult {
  const population = otherScores.length;
  if (population < MIN_PERCENTILE_SAMPLE) {
    return { population, percentile: null };
  }
  const beaten = otherScores.filter((s) => s < selfScore).length;
  return { population, percentile: (beaten / population) * 100 };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\scoring.ts"
} catch {
    Write-Host "FAILED: src\lib\scoring.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\scoring.ts"
}

try {
    $path = "src\lib\server-error-i18n.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Locale } from "@/lib/locale";

/**
 * i18n v1: server actions and DB helpers keep returning their original
 * English error strings (so server logic, logging and every existing
 * test are untouched). The UI localizes them at display time with this
 * pure lookup. Unknown messages fall back to the original English text
 * — never a raw backend/database error, because the server never
 * returns one.
 */
const EXACT_ES: Record<string, string> = {
  "This event doesn't exist.": "Este evento no existe.",
  "Predictions for this event aren't open yet.": "Las predicciones de este evento aún no están abiertas.",
  "This event has no contestants configured.": "Este evento no tiene participantes configuradas.",
  "Missing device token.": "Falta el identificador del dispositivo. Recarga la página e inténtalo de nuevo.",
  "That doesn't look like a valid email address.": "Ese correo electrónico no parece válido.",
  "Verification isn't available right now — try again shortly.":
    "La verificación no está disponible en este momento — inténtalo de nuevo en unos minutos.",
  "We couldn't send a code — try again in a moment.":
    "No pudimos enviar el código — inténtalo de nuevo en un momento.",
  "We couldn't lock your prediction. Your Top 10 is still saved — try again.":
    "No pudimos guardar tu predicción. Tu Top 10 sigue guardado — inténtalo de nuevo.",
  "That code expired.": "Ese código expiró.",
  "That code didn't match. Check your email and try again.":
    "Ese código no coincide. Revisa tu correo e inténtalo de nuevo.",
  "Your verification expired — please request a new code.":
    "Tu verificación expiró — solicita un código nuevo.",
  "We couldn't find that prediction.": "No encontramos esa predicción.",
  "This isn't your prediction.": "Esta predicción no es tuya.",
  "Predictions for this event are locked.": "Las predicciones de este evento están cerradas.",
  "Predictions for this event haven't opened yet.":
    "Las predicciones de este evento todavía no han abierto.",
  "We couldn't save your changes. Your Top 10 is still what it was — try again.":
    "No pudimos guardar tus cambios. Tu Top 10 sigue igual — inténtalo de nuevo.",
  "Duplicate contestants aren't allowed.": "No se permiten participantes repetidas.",
  "One or more contestants are invalid for this event.":
    "Una o más participantes no son válidas para este evento.",
  "Invalid nickname.": "Apodo no válido.",
  "Invalid country.": "País no válido.",
  "Submissions aren't available yet — the database isn't configured.":
    "Aún no se pueden enviar predicciones.",
  "We couldn't save your prediction. Please try again.":
    "No pudimos guardar tu predicción. Inténtalo de nuevo.",
  "We couldn't generate a unique link. Please try again.":
    "No pudimos generar un enlace único. Inténtalo de nuevo.",
  "Editing isn't available right now — the database isn't configured.":
    "La edición no está disponible en este momento.",
  "We couldn't verify your prediction's current version.":
    "No pudimos verificar la versión actual de tu predicción.",
  "Your prediction changed elsewhere since you opened this — please reload and try again.":
    "Tu predicción cambió en otro lugar desde que abriste esta página — recarga e inténtalo de nuevo.",
  "We couldn't save your changes. Please try again.":
    "No pudimos guardar tus cambios. Inténtalo de nuevo.",
};

const PATTERNS_ES: Array<[RegExp, (match: RegExpMatchArray) => string]> = [
  [/^Exactly (\d+) contestants are required\.$/, (m) => `Se requieren exactamente ${m[1]} participantes.`],
  [/^Nickname must be (\d+) characters or fewer\.$/, (m) => `El apodo debe tener ${m[1]} caracteres o menos.`],
];

export function translateServerError(message: string | null, locale: Locale): string | null {
  if (!message || locale === "en") return message;

  const exact = EXACT_ES[message];
  if (exact) return exact;

  for (const [pattern, build] of PATTERNS_ES) {
    const match = message.match(pattern);
    if (match) return build(match);
  }
  return message;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\server-error-i18n.ts"
} catch {
    Write-Host "FAILED: src\lib\server-error-i18n.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\server-error-i18n.ts"
}

try {
    $path = "src\types\scoring.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * FOUCH Score Engine types.
 *
 * Only STAGE_RANKING is implemented in Sprint 4. FULL_RANKING and
 * CATEGORY_PICK are declared so the architecture doesn't need a
 * rewrite when those event families arrive (see
 * FOUCH_SCORING_RESEARCH.md §15) — nothing about their scoring logic
 * is implemented here.
 */
export type ScoringMode = "STAGE_RANKING" | "FULL_RANKING" | "CATEGORY_PICK";

export interface StageRankingWeights {
  winner: number;
  podium: number;
  top5: number;
  top10: number;
  ranking: number;
}

export interface StageRankingConfig {
  mode: "STAGE_RANKING";
  weights: StageRankingWeights;
  predictionSize: number;
  stages: { podium: number; top5: number; top10: number };
}

/**
 * The official result, expressed only as what was actually published —
 * exact positions for the podium, unordered sets for the Top5/Top10
 * extras. Never a full 1-10 ordering (see FOUCH_SCORING_RESEARCH.md §3).
 */
export interface OfficialResultInput {
  winner: string;
  firstRunnerUp: string;
  secondRunnerUp: string;
  /** Exactly 2 participant IDs, unordered relative to each other. */
  top5Extras: string[];
  /** 5 participant IDs (6 when the competition announced a tied Top 11),
   * unordered relative to each other — never an invented 6–11 ordering. */
  top10Extras: string[];
}

export type ScoreBand = "MISSED_IT" | "FAIR" | "GOOD" | "EXCELLENT" | "ELITE";

export interface ScoreComponent {
  earned: number;
  max: number;
  hits?: number;
  total?: number;
  hit?: boolean;
}

export interface ScoreBreakdown {
  /** Full precision — never rounded internally. */
  score: number;
  /** Rounded integer — the only number the UI should ever display. */
  displayScore: number;
  band: ScoreBand;
  components: {
    winner: ScoreComponent;
    podium: ScoreComponent;
    top5: ScoreComponent;
    top10: ScoreComponent;
    ranking: ScoreComponent;
  };
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\types\scoring.ts"
} catch {
    Write-Host "FAILED: src\types\scoring.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\types\scoring.ts"
}

try {
    $path = "src\components\OfficialResult.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { CountryFlag } from "@/components/CountryFlag";
import { resolveParticipantsByIds } from "@/lib/participants";
import { buildOfficialFinish, allOfficialIds } from "@/lib/official-result-display";
import { STAGE_RANKING_V1_CONFIG } from "@/lib/scoring";
import { fmt } from "@/lib/i18n";
import type { Dictionary } from "@/content/types";
import type { Locale } from "@/lib/locale";
import type { Participant } from "@/types/participant";
import type { OfficialResultInput } from "@/types/scoring";

/**
 * Post-event: the official finish, shown with the same finalist
 * structure the score uses (exact podium, unordered Top 5 extras,
 * unordered remaining tied finalists) — never an invented 1-11 order.
 * Presentation only: reads the stored result, changes nothing.
 */
export async function OfficialResult({
  eventSlug,
  official,
  dictionary,
  locale,
}: {
  eventSlug: string;
  official: OfficialResultInput;
  dictionary: Dictionary;
  locale: Locale;
}) {
  const finish = buildOfficialFinish(official);
  const byId = await resolveParticipantsByIds(eventSlug, allOfficialIds(finish), locale);
  const t = dictionary.results;
  const weights = STAGE_RANKING_V1_CONFIG.weights;

  const row = (id: string, label?: string) => {
    const participant: Participant | undefined = byId.get(id);
    if (!participant) return null;
    return (
      <li key={id} className="flex items-center gap-3 rounded border border-border bg-surface px-4 py-2.5">
        {label ? (
          <span className="w-28 shrink-0 text-xs uppercase tracking-[0.12em] text-accent-strong">{label}</span>
        ) : null}
        <CountryFlag countryCode={participant.countryCode} className="text-lg" />
        <span className="truncate text-sm text-text-primary">
          {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
        </span>
      </li>
    );
  };

  return (
    <section className="mt-12 border-t border-border pt-10">
      <p className="font-display text-2xl uppercase tracking-tight text-text-primary">{t.heading}</p>

      <ol className="mt-5 space-y-1.5">
        {row(finish.winner, t.winner)}
        {row(finish.firstRunnerUp, t.firstRunnerUp)}
        {row(finish.secondRunnerUp, t.secondRunnerUp)}
      </ol>

      <p className="mt-6 text-xs uppercase tracking-[0.15em] text-text-muted">{t.top5Group}</p>
      <ol className="mt-2 space-y-1.5">{finish.top5Extras.map((id) => row(id))}</ol>

      <p className="mt-6 text-xs uppercase tracking-[0.15em] text-text-muted">
        {fmt(t.remainingGroup, { n: finish.topSize })}
      </p>
      <ol className="mt-2 space-y-1.5">{finish.remaining.map((id) => row(id))}</ol>

      {finish.topSize !== 10 ? (
        <p className="mt-4 text-xs text-text-muted">{fmt(t.tiedNote, { n: finish.topSize })}</p>
      ) : null}

      <div className="mt-8 rounded border border-border bg-surface p-4">
        <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-secondary">{t.howScoreWorks}</p>
        <p className="mt-2 text-sm text-text-secondary">
          {fmt(t.scoreExplain, {
            winner: weights.winner,
            podium: weights.podium,
            top5: weights.top5,
            top10: weights.top10,
            ranking: weights.ranking,
          })}
        </p>
      </div>
    </section>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\OfficialResult.tsx"
} catch {
    Write-Host "FAILED: src\components\OfficialResult.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\OfficialResult.tsx"
}

try {
    $path = "src\components\PredictionUnavailable.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import { ArrowLeft } from "lucide-react";
import { LanguageSwitcher } from "@/components/LanguageSwitcher";
import { fmt } from "@/lib/i18n";
import type { Dictionary } from "@/content/types";

/**
 * Replaces the builder/review when an event can't take predictions:
 *  - "closed": the prediction window has ended -> link to results;
 *  - "coming_soon": the official roster isn't loaded yet (placeholder
 *    data must never be predicted against).
 */
export function PredictionUnavailable({
  variant,
  eventName,
  eventSlug,
  dictionary,
}: {
  variant: "closed" | "coming_soon";
  eventName: string;
  eventSlug: string;
  dictionary: Dictionary;
}) {
  const t = dictionary.unavailable;

  return (
    <main className="mx-auto max-w-content px-6 py-10">
      <div className="flex items-center justify-between">
        <Link href="/" className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary">
          <ArrowLeft className="h-4 w-4" aria-hidden />
          {t.backHome}
        </Link>
        <LanguageSwitcher eventSlug={eventSlug} />
      </div>

      <p className="mt-10 text-xs font-medium uppercase tracking-[0.25em] text-text-muted">
        {variant === "coming_soon" ? t.comingSoonLabel : eventName}
      </p>
      <h1 className="mt-3 font-display text-3xl uppercase leading-tight tracking-tight text-text-primary sm:text-5xl">
        {variant === "coming_soon" ? fmt(t.comingSoonTitle, { event: eventName }) : t.closedTitle}
      </h1>
      <p className="mt-4 max-w-md text-text-secondary">{variant === "coming_soon" ? t.comingSoonBody : t.closedBody}</p>

      {variant === "closed" ? (
        <Link
          href={`/events/${eventSlug}/leaderboard`}
          className="mt-8 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
        >
          {t.viewResults}
        </Link>
      ) : null}
    </main>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\PredictionUnavailable.tsx"
} catch {
    Write-Host "FAILED: src\components\PredictionUnavailable.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\PredictionUnavailable.tsx"
}

try {
    $path = "src\components\ResultsLink.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { fmt } from "@/lib/i18n";
import { getEventShortLabel } from "@/lib/event-name-split";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";

/**
 * Home: a discreet but visible link from a completed event to its
 * final leaderboard (and, through it, every historical prediction).
 */
export function ResultsLink({ event, dictionary }: { event: FouchEvent; dictionary: Dictionary }) {
  return (
    <section className="mx-auto max-w-content px-6 pb-2 pt-2">
      <Link
        href={`/events/${event.slug}/leaderboard`}
        className="group inline-flex items-center gap-2 rounded border border-border-strong px-4 py-2.5 text-sm text-text-secondary transition-colors hover:border-accent hover:text-text-primary"
      >
        <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-accent" />
        {fmt(dictionary.homeResults.link, { event: getEventShortLabel(event.name) })}
        <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
      </Link>
    </section>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\ResultsLink.tsx"
} catch {
    Write-Host "FAILED: src\components\ResultsLink.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\ResultsLink.tsx"
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\post-event-surfaces.test.ts"
} catch {
    Write-Host "FAILED: src\components\post-event-surfaces.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\post-event-surfaces.test.ts"
}

try {
    $path = "src\lib\event-readiness.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { isDemoPredictionBlocked } from "./event-readiness";

describe("isDemoPredictionBlocked — never predict against placeholder data", () => {
  it("blocks a demo roster by default", () => {
    expect(isDemoPredictionBlocked("demo", false)).toBe(true);
  });
  it("never blocks a verified roster", () => {
    expect(isDemoPredictionBlocked("verified", false)).toBe(false);
    expect(isDemoPredictionBlocked("verified", true)).toBe(false);
  });
  it("local development can explicitly opt in", () => {
    expect(isDemoPredictionBlocked("demo", true)).toBe(false);
  });
  it("the default (no argument) reads ALLOW_DEMO_PREDICTIONS and is blocked when unset", () => {
    const original = process.env.ALLOW_DEMO_PREDICTIONS;
    delete process.env.ALLOW_DEMO_PREDICTIONS;
    expect(isDemoPredictionBlocked("demo")).toBe(true);
    process.env.ALLOW_DEMO_PREDICTIONS = "true";
    expect(isDemoPredictionBlocked("demo")).toBe(false);
    if (original === undefined) delete process.env.ALLOW_DEMO_PREDICTIONS;
    else process.env.ALLOW_DEMO_PREDICTIONS = original;
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-readiness.test.ts"
} catch {
    Write-Host "FAILED: src\lib\event-readiness.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-readiness.test.ts"
}

try {
    $path = "src\lib\event-readiness.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Predictions must never be taken against placeholder (demo) data.
 * A "demo" roster (the hardcoded Miss Universe development list) is
 * not a real lineup: until the official roster is loaded, the event
 * shows "Coming soon" and the server refuses to create predictions
 * for it. Local development can opt back in with
 * ALLOW_DEMO_PREDICTIONS=true (never set it in production).
 */
export function isDemoPredictionBlocked(
  participantDataStatus: "demo" | "verified",
  allowDemo: boolean = process.env.ALLOW_DEMO_PREDICTIONS === "true",
): boolean {
  return participantDataStatus === "demo" && !allowDemo;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-readiness.ts"
} catch {
    Write-Host "FAILED: src\lib\event-readiness.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-readiness.ts"
}

try {
    $path = "src\lib\leaderboard-exclusions.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { applyLeaderboardExclusions, LEADERBOARD_EXCLUDED_PUBLIC_IDS } from "./leaderboard-exclusions";
import { buildLeaderboard } from "./leaderboard";

const rows = [
  { publicId: "aaa", nickname: "A", countryCode: null, displayScore: 90 },
  { publicId: "bbb", nickname: "B", countryCode: null, displayScore: 80 },
  { publicId: "ccc", nickname: "C", countryCode: null, displayScore: 70 },
];

describe("leaderboard exclusions — explicit IDs only, nothing edited or deleted", () => {
  it("ships EMPTY: nothing is excluded until the founder confirms specific test IDs", () => {
    expect(Object.values(LEADERBOARD_EXCLUDED_PUBLIC_IDS).flat()).toEqual([]);
    expect(applyLeaderboardExclusions(rows, "miss-grand-international-2026")).toEqual(rows);
  });

  it("removes only the listed public_ids for THAT event", () => {
    const excluded = { "event-a": ["bbb"] };
    expect(applyLeaderboardExclusions(rows, "event-a", excluded).map((r) => r.publicId)).toEqual(["aaa", "ccc"]);
    expect(applyLeaderboardExclusions(rows, "event-b", excluded)).toEqual(rows);
  });

  it("ranks the remaining entries correctly (no gap where an excluded test was)", () => {
    const board = buildLeaderboard(applyLeaderboardExclusions(rows, "e", { e: ["aaa"] }));
    expect(board.map((r) => [r.publicId, r.rank])).toEqual([
      ["bbb", 1],
      ["ccc", 2],
    ]);
  });

  it("does not mutate its input", () => {
    const before = JSON.stringify(rows);
    applyLeaderboardExclusions(rows, "e", { e: ["aaa"] });
    expect(JSON.stringify(rows)).toBe(before);
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\leaderboard-exclusions.test.ts"
} catch {
    Write-Host "FAILED: src\lib\leaderboard-exclusions.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\leaderboard-exclusions.test.ts"
}

try {
    $path = "src\lib\leaderboard-exclusions.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Explicit, per-event list of public_ids kept OFF the public
 * leaderboard (internal tests). Nothing is deleted or edited: an
 * excluded prediction keeps its public page, its score, its history
 * and its share cards — it simply isn't listed or ranked on the
 * public board. Empty until the founder confirms specific test IDs.
 */
export const LEADERBOARD_EXCLUDED_PUBLIC_IDS: Record<string, readonly string[]> = {};

export function applyLeaderboardExclusions<T extends { publicId: string }>(
  entries: T[],
  eventSlug: string,
  excluded: Record<string, readonly string[]> = LEADERBOARD_EXCLUDED_PUBLIC_IDS,
): T[] {
  const ids = excluded[eventSlug];
  if (!ids || ids.length === 0) return entries;
  const blocked = new Set(ids);
  return entries.filter((entry) => !blocked.has(entry.publicId));
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\leaderboard-exclusions.ts"
} catch {
    Write-Host "FAILED: src\lib\leaderboard-exclusions.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\leaderboard-exclusions.ts"
}

try {
    $path = "src\lib\next-event.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\next-event.ts"
} catch {
    Write-Host "FAILED: src\lib\next-event.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\next-event.ts"
}

try {
    $path = "src\lib\official-result-display.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { classifyPicks, buildOfficialFinish, allOfficialIds } from "./official-result-display";
import { scorePrediction } from "./scoring";
import type { OfficialResultInput } from "@/types/scoring";

const MGI: OfficialResultInput = {
  winner: "TZ",
  firstRunnerUp: "EC",
  secondRunnerUp: "NL",
  top5Extras: ["GT", "VN"],
  top10Extras: ["CI", "CU", "MX", "PR", "TH", "VE"], // six equal 5th runners-up
};

describe("buildOfficialFinish — the tied Top 11 is shown as announced", () => {
  it("reports an 11-member finish with 3 + 2 + 6 groups and no invented order", () => {
    const finish = buildOfficialFinish(MGI);
    expect(finish.topSize).toBe(11);
    expect(finish.top5Extras).toEqual(["GT", "VN"]);
    expect(finish.remaining).toHaveLength(6);
    expect(allOfficialIds(finish)).toHaveLength(11);
  });

  it("a conventional result is a Top 10", () => {
    expect(buildOfficialFinish({ ...MGI, top10Extras: MGI.top10Extras.slice(0, 5) }).topSize).toBe(10);
  });
});

describe("classifyPicks — marks use the SAME ranges the score uses", () => {
  it("exact when inside the official range; in_top when a finalist elsewhere; out when not a finalist", () => {
    const picks = ["TZ", "NL", "EC", "VE", "GT", "CI", "XX", "CU", "VN", "ZZ"];
    const marks = classifyPicks(picks, MGI);
    expect(marks["TZ"]).toBe("exact"); // winner at #1
    expect(marks["NL"]).toBe("in_top"); // 2nd RU predicted #2? -> official #3
    expect(marks["EC"]).toBe("in_top"); // 1st RU predicted #3 -> official #2
    expect(marks["VE"]).toBe("in_top"); // tied finalist predicted #4 (range 6-10)
    expect(marks["GT"]).toBe("exact"); // top-5 member at #5 (range 4-5)
    expect(marks["CI"]).toBe("exact"); // tied finalist at #6
    expect(marks["CU"]).toBe("exact"); // tied finalist at #8
    expect(marks["VN"]).toBe("in_top"); // top-5 member predicted #9
    expect(marks["XX"]).toBe("out");
    expect(marks["ZZ"]).toBe("out");
  });

  it("every tied finalist gets the identical mark at the same slot (no tied finalist is favored)", () => {
    for (const slot of [4, 5, 6, 8, 10]) {
      const marks = MGI.top10Extras.map((id) => {
        const picks = ["TZ", "EC", "NL", "GT", "VN", "O1", "O2", "O3", "O4", "O5"];
        picks[slot - 1] = id;
        return classifyPicks(picks, MGI)[id];
      });
      expect(new Set(marks).size).toBe(1);
    }
  });

  it("consistency with the scorer: a prediction where every pick is 'exact' earns the full ranking component", () => {
    const perfect = ["TZ", "EC", "NL", "GT", "VN", "CI", "CU", "MX", "PR", "TH"];
    const marks = classifyPicks(perfect, MGI);
    expect(Object.values(marks).every((m) => m === "exact")).toBe(true);
    const { components } = scorePrediction(perfect, MGI);
    expect(components.ranking.earned).toBeCloseTo(components.ranking.max, 10);
  });

  it("never mutates or re-scores: same input, same output", () => {
    const picks = ["TZ", "EC", "NL", "GT", "VN", "CI", "CU", "MX", "PR", "TH"];
    expect(classifyPicks(picks, MGI)).toEqual(classifyPicks([...picks], { ...MGI }));
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\official-result-display.test.ts"
} catch {
    Write-Host "FAILED: src\lib\official-result-display.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\official-result-display.test.ts"
}

try {
    $path = "src\lib\official-result-display.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { getAcceptedRanges } from "@/lib/scoring";
import type { OfficialResultInput } from "@/types/scoring";

/**
 * Post-event presentation helpers. They reuse scoring.ts's own
 * accepted-position ranges (getAcceptedRanges) so what the UI marks as
 * "right place" is exactly what the score treats as zero distance —
 * there is no second definition of the official finish.
 */
export type PickMark = "exact" | "in_top" | "out";

/**
 * For each picked participant:
 *  - "exact":  placed inside the position range the official result
 *              gives that finalist (winner #1, 1st RU #2, ... tied
 *              finalists anywhere in the tied block);
 *  - "in_top": a finalist, but in a different place than the official one;
 *  - "out":    not a finalist.
 */
export function classifyPicks(
  predictedRankedIds: string[],
  official: OfficialResultInput,
): Record<string, PickMark> {
  const ranges = getAcceptedRanges(official);
  const marks: Record<string, PickMark> = {};
  predictedRankedIds.forEach((id, index) => {
    const range = ranges.get(id);
    if (!range) {
      marks[id] = "out";
      return;
    }
    const position = index + 1;
    marks[id] = position >= range[0] && position <= range[1] ? "exact" : "in_top";
  });
  return marks;
}

export interface OfficialFinish {
  winner: string;
  firstRunnerUp: string;
  secondRunnerUp: string;
  /** Positions 4-5, unordered (as stored — never an invented 4th/5th split). */
  top5Extras: string[];
  /** The remaining tied finalists, unordered. */
  remaining: string[];
  /** 10 for a conventional Top 10, 11 for a tied Top 11. */
  topSize: number;
}

export function buildOfficialFinish(official: OfficialResultInput): OfficialFinish {
  return {
    winner: official.winner,
    firstRunnerUp: official.firstRunnerUp,
    secondRunnerUp: official.secondRunnerUp,
    top5Extras: official.top5Extras,
    remaining: official.top10Extras,
    topSize: 5 + official.top10Extras.length,
  };
}

export function allOfficialIds(finish: OfficialFinish): string[] {
  return [finish.winner, finish.firstRunnerUp, finish.secondRunnerUp, ...finish.top5Extras, ...finish.remaining];
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\official-result-display.ts"
} catch {
    Write-Host "FAILED: src\lib\official-result-display.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\official-result-display.ts"
}

try {
    $path = "src\lib\scoring-top11.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { scorePrediction } from "./scoring";
import { validateOfficialResult } from "./official-result-validation";
import type { OfficialResultInput } from "@/types/scoring";
import type { Participant } from "@/types/participant";

/**
 * Miss Grand International 2026 announced a TIED Top 11: winner,
 * 1st/2nd runner-up, two more in the Top 5 (3rd/4th runner-up), and
 * SIX equal 5th runners-up. These tests prove the frozen FOUCH Score
 * v1.0 formula handles that structure with no arbitrary advantage or
 * penalty — WITHOUT changing scoring.ts's behavior.
 */
const W = "W";
const R1 = "R1";
const R2 = "R2";
const E = ["E4", "E5"];
const T = ["T1", "T2", "T3", "T4", "T5", "T6"]; // six equal 5th runners-up
const OTHERS = Array.from({ length: 12 }, (_, i) => `O${i + 1}`);

const OFFICIAL_11: OfficialResultInput = {
  winner: W,
  firstRunnerUp: R1,
  secondRunnerUp: R2,
  top5Extras: E,
  top10Extras: T,
};

const permutations = <X,>(items: X[]): X[][] =>
  items.length <= 1
    ? [items]
    : items.flatMap((item, i) =>
        permutations([...items.slice(0, i), ...items.slice(i + 1)]).map((rest) => [item, ...rest]),
      );

describe("Top 11 (six tied 5th runners-up) — validator", () => {
  const participants: Participant[] = [W, R1, R2, ...E, ...T, ...OTHERS].map((id, i) => ({
    id,
    eventId: "e",
    displayName: id,
    countryCode: "XX",
    countryName: id,
    sortOrder: i,
    isActive: true,
  }));

  it("accepts the real MGI 2026 structure (2 + 6 extras)", () => {
    expect(validateOfficialResult(OFFICIAL_11, participants).valid).toBe(true);
  });

  it("still accepts a conventional Top 10 (2 + 5 extras)", () => {
    expect(validateOfficialResult({ ...OFFICIAL_11, top10Extras: T.slice(0, 5) }, participants).valid).toBe(true);
  });

  it("rejects 4 or 7 top10Extras, and a duplicated tied finalist", () => {
    expect(validateOfficialResult({ ...OFFICIAL_11, top10Extras: T.slice(0, 4) }, participants).valid).toBe(false);
    expect(validateOfficialResult({ ...OFFICIAL_11, top10Extras: [...T, "O1"] }, participants).valid).toBe(false);
    expect(validateOfficialResult({ ...OFFICIAL_11, top10Extras: [...T.slice(0, 5), "T1"] }, participants).valid).toBe(false);
  });

  it("rejects a tied finalist that is not an active participant", () => {
    expect(validateOfficialResult({ ...OFFICIAL_11, top10Extras: [...T.slice(0, 5), "ghost"] }, participants).valid).toBe(false);
  });
});

describe("Top 11 — the frozen formula treats the tie fairly", () => {
  it("a perfect call scores exactly 100 (the maximum is still reachable)", () => {
    const perfect = [W, R1, R2, ...E, ...T.slice(0, 5)];
    expect(scorePrediction(perfect, OFFICIAL_11).score).toBeCloseTo(100, 10);
  });

  it("a perfect call scores 100 whichever ONE of the six tied finalists is left out — no tied finalist is 'required'", () => {
    for (let omit = 0; omit < 6; omit++) {
      const fiveOfSix = T.filter((_, i) => i !== omit);
      const prediction = [W, R1, R2, ...E, ...fiveOfSix];
      expect(scorePrediction(prediction, OFFICIAL_11).score, `omit ${T[omit]}`).toBeCloseTo(100, 10);
    }
  });

  it("symmetry: relabeling WHICH tied finalists a prediction picked (all 720 permutations) never changes its score", () => {
    // A deliberately messy prediction: tied finalists at 1, 4, 6, 8 and 10, a top-5 member at 3.
    const template = [T[0]!, W, E[0]!, T[1]!, O(1), T[2]!, R1, T[3]!, O(2), T[4]!];
    const baseline = scorePrediction(template, OFFICIAL_11).score;
    for (const perm of permutations(T)) {
      const relabeled = template.map((id) => {
        const idx = T.indexOf(id);
        return idx === -1 ? id : perm[idx]!;
      });
      expect(scorePrediction(relabeled, OFFICIAL_11).score).toBeCloseTo(baseline, 10);
    }
  });

  it("a tied finalist placed too high (#4) earns the SAME partial credit whichever of the six it is — no arbitrary position is implied", () => {
    const scores = T.map((id) =>
      scorePrediction([W, R1, R2, id, E[0]!, E[1]!, O(1), O(2), O(3), O(4)], OFFICIAL_11).score,
    );
    for (const s of scores) expect(s).toBeCloseTo(scores[0]!, 10);
  });

  it("tied finalists anywhere in #6-#10 receive no distance penalty (accepted range is the whole tied block)", () => {
    for (let slot = 6; slot <= 10; slot++) {
      const prediction = [W, R1, R2, ...E, O(1), O(2), O(3), O(4), O(5)];
      prediction[slot - 1] = T[0]!;
      const expectedRankingRaw = 5 + 1; // 5 exact + the tied one at full credit
      const ranking = scorePrediction(prediction, OFFICIAL_11).components.ranking.earned;
      expect(ranking).toBeCloseTo((expectedRankingRaw / 10) * 15, 10);
    }
  });

  it("scores always stay within 0-100 (500 deterministic pseudo-random predictions)", () => {
    const pool = [W, R1, R2, ...E, ...T, ...OTHERS];
    let seed = 20261010;
    const rand = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;
    for (let n = 0; n < 500; n++) {
      const shuffled = [...pool].sort(() => rand() - 0.5).slice(0, 10);
      const { score } = scorePrediction(shuffled, OFFICIAL_11);
      expect(score).toBeGreaterThanOrEqual(0);
      expect(score).toBeLessThanOrEqual(100 + 1e-9);
    }
  });

  it("adding a sixth tied finalist to the official result NEVER lowers any prediction's score (monotonic — no hidden penalty)", () => {
    const official10: OfficialResultInput = { ...OFFICIAL_11, top10Extras: T.slice(0, 5) };
    const pool = [W, R1, R2, ...E, ...T, ...OTHERS];
    let seed = 7;
    const rand = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;
    for (let n = 0; n < 500; n++) {
      const prediction = [...pool].sort(() => rand() - 0.5).slice(0, 10);
      expect(scorePrediction(prediction, OFFICIAL_11).score).toBeGreaterThanOrEqual(
        scorePrediction(prediction, official10).score - 1e-9,
      );
    }
  });

  it("podium, winner and Top-5 components are completely unaffected by the extra tied finalist", () => {
    const official10: OfficialResultInput = { ...OFFICIAL_11, top10Extras: T.slice(0, 5) };
    const prediction = [R1, W, R2, E[1]!, E[0]!, T[0]!, T[5]!, O(1), O(2), O(3)];
    const a = scorePrediction(prediction, OFFICIAL_11).components;
    const b = scorePrediction(prediction, official10).components;
    expect(a.winner).toEqual(b.winner);
    expect(a.podium).toEqual(b.podium);
    expect(a.top5).toEqual(b.top5);
  });
});

function O(n: number): string {
  return `O${n}`;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\scoring-top11.test.ts"
} catch {
    Write-Host "FAILED: src\lib\scoring-top11.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\scoring-top11.test.ts"
}

try {
    $path = "supabase\imports\miss-grand-international-2026-results.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- FOUCH — Miss Grand International 2026: load the OFFICIAL result and close the event.
--
-- Run ONCE in the Supabase SQL Editor (production), after founder approval.
-- Plain data load, not a schema migration. It never touches predictions,
-- prediction versions, participants, scoring, or prediction_lock_at.
--
-- Official final (Grand Final, 10 Oct 2026, MGI Hall, Bangkok):
--   Winner ............ Tanzania        (TZ)
--   1st runner-up ..... Ecuador         (EC)
--   2nd runner-up ..... Netherlands     (NL)
--   3rd runner-up ..... Guatemala       (GT)  } stored as the unordered
--   4th runner-up ..... Vietnam         (VN)  } "Top 5 extras" (positions 4-5)
--   SIX equal 5th runners-up (a TIED Top 11 — no invented positions 6-11):
--     Côte d'Ivoire (CI), Cuba (CU), Mexico (MX), Puerto Rico (PR),
--     Thailand (TH), Venezuela (VE)
--
-- Participants are matched by country_code (never by name) against the
-- ACTIVE roster. The script ABORTS — inserting nothing — if any finalist
-- doesn't map to exactly one ACTIVE participant, or if a verified result
-- already exists (it never overwrites).

begin;

do $$
declare
  finalists text[] := array['TZ','EC','NL','GT','VN','CI','CU','MX','PR','TH','VE'];
  mapped int;
begin
  select count(*) into mapped
  from event_participants
  where event_slug = 'miss-grand-international-2026'
    and status = 'ACTIVE'
    and country_code = any (finalists);

  if mapped <> 11 then
    raise exception 'Expected 11 ACTIVE finalists to map, found %. Nothing was written.', mapped;
  end if;

  if (select count(distinct country_code) from event_participants
      where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE'
        and country_code = any (finalists)) <> 11 then
    raise exception 'A finalist country maps to more than one ACTIVE participant. Nothing was written.';
  end if;

  if exists (
    select 1 from event_results
    where event_slug = 'miss-grand-international-2026' and data_status = 'verified'
  ) then
    raise exception 'A verified result already exists for this event — refusing to overwrite.';
  end if;

  if not exists (select 1 from events where slug = 'miss-grand-international-2026') then
    raise exception 'Event row miss-grand-international-2026 not found.';
  end if;
end $$;

insert into event_results (
  event_slug,
  data_status,
  winner_participant_id,
  first_runner_up_participant_id,
  second_runner_up_participant_id,
  top5_extra_participant_ids,
  top10_extra_participant_ids,
  source_note
)
select
  'miss-grand-international-2026',
  'verified',
  (select id::text from event_participants where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE' and country_code = 'TZ'),
  (select id::text from event_participants where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE' and country_code = 'EC'),
  (select id::text from event_participants where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE' and country_code = 'NL'),
  array(select id::text from event_participants where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE' and country_code in ('GT','VN') order by country_code),
  array(select id::text from event_participants where event_slug = 'miss-grand-international-2026' and status = 'ACTIVE' and country_code in ('CI','CU','MX','PR','TH','VE') order by country_code),
  'Official Grand Final result, 10 Oct 2026 (Bangkok): winner Tanzania; runners-up Ecuador, Netherlands, Guatemala, Vietnam; six equal 5th runners-up (tied Top 11): Cote d''Ivoire, Cuba, Mexico, Puerto Rico, Thailand, Venezuela. Tied finalists stored unordered.';

-- Close the event. Leaves is_featured for Miss Universe untouched; MGI simply
-- stops being featured/upcoming. prediction_lock_at is NOT modified.
update events
set status = 'completed',
    is_featured = false
where slug = 'miss-grand-international-2026';

-- Verification (read this output before trusting the load):
select
  r.event_slug,
  r.data_status,
  array_length(r.top5_extra_participant_ids, 1)  as top5_extras,
  array_length(r.top10_extra_participant_ids, 1) as tied_top11_extras,
  e.status,
  e.is_featured,
  e.prediction_lock_at
from event_results r
join events e on e.slug = r.event_slug
where r.event_slug = 'miss-grand-international-2026';

commit;

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\imports\miss-grand-international-2026-results.sql"
} catch {
    Write-Host "FAILED: supabase\imports\miss-grand-international-2026-results.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\imports\miss-grand-international-2026-results.sql"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 35 files written successfully." -ForegroundColor Green
}