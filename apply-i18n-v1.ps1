# FOUCH Internationalization v1 — English + Spanish (one product, localized presentation).
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-i18n-v1.ps1
$failures = @()

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
    $path = "src\app\layout.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Metadata } from "next";
import { siteUrl } from "@/lib/site";
import { getI18n } from "@/lib/i18n-server";
import { localizePath } from "@/lib/locale";
import { I18nProvider } from "@/components/I18nProvider";
import "./globals.css";

/**
 * i18n v1: metadata is generated per request locale. Canonical strategy
 * is unchanged from before i18n — every page canonicalizes to the
 * site root on https://joinfouch.com (siteUrl) — now one canonical per
 * locale ("/" for English, "/es" for Spanish), with hreflang tying the
 * two together plus x-default (English). The canonical DOMAIN is
 * unchanged and never falls back to the legacy Vercel domain.
 */
export async function generateMetadata(): Promise<Metadata> {
  const { locale, dict } = await getI18n();
  const canonical = localizePath("/", locale);

  return {
    metadataBase: new URL(siteUrl),
    alternates: {
      canonical,
      languages: {
        en: localizePath("/", "en"),
        es: localizePath("/", "es"),
        "x-default": localizePath("/", "en"),
      },
    },
    title: {
      default: dict.meta.title,
      template: "%s · Fouch",
    },
    description: dict.meta.description,
    openGraph: {
      title: dict.meta.title,
      description: dict.meta.description,
      url: `${siteUrl}${canonical === "/" ? "" : canonical}`,
      siteName: "Fouch",
      locale: locale === "es" ? "es_LA" : "en_US",
      type: "website",
    },
    twitter: {
      card: "summary_large_image",
      title: dict.meta.title,
      description: dict.meta.description,
    },
  };
}

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  const { locale, dict } = await getI18n();

  return (
    <html lang={locale}>
      <body>
        <I18nProvider locale={locale} dict={dict}>
          {children}
        </I18nProvider>
      </body>
    </html>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\layout.tsx"
} catch {
    Write-Host "FAILED: src\app\layout.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\layout.tsx"
}

try {
    $path = "src\app\p\[publicId]\card\post\route.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { PredictionCardMarkup } from "@/components/prediction/PredictionCardMarkup";
import { siteUrl } from "@/lib/site";
import { LOCALE_HEADER, localeFromHeaderValue } from "@/lib/locale";

export const runtime = "edge";

const WIDTH = 1080;
const HEIGHT = 1350;

export async function GET(
  request: Request,
  { params }: { params: Promise<{ publicId: string }> },
) {
  const { publicId } = await params;
  const locale = localeFromHeaderValue(request.headers.get(LOCALE_HEADER));
  const record = await getPredictionWithParticipants(publicId, locale);

  if (!record) {
    return new Response("Prediction not found", { status: 404 });
  }

  return new ImageResponse(
    (
      <PredictionCardMarkup
        width={WIDTH}
        height={HEIGHT}
        siteDomain={siteUrl.replace(/^https?:\/\//, "")}
        data={{
          eventName: record.event.name,
          nickname: record.prediction.nickname,
          countryCode: record.prediction.countryCode,
          isDemo: record.prediction.dataStatus === "demo",
          locale,
          rankedParticipants: record.rankedParticipants,
        }}
      />
    ),
    { width: WIDTH, height: HEIGHT },
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\card\post\route.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\card\post\route.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\card\post\route.tsx"
}

try {
    $path = "src\app\p\[publicId]\card\story\route.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { PredictionCardMarkup } from "@/components/prediction/PredictionCardMarkup";
import { siteUrl } from "@/lib/site";
import { LOCALE_HEADER, localeFromHeaderValue } from "@/lib/locale";

export const runtime = "edge";

const WIDTH = 1080;
const HEIGHT = 1920;

export async function GET(
  request: Request,
  { params }: { params: Promise<{ publicId: string }> },
) {
  const { publicId } = await params;
  const locale = localeFromHeaderValue(request.headers.get(LOCALE_HEADER));
  const record = await getPredictionWithParticipants(publicId, locale);

  if (!record) {
    return new Response("Prediction not found", { status: 404 });
  }

  return new ImageResponse(
    (
      <PredictionCardMarkup
        width={WIDTH}
        height={HEIGHT}
        siteDomain={siteUrl.replace(/^https?:\/\//, "")}
        data={{
          eventName: record.event.name,
          nickname: record.prediction.nickname,
          countryCode: record.prediction.countryCode,
          isDemo: record.prediction.dataStatus === "demo",
          locale,
          rankedParticipants: record.rankedParticipants,
        }}
      />
    ),
    { width: WIDTH, height: HEIGHT },
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\card\story\route.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\card\story\route.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\card\story\route.tsx"
}

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

  if (!prediction.hasVerifiedOwner) {
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
    $path = "src\app\p\[publicId]\opengraph-image.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getLocale } from "@/lib/i18n-server";
import { getDictionary } from "@/lib/i18n";

export const runtime = "edge";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpengraphImage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const locale = await getLocale();
  const sd = getDictionary(locale).share;
  const record = await getPredictionWithParticipants(publicId, locale);

  const ink = "#141318";
  const accent = "#A6342E";
  const textPrimary = "#F2EFE6";
  const textMuted = "#A39FB0";

  if (!record) {
    return new ImageResponse(
      (
        <div
          style={{
            width: "100%",
            height: "100%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            backgroundColor: ink,
            color: textPrimary,
            fontFamily: "Georgia, serif",
            fontSize: 48,
          }}
        >
          FOUCH
        </div>
      ),
      { ...size },
    );
  }

  const top3 = record.rankedParticipants.slice(0, 3);
  const heading = record.prediction.nickname
    ? sd.ogHeadingNamed.replace("{name}", record.prediction.nickname)
    : sd.ogHeadingAnon;

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "60px 70px",
          backgroundColor: ink,
          color: textPrimary,
          fontFamily: "Georgia, serif",
        }}
      >
        <div style={{ display: "flex", fontSize: 26, letterSpacing: 4, color: accent }}>FOUCH</div>
        <div style={{ display: "flex", fontSize: 46, marginTop: 12 }}>{heading}</div>
        <div style={{ display: "flex", fontSize: 26, color: textMuted, marginTop: 6 }}>
          {record.event.name}
        </div>
        <div style={{ display: "flex", marginTop: 30, gap: 24 }}>
          {top3.map((participant, index) => (
            <div key={participant.id} style={{ display: "flex", alignItems: "center", fontSize: 28 }}>
              <span style={{ display: "flex", color: accent, marginRight: 10 }}>{index + 1}</span>
              <span style={{ display: "flex" }}>{participant.displayName}</span>
              <span
                style={{
                  display: "flex",
                  fontSize: 15,
                  fontWeight: 700,
                  color: textMuted,
                  marginLeft: 10,
                  overflow: "hidden",
                  whiteSpace: "nowrap",
                  textOverflow: "ellipsis",
                  maxWidth: 160,
                }}
              >
                · {participant.countryName}
              </span>
            </div>
          ))}
        </div>
      </div>
    ),
    { ...size },
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\opengraph-image.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\opengraph-image.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\opengraph-image.tsx"
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

  // FOUCH 0.3A: editing is offered only for a verified prediction
  // while the event is still open â€” fetched fresh on every page view
  // from the single authoritative source, never cached/assumed.
  const lockConfig = await getEventLockConfig(event.slug);
  const isPredictionOpen = isPredictionWindowOpen(lockConfig, Date.now());
  const canEdit = prediction.hasVerifiedOwner && isPredictionOpen;
  const showLockedNotice = prediction.hasVerifiedOwner && !isPredictionOpen;

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
    $path = "src\app\p\[publicId]\result-card\post\route.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getPredictionScore } from "@/lib/scoring-service";
import { ResultCardMarkup } from "@/components/scoring/ResultCardMarkup";
import { siteUrl } from "@/lib/site";
import { LOCALE_HEADER, localeFromHeaderValue } from "@/lib/locale";

export const runtime = "edge";

const WIDTH = 1080;
const HEIGHT = 1350;

export async function GET(
  request: Request,
  { params }: { params: Promise<{ publicId: string }> },
) {
  const { publicId } = await params;
  const locale = localeFromHeaderValue(request.headers.get(LOCALE_HEADER));
  const record = await getPredictionWithParticipants(publicId, locale);
  if (!record) return new Response("Prediction not found", { status: 404 });

  const result = await getPredictionScore(
    record.prediction.id,
    record.prediction.rankedParticipantIds,
    record.event.slug,
    record.prediction.dataStatus,
  );
  if (!result) return new Response("No official result yet", { status: 404 });

  return new ImageResponse(
    (
      <ResultCardMarkup
        width={WIDTH}
        height={HEIGHT}
        siteDomain={siteUrl.replace(/^https?:\/\//, "")}
        data={{
          eventName: record.event.name,
          nickname: record.prediction.nickname,
          countryCode: record.prediction.countryCode,
          isDemo: record.prediction.dataStatus === "demo",
          locale,
          breakdown: result.breakdown,
          percentile: result.percentile.percentile,
        }}
      />
    ),
    { width: WIDTH, height: HEIGHT },
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\result-card\post\route.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\result-card\post\route.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\result-card\post\route.tsx"
}

try {
    $path = "src\app\p\[publicId]\result-card\story\route.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getPredictionScore } from "@/lib/scoring-service";
import { ResultCardMarkup } from "@/components/scoring/ResultCardMarkup";
import { siteUrl } from "@/lib/site";
import { LOCALE_HEADER, localeFromHeaderValue } from "@/lib/locale";

export const runtime = "edge";

const WIDTH = 1080;
const HEIGHT = 1920;

export async function GET(
  request: Request,
  { params }: { params: Promise<{ publicId: string }> },
) {
  const { publicId } = await params;
  const locale = localeFromHeaderValue(request.headers.get(LOCALE_HEADER));
  const record = await getPredictionWithParticipants(publicId, locale);
  if (!record) return new Response("Prediction not found", { status: 404 });

  const result = await getPredictionScore(
    record.prediction.id,
    record.prediction.rankedParticipantIds,
    record.event.slug,
    record.prediction.dataStatus,
  );
  if (!result) return new Response("No official result yet", { status: 404 });

  return new ImageResponse(
    (
      <ResultCardMarkup
        width={WIDTH}
        height={HEIGHT}
        siteDomain={siteUrl.replace(/^https?:\/\//, "")}
        data={{
          eventName: record.event.name,
          nickname: record.prediction.nickname,
          countryCode: record.prediction.countryCode,
          isDemo: record.prediction.dataStatus === "demo",
          locale,
          breakdown: result.breakdown,
          percentile: result.percentile.percentile,
        }}
      />
    ),
    { width: WIDTH, height: HEIGHT },
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\p\[publicId]\result-card\story\route.tsx"
} catch {
    Write-Host "FAILED: src\app\p\[publicId]\result-card\story\route.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\p\[publicId]\result-card\story\route.tsx"
}

try {
    $path = "src\app\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\page.tsx"
} catch {
    Write-Host "FAILED: src\app\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\page.tsx"
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
    $path = "src\app\sitemap.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { MetadataRoute } from "next";
import { getFeaturedEvent } from "@/lib/events";
import { siteUrl } from "@/lib/site";

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const entries: MetadataRoute.Sitemap = [
    {
      url: siteUrl,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 1,
      // i18n v1: hreflang for the two locales of the home page. URLs
      // stay on the canonical joinfouch.com origin (siteUrl).
      alternates: { languages: { en: siteUrl, es: `${siteUrl}/es` } },
    },
  ];

  const featuredEvent = await getFeaturedEvent();
  if (featuredEvent) {
    entries.push({
      url: `${siteUrl}/predict/${featuredEvent.slug}`,
      lastModified: new Date(),
      changeFrequency: "weekly",
      priority: 0.8,
    });
  }

  return entries;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\sitemap.ts"
} catch {
    Write-Host "FAILED: src\app\sitemap.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\sitemap.ts"
}

try {
    $path = "src\components\ClosingMoment.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import { CinematicBackdrop } from "./CinematicBackdrop";

/**
 * FOUCH Home v1.1 Round 2 — restrained closing brand statement, the
 * "final frame of a trailer": large typography, generous breathing
 * room, one strong CTA. No data dependency, no per-event content.
 */
export function ClosingMoment({ eventSlug, dictionary }: { eventSlug: string | null; dictionary: Dictionary }) {
  return (
    <section className="relative overflow-hidden py-20 text-center sm:py-48">
      <CinematicBackdrop variant={0} />
      <div className="relative mx-auto max-w-content px-6">
        <h2 className="font-display text-4xl uppercase leading-[1.05] tracking-tight text-text-primary sm:text-6xl md:text-8xl">
          {dictionary.closing.lineOne}
          <br />
          <span className="text-accent-strong">{dictionary.closing.lineTwo}</span>
        </h2>
        <p className="mt-8 text-sm uppercase tracking-[0.35em] text-text-muted">
          {dictionary.closing.tagline}
        </p>

        {eventSlug ? (
          <Link
            href={`/predict/${eventSlug}`}
            className="group mt-12 inline-flex items-center gap-2 rounded bg-accent px-9 py-5 text-lg font-medium text-on-accent shadow-[0_8px_40px_-8px_rgba(166,52,46,0.6)] transition-colors hover:bg-accent-strong"
          >
            {dictionary.closing.cta}
            <ArrowRight className="h-5 w-5 transition-transform group-hover:translate-x-0.5" aria-hidden />
          </Link>
        ) : null}
      </div>
    </section>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\ClosingMoment.tsx"
} catch {
    Write-Host "FAILED: src\components\ClosingMoment.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\ClosingMoment.tsx"
}

try {
    $path = "src\components\CrowdPanel.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import { CountryFlag } from "@/components/CountryFlag";
import { getSampleSizeBucket } from "@/lib/community-comparison";
import type { CrowdTopPicks } from "@/lib/crowd-picks";
import type { Dictionary } from "@/content/types";
import { fmt } from "@/lib/i18n";

/**
 * FOUCH Home v1.1 Round 2 "The Crowd" — presentational only; all
 * numbers come from getCrowdTopPicks (real, current-version,
 * is_final predictions). Small-sample behavior reuses
 * getSampleSizeBucket's existing "0"/"1_4" tiers unchanged — this
 * pass only restyles the same two states, it does not add a third
 * or move the threshold.
 */
export function CrowdPanel({
  crowd,
  eventSlug,
  predictHref,
  dictionary,
}: {
  crowd: CrowdTopPicks;
  eventSlug: string;
  predictHref: string;
  dictionary: Dictionary;
}) {
  const t = dictionary.crowd;
  const bucket = getSampleSizeBucket(crowd.population);
  const isEarly = bucket === "0" || bucket === "1_4";

  return (
    <div className="relative overflow-hidden rounded-lg border border-white/10 bg-white/[0.03] p-6 backdrop-blur-sm">
      <span className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-accent/60 to-transparent" aria-hidden />

      <div className="flex items-center gap-2">
        <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-accent" />
        <p className="text-xs font-medium uppercase tracking-[0.25em] text-text-secondary">{t.title}</p>
      </div>

      {isEarly ? (
        <>
          <p className="mt-5 font-display text-3xl uppercase tracking-tight text-text-primary">
            {t.earlyTitle}
          </p>
          <p className="mt-3 text-sm text-text-secondary">
            {t.earlyBody}
          </p>
          <Link
            href={predictHref}
            className="mt-6 inline-flex items-center gap-1 text-sm font-medium text-accent-strong hover:text-accent"
          >
            {t.earlyCta}
          </Link>
        </>
      ) : (
        <>
          <div className="mt-3 flex items-center justify-between">
            <p className="text-sm text-text-secondary">{t.question}</p>
            <Link
              href={`/events/${eventSlug}/leaderboard`}
              className="shrink-0 text-xs text-text-muted hover:text-text-secondary"
            >
              {t.viewAll}
            </Link>
          </div>

          <ol className="mt-5 space-y-3.5">
            {crowd.picks.map((pick, index) => (
              <li key={pick.participant.id} className="flex items-center gap-3">
                <span className="font-display w-4 shrink-0 text-sm text-text-muted">{index + 1}</span>
                <CountryFlag countryCode={pick.participant.countryCode} className="h-4 w-6 shrink-0 rounded-sm" />
                <span className="flex-1 truncate text-sm text-text-primary">
                  {pick.participant.displayName}{" "}
                  <span className="text-text-muted">· {pick.participant.countryName}</span>
                </span>
                <div className="flex w-24 items-center gap-2">
                  <span className="h-1 flex-1 overflow-hidden rounded-full bg-white/10">
                    <span
                      className="block h-full rounded-full bg-accent"
                      style={{ width: `${Math.max(4, pick.pct)}%` }}
                    />
                  </span>
                  <span className="w-9 shrink-0 text-right text-xs text-text-muted">{pick.pct}%</span>
                </div>
              </li>
            ))}
          </ol>

          <p className="mt-5 text-xs text-text-muted">{fmt(t.basedOn, { n: crowd.population })}</p>
        </>
      )}
    </div>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\CrowdPanel.tsx"
} catch {
    Write-Host "FAILED: src\components\CrowdPanel.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\CrowdPanel.tsx"
}

try {
    $path = "src\components\FeaturedEvent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { getParticipantsForEvent } from "@/lib/participants";
import { getOfficialResult } from "@/lib/results-db";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getCrowdTopPicks } from "@/lib/crowd-picks";
import { splitEventNameYear } from "@/lib/event-name-split";
import { formatEventDayMonth } from "@/lib/event-time-display";
import type { Locale } from "@/lib/locale";
import { CinematicBackdrop } from "./CinematicBackdrop";
import { CrowdPanel } from "./CrowdPanel";
import { TrackedLink } from "./TrackedLink";

export async function FeaturedEvent({
  event,
  dictionary,
  locale = "en",
}: {
  event: FouchEvent;
  dictionary: Dictionary;
  locale?: Locale;
}) {
  const dayMonth = formatEventDayMonth(event.eventDate, locale);

  // Sprint 5.1: the secondary leaderboard link is event/result-state
  // driven, never hardcoded to a specific slug — it only appears once
  // an official/demo result genuinely exists to rank against.
  const participantData = await getParticipantsForEvent(event.slug);
  const hasLeaderboard = participantData
    ? Boolean(await getOfficialResult(event.slug, participantData.status))
    : false;

  // Home v1.1: "Now Predicting" must reflect the ACTUAL prediction
  // window, never assume an "upcoming"/"open" DB status means
  // predictions are open right now (brief §3: "Do not label an event
  // NOW PREDICTING if its prediction window is closed").
  const lockConfig = await getEventLockConfig(event.slug);
  const isOpen = isPredictionWindowOpen(lockConfig, Date.now());
  const eyebrow = isOpen ? dictionary.featuredEvent.eyebrowNow : dictionary.featuredEvent.eyebrowClosed;

  const crowd = participantData ? await getCrowdTopPicks(event.slug, participantData.status, 5, locale) : null;

  const { primary, year } = splitEventNameYear(event.name);

  return (
    <section id="featured-event" className="relative scroll-mt-20 overflow-hidden py-16 sm:py-24">
      <CinematicBackdrop variant={0} />

      <div className="relative mx-auto grid max-w-content gap-y-20 gap-x-12 px-6 lg:grid-cols-[1fr_340px] lg:items-end lg:gap-10">
        <div>
          <div className="flex items-center gap-3">
            <span className="font-display text-sm text-accent-strong/70">01</span>
            <span className="h-px w-8 bg-border-strong" aria-hidden />
            <span
              aria-hidden
              className={
                isOpen
                  ? "h-1.5 w-1.5 rounded-full bg-accent animate-pulse motion-reduce:animate-none"
                  : "h-1.5 w-1.5 rounded-full bg-text-muted"
              }
            />
            <span className="text-xs font-medium uppercase tracking-[0.25em] text-text-secondary">
              {eyebrow}
            </span>
          </div>

          <h2 className="mt-6 font-display leading-[0.9] text-text-primary">
            <span className="block text-3xl sm:text-4xl">{primary}</span>
            {year ? (
              <span className="block bg-gradient-to-b from-text-primary to-text-primary/70 bg-clip-text text-8xl font-semibold tracking-tight text-transparent sm:text-9xl">
                {year}
              </span>
            ) : null}
          </h2>

          <p className="mt-5 text-sm uppercase tracking-[0.2em] text-text-muted">
            {dayMonth} · {event.subtitle}
          </p>

          <p className="mt-8 text-lg text-text-secondary">{dictionary.featuredEvent.prompt}</p>

          <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3">
            <TrackedLink
              href={`/predict/${event.slug}`}
              event="featured_event_clicked"
              eventProperties={{ slug: event.slug }}
              className="group inline-flex items-center gap-2 rounded bg-accent px-8 py-5 text-lg font-medium text-on-accent shadow-[0_8px_40px_-8px_rgba(166,52,46,0.6)] transition-colors hover:bg-accent-strong"
            >
              {dictionary.featuredEvent.cta}
              <ArrowRight
                className="h-5 w-5 transition-transform group-hover:translate-x-0.5"
                aria-hidden
              />
            </TrackedLink>

            {hasLeaderboard ? (
              <TrackedLink
                href={`/events/${event.slug}/leaderboard`}
                event="leaderboard_from_score_clicked"
                eventProperties={{ event_slug: event.slug, source: "home" }}
                className="text-sm text-text-secondary transition-colors hover:text-accent-strong"
              >
                {dictionary.featuredEvent.viewLeaderboard}
              </TrackedLink>
            ) : null}
          </div>
        </div>

        {crowd ? (
          <CrowdPanel crowd={crowd} eventSlug={event.slug} predictHref={`/predict/${event.slug}`} dictionary={dictionary} />
        ) : null}
      </div>
    </section>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\FeaturedEvent.tsx"
} catch {
    Write-Host "FAILED: src\components\FeaturedEvent.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\FeaturedEvent.tsx"
}

try {
    $path = "src\components\Footer.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import type { Dictionary } from "@/content/types";
import { LanguageSwitcher } from "./LanguageSwitcher";

export function Footer({ dictionary }: { dictionary: Dictionary }) {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto max-w-content px-6 py-8">
        <p className="font-display text-base font-semibold tracking-[0.12em] text-text-primary">
          FOUCH
        </p>
        <p className="mt-1 text-sm text-text-muted">{dictionary.footer.tagline}</p>
        <p className="mt-1 text-xs text-text-muted">
          {dictionary.footer.disclaimer}
        </p>
        <div className="mt-3 flex gap-4 text-xs text-text-muted">
          <Link href="/privacy" className="underline hover:text-text-secondary">
            {dictionary.footer.privacy}
          </Link>
          <Link href="/terms" className="underline hover:text-text-secondary">
            {dictionary.footer.terms}
          </Link>
          <span aria-hidden className="text-border-strong">
            ·
          </span>
          <LanguageSwitcher />
        </div>
      </div>
    </footer>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\Footer.tsx"
} catch {
    Write-Host "FAILED: src\components\Footer.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\Footer.tsx"
}

try {
    $path = "src\components\Hero.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import { ArrowRight, Trophy, BarChart3, Star } from "lucide-react";
import type { Dictionary } from "@/content/types";

export function Hero({
  dictionary,
  eventSlug,
  predictionsOpen,
}: {
  dictionary: Dictionary;
  eventSlug: string | null;
  /** Home v1.1: only true when the featured event's own prediction
   * window is genuinely open right now (isPredictionWindowOpen) —
   * never assumed from event.status alone. Null/false renders no
   * status badge at all rather than a misleading one. */
  predictionsOpen: boolean;
}) {
  return (
    <section className="relative overflow-hidden">
      {/* Subtle decorative glow — not neon, not animated, just enough to
          suggest something is about to happen behind the headline. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-32 left-1/2 h-[28rem] w-[28rem] -translate-x-1/2 rounded-full bg-accent/10 blur-3xl"
      />
      {/* Right-side atmospheric balance — desktop only, purely CSS: an
          oversized, near-invisible numeral plus a warm glow, giving the
          hero visual weight on the right without any photography, card,
          or fabricated content. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -right-10 top-1/2 hidden -translate-y-1/2 select-none font-display text-[26rem] font-semibold leading-none text-white/[0.025] lg:block"
      >
        01
      </div>
      <div
        aria-hidden
        className="pointer-events-none absolute -right-32 top-1/3 hidden h-[24rem] w-[24rem] rounded-full bg-accent/10 blur-[100px] lg:block"
      />

      <div className="relative mx-auto max-w-content px-6 pb-10 pt-12 sm:pb-14 sm:pt-20">
        <p className="text-xs font-medium uppercase tracking-[0.25em] text-text-muted">
          {dictionary.hero.eyebrow}
        </p>

        <h1 className="mt-3 font-display text-[3.25rem] font-semibold uppercase leading-[0.95] tracking-tight text-text-primary sm:text-7xl">
          {dictionary.hero.headlineLines.map((line, index) => (
            <span key={line}>
              {index > 0 ? <br /> : null}
              {line}
            </span>
          ))}
        </h1>

        <p className="mt-6 max-w-sm text-lg text-text-secondary">
          {dictionary.hero.subhead}
        </p>

        <div className="mt-9 flex flex-wrap items-center gap-x-6 gap-y-4">
          {eventSlug ? (
            <Link
              href={`/predict/${eventSlug}`}
              className="group inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent shadow-[0_0_0_1px_rgba(166,52,46,0.4)] transition-colors hover:bg-accent-strong"
            >
              {dictionary.hero.cta}
              <ArrowRight
                className="h-4 w-4 transition-transform group-hover:translate-x-0.5"
                aria-hidden
              />
            </Link>
          ) : null}

          {predictionsOpen ? (
            <span className="inline-flex items-center gap-2 text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
              <span
                aria-hidden
                className="h-1.5 w-1.5 rounded-full bg-accent animate-pulse motion-reduce:animate-none"
              />
              {dictionary.hero.predictionsOpen}
            </span>
          ) : null}
        </div>

        <div className="mt-10 flex flex-wrap gap-x-8 gap-y-3 border-t border-border pt-6 text-sm text-text-muted">
          <span className="inline-flex items-center gap-2">
            <Trophy className="h-4 w-4" aria-hidden />
            {dictionary.hero.predictLabel}
            <span className="hidden text-text-secondary sm:inline">{dictionary.hero.predictHint}</span>
          </span>
          <span className="inline-flex items-center gap-2">
            <BarChart3 className="h-4 w-4" aria-hidden />
            {dictionary.hero.competeLabel}
            <span className="hidden text-text-secondary sm:inline">{dictionary.hero.competeHint}</span>
          </span>
          <span className="inline-flex items-center gap-2">
            <Star className="h-4 w-4" aria-hidden />
            {dictionary.hero.proveLabel}
          </span>
        </div>
      </div>
    </section>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\Hero.tsx"
} catch {
    Write-Host "FAILED: src\components\Hero.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\Hero.tsx"
}

try {
    $path = "src\components\HowItWorks.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { CountryFlag } from "@/components/CountryFlag";
import type { Dictionary } from "@/content/types";

/**
 * FOUCH Home v1.1 Round 2 — each step pairs its copy with a small,
 * explicitly illustrative visual (a mini ranking card, a comparison
 * bar, a score ring). These are demonstrative UI, not live data —
 * none of them read from any real prediction, event, or user, and
 * the score example is labeled "Example score" so it can't be
 * mistaken for real platform activity.
 */
export function HowItWorks({ dictionary }: { dictionary: Dictionary }) {
  const predictCard = (
    <div
      key="predict"
      aria-hidden
      className="mt-5 rounded-lg border border-white/10 bg-white/[0.03] p-4"
    >
      {[
        { pos: 1, code: "CL" },
        { pos: 2, code: "VE" },
        { pos: 3, code: "AR" },
      ].map((row) => (
        <div key={row.pos} className="flex items-center gap-3 py-2">
          <span className="font-display w-5 text-sm text-accent-strong/80">{row.pos}</span>
          <CountryFlag countryCode={row.code} className="h-4 w-6 rounded-sm" />
          <span className="h-2 flex-1 rounded-full bg-white/10" />
        </div>
      ))}
    </div>
  );

  const competeCard = (
    <div key="compete" aria-hidden className="mt-5 space-y-3">
      <div className="flex items-center gap-2 text-xs uppercase tracking-wide text-text-muted">
        <span className="w-14 shrink-0">{dictionary.howItWorks.you}</span>
        <span className="h-2 flex-1 overflow-hidden rounded-full bg-white/10">
          <span className="block h-full w-2/3 rounded-full bg-accent" />
        </span>
      </div>
      <div className="flex items-center gap-2 text-xs uppercase tracking-wide text-text-muted">
        <span className="w-14 shrink-0">{dictionary.howItWorks.crowd}</span>
        <span className="h-2 flex-1 overflow-hidden rounded-full bg-white/10">
          <span className="block h-full w-5/12 rounded-full bg-white/30" />
        </span>
      </div>
    </div>
  );

  const proveCard = (
    <div key="prove" aria-hidden className="mt-5 flex flex-col items-start gap-3">
      <div
        className="flex h-32 w-32 shrink-0 items-center justify-center rounded-full"
        style={{ background: "conic-gradient(var(--color-accent-strong, #c94a3f) 82%, rgba(255,255,255,0.08) 0)" }}
      >
        <div className="flex h-26 w-26 flex-col items-center justify-center rounded-full bg-black" style={{ height: "6.25rem", width: "6.25rem" }}>
          <span className="font-display text-4xl text-text-primary">82</span>
          <span className="text-[10px] uppercase tracking-wide text-text-muted">{dictionary.howItWorks.excellent}</span>
        </div>
      </div>
      <span className="text-xs uppercase tracking-[0.2em] text-text-muted">{dictionary.howItWorks.exampleScore}</span>
    </div>
  );

  const visuals = [predictCard, competeCard, proveCard];

  return (
    <section className="relative mx-auto max-w-content px-6 pb-16 pt-10 sm:py-28">
      <p className="text-xs font-medium uppercase tracking-[0.25em] text-text-secondary">
        {dictionary.howItWorks.title}
      </p>
      <div className="mt-8 grid gap-12 sm:grid-cols-3 sm:gap-10">
        {dictionary.howItWorks.steps.map((step, index) => (
          <div key={step.title}>
            <p className="font-display text-5xl text-border-strong">
              {String(index + 1).padStart(2, "0")}
            </p>
            <p className="mt-3 font-display text-2xl uppercase tracking-tight text-text-primary">
              {step.title}
            </p>
            <p className="mt-1 text-sm text-text-secondary">{step.body}</p>
            {visuals[index]}
          </div>
        ))}
      </div>
    </section>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\HowItWorks.tsx"
} catch {
    Write-Host "FAILED: src\components\HowItWorks.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\HowItWorks.tsx"
}

try {
    $path = "src\components\Nav.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import Link from "next/link";
import { LanguageSwitcher } from "./LanguageSwitcher";

export function Nav() {
  return (
    <header className="border-b border-border">
      <div className="mx-auto flex max-w-content items-center justify-between px-6 py-5">
        <Link
          href="/"
          className="font-display text-xl font-semibold tracking-[0.12em] text-text-primary"
        >
          FOUCH
        </Link>
        <LanguageSwitcher />
      </div>
    </header>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\Nav.tsx"
} catch {
    Write-Host "FAILED: src\components\Nav.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\Nav.tsx"
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
}: {
  events: FouchEvent[];
  dictionary: Dictionary;
  locale?: Locale;
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

                <TrackedLink
                  href={`/predict/${event.slug}`}
                  event="featured_event_clicked"
                  eventProperties={{ slug: event.slug, source: "upcoming_secondary" }}
                  className="group inline-flex shrink-0 items-center gap-2 rounded bg-accent px-6 py-3.5 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
                >
                  {dictionary.featuredEvent.cta}
                  <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
                </TrackedLink>
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
    $path = "src\components\prediction\EditPredictionFlow.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { track } from "@/lib/analytics";
import { formatEventLocalLockTime } from "@/lib/event-time-display";
import {
  startEmailVerification,
  verifyEmailAndEditPrediction,
  retryEditWithVerifiedSession,
  type VerifyAndEditResult,
} from "@/app/predict/[slug]/verify-actions";
import type { Participant } from "@/types/participant";
import { TopTenList } from "./TopTenList";
import { ParticipantBrowser } from "./ParticipantBrowser";
import { EmailStep } from "./EmailStep";
import { OtpStep } from "./OtpStep";
import { useI18n } from "@/components/I18nProvider";
import { fmt } from "@/lib/i18n";
import { translateServerError } from "@/lib/server-error-i18n";

type Step = "edit" | "email" | "otp";

/**
 * FOUCH 0.3A â€” reuses the SAME ranking primitives as
 * PredictionBuilder.tsx (TopTenList, ParticipantBrowser) and the SAME
 * verification primitives as ReviewContent.tsx (EmailStep, OtpStep) â€”
 * deliberately not a second, independent builder. The only real
 * difference from PredictionBuilder is persistence: this component's
 * ranking state starts from the prediction's CURRENT version (passed
 * in from the server) and is never written to localStorage â€” there is
 * nothing "in progress" to resume here, only a specific saved
 * prediction being edited.
 */
export function EditPredictionFlow({
  eventSlug,
  publicId,
  allParticipants,
  initialRankedParticipants,
  requiredCount,
  expectedVersionNumber,
  predictionLockAt,
  predictionTimezone,
}: {
  eventSlug: string;
  publicId: string;
  /** Only currently-selectable (ACTIVE) contestants â€” what
   * ParticipantBrowser offers to pick from. */
  allParticipants: Participant[];
  /** FOUCH 0.3B: the CURRENT ranking resolved regardless of status â€”
   * may include a WITHDRAWN/REPLACED entry (isActive: false), which
   * must still display with its real name so it can be seen and
   * explicitly swapped out, never silently dropped from the list. */
  initialRankedParticipants: Participant[];
  requiredCount: number;
  expectedVersionNumber: number;
  predictionLockAt: string | null;
  /** FOUCH 0.3A.1 â€” IANA timezone identifier for the event, used only
   * for unambiguous display of predictionLockAt (see
   * event-time-display.ts). */
  predictionTimezone: string | null;
}) {
  const { locale, dict } = useI18n();
  const bt = dict.builder;
  const router = useRouter();
  const [selectedIds, setSelectedIds] = useState<string[]>(
    initialRankedParticipants.map((participant) => participant.id),
  );
  const [step, setStep] = useState<Step>("edit");

  const [emailSubmitting, setEmailSubmitting] = useState(false);
  const [emailError, setEmailError] = useState<string | null>(null);
  const [email, setEmail] = useState("");

  const [otpSubmitting, setOtpSubmitting] = useState(false);
  const [otpError, setOtpError] = useState<string | null>(null);
  const [wrongAttemptCount, setWrongAttemptCount] = useState(0);
  const [accessTokenForRetry, setAccessTokenForRetry] = useState<string | null>(null);

  // FOUCH 0.3B: merges the selectable roster with whatever the
  // current ranking already contains â€” this is what lets a
  // WITHDRAWN/REPLACED entry the user hasn't removed yet keep
  // resolving to its real name (isActive: false) instead of vanishing
  // from the Top N the moment its status changed. ParticipantBrowser
  // below still only ever offers `allParticipants` (active-only) to
  // pick from, so a removed inactive entry can only be replaced by a
  // currently-active contestant â€” never re-added.
  const participantsById = new Map(
    [...allParticipants, ...initialRankedParticipants].map((participant) => [participant.id, participant]),
  );

  const rankedParticipants = selectedIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  const isComplete = selectedIds.length >= requiredCount;
  // FOUCH 0.3B Â§7: a saved version can never include a participant
  // who is no longer ACTIVE â€” checked client-side here purely to
  // give an immediate, clear message instead of a round-trip to the
  // server; validateSubmission enforces the same rule authoritatively
  // regardless of this check (see verify-actions.ts's edit flow).
  const hasUnavailableSelection = rankedParticipants.some((participant) => !participant.isActive);
  const canSave = isComplete && !hasUnavailableSelection;

  function handleToggle(id: string) {
    setSelectedIds((current) => {
      if (current.includes(id)) {
        return current.filter((selectedId) => selectedId !== id);
      }
      if (current.length >= requiredCount) return current;
      return [...current, id];
    });
  }

  function handleRemove(id: string) {
    setSelectedIds((current) => current.filter((selectedId) => selectedId !== id));
  }

  function swap(array: string[], i: number, j: number): string[] {
    const next = [...array];
    const a = next[i];
    const b = next[j];
    if (a === undefined || b === undefined) return array;
    next[i] = b;
    next[j] = a;
    return next;
  }

  function handleMoveUp(index: number) {
    if (index === 0) return;
    setSelectedIds((current) => {
      track("prediction_edit_reordered", { event_slug: eventSlug });
      return swap(current, index - 1, index);
    });
  }

  function handleMoveDown(index: number) {
    setSelectedIds((current) => {
      if (index === current.length - 1) return current;
      track("prediction_edit_reordered", { event_slug: eventSlug });
      return swap(current, index, index + 1);
    });
  }

  function handleStartSave() {
    track("prediction_edit_started", { event_slug: eventSlug });
    setStep("email");
  }

  async function handleSendCode(targetEmail: string) {
    if (emailSubmitting) return;
    setEmailSubmitting(true);
    setEmailError(null);

    let result;
    try {
      result = await startEmailVerification(targetEmail);
    } catch {
      setEmailError("We couldn't send a code — try again in a moment.");
      setEmailSubmitting(false);
      return;
    }

    setEmailSubmitting(false);

    if (!result.success) {
      setEmailError(result.error);
      return;
    }

    setEmail(targetEmail);
    setOtpError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
    setStep("otp");
  }

  function handleEditResult(result: VerifyAndEditResult) {
    if (result.success) {
      track("prediction_updated", {
        event_slug: eventSlug,
        version_number: result.versionNumber,
        unchanged: result.unchanged,
      });
      router.push(`/p/${publicId}?edited=1`);
      return;
    }

    setOtpError(result.error);
    setAccessTokenForRetry(result.accessToken ?? null);
    if (result.failureReason === "invalid_code") {
      setWrongAttemptCount((count) => count + 1);
    }
  }

  async function handleVerify(code: string) {
    if (otpSubmitting) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndEditResult;
    try {
      result = await verifyEmailAndEditPrediction(email, code, {
        publicId,
        participantIds: selectedIds,
        expectedVersionNumber,
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't verify your code — try again.");
      return;
    }

    setOtpSubmitting(false);
    handleEditResult(result);
  }

  async function handleRetry() {
    if (otpSubmitting || !accessTokenForRetry) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndEditResult;
    try {
      result = await retryEditWithVerifiedSession(accessTokenForRetry, {
        publicId,
        participantIds: selectedIds,
        expectedVersionNumber,
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't save your changes. Try again.");
      return;
    }

    setOtpSubmitting(false);
    handleEditResult(result);
  }

  function handleUseDifferentEmail() {
    setStep("email");
    setEmail("");
    setOtpError(null);
    setEmailError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
  }

  return (
    <div className="mt-6">
      {predictionLockAt ? (
        <p className="mb-4 text-xs text-text-muted">
          {fmt(dict.publicPrediction.updateUntil, { when: formatEventLocalLockTime(predictionLockAt, predictionTimezone, locale) })}
        </p>
      ) : null}

      {step === "edit" ? (
        <div className="lg:grid lg:grid-cols-[380px_1fr] lg:gap-10">
          <section aria-label={fmt(bt.yourTop, { n: requiredCount })} className="lg:sticky lg:top-20 lg:self-start">
            <h2 className="font-display text-lg text-text-primary">{fmt(bt.yourTop, { n: requiredCount })}</h2>
            <div className="mt-3">
              <TopTenList
                rankedParticipants={rankedParticipants}
                requiredCount={requiredCount}
                onRemove={handleRemove}
                onMoveUp={handleMoveUp}
                onMoveDown={handleMoveDown}
              />
            </div>

            {isComplete ? (
              <>
                <button
                  type="button"
                  onClick={handleStartSave}
                  disabled={!canSave}
                  className="mt-6 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-50 sm:w-auto"
                >
                  {fmt(dict.review.saveCta, { n: requiredCount })}
                </button>
                {hasUnavailableSelection ? (
                  <p className="mt-2 text-xs text-text-muted">
                    {bt.replaceHint}
                  </p>
                ) : null}
              </>
            ) : null}
          </section>

          <section aria-label={bt.allContestants} className="mt-10 lg:mt-0">
            <h2 className="font-display text-lg text-text-primary">{bt.allContestants}</h2>
            <div className="mt-3">
              <ParticipantBrowser
                participants={allParticipants}
                selectedIds={new Set(selectedIds)}
                atMax={isComplete}
                onToggle={handleToggle}
              />
            </div>
          </section>
        </div>
      ) : null}

      {step === "email" ? (
        <EmailStep mode="edit" submitting={emailSubmitting} errorMessage={emailError} onSendCode={handleSendCode} />
      ) : null}

      {step === "otp" && accessTokenForRetry ? (
        <div className="mt-8 border-t border-border pt-6">
          {otpError ? (
            <p className="text-sm text-accent-strong" role="alert" aria-live="polite">
              {translateServerError(otpError, locale)}
            </p>
          ) : null}
          <button
            type="button"
            disabled={otpSubmitting}
            onClick={handleRetry}
            className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
          >
            {otpSubmitting ? dict.review.tryingAgain : dict.review.tryAgain}
          </button>
        </div>
      ) : step === "otp" ? (
        <OtpStep
          email={email}
          submitting={otpSubmitting}
          errorMessage={otpError}
          wrongAttemptCount={wrongAttemptCount}
          onVerify={handleVerify}
          onResend={() => handleSendCode(email)}
          onUseDifferentEmail={handleUseDifferentEmail}
        />
      ) : null}
    </div>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\EditPredictionFlow.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\EditPredictionFlow.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\EditPredictionFlow.tsx"
}

try {
    $path = "src\components\prediction\EmailStep.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useState } from "react";
import { getEmailStepHeading, type EmailStepMode } from "@/lib/email-step-copy";
import { useI18n } from "@/components/I18nProvider";
import { translateServerError } from "@/lib/server-error-i18n";

export function EmailStep({
  mode,
  submitting,
  errorMessage,
  onSendCode,
}: {
  /** FOUCH 0.3A.1 — "create" for a first-time submission, "edit" for
   * an existing verified prediction. Drives the heading copy only;
   * OTP behavior is identical either way (brief §8-9). */
  mode: EmailStepMode;
  submitting: boolean;
  errorMessage: string | null;
  onSendCode: (email: string) => void;
}) {
  const [email, setEmail] = useState("");
  const { locale, dict } = useI18n();
  const t = dict.auth;

  return (
    <div className="mt-8 border-t border-border pt-6">
      <p className="font-display text-xl text-text-primary">{getEmailStepHeading(mode, { create: t.headingCreate, edit: t.headingEdit })}</p>
      <p className="mt-1 text-sm text-text-secondary">{t.subheading}</p>

      <label className="mt-4 block">
        <span className="text-sm text-text-secondary">{t.emailLabel}</span>
        <input
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          placeholder={t.emailPlaceholder}
          autoComplete="email"
          className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
        />
      </label>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          {translateServerError(errorMessage, locale)}
        </p>
      ) : null}

      <button
        type="button"
        disabled={submitting || email.trim().length === 0}
        onClick={() => onSendCode(email)}
        className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
      >
        {submitting ? t.sending : t.sendCode}
      </button>

      <p className="mt-3 text-xs text-text-muted">
        {t.privacyNote}
      </p>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\EmailStep.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\EmailStep.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\EmailStep.tsx"
}

try {
    $path = "src\components\prediction\OtpStep.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";
import { useI18n } from "@/components/I18nProvider";
import { fmt } from "@/lib/i18n";
import { translateServerError } from "@/lib/server-error-i18n";

/** Matches Supabase Auth's own default OTP resend cooldown, confirmed
 * in Phase B — never invent a different number here. */
const RESEND_COOLDOWN_SECONDS = 60;
/** Must match this project's actual configured "Email OTP length" in
 * Supabase (Authentication → Providers → Email) — confirmed as 8 in
 * this project, NOT the commonly-assumed 6. A mismatch here silently
 * truncates every real code and makes verification fail, misleadingly
 * reported as "expired" — a real bug found and fixed during Gate 1
 * manual testing, not a hypothetical. */
const OTP_LENGTH = 8;
/** UX guardrail only, not a security control — see
 * FOUCH_AUTH_FLOW.md's "Wrong code" state. Supabase Auth's own OTP
 * expiry/rate-limiting is the real protection. */
const MAX_UX_ATTEMPTS = 5;

export function OtpStep({
  email,
  submitting,
  errorMessage,
  wrongAttemptCount,
  onVerify,
  onResend,
  onUseDifferentEmail,
}: {
  email: string;
  submitting: boolean;
  errorMessage: string | null;
  wrongAttemptCount: number;
  onVerify: (code: string) => void;
  onResend: () => void;
  onUseDifferentEmail: () => void;
}) {
  const [code, setCode] = useState("");
  const { locale, dict } = useI18n();
  const t = dict.auth;
  const [secondsLeft, setSecondsLeft] = useState(RESEND_COOLDOWN_SECONDS);

  useEffect(() => {
    if (secondsLeft <= 0) return;
    const timer = setInterval(() => setSecondsLeft((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(timer);
  }, [secondsLeft]);

  const lockedOut = wrongAttemptCount >= MAX_UX_ATTEMPTS;

  function handleResend() {
    setCode("");
    setSecondsLeft(RESEND_COOLDOWN_SECONDS);
    onResend();
  }

  return (
    <div className="mt-8 border-t border-border pt-6">
      <p className="font-display text-xl text-text-primary">{fmt(t.enterCode, { email })}</p>

      <label className="mt-4 block">
        <span className="text-sm text-text-secondary">{t.codeLabel}</span>
        <input
          type="text"
          inputMode="numeric"
          autoComplete="one-time-code"
          maxLength={OTP_LENGTH}
          value={code}
          onChange={(event) => setCode(event.target.value.replace(/\D/g, "").slice(0, OTP_LENGTH))}
          disabled={lockedOut}
          className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-lg tracking-[0.3em] text-text-primary placeholder:text-text-muted focus:border-accent disabled:opacity-60"
        />
      </label>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert" aria-live="polite">
          {translateServerError(errorMessage, locale)}
        </p>
      ) : null}

      {lockedOut ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          {t.tooManyAttempts}
        </p>
      ) : (
        <button
          type="button"
          disabled={submitting || code.length !== OTP_LENGTH}
          onClick={() => onVerify(code)}
          className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
        >
          {submitting ? t.verifying : t.verifyCta}
        </button>
      )}

      <div className="mt-4 flex flex-wrap items-center gap-x-4 gap-y-2 text-sm">
        {secondsLeft > 0 ? (
          <span className="text-text-muted">{fmt(t.resendIn, { s: String(secondsLeft).padStart(2, "0") })}</span>
        ) : (
          <button type="button" onClick={handleResend} className="text-text-secondary underline hover:text-accent-strong">
            {t.resendCode}
          </button>
        )}
        <button type="button" onClick={onUseDifferentEmail} className="text-text-secondary underline hover:text-accent-strong">
          {t.differentEmail}
        </button>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\OtpStep.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\OtpStep.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\OtpStep.tsx"
}

try {
    $path = "src\components\prediction\ParticipantBrowser.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useMemo, useState } from "react";
import { Search } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import type { Participant } from "@/types/participant";
import { useI18n } from "@/components/I18nProvider";
import { fmt } from "@/lib/i18n";

export function ParticipantBrowser({
  participants,
  selectedIds,
  atMax,
  onToggle,
}: {
  participants: Participant[];
  selectedIds: Set<string>;
  atMax: boolean;
  onToggle: (id: string) => void;
}) {
  const [query, setQuery] = useState("");

  const { dict } = useI18n();
  const t = dict.builder;

  const filtered = useMemo(() => {
    const normalized = query.trim().toLowerCase();
    if (!normalized) return participants;

    return participants.filter(
      (participant) =>
        participant.displayName.toLowerCase().includes(normalized) ||
        participant.countryName.toLowerCase().includes(normalized),
    );
  }, [participants, query]);

  return (
    <div>
      <div className="relative">
        <Search
          className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-text-muted"
          aria-hidden
        />
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          placeholder={t.searchPlaceholder}
          aria-label={t.searchAria}
          className="w-full rounded border border-border bg-surface py-2.5 pl-10 pr-3 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
        />
      </div>

      {filtered.length === 0 ? (
        <p className="mt-6 text-sm text-text-muted">{fmt(t.noMatch, { query })}</p>
      ) : (
        <ul className="mt-4 divide-y divide-border">
          {filtered.map((participant) => {
            const selected = selectedIds.has(participant.id);
            const disabled = atMax && !selected;

            return (
              <li key={participant.id}>
                <button
                  type="button"
                  onClick={() => onToggle(participant.id)}
                  disabled={disabled}
                  aria-pressed={selected}
                  className={`flex w-full items-center gap-3 py-3 text-left transition-colors disabled:cursor-not-allowed disabled:opacity-40 ${
                    selected ? "text-accent-strong" : "text-text-primary hover:text-accent-strong"
                  }`}
                >
                  <CountryFlag countryCode={participant.countryCode} className="text-lg" />
                  <span className="flex-1 truncate text-sm">
                    {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
                  </span>
                  {selected ? (
                    <span className="text-xs font-medium uppercase tracking-wide">{t.selected}</span>
                  ) : null}
                </button>
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ParticipantBrowser.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ParticipantBrowser.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ParticipantBrowser.tsx"
}

try {
    $path = "src\components\prediction\PredictionBuilder.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useRef, useState } from "react";
import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { track } from "@/lib/analytics";
import { loadPrediction, savePrediction } from "@/lib/prediction-storage";
import type { Participant } from "@/types/participant";
import { TopTenList } from "./TopTenList";
import { ParticipantBrowser } from "./ParticipantBrowser";
import { useI18n } from "@/components/I18nProvider";
import { fmt } from "@/lib/i18n";

export function PredictionBuilder({
  eventSlug,
  participants,
  requiredCount,
  sourcePredictionId,
}: {
  eventSlug: string;
  participants: Participant[];
  requiredCount: number;
  /** Public ID of the shared prediction this visitor arrived from, if any. */
  sourcePredictionId?: string;
}) {
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [hydrated, setHydrated] = useState(false);
  const hasFiredCompletion = useRef(false);

  const participantsById = new Map(participants.map((participant) => [participant.id, participant]));

  // Restore any in-progress prediction once, on mount, then mark
  // "hydrated" so we don't overwrite it with an empty save before the
  // restore runs.
  useEffect(() => {
    const validIds = new Set(participants.map((participant) => participant.id));
    const restored = loadPrediction(eventSlug, validIds);
    setSelectedIds(restored.slice(0, requiredCount));
    setHydrated(true);
    track("start_prediction", {
      event_slug: eventSlug,
      source_prediction_public_id: sourcePredictionId ?? null,
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!hydrated) return;
    savePrediction(eventSlug, selectedIds);

    if (selectedIds.length >= requiredCount && !hasFiredCompletion.current) {
      hasFiredCompletion.current = true;
      track("prediction_completed", { event_slug: eventSlug, selected_count: selectedIds.length });
    }
    if (selectedIds.length < requiredCount) {
      hasFiredCompletion.current = false;
    }
  }, [selectedIds, eventSlug, requiredCount, hydrated]);

  function handleToggle(id: string) {
    setSelectedIds((current) => {
      if (current.includes(id)) {
        track("participant_removed", { event_slug: eventSlug, selected_count: current.length - 1 });
        return current.filter((selectedId) => selectedId !== id);
      }
      if (current.length >= requiredCount) return current;

      track("participant_selected", { event_slug: eventSlug, position: current.length + 1 });
      return [...current, id];
    });
  }

  function handleRemove(id: string) {
    setSelectedIds((current) => {
      track("participant_removed", { event_slug: eventSlug, selected_count: current.length - 1 });
      return current.filter((selectedId) => selectedId !== id);
    });
  }

  function swap(array: string[], i: number, j: number): string[] {
    const next = [...array];
    const a = next[i];
    const b = next[j];
    if (a === undefined || b === undefined) return array;
    next[i] = b;
    next[j] = a;
    return next;
  }

  function handleMoveUp(index: number) {
    if (index === 0) return;
    setSelectedIds((current) => {
      track("prediction_reordered", { event_slug: eventSlug });
      return swap(current, index - 1, index);
    });
  }

  function handleMoveDown(index: number) {
    setSelectedIds((current) => {
      if (index === current.length - 1) return current;
      track("prediction_reordered", { event_slug: eventSlug });
      return swap(current, index, index + 1);
    });
  }

  const rankedParticipants = selectedIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  const isComplete = selectedIds.length >= requiredCount;
  const { dict } = useI18n();
  const t = dict.builder;

  return (
    <div>
      {/* Compact sticky progress — one line, not a large banner. */}
      <div className="sticky top-0 z-10 w-full border-b border-border bg-background/95 backdrop-blur">
        <div className="mx-auto flex max-w-content items-center justify-between px-6 py-3">
          <span className="text-xs font-medium uppercase tracking-[0.15em] text-text-secondary">
            {fmt(t.selectedCount, { count: selectedIds.length, total: requiredCount })}
          </span>
          <div className="h-1 w-24 overflow-hidden rounded-full bg-surface-raised">
            <div
              className="h-full bg-accent transition-[width]"
              style={{ width: `${(selectedIds.length / requiredCount) * 100}%` }}
            />
          </div>
        </div>
      </div>

      <div className="mx-auto max-w-content px-6 py-8 lg:grid lg:grid-cols-[380px_1fr] lg:gap-10">
        <section aria-label={fmt(t.yourTop, { n: requiredCount })} className="lg:sticky lg:top-20 lg:self-start">
          <h2 className="font-display text-lg text-text-primary">{fmt(t.yourTop, { n: requiredCount })}</h2>
          <div className="mt-3">
            <TopTenList
              rankedParticipants={rankedParticipants}
              requiredCount={requiredCount}
              onRemove={handleRemove}
              onMoveUp={handleMoveUp}
              onMoveDown={handleMoveDown}
            />
          </div>

          {isComplete ? (
            <div className="mt-6 rounded border border-accent/40 bg-accent/10 p-4">
              <p className="font-display text-base text-text-primary">{fmt(t.topReady, { n: requiredCount })}</p>
              <Link
                href={`/predict/${eventSlug}/review`}
                className="group mt-3 inline-flex items-center gap-2 rounded bg-accent px-5 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
              >
                {t.reviewCta}
                <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
              </Link>
            </div>
          ) : null}
        </section>

        <section aria-label={t.allContestants} className="mt-10 lg:mt-0">
          <h2 className="font-display text-lg text-text-primary">{t.allContestants}</h2>
          <div className="mt-3">
            <ParticipantBrowser
              participants={participants}
              selectedIds={new Set(selectedIds)}
              atMax={isComplete}
              onToggle={handleToggle}
            />
          </div>
        </section>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PredictionBuilder.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PredictionBuilder.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PredictionBuilder.tsx"
}

try {
    $path = "src\components\prediction\PredictionCardMarkup.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Participant } from "@/types/participant";
import { getPredictorCountryName } from "@/lib/countries";
import { getDictionary } from "@/lib/i18n";
import type { Locale } from "@/lib/locale";

export interface CardData {
  eventName: string;
  nickname: string | null;
  countryCode: string | null;
  isDemo: boolean;
  rankedParticipants: Participant[];
  /** i18n v1 — presentation language only; ranking/identity never change. */
  locale?: Locale;
}

const INK = "#141318";
const SURFACE = "#232028";
const ACCENT = "#A6342E";
const ACCENT_STRONG = "#C44C42";
const TEXT_PRIMARY = "#F2EFE6";
const TEXT_MUTED = "#A39FB0";

/**
 * `next/og` (Satori under the hood) does not render Unicode flag
 * emoji reliably — confirmed by generating and visually inspecting
 * the actual output, which showed blank space where a flag should be.
 * Plain country-name text is the robust substitute: no emoji font
 * dependency, no network fetch, renders identically everywhere — and,
 * per Cohort 0 feedback, is what users actually asked for (a bare ISO
 * code like "VE" wasn't recognizable on its own). `maxWidth` + the
 * overflow/ellipsis trio keeps a long country name from breaking this
 * fixed-size image's layout.
 */
function CountryBadge({ name, fontSize, maxWidth }: { name: string; fontSize: number; maxWidth: number }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "flex-end",
        fontSize,
        fontWeight: 700,
        color: TEXT_MUTED,
        maxWidth,
        overflow: "hidden",
        whiteSpace: "nowrap",
        textOverflow: "ellipsis",
      }}
    >
      {name}
    </div>
  );
}

/**
 * Shared visual system for both the Story (1080x1920) and Post
 * (1080x1350) formats — same tokens as the product UI (ink
 * background, oxblood accent) but bolder/bigger, per the approved
 * "energetic / shareable" direction for social cards. `height` also
 * drives a scale factor so the taller Story format fills its frame
 * instead of leaving a dead zone below a 10-item list.
 */
export function PredictionCardMarkup({
  data,
  width,
  height,
  siteDomain,
}: {
  data: CardData;
  width: number;
  height: number;
  siteDomain: string;
}) {
  const scale = Math.min(1.32, Math.max(1, height / 1350));
  const top3 = data.rankedParticipants.slice(0, 3);
  const rest = data.rankedParticipants.slice(3, 10);
  const locale = data.locale ?? "en";
  const sd = getDictionary(locale).share;
  const predictorCountryName = getPredictorCountryName(data.countryCode, locale);
  const whoBy = data.nickname
    ? `${data.nickname}${predictorCountryName ? ` · ${predictorCountryName}` : ""}`
    : predictorCountryName;

  return (
    <div
      style={{
        width,
        height,
        display: "flex",
        flexDirection: "column",
        backgroundColor: INK,
        fontFamily: "Georgia, serif",
        padding: `${64 * scale}px 56px`,
        color: TEXT_PRIMARY,
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", flexDirection: "column" }}>
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div style={{ display: "flex", fontSize: 28, letterSpacing: 4, color: TEXT_MUTED }}>
            FOUCH
          </div>
          {data.isDemo ? (
            <div
              style={{
                display: "flex",
                fontSize: 22,
                color: TEXT_MUTED,
                border: `1px solid ${TEXT_MUTED}`,
                borderRadius: 6,
                padding: "6px 14px",
              }}
            >
              {sd.cardDemo}
            </div>
          ) : null}
        </div>
        <div style={{ display: "flex", fontSize: 46 * scale, fontWeight: 700, marginTop: 18 }}>
          {sd.cardHeadline}
        </div>
        <div style={{ display: "flex", fontSize: 30, color: TEXT_MUTED, marginTop: 8 }}>
          {data.eventName}
        </div>
        {whoBy ? (
          <div
            style={{
              display: "flex",
              fontSize: 28,
              color: ACCENT_STRONG,
              marginTop: 10,
              maxWidth: width - 112,
              overflow: "hidden",
              whiteSpace: "nowrap",
              textOverflow: "ellipsis",
            }}
          >
            {whoBy}
          </div>
        ) : null}
      </div>

      {/* Top 3 — big, energetic blocks */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: 44 * scale, gap: 18 * scale }}>
        {top3.map((participant, index) => (
          <div
            key={participant.id}
            style={{
              display: "flex",
              alignItems: "center",
              backgroundColor: index === 0 ? ACCENT : SURFACE,
              borderRadius: 20,
              padding: `${26 * scale}px 32px`,
            }}
          >
            <div style={{ display: "flex", fontSize: 64 * scale, fontWeight: 700, width: 110 }}>
              {index + 1}
            </div>
            <div style={{ display: "flex", fontSize: 40 * scale, fontWeight: 700, flex: 1 }}>
              {participant.displayName}
            </div>
            <CountryBadge name={participant.countryName} fontSize={26 * scale} maxWidth={230} />
          </div>
        ))}
      </div>

      {/* 4-10 — compact list */}
      {rest.length > 0 ? (
        <div style={{ display: "flex", flexDirection: "column", marginTop: 26 * scale, gap: 12 * scale }}>
          {rest.map((participant, index) => (
            <div key={participant.id} style={{ display: "flex", alignItems: "center", fontSize: 27 * scale }}>
              <div style={{ display: "flex", width: 60, color: TEXT_MUTED }}>{index + 4}</div>
              <div style={{ display: "flex", flex: 1, color: TEXT_PRIMARY }}>{participant.displayName}</div>
              <CountryBadge name={participant.countryName} fontSize={20} maxWidth={170} />
            </div>
          ))}
        </div>
      ) : null}

      {/* Footer */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: "auto" }}>
        <div style={{ display: "flex", fontSize: 34, fontWeight: 700 }}>{sd.cardFooter}</div>
        <div style={{ display: "flex", fontSize: 24, color: TEXT_MUTED, marginTop: 6 }}>
          {siteDomain}
        </div>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\PredictionCardMarkup.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\PredictionCardMarkup.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\PredictionCardMarkup.tsx"
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
import { Pencil } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { siteUrl } from "@/lib/site";
import { formatEventLocalLockTime } from "@/lib/event-time-display";
import type { Participant } from "@/types/participant";
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
          </li>
        ))}
      </ol>

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

      {youVsTheWorld}

      {yourCrowdChanged}

      {/* Pre-result: original prediction sharing stays primary and sits
          right before the "Make your Top 10" CTA, unchanged from Sprint 2/3.
          Post-result: it becomes a secondary, de-emphasized block, per the
          hierarchy in Sprint 4.1's brief (Result Card is the stronger
          social object once scoring exists). */}
      {!hasResult ? originalPredictionShare : null}

      <Link
        href={`/predict/${eventSlug}?from=${publicId}`}
        onClick={() => track("public_prediction_cta_clicked", { event_slug: eventSlug })}
        className="mt-10 inline-flex items-center justify-center rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        {pt.makeYourTop}
      </Link>

      {hasResult ? originalPredictionShare : null}
    </div>
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
    $path = "src\components\prediction\ReviewContent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { Pencil } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import { track } from "@/lib/analytics";
import { captureUtmSource } from "@/lib/attribution";
import { loadPrediction, clearPrediction } from "@/lib/prediction-storage";
import { getDeviceToken } from "@/lib/device-token";
import { checkExistingSubmission } from "@/app/predict/[slug]/actions";
import {
  startEmailVerification,
  verifyEmailAndLockPrediction,
  retryLockWithVerifiedSession,
  type VerifyAndLockResult,
} from "@/app/predict/[slug]/verify-actions";
import type { Participant } from "@/types/participant";
import { SubmitPanel } from "./SubmitPanel";
import { EmailStep } from "./EmailStep";
import { OtpStep } from "./OtpStep";
import { useI18n } from "@/components/I18nProvider";
import { fmt } from "@/lib/i18n";
import { translateServerError } from "@/lib/server-error-i18n";

type Step = "review" | "email" | "otp";

/**
 * Beta Hardening 0.2 Phase C — GATE 1 implementation. This component
 * now runs the full email-OTP verified-lock flow client-side. It is
 * fully wired and tested, but production still has the old
 * `predictions_event_device_unique` constraint active — deploying
 * this to production before that constraint is dropped (Gate 2,
 * founder-approved cutover) would risk incorrectly blocking two
 * different verified people sharing a device. See
 * FOUCH_BETA_HARDENING_02_PHASE_C.md before deploying.
 */
export function ReviewContent({
  eventSlug,
  participants,
  requiredCount,
}: {
  eventSlug: string;
  participants: Participant[];
  requiredCount: number;
}) {
  const { locale, dict } = useI18n();
  const rt = dict.review;
  const router = useRouter();
  const [rankedIds, setRankedIds] = useState<string[] | null>(null);
  const [checkingExisting, setCheckingExisting] = useState(true);

  const [step, setStep] = useState<Step>("review");
  const [pendingNickname, setPendingNickname] = useState("");
  const [pendingCountryCode, setPendingCountryCode] = useState("");

  const [emailSubmitting, setEmailSubmitting] = useState(false);
  const [emailError, setEmailError] = useState<string | null>(null);
  const [email, setEmail] = useState("");

  const [otpSubmitting, setOtpSubmitting] = useState(false);
  const [otpError, setOtpError] = useState<string | null>(null);
  const [wrongAttemptCount, setWrongAttemptCount] = useState(0);
  /** Present only after OTP verification succeeded but the lock
   * insert failed transiently — enables a no-new-OTP retry. */
  const [accessTokenForRetry, setAccessTokenForRetry] = useState<string | null>(null);

  useEffect(() => {
    const validIds = new Set(participants.map((participant) => participant.id));
    setRankedIds(loadPrediction(eventSlug, validIds));

    // A submitted prediction is immutable — if this device already has
    // one for this event, go straight to it instead of showing the
    // submit form again.
    const deviceToken = getDeviceToken();
    checkExistingSubmission(eventSlug, deviceToken)
      .then((existing) => {
        if (existing) {
          router.replace(`/p/${existing.publicId}`);
          return;
        }
        setCheckingExisting(false);
      })
      .catch(() => setCheckingExisting(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const participantsById = new Map(participants.map((participant) => [participant.id, participant]));
  const ranked = (rankedIds ?? [])
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  useEffect(() => {
    if (rankedIds !== null && ranked.length >= requiredCount) {
      track("prediction_reviewed", { event_slug: eventSlug });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rankedIds]);

  function handleProceedToEmail(nickname: string, countryCode: string) {
    setPendingNickname(nickname);
    setPendingCountryCode(countryCode);
    setStep("email");
  }

  async function handleSendCode(targetEmail: string) {
    if (emailSubmitting) return;
    setEmailSubmitting(true);
    setEmailError(null);
    track("verification_started", { event_slug: eventSlug });

    let result;
    try {
      result = await startEmailVerification(targetEmail);
    } catch {
      setEmailError("We couldn't send a code — try again in a moment.");
      setEmailSubmitting(false);
      return;
    }

    setEmailSubmitting(false);

    if (!result.success) {
      setEmailError(result.error);
      return;
    }

    track("verification_sent", { event_slug: eventSlug });
    setEmail(targetEmail);
    setOtpError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
    setStep("otp");
  }

  function handleLockResult(result: VerifyAndLockResult) {
    if (result.success) {
      track("verification_completed", { event_slug: eventSlug });
      if (result.duplicateDeviceSignal) {
        track("duplicate_prediction_attempt", { event_slug: eventSlug });
      }
      const utmSource = captureUtmSource();
      track("prediction_submitted", {
        event_slug: eventSlug,
        ...(utmSource ? { utm_source: utmSource } : {}),
      });
      clearPrediction(eventSlug);
      router.push(`/p/${result.publicId}?new=1`);
      return;
    }

    track("verification_failed", { event_slug: eventSlug, failure_reason: result.failureReason });
    setOtpError(result.error);
    setAccessTokenForRetry(result.accessToken ?? null);
    if (result.failureReason === "invalid_code") {
      setWrongAttemptCount((count) => count + 1);
    }
  }

  async function handleVerify(code: string) {
    if (otpSubmitting) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndLockResult;
    try {
      result = await verifyEmailAndLockPrediction(email, code, {
        eventSlug,
        participantIds: rankedIds ?? [],
        nickname: pendingNickname.trim() || undefined,
        countryCode: pendingCountryCode || undefined,
        deviceToken: getDeviceToken(),
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't verify your code — try again.");
      return;
    }

    setOtpSubmitting(false);
    handleLockResult(result);
  }

  async function handleRetryLock() {
    if (otpSubmitting || !accessTokenForRetry) return;
    setOtpSubmitting(true);
    setOtpError(null);

    let result: VerifyAndLockResult;
    try {
      result = await retryLockWithVerifiedSession(accessTokenForRetry, {
        eventSlug,
        participantIds: rankedIds ?? [],
        nickname: pendingNickname.trim() || undefined,
        countryCode: pendingCountryCode || undefined,
        deviceToken: getDeviceToken(),
      });
    } catch {
      setOtpSubmitting(false);
      setOtpError("We couldn't lock your prediction. Your Top 10 is still saved — try again.");
      return;
    }

    setOtpSubmitting(false);
    handleLockResult(result);
  }

  function handleUseDifferentEmail() {
    setStep("email");
    setEmail("");
    setOtpError(null);
    setEmailError(null);
    setWrongAttemptCount(0);
    setAccessTokenForRetry(null);
  }

  // Avoid a flash of the form before we know whether this device
  // already has a locked-in prediction.
  if (rankedIds === null || checkingExisting) return null;

  if (ranked.length < requiredCount) {
    return (
      <div>
        <p className="text-text-secondary">
          {rt.incomplete}
        </p>
        <Link
          href={`/predict/${eventSlug}`}
          className="mt-4 inline-flex items-center gap-2 rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
        >
          {fmt(rt.buildCta, { n: requiredCount })}
        </Link>
      </div>
    );
  }

  return (
    <div>
      <ol className="space-y-1.5">
        {ranked.map((participant, index) => (
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
          </li>
        ))}
      </ol>

      {step === "review" ? (
        <Link
          href={`/predict/${eventSlug}`}
          className="mt-6 inline-flex items-center gap-2 rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          <Pencil className="h-4 w-4" aria-hidden />
          {fmt(rt.editCta, { n: requiredCount })}
        </Link>
      ) : null}

      {step === "review" ? (
        <SubmitPanel
          requiredCount={requiredCount}
          submitting={false}
          errorMessage={null}
          onSubmit={handleProceedToEmail}
        />
      ) : null}

      {step === "email" ? (
        <EmailStep mode="create" submitting={emailSubmitting} errorMessage={emailError} onSendCode={handleSendCode} />
      ) : null}

      {step === "otp" && accessTokenForRetry ? (
        <div className="mt-8 border-t border-border pt-6">
          {otpError ? (
            <p className="text-sm text-accent-strong" role="alert" aria-live="polite">
              {translateServerError(otpError, locale)}
            </p>
          ) : null}
          <button
            type="button"
            disabled={otpSubmitting}
            onClick={handleRetryLock}
            className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
          >
            {otpSubmitting ? rt.tryingAgain : rt.tryAgain}
          </button>
        </div>
      ) : step === "otp" ? (
        <OtpStep
          email={email}
          submitting={otpSubmitting}
          errorMessage={otpError}
          wrongAttemptCount={wrongAttemptCount}
          onVerify={handleVerify}
          onResend={() => handleSendCode(email)}
          onUseDifferentEmail={handleUseDifferentEmail}
        />
      ) : null}
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ReviewContent.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ReviewContent.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ReviewContent.tsx"
}

try {
    $path = "src\components\prediction\ShareActions.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useEffect, useState } from "react";
import { Share2, Download, Link2, Check, Camera } from "lucide-react";
import { track } from "@/lib/analytics";
import type { FouchAnalyticsEvent } from "@/lib/analytics";
import { useI18n } from "@/components/I18nProvider";
import {
  getDeviceType,
  resolveInstagramShareMethod,
  buildInstagramStoryShareProperties,
} from "@/lib/instagram-story-share";

interface ShareEventNames {
  share: FouchAnalyticsEvent;
  nativeOpened: FouchAnalyticsEvent | null;
  download: FouchAnalyticsEvent;
  copyLink: FouchAnalyticsEvent;
}

const EVENT_NAMES: Record<"prediction" | "result", ShareEventNames> = {
  prediction: {
    share: "share_clicked",
    nativeOpened: "native_share_opened",
    download: "image_downloaded",
    copyLink: "copy_link_clicked",
  },
  result: {
    share: "result_card_shared",
    nativeOpened: null,
    download: "result_card_saved",
    copyLink: "result_share_link_copied",
  },
};

/** Triggers a browser download of a Blob without navigating away —
 * the same mechanism the browser's own download attribute uses, just
 * invoked programmatically since Instagram Story's file comes from a
 * fetch(), not a plain <a href> the user clicked. */
function downloadBlob(blob: Blob, filename: string) {
  const url = URL.createObjectURL(blob);
  const link = document.createElement("a");
  link.href = url;
  link.download = filename;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

export function ShareActions({
  eventSlug,
  publicId,
  publicUrl,
  storyCardUrl,
  postCardUrl,
  variant = "prediction",
}: {
  eventSlug: string;
  /** The prediction's public_id — already public (it's the URL slug)
   * — used only as an analytics property, never a private/internal id. */
  publicId: string;
  publicUrl: string;
  storyCardUrl: string;
  postCardUrl: string;
  /** Defaults to "prediction" — the existing, unchanged behavior. Pass
   * "result" to reuse this exact component for the post-result Result
   * Card, firing the distinct result_* analytics events instead. */
  variant?: "prediction" | "result";
}) {
  const [format, setFormat] = useState<"story" | "post">("story");
  const [copied, setCopied] = useState(false);
  const [canNativeShare, setCanNativeShare] = useState(false);
  const [instagramState, setInstagramState] = useState<"idle" | "generating" | "ready">("idle");
  const [instagramDeviceType, setInstagramDeviceType] = useState<"mobile" | "desktop">("desktop");
  const events = EVENT_NAMES[variant];
  const { dict } = useI18n();
  const st = dict.share;

  // navigator.share only exists client-side — checked once after mount
  // so server and initial client render stay consistent (no
  // hydration mismatch).
  useEffect(() => {
    if (typeof navigator !== "undefined" && "share" in navigator) {
      setCanNativeShare(true);
    }
  }, []);

  const activeCardUrl = format === "story" ? storyCardUrl : postCardUrl;

  async function handleShare() {
    track(events.share, { event_slug: eventSlug, share_method: "native" });
    if (!canNativeShare) return;

    try {
      await navigator.share({ title: st.shareTitle, url: publicUrl });
      if (events.nativeOpened) track(events.nativeOpened, { event_slug: eventSlug });
    } catch {
      // User cancelled the share sheet — not an error worth surfacing.
    }
  }

  async function handleCopyLink() {
    track(events.copyLink, { event_slug: eventSlug });
    try {
      await navigator.clipboard.writeText(publicUrl);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      // Clipboard API unavailable — the link is still visible/selectable
      // in the UI as a fallback (see the public page).
    }
  }

  function handleDownload() {
    track(events.download, { event_slug: eventSlug, share_method: format });
  }

  /**
   * Instagram Story is deliberately NOT the generic handleShare above.
   * It always targets the 9:16 Story image regardless of the
   * Story/Post toggle above, and never opens the generic OS share
   * sheet without the image file attached — see brief §1/§3/§4. We
   * never claim Instagram specifically will appear; the OS decides
   * what shows up in its own share sheet.
   */
  async function handleInstagramStory() {
    const deviceType = getDeviceType(typeof navigator !== "undefined" ? navigator.userAgent : "");
    setInstagramDeviceType(deviceType);
    setInstagramState("generating");

    let blob: Blob;
    try {
      const response = await fetch(storyCardUrl);
      blob = await response.blob();
    } catch {
      setInstagramState("idle");
      return;
    }

    const file = new File([blob], "fouch-story.png", { type: "image/png" });
    const canShareFile =
      typeof navigator !== "undefined" &&
      "share" in navigator &&
      "canShare" in navigator &&
      navigator.canShare({ files: [file] });

    const shareMethod = resolveInstagramShareMethod(canShareFile, deviceType);
    const properties = buildInstagramStoryShareProperties({
      eventSlug,
      predictionPublicId: publicId,
      deviceType,
      shareMethod,
    });

    if (shareMethod === "native_share") {
      try {
        await navigator.share({ files: [file], url: publicUrl, title: st.shareTitle });
        track("instagram_story_clicked", { ...properties });
        // Brief §6: Instagram Story always fires the literal
        // share_clicked signal (never events.share, which for the
        // "result" variant is result_card_shared) — this is a
        // dedicated, variant-independent share-intent signal.
        track("share_clicked", { event_slug: eventSlug, share_channel: "instagram_story" });
      } catch {
        // User cancelled the native share sheet — not an error.
      }
      setInstagramState("idle");
      return;
    }

    downloadBlob(blob, "fouch-story.png");
    track("instagram_story_clicked", { ...properties });
    track("share_clicked", { event_slug: eventSlug, share_channel: "instagram_story" });
    setInstagramState("ready");
  }

  return (
    <div>
      <div className="inline-flex rounded border border-border p-1 text-sm">
        <button
          type="button"
          onClick={() => setFormat("story")}
          className={`rounded px-3 py-1.5 transition-colors ${
            format === "story" ? "bg-surface-raised text-text-primary" : "text-text-muted"
          }`}
        >
          {st.story}
        </button>
        <button
          type="button"
          onClick={() => setFormat("post")}
          className={`rounded px-3 py-1.5 transition-colors ${
            format === "post" ? "bg-surface-raised text-text-primary" : "text-text-muted"
          }`}
        >
          {st.post}
        </button>
      </div>

      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={activeCardUrl}
        alt={variant === "result" ? st.resultCardAlt : st.predictionCardAlt}
        className="mt-3 w-full max-w-xs rounded border border-border"
      />

      {instagramState === "ready" ? (
        <div className="mt-4 rounded border border-border-strong p-4">
          <p className="text-sm font-medium uppercase tracking-wide text-text-primary">
            {st.storyReady}
          </p>
          <p className="mt-2 text-sm text-text-secondary">
            {instagramDeviceType === "mobile"
              ? st.storyReadyMobile
              : st.storyReadyDesktop}
          </p>
          <button
            type="button"
            onClick={handleCopyLink}
            className="mt-3 inline-flex items-center gap-2 rounded border border-border-strong px-4 py-2.5 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            {copied ? <Check className="h-4 w-4" aria-hidden /> : <Link2 className="h-4 w-4" aria-hidden />}
            {copied ? st.copied : st.copyPredictionLink}
          </button>
        </div>
      ) : (
        <div className="mt-4 flex flex-wrap gap-2">
          <button
            type="button"
            onClick={handleInstagramStory}
            disabled={instagramState === "generating"}
            className="inline-flex items-center gap-2 rounded bg-accent px-5 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60"
          >
            <Camera className="h-4 w-4" aria-hidden />
            {instagramState === "generating" ? st.preparing : st.instagramStory}
          </button>

          {canNativeShare ? (
            <button
              type="button"
              onClick={handleShare}
              className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
            >
              <Share2 className="h-4 w-4" aria-hidden />
              {st.share}
            </button>
          ) : null}

          <a
            href={activeCardUrl}
            download={`fouch-${variant}-${format}.png`}
            onClick={handleDownload}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            <Download className="h-4 w-4" aria-hidden />
            {st.saveImage}
          </a>

          <button
            type="button"
            onClick={handleCopyLink}
            className="inline-flex items-center gap-2 rounded border border-border-strong px-5 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
          >
            {copied ? <Check className="h-4 w-4" aria-hidden /> : <Link2 className="h-4 w-4" aria-hidden />}
            {copied ? st.copied : st.copyLink}
          </button>
        </div>
      )}
    </div>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ShareActions.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ShareActions.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ShareActions.tsx"
}

try {
    $path = "src\components\prediction\ShareYourCallCta.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { track } from "@/lib/analytics";
import { useI18n } from "@/components/I18nProvider";

export function ShareYourCallCta({ standsOut = false }: { standsOut?: boolean }) {
  const { dict } = useI18n();
  return (
    <div className="mt-2">
      <p className="font-display text-lg text-text-primary">
        {standsOut ? dict.community.shareStandsOut : dict.community.shareWrong}
      </p>
      <Link
        href="#share"
        onClick={() => track("community_share_clicked")}
        className="group mt-3 inline-flex items-center gap-2 rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
      >
        {dict.community.shareCta}
        <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
      </Link>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\ShareYourCallCta.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\ShareYourCallCta.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\ShareYourCallCta.tsx"
}

try {
    $path = "src\components\prediction\SubmitPanel.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { useState } from "react";
import { PREDICTOR_COUNTRIES, getLocalizedCountryName } from "@/lib/countries";
import { useI18n } from "@/components/I18nProvider";
import { fmt } from "@/lib/i18n";
import { translateServerError } from "@/lib/server-error-i18n";

export function SubmitPanel({
  requiredCount,
  submitting,
  errorMessage,
  onSubmit,
}: {
  requiredCount: number;
  submitting: boolean;
  errorMessage: string | null;
  onSubmit: (nickname: string, countryCode: string) => void;
}) {
  const [nickname, setNickname] = useState("");
  const [countryCode, setCountryCode] = useState("");
  const { locale, dict } = useI18n();
  const t = dict.review;
  const countryOptions = PREDICTOR_COUNTRIES.map((country) => ({
    code: country.code,
    name: getLocalizedCountryName(country.code, country.name, locale),
  })).sort((a, b) => a.name.localeCompare(b.name, locale));

  return (
    <div className="mt-8 border-t border-border pt-6">
      <div className="grid gap-4 sm:grid-cols-2">
        <label className="block">
          <span className="text-sm text-text-secondary">{t.nickname}</span>
          <input
            type="text"
            value={nickname}
            onChange={(event) => setNickname(event.target.value)}
            maxLength={24}
            placeholder={t.optional}
            className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary placeholder:text-text-muted focus:border-accent"
          />
        </label>

        <label className="block">
          <span className="text-sm text-text-secondary">{t.country}</span>
          <select
            value={countryCode}
            onChange={(event) => setCountryCode(event.target.value)}
            className="mt-1.5 w-full rounded border border-border bg-surface px-3 py-2.5 text-sm text-text-primary focus:border-accent"
          >
            <option value="">{t.optional}</option>
            {countryOptions.map((country) => (
              <option key={country.code} value={country.code}>
                {country.name}
              </option>
            ))}
          </select>
        </label>
      </div>

      <p className="mt-2 text-xs text-text-muted">
        {t.optionalNote}
      </p>

      {errorMessage ? (
        <p className="mt-3 text-sm text-accent-strong" role="alert">
          {translateServerError(errorMessage, locale)}
        </p>
      ) : null}

      <button
        type="button"
        disabled={submitting}
        onClick={() => onSubmit(nickname, countryCode)}
        className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
      >
        {submitting ? t.saving : fmt(t.saveCta, { n: requiredCount })}
      </button>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\SubmitPanel.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\SubmitPanel.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\SubmitPanel.tsx"
}

try {
    $path = "src\components\prediction\TopTenList.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { ChevronUp, ChevronDown, X } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import type { Participant } from "@/types/participant";
import { useI18n } from "@/components/I18nProvider";
import { fmt } from "@/lib/i18n";

export function TopTenList({
  rankedParticipants,
  requiredCount,
  onRemove,
  onMoveUp,
  onMoveDown,
}: {
  rankedParticipants: Participant[];
  requiredCount: number;
  onRemove: (id: string) => void;
  onMoveUp: (index: number) => void;
  onMoveDown: (index: number) => void;
}) {
  const { dict } = useI18n();
  const t = dict.builder;

  if (rankedParticipants.length === 0) {
    return (
      <p className="rounded border border-dashed border-border-strong px-4 py-6 text-sm text-text-muted">
        {t.emptyList}
      </p>
    );
  }

  return (
    <ol className="space-y-1.5">
      {rankedParticipants.map((participant, index) => (
        <li
          key={participant.id}
          className="flex items-center gap-3 rounded border border-border bg-surface px-3 py-2.5"
        >
          <span className="font-display w-6 shrink-0 text-sm text-accent-strong">
            {String(index + 1).padStart(2, "0")}
          </span>
          <CountryFlag countryCode={participant.countryCode} className="text-lg" />
          <span className="flex-1 truncate text-sm text-text-primary">
            {participant.displayName} <span className="text-text-muted">· {participant.countryName}</span>
          </span>
          {!participant.isActive ? (
            <span
              className="shrink-0 rounded border border-accent-strong px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-accent-strong"
              title={t.replaceTitle}
            >
              {t.replaceBadge}
            </span>
          ) : null}

          <div className="flex items-center gap-0.5">
            <button
              type="button"
              onClick={() => onMoveUp(index)}
              disabled={index === 0}
              aria-label={fmt(t.moveUpAria, { name: participant.displayName, pos: index + 1, total: requiredCount })}
              className="rounded p-2 text-text-secondary transition-colors hover:bg-surface-raised disabled:opacity-30"
            >
              <ChevronUp className="h-4 w-4" aria-hidden />
            </button>
            <button
              type="button"
              onClick={() => onMoveDown(index)}
              disabled={index === rankedParticipants.length - 1}
              aria-label={fmt(t.moveDownAria, { name: participant.displayName, pos: index + 1, total: requiredCount })}
              className="rounded p-2 text-text-secondary transition-colors hover:bg-surface-raised disabled:opacity-30"
            >
              <ChevronDown className="h-4 w-4" aria-hidden />
            </button>
            <button
              type="button"
              onClick={() => onRemove(participant.id)}
              aria-label={fmt(t.removeAria, { name: participant.displayName, total: requiredCount })}
              className="rounded p-2 text-text-secondary transition-colors hover:bg-surface-raised hover:text-accent-strong"
            >
              <X className="h-4 w-4" aria-hidden />
            </button>
          </div>
        </li>
      ))}
    </ol>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\TopTenList.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\TopTenList.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\TopTenList.tsx"
}

try {
    $path = "src\components\prediction\YouVsTheWorld.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { CountryFlag } from "@/components/CountryFlag";
import { getEntryNoun } from "@/lib/events";
import { getEligiblePredictionsForComparison, type PredictionRecord } from "@/lib/predictions-db";
import { resolveParticipantsByIds } from "@/lib/participants";
import {
  computeComparison,
  getSampleSizeBucket,
  getComparisonDisplayMode,
} from "@/lib/community-comparison";
import type { FouchEvent } from "@/types/event";
import { ShareYourCallCta } from "./ShareYourCallCta";
import { YouVsTheWorldTracker } from "./YouVsTheWorldTracker";
import { getI18n } from "@/lib/i18n-server";
import { fmt } from "@/lib/i18n";

function formatPct(pct: number): string {
  return `${Math.round(pct * 100)}%`;
}

/**
 * Sprint 3.1: for a small sample, "X of Y" is honest; a percentage
 * ("25%") implies more statistical weight than 1-of-4 actually
 * carries. Every place that shows a ratio goes through this one
 * function instead of each component deciding for itself.
 */
function formatRatio(count: number, population: number, mode: ReturnType<typeof getComparisonDisplayMode>): string {
  if (mode === "count") return `${count} OF ${population}`;
  return formatPct(count / population);
}

export async function YouVsTheWorld({
  prediction,
  event,
}: {
  prediction: PredictionRecord;
  event: FouchEvent;
}) {
  const eligible = await getEligiblePredictionsForComparison(event.slug, prediction.dataStatus);
  const comparison = computeComparison(prediction.rankedParticipantIds, eligible, prediction.id);
  const bucket = getSampleSizeBucket(comparison.population);
  const mode = getComparisonDisplayMode(comparison.population);
  const pluralNoun = getEntryNoun(event, true);
  const { locale, dict } = await getI18n();
  const ct = dict.community;
  // English keeps the event-configurable entry noun ("picks"); Spanish uses
  // a fixed natural noun (predicción/predicciones).
  const nounFor = (count: number) =>
    locale === "en"
      ? count === 1
        ? pluralNoun.slice(0, -1)
        : pluralNoun
      : count === 1
        ? ct.nounOne
        : ct.nounMany;

  // FOUCH 0.3B: resolves every participant id this section could
  // possibly render â€” the viewer's own winner pick AND whatever ids
  // appear in the community aggregate (sameWinner/boldestPick/
  // communityTop10) â€” regardless of current status. Any of those ids
  // could belong to someone else's prediction referencing a country
  // whose delegate has since become WITHDRAWN/REPLACED; this must
  // still resolve to a real name/country, never silently vanish.
  const idsToResolve = new Set<string>();
  if (comparison.sameWinner) idsToResolve.add(comparison.sameWinner.participantId);
  if (comparison.boldestPick) idsToResolve.add(comparison.boldestPick.participantId);
  for (const entry of comparison.communityTop10) idsToResolve.add(entry.participantId);

  const participantsById = await resolveParticipantsByIds(event.slug, Array.from(idsToResolve), locale);

  return (
    <section className="mt-12 border-t border-border pt-10">
      <YouVsTheWorldTracker
        eventSlug={event.slug}
        dataStatus={prediction.dataStatus}
        bucket={bucket}
        hasSameWinner={Boolean(comparison.sameWinner)}
        hasTop3Match={Boolean(comparison.top3Match)}
        hasBoldestPick={Boolean(comparison.boldestPick)}
        hasCommunityTop10={comparison.communityTop10.length > 0}
      />
      <p className="font-display text-2xl uppercase tracking-tight text-text-primary">
        {ct.youVsWorld}
      </p>

      {prediction.dataStatus === "demo" ? (
        <p className="mt-2 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          {fmt(ct.demoNote, { noun: locale === "en" ? pluralNoun : ct.nounMany })}
        </p>
      ) : null}

      {mode === "none" ? (
        <div className="mt-6">
          <p className="font-display text-xl text-text-primary">{ct.earlyTitle}</p>
          <p className="mt-1 text-sm text-text-secondary">{ct.earlyBody}</p>
          <ShareYourCallCta />
        </div>
      ) : (
        <div className="mt-8 space-y-10">
          {bucket === "1_4" ? (
            <p className="text-sm text-text-muted">
              {fmt(ct.forming, { n: comparison.population, noun: nounFor(comparison.population) })}
            </p>
          ) : null}
          {bucket === "5_9" ? (
            <p className="text-xs uppercase tracking-[0.15em] text-text-muted">
              {fmt(ct.earlySignal, { n: comparison.population })}
            </p>
          ) : null}

          {comparison.sameWinner ? (
            <div>
              <p className="font-display text-6xl text-accent-strong">
                {formatRatio(comparison.sameWinner.count, comparison.population, mode)}
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                {ct.sameWinner}
              </p>
              <p className="mt-2 text-text-primary">
                <CountryFlag
                  countryCode={participantsById.get(comparison.sameWinner.participantId)?.countryCode}
                />{" "}
                {participantsById.get(comparison.sameWinner.participantId)?.displayName}{" "}
                <span className="text-text-muted">
                  · {participantsById.get(comparison.sameWinner.participantId)?.countryName}
                </span>{" "}
                —{" "}
                {comparison.sameWinner.count === 0
                  ? ct.nobodySameCall
                  : mode === "count"
                    ? fmt(ct.sameWinnerCount, { count: comparison.sameWinner.count, total: comparison.population })
                    : fmt(ct.sameWinnerPct, { pct: formatPct(comparison.sameWinner.pct), total: comparison.population })}
              </p>
            </div>
          ) : null}

          {comparison.top3Match ? (
            <div>
              <p className="font-display text-6xl text-accent-strong">
                {comparison.top3Match.overlap} / 3
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                {ct.top3Match}
              </p>
              <p className="mt-2 text-text-primary">
                {fmt(ct.youShare, { n: comparison.top3Match.overlap })}
              </p>
            </div>
          ) : null}

          {comparison.boldestPick ? (
            <div>
              <p className="font-display text-4xl text-text-primary">
                <CountryFlag
                  countryCode={participantsById.get(comparison.boldestPick.participantId)?.countryCode}
                />{" "}
                {participantsById.get(comparison.boldestPick.participantId)?.displayName}{" "}
                <span className="text-text-muted">
                  · {participantsById.get(comparison.boldestPick.participantId)?.countryName}
                </span>
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                {ct.boldest}
              </p>
              <p className="mt-2 text-text-primary">
                {mode === "count"
                  ? fmt(ct.boldestCount, { count: comparison.boldestPick.count, total: comparison.population })
                  : fmt(ct.boldestPct, { pct: formatPct(comparison.boldestPick.inclusionPct) })}
              </p>
            </div>
          ) : null}

          {comparison.communityTop10.length > 0 ? (
            <div>
              <p className="font-display text-xl text-text-primary">{ct.worldTop10}</p>
              <p className="mt-1 text-xs text-text-muted">
                {ct.worldTop10Hint}
              </p>
              <ol className="mt-4 space-y-1.5">
                {comparison.communityTop10.map((entry, index) => {
                  const participant = participantsById.get(entry.participantId);
                  if (!participant) return null;
                  return (
                    <li
                      key={entry.participantId}
                      className="flex items-center gap-3 rounded border border-border bg-surface px-4 py-2.5"
                    >
                      <span className="font-display w-7 shrink-0 text-sm text-accent-strong">
                        {String(index + 1).padStart(2, "0")}
                      </span>
                      <CountryFlag countryCode={participant.countryCode} />
                      <span className="flex-1 truncate text-sm text-text-primary">
                        {participant.displayName}{" "}
                        <span className="text-text-muted">· {participant.countryName}</span>
                      </span>
                      <span className="text-right text-xs text-text-muted">
                        {fmt(ct.picked, { ratio: formatRatio(entry.top10Count, comparison.population, mode) })}
                        <br />
                        {fmt(ct.avgPos, { n: entry.averagePosition.toFixed(1) })}
                      </span>
                    </li>
                  );
                })}
              </ol>
              <p className="mt-2 text-xs text-text-muted">
                {fmt(comparison.population === 1 ? ct.basedOnOne : ct.basedOnMany, { n: comparison.population })}
              </p>
            </div>
          ) : null}

          <ShareYourCallCta standsOut={Boolean(comparison.sameWinner && comparison.sameWinner.pct < 0.3)} />
        </div>
      )}
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\prediction\YouVsTheWorld.tsx"
} catch {
    Write-Host "FAILED: src\components\prediction\YouVsTheWorld.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\prediction\YouVsTheWorld.tsx"
}

try {
    $path = "src\components\scoring\FouchScore.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { getEntryNoun } from "@/lib/events";
import { resolveParticipantsByIds } from "@/lib/participants";
import { getPredictionScore } from "@/lib/scoring-service";
import { getOfficialResult } from "@/lib/results-db";
import { MIN_PERCENTILE_SAMPLE } from "@/lib/scoring";
import { siteUrl } from "@/lib/site";
import { CountryFlag } from "@/components/CountryFlag";
import type { PredictionRecord } from "@/lib/predictions-db";
import type { FouchEvent } from "@/types/event";
import { FouchScoreTracker } from "./FouchScoreTracker";
import { ShareActions } from "@/components/prediction/ShareActions";
import { TrackedLink } from "@/components/TrackedLink";
import { getI18n } from "@/lib/i18n-server";
import { fmt } from "@/lib/i18n";
import { localizePath } from "@/lib/locale";


/** "8.333..." -> "8.3", "25.0" -> "25" â€” one decimal, no trailing ".0". */
function formatPoints(value: number): string {
  const rounded = Math.round(value * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

/**
 * Renders nothing (returns null) when there's no official result yet â€”
 * the pre-result experience is unchanged, never a fabricated score.
 * Server Component: fetches + scores server-side, only the final
 * numbers reach the client (via the tracker's props, not raw data).
 *
 * Sprint 4.1: UI clarity only. Every number below comes straight from
 * the existing score engine's ScoreBreakdown â€” nothing here
 * recalculates or duplicates scoring logic.
 */
export async function FouchScore({
  prediction,
  event,
  publicId,
}: {
  prediction: PredictionRecord;
  event: FouchEvent;
  publicId: string;
}) {
  const { locale, dict } = await getI18n();
  const result = await getPredictionScore(
    prediction.id,
    prediction.rankedParticipantIds,
    event.slug,
    prediction.dataStatus,
  );
  if (!result) return null;

  // Re-reads the same official-result row already used inside
  // getPredictionScore, purely to display who the actual winner was â€”
  // no scoring logic is duplicated, only a read.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);

  // FOUCH 0.3B: resolves regardless of current participant status â€”
  // both the user's own historical winner pick and the official
  // result's winner id must still render even if that country's
  // delegate has since become WITHDRAWN/REPLACED.
  const idsToResolve = new Set<string>();
  if (prediction.rankedParticipantIds[0]) idsToResolve.add(prediction.rankedParticipantIds[0]);
  if (official) idsToResolve.add(official.winner);

  const participantsById = await resolveParticipantsByIds(event.slug, Array.from(idsToResolve), locale);
  const userWinnerPick = prediction.rankedParticipantIds[0]
    ? participantsById.get(prediction.rankedParticipantIds[0])
    : undefined;
  const actualWinner = official ? participantsById.get(official.winner) : undefined;
  const pluralNoun = getEntryNoun(event, true);
  const st = dict.score;
  const { breakdown, percentile } = result;
  const { winner, podium, top5, top10, ranking } = breakdown.components;

  return (
    <section className="mt-12 border-t border-border pt-10">
      <FouchScoreTracker
        eventSlug={event.slug}
        scoreBand={breakdown.band}
        percentileAvailable={percentile.percentile !== null}
        dataStatus={prediction.dataStatus}
      />

      <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">{st.title}</p>

      {prediction.dataStatus === "demo" ? (
        <p className="mt-2 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          {st.demoResult}
        </p>
      ) : null}

      <p className="mt-3 font-display text-7xl text-accent-strong">{breakdown.displayScore}</p>
      <p className="mt-1 font-display text-2xl uppercase tracking-tight text-text-primary">
        {st.bands[breakdown.band]}
      </p>

      {percentile.percentile !== null ? (
        <p className="mt-2 text-sm text-text-secondary">
          {fmt(st.beat, {
            pct: Math.round(percentile.percentile),
            noun: locale === "en" ? (pluralNoun === "picks" ? "predictions" : pluralNoun) : "predicciones",
            n: percentile.population,
          })}
        </p>
      ) : (
        <p className="mt-2 text-xs text-text-muted">
          {fmt(st.worldUnlocks, { n: MIN_PERCENTILE_SAMPLE })}
        </p>
      )}

      <dl className="mt-6 space-y-3 text-sm">
        <div className="border-b border-border pb-3">
          <dt className="flex items-center justify-between">
            <span className="text-text-secondary">{st.winner}</span>
            <span className="text-text-muted">{formatPoints(winner.earned)} / {winner.max}</span>
          </dt>
          <dd className="mt-2">
            {winner.hit ? (
              <span className="inline-flex items-center gap-1.5 text-accent-strong">
                ✓
                {userWinnerPick ? (
                  <>
                    <CountryFlag countryCode={userWinnerPick.countryCode} />
                    {userWinnerPick.displayName}
                    <span className="text-text-muted">· {userWinnerPick.countryName}</span>
                  </>
                ) : (
                  st.correct
                )}
              </span>
            ) : (
              <div className="space-y-1 text-text-primary">
                <p className="flex items-center gap-1.5">
                  <span className="text-text-muted">{st.missed}</span>
                  {userWinnerPick ? (
                    <>
                      <CountryFlag countryCode={userWinnerPick.countryCode} />
                      {userWinnerPick.displayName}
                      <span className="text-text-muted">· {userWinnerPick.countryName}</span>
                    </>
                  ) : (
                    "—"
                  )}
                </p>
                {actualWinner ? (
                  <p className="flex items-center gap-1.5 text-text-secondary">
                    <span className="text-text-muted">{st.actual}</span>
                    <CountryFlag countryCode={actualWinner.countryCode} />
                    {actualWinner.displayName}
                    <span className="text-text-muted">· {actualWinner.countryName}</span>
                  </p>
                ) : null}
              </div>
            )}
          </dd>
        </div>

        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">{st.podium}</dt>
          <dd className="text-text-primary">
            {podium.hits} of {podium.total} · {formatPoints(podium.earned)} / {podium.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">{st.top5}</dt>
          <dd className="text-text-primary">
            {top5.hits} of {top5.total} · {formatPoints(top5.earned)} / {top5.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">{st.top10}</dt>
          <dd className="text-text-primary">
            {top10.hits} of {top10.total} · {formatPoints(top10.earned)} / {top10.max}
          </dd>
        </div>
        <div>
          <div className="flex items-center justify-between">
            <dt className="text-text-secondary">{st.ranking}</dt>
            <dd className="text-text-primary">
              {formatPoints(ranking.earned)} / {ranking.max}
            </dd>
          </div>
          <p className="mt-1 text-xs text-text-muted">{st.closeness}</p>
        </div>
      </dl>

      <div className="mt-8">
        <TrackedLink
          href={`/events/${event.slug}/leaderboard?from=${publicId}`}
          event="leaderboard_from_score_clicked"
          eventProperties={{ event_slug: event.slug }}
          className="inline-flex items-center justify-center rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          {st.seeFinish}
        </TrackedLink>
      </div>

      <div className="mt-8">
        <p className="font-display text-lg text-text-primary">{dict.share.shareResult}</p>
        <div className="mt-3">
          <ShareActions
            variant="result"
            eventSlug={event.slug}
            publicId={publicId}
            publicUrl={`${siteUrl}${localizePath(`/p/${publicId}`, locale)}`}
            storyCardUrl={`${localizePath(`/p/${publicId}`, locale)}/result-card/story`}
            postCardUrl={`${localizePath(`/p/${publicId}`, locale)}/result-card/post`}
          />
        </div>
      </div>
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\FouchScore.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\FouchScore.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\FouchScore.tsx"
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
      <CountryFlag countryCode={entry.countryCode} className={prominent ? "text-2xl" : "text-lg"} />
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
    $path = "src\components\scoring\ResultCardMarkup.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { ScoreBreakdown } from "@/types/scoring";
import { getPredictorCountryName } from "@/lib/countries";
import { getDictionary } from "@/lib/i18n";
import type { Locale } from "@/lib/locale";

export interface ResultCardData {
  /** i18n v1 — presentation language only. */
  locale?: Locale;
  eventName: string;
  nickname: string | null;
  countryCode: string | null;
  isDemo: boolean;
  breakdown: ScoreBreakdown;
  percentile: number | null;
}

const INK = "#141318";
const SURFACE = "#232028";
const ACCENT = "#A6342E";
const ACCENT_STRONG = "#C44C42";
const TEXT_PRIMARY = "#F2EFE6";
const TEXT_MUTED = "#A39FB0";


/**
 * Same visual system as PredictionCardMarkup — same tokens, same
 * "no Unicode emoji, no photography" constraints (Satori can't render
 * flag emoji reliably; see PredictionCardMarkup.tsx's note). This is a
 * separate component (not a reskin of PredictionCardMarkup) because its
 * content is fundamentally different — a result, not a pick list — but
 * it deliberately reuses every token and spacing decision so it reads
 * as unmistakably the same product.
 */
export function ResultCardMarkup({
  data,
  width,
  height,
  siteDomain,
}: {
  data: ResultCardData;
  width: number;
  height: number;
  siteDomain: string;
}) {
  const scale = Math.min(1.32, Math.max(1, height / 1350));
  const locale = data.locale ?? "en";
  const dict = getDictionary(locale);
  const sd = dict.share;
  const predictorCountryName = getPredictorCountryName(data.countryCode, locale);
  const whoBy = data.nickname
    ? `${data.nickname}${predictorCountryName ? ` · ${predictorCountryName}` : ""}`
    : predictorCountryName;
  const { breakdown } = data;

  return (
    <div
      style={{
        width,
        height,
        display: "flex",
        flexDirection: "column",
        backgroundColor: INK,
        fontFamily: "Georgia, serif",
        padding: `${64 * scale}px 56px`,
        color: TEXT_PRIMARY,
      }}
    >
      {/* Header */}
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
        <div style={{ display: "flex", fontSize: 28, letterSpacing: 4, color: TEXT_MUTED }}>FOUCH</div>
        {data.isDemo ? (
          <div
            style={{
              display: "flex",
              fontSize: 22,
              color: TEXT_MUTED,
              border: `1px solid ${TEXT_MUTED}`,
              borderRadius: 6,
              padding: "6px 14px",
            }}
          >
            DEMO
          </div>
        ) : null}
      </div>

      <div style={{ display: "flex", fontSize: 30, color: TEXT_MUTED, marginTop: 24 }}>{data.eventName}</div>
      {whoBy ? (
        <div
          style={{
            display: "flex",
            fontSize: 26,
            color: ACCENT_STRONG,
            marginTop: 8,
            maxWidth: width - 112,
            overflow: "hidden",
            whiteSpace: "nowrap",
            textOverflow: "ellipsis",
          }}
        >
          {whoBy}
        </div>
      ) : null}

      {/* Score — the hero element */}
      <div
        style={{
          display: "flex",
          fontSize: 170 * scale,
          fontWeight: 700,
          marginTop: 20,
          lineHeight: 1,
          letterSpacing: 4,
        }}
      >
        {breakdown.displayScore}
      </div>
      <div style={{ display: "flex", fontSize: 46 * scale, fontWeight: 700, color: ACCENT, marginTop: 4 }}>
        {dict.score.bands[breakdown.band].toUpperCase()}
      </div>

      {/* Breakdown */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: 64 * scale, gap: 28 * scale }}>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>{sd.cardWinner}</div>
          <div style={{ display: "flex", color: breakdown.components.winner.hit ? ACCENT_STRONG : TEXT_MUTED }}>
            {breakdown.components.winner.hit ? sd.cardCorrect : sd.cardMissed}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>{sd.cardPodium}</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.podium.hits} / {breakdown.components.podium.total}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>{sd.cardTop5}</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.top5.hits} / {breakdown.components.top5.total}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>{sd.cardTop10}</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.top10.hits} / {breakdown.components.top10.total}
          </div>
        </div>
      </div>

      {data.percentile !== null ? (
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            marginTop: 44 * scale,
            padding: "28px 32px",
            backgroundColor: SURFACE,
            borderRadius: 16,
          }}
        >
          <div style={{ display: "flex", fontSize: 30 * scale, color: TEXT_MUTED }}>{sd.cardTopPct.replace("{n}", String(100 - Math.round(data.percentile)))}</div>
          <div style={{ display: "flex", fontSize: 38 * scale, fontWeight: 700 }}>{sd.cardWorldwide}</div>
        </div>
      ) : null}

      {/* Footer */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: "auto" }}>
        <div style={{ display: "flex", fontSize: 34, fontWeight: 700 }}>{sd.cardBeatIt}</div>
        <div style={{ display: "flex", fontSize: 24, color: TEXT_MUTED, marginTop: 6 }}>{siteDomain}</div>
      </div>
    </div>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\ResultCardMarkup.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\ResultCardMarkup.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\ResultCardMarkup.tsx"
}

try {
    $path = "src\components\scoring\YourCrowdChanged.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { CountryFlag } from "@/components/CountryFlag";
import { resolveParticipantsByIds } from "@/lib/participants";
import { getConsensusChangeForPrediction } from "@/lib/consensus-change-service";
import { bucketSample } from "@/lib/consensus-change";
import type { PredictionRecord } from "@/lib/predictions-db";
import type { FouchEvent } from "@/types/event";
import { ConsensusChangeTracker } from "./ConsensusChangeTracker";
import { getI18n } from "@/lib/i18n-server";

/**
 * Experiment 01 ("Your Crowd Changed") â€” FOUCH_EXPERIMENT_01.md.
 * Renders nothing whenever the movement isn't eligible (small sample,
 * or change under MIN_MOVEMENT_POINTS) â€” silence is the correct,
 * expected behavior, not a bug or a loading state.
 */
export async function YourCrowdChanged({
  prediction,
  event,
}: {
  prediction: PredictionRecord;
  event: FouchEvent;
}) {
  const winnerId = prediction.rankedParticipantIds[0];
  if (!winnerId) return null;
  const { locale, dict } = await getI18n();
  const ct = dict.community;

  const result = await getConsensusChangeForPrediction(
    prediction.id,
    prediction.submittedAt,
    winnerId,
    event.slug,
    prediction.dataStatus,
  );
  if (!result.eligible || !result.direction) return null;

  // FOUCH 0.3B: resolves regardless of current status â€” winnerId
  // comes from the community's aggregate winner picks and may
  // reference a participant who has since become
  // WITHDRAWN/REPLACED.
  const participantsById = await resolveParticipantsByIds(event.slug, [winnerId], locale);
  const winner = participantsById.get(winnerId);
  if (!winner) return null;

  const arrow = result.direction === "toward" ? "↑" : "↓";
  const sign = result.changePoints > 0 ? "+" : "";
  const directionCopy =
    result.direction === "toward"
      ? ct.crowdMovingToward
      : ct.crowdMovingAway;

  return (
    <section className="mt-12 border-t border-border pt-10">
      <ConsensusChangeTracker
        eventSlug={event.slug}
        dataStatus={prediction.dataStatus}
        direction={result.direction}
        changePoints={result.changePoints}
        thenSampleBucket={bucketSample(result.thenSample)}
        nowSampleBucket={bucketSample(result.nowSample)}
      />

      <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">
        {ct.crowdChanged}
      </p>

      <div className="mt-3 flex items-center gap-2">
        <CountryFlag countryCode={winner.countryCode} className="text-2xl" />
        <span className="font-display text-xl text-text-primary">
          {winner.displayName} <span className="text-text-muted text-base">· {winner.countryName}</span>
        </span>
      </div>

      <p className="mt-2 font-display text-4xl text-accent-strong">
        {Math.round(result.thenSupport)}% → {Math.round(result.nowSupport)}%
      </p>
      <p className="mt-1 text-sm text-text-secondary">
        {arrow} {sign}
        {Math.round(result.changePoints)} {ct.pts}
      </p>

      <p className="mt-3 text-text-primary">{directionCopy}</p>
      <p className="mt-2 text-xs text-text-muted">{ct.crowdBasedOn}</p>
    </section>
  );
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\scoring\YourCrowdChanged.tsx"
} catch {
    Write-Host "FAILED: src\components\scoring\YourCrowdChanged.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\scoring\YourCrowdChanged.tsx"
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
    $path = "src\content\pt.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
// STALE Sprint-0 stub — NOT wired into anything and NOT part of i18n v1
// (English + Spanish only; Portuguese is explicitly out of scope for
// now). Its shape predates the current Dictionary, so it is excluded
// from the typed Dictionary rather than silently "fixed" with unreviewed
// Portuguese copy. Rebuild it against src/content/en.ts when
// Portuguese is actually scoped.

// Prepared for future localization. Not yet wired into routing in Sprint 0 —
// English is the only live locale.
export const pt = {
  meta: {
    title: "Fouch — Faça sua previsão",
    description:
      "Preveja os maiores momentos do entretenimento e veja como suas escolhas se comparam com o mundo.",
  },
  nav: {
    wordmark: "Fouch",
  },
  hero: {
    headline: "Faça sua previsão.",
    subhead: "Preveja os momentos dos quais todos vão falar.",
    cta: "Monte seu Top 10",
  },
  featuredEvent: {
    eyebrowUpcoming: "Em breve",
    prompt: "Quem entra no seu Top 10?",
    cta: "Monte seu Top 10",
  },
  howItWorks: {
    title: "Como funciona",
    steps: [
      { title: "Preveja", body: "Monte seu ranking." },
      { title: "Compita", body: "Veja como suas escolhas se comparam." },
      { title: "Comprove", body: "Receba sua pontuação quando sair o resultado." },
    ],
  },
  eventPage: {
    back: "Voltar ao Fouch",
    comingSoon: "O criador de previsões deste evento abre em breve.",
  },
  footer: {
    tagline: "Previsões de entretenimento.",
  },
};
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\content\pt.ts"
} catch {
    Write-Host "FAILED: src\content\pt.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\content\pt.ts"
}

try {
    $path = "src\content\types.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { en } from "./en";

/** Structure derived from the English source of truth: every leaf is a
 * string (templates use {placeholders}), so the whole dictionary is
 * JSON-serializable and can cross the server -> client boundary.
 * es.ts is typed as Dictionary, so a missing Spanish key is a
 * compile-time error, not a runtime surprise. */
type DeepString<T> = T extends string
  ? string
  : T extends readonly (infer U)[]
    ? DeepString<U>[]
    : { [K in keyof T]: DeepString<T[K]> };

export type Dictionary = DeepString<typeof en>;

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\content\types.ts"
} catch {
    Write-Host "FAILED: src\content\types.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\content\types.ts"
}

try {
    $path = "src\lib\analytics.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Analytics seam — Beta Hardening 0.1.
 *
 * Every call site still imports the same `track(event, properties)`
 * function as before; only the transport underneath changed, from a
 * console.debug stub to real PostHog capture. The contract is
 * unchanged on purpose so no component needed to be touched.
 *
 * Configuration (set in Vercel):
 *   NEXT_PUBLIC_POSTHOG_KEY  — PostHog project API key (public by
 *     design — PostHog's own docs confirm this key is meant to be
 *     browser-visible; it is not a secret).
 *   NEXT_PUBLIC_POSTHOG_HOST — defaults to https://us.i.posthog.com
 *     if unset; only needed for a self-hosted or EU-region instance.
 *
 * Without NEXT_PUBLIC_POSTHOG_KEY configured, track() falls back to
 * the original console.debug behavior — nothing crashes, nothing is
 * silently required. Analytics is always best-effort: every call is
 * wrapped so a PostHog failure (network, ad blocker, misconfiguration)
 * can never throw into product code. Prediction submission, sharing,
 * and every public page must keep working exactly the same whether or
 * not analytics succeeds.
 *
 * Properties must never carry personally identifiable information or
 * free-text nickname/contestant input — only structural values like
 * an event slug, a count, a position, or a share method. This function
 * also never calls posthog.identify() — every event stays on
 * PostHog's normal anonymous, cookie/localStorage-backed distinct_id.
 * Connecting anonymous activity to a verified identity is explicitly
 * deferred to Beta Hardening 0.2.
 */

import posthog from "posthog-js";

let posthogReady = false;

function ensurePostHogInitialized(): boolean {
  if (typeof window === "undefined") return false;

  const key = process.env.NEXT_PUBLIC_POSTHOG_KEY;
  if (!key) return false;

  if (!posthogReady) {
    try {
      posthog.init(key, {
        api_host: process.env.NEXT_PUBLIC_POSTHOG_HOST || "https://us.i.posthog.com",
        // Beta-appropriate defaults: no automatic pageview capture (we
        // fire explicit, typed events already, e.g. landing_view), and
        // no full "person" profile creation for anonymous beta traffic
        // — keeps this cheap and avoids modeling identity we haven't
        // decided on yet (that's Beta Hardening 0.2).
        capture_pageview: false,
        person_profiles: "identified_only",
      });
      posthogReady = true;
    } catch {
      return false;
    }
  }

  return true;
}

export type FouchAnalyticsEvent =
  | "landing_view"
  | "featured_event_clicked"
  | "start_prediction"
  | "participant_selected"
  | "participant_removed"
  | "prediction_reordered"
  | "prediction_completed"
  | "prediction_reviewed"
  | "prediction_submit_started"
  | "prediction_submitted"
  | "prediction_card_generated"
  | "share_clicked"
  | "instagram_story_clicked"
  | "language_changed"
  | "native_share_opened"
  | "copy_link_clicked"
  | "image_downloaded"
  | "public_prediction_viewed"
  | "public_prediction_cta_clicked"
  | "prediction_edit_started"
  | "prediction_edit_reordered"
  | "prediction_updated"
  | "you_vs_world_viewed"
  | "same_winner_viewed"
  | "top3_match_viewed"
  | "boldest_pick_viewed"
  | "community_top10_viewed"
  | "community_share_clicked"
  | "score_viewed"
  | "score_breakdown_viewed"
  | "percentile_viewed"
  | "result_card_generated"
  | "result_card_shared"
  | "result_card_saved"
  | "result_share_link_copied"
  | "leaderboard_viewed"
  | "leaderboard_row_clicked"
  | "own_rank_viewed"
  | "leaderboard_from_score_clicked"
  | "consensus_change_viewed"
  | "verification_started"
  | "verification_sent"
  | "verification_completed"
  | "verification_failed"
  | "duplicate_prediction_attempt";

/**
 * i18n v1: the UI language, attached as `locale` to EVERY tracked event
 * (so the existing funnels — landing_view -> start_prediction ->
 * prediction_submitted — can be broken down EN vs ES without renaming
 * or duplicating any event). Set synchronously by I18nProvider before
 * any child effect fires. Stays null (no property added) until set, so
 * non-localized contexts and the original tests are unaffected. An
 * explicit `locale` in a call's own properties always wins.
 */
let currentLocale: string | null = null;

export function setAnalyticsLocale(locale: string | null) {
  currentLocale = locale;
}

export function track(event: FouchAnalyticsEvent, properties?: Record<string, unknown>) {
  if (typeof window === "undefined") return;

  const enriched = currentLocale ? { locale: currentLocale, ...(properties ?? {}) } : properties;

  try {
    if (ensurePostHogInitialized()) {
      posthog.capture(event, enriched);
      return;
    }
  } catch {
    // Analytics must never break the product — fall through to the
    // silent/dev-visible fallback below rather than propagate.
  }

  // No PostHog key configured (or init/capture failed): preserve the
  // original, harmless console.debug behavior rather than losing
  // visibility entirely during local development or misconfiguration.
  console.debug("[fouch:analytics]", event, enriched ?? {});
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\analytics.ts"
} catch {
    Write-Host "FAILED: src\lib\analytics.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\analytics.ts"
}

try {
    $path = "src\lib\countries.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Locale } from "@/lib/locale";

/**
 * FOUCH Country Selector Globalization — the canonical, global list
 * of countries for user-identity metadata (the optional "your
 * country" field on a prediction). This is about the PREDICTOR, not
 * an event's contestants (see src/lib/participants.ts /
 * event-participants-db.ts for those) — a predictor can be from
 * anywhere in the world, so this list is deliberately complete and
 * entirely independent of any event's roster.
 *
 * Generated from the same country-flag-icons package FOUCH already
 * depends on for flag rendering (CountryFlag.tsx), using each code's
 * standard English display name (Intl.DisplayNames), with a small,
 * explicit set of uninhabited/non-country/testing entries excluded
 * (Antarctica, Bouvet Island, the "European Union" pseudo-region,
 * ICU's "Pseudo-Accents" test locale, and similar). Every other
 * ISO 3166-1 code the flag package recognizes is included — the full
 * worldwide set, not a curated subset — so a predictor's country is
 * never missing here regardless of nationality.
 *
 * ISO 3166-1 alpha-2 codes, validated server-side against the same
 * pattern regardless of whether the code appears here.
 */
export const PREDICTOR_COUNTRIES: Array<{ code: string; name: string }> = [
  { code: "AF", name: "Afghanistan" },
  { code: "AX", name: "Åland Islands" },
  { code: "AL", name: "Albania" },
  { code: "DZ", name: "Algeria" },
  { code: "AS", name: "American Samoa" },
  { code: "AD", name: "Andorra" },
  { code: "AO", name: "Angola" },
  { code: "AI", name: "Anguilla" },
  { code: "AG", name: "Antigua & Barbuda" },
  { code: "AR", name: "Argentina" },
  { code: "AM", name: "Armenia" },
  { code: "AW", name: "Aruba" },
  { code: "AC", name: "Ascension Island" },
  { code: "AU", name: "Australia" },
  { code: "AT", name: "Austria" },
  { code: "AZ", name: "Azerbaijan" },
  { code: "BS", name: "Bahamas" },
  { code: "BH", name: "Bahrain" },
  { code: "BD", name: "Bangladesh" },
  { code: "BB", name: "Barbados" },
  { code: "BY", name: "Belarus" },
  { code: "BE", name: "Belgium" },
  { code: "BZ", name: "Belize" },
  { code: "BJ", name: "Benin" },
  { code: "BM", name: "Bermuda" },
  { code: "BT", name: "Bhutan" },
  { code: "BO", name: "Bolivia" },
  { code: "BA", name: "Bosnia & Herzegovina" },
  { code: "BW", name: "Botswana" },
  { code: "BR", name: "Brazil" },
  { code: "VG", name: "British Virgin Islands" },
  { code: "BN", name: "Brunei" },
  { code: "BG", name: "Bulgaria" },
  { code: "BF", name: "Burkina Faso" },
  { code: "BI", name: "Burundi" },
  { code: "KH", name: "Cambodia" },
  { code: "CM", name: "Cameroon" },
  { code: "CA", name: "Canada" },
  { code: "IC", name: "Canary Islands" },
  { code: "CV", name: "Cape Verde" },
  { code: "BQ", name: "Caribbean Netherlands" },
  { code: "KY", name: "Cayman Islands" },
  { code: "CF", name: "Central African Republic" },
  { code: "TD", name: "Chad" },
  { code: "CL", name: "Chile" },
  { code: "CN", name: "China" },
  { code: "CO", name: "Colombia" },
  { code: "KM", name: "Comoros" },
  { code: "CG", name: "Congo - Brazzaville" },
  { code: "CD", name: "Congo - Kinshasa" },
  { code: "CK", name: "Cook Islands" },
  { code: "CR", name: "Costa Rica" },
  { code: "CI", name: "Côte d’Ivoire" },
  { code: "HR", name: "Croatia" },
  { code: "CU", name: "Cuba" },
  { code: "CW", name: "Curaçao" },
  { code: "CY", name: "Cyprus" },
  { code: "CZ", name: "Czechia" },
  { code: "DK", name: "Denmark" },
  { code: "DJ", name: "Djibouti" },
  { code: "DM", name: "Dominica" },
  { code: "DO", name: "Dominican Republic" },
  { code: "EC", name: "Ecuador" },
  { code: "EG", name: "Egypt" },
  { code: "SV", name: "El Salvador" },
  { code: "GQ", name: "Equatorial Guinea" },
  { code: "ER", name: "Eritrea" },
  { code: "EE", name: "Estonia" },
  { code: "SZ", name: "Eswatini" },
  { code: "ET", name: "Ethiopia" },
  { code: "FK", name: "Falkland Islands" },
  { code: "FO", name: "Faroe Islands" },
  { code: "FJ", name: "Fiji" },
  { code: "FI", name: "Finland" },
  { code: "FR", name: "France" },
  { code: "GF", name: "French Guiana" },
  { code: "PF", name: "French Polynesia" },
  { code: "GA", name: "Gabon" },
  { code: "GM", name: "Gambia" },
  { code: "GE", name: "Georgia" },
  { code: "DE", name: "Germany" },
  { code: "GH", name: "Ghana" },
  { code: "GI", name: "Gibraltar" },
  { code: "GR", name: "Greece" },
  { code: "GL", name: "Greenland" },
  { code: "GD", name: "Grenada" },
  { code: "GP", name: "Guadeloupe" },
  { code: "GU", name: "Guam" },
  { code: "GT", name: "Guatemala" },
  { code: "GG", name: "Guernsey" },
  { code: "GN", name: "Guinea" },
  { code: "GW", name: "Guinea-Bissau" },
  { code: "GY", name: "Guyana" },
  { code: "HT", name: "Haiti" },
  { code: "HN", name: "Honduras" },
  { code: "HK", name: "Hong Kong SAR China" },
  { code: "HU", name: "Hungary" },
  { code: "IS", name: "Iceland" },
  { code: "IN", name: "India" },
  { code: "ID", name: "Indonesia" },
  { code: "IR", name: "Iran" },
  { code: "IQ", name: "Iraq" },
  { code: "IE", name: "Ireland" },
  { code: "IM", name: "Isle of Man" },
  { code: "IL", name: "Israel" },
  { code: "IT", name: "Italy" },
  { code: "JM", name: "Jamaica" },
  { code: "JP", name: "Japan" },
  { code: "JE", name: "Jersey" },
  { code: "JO", name: "Jordan" },
  { code: "KZ", name: "Kazakhstan" },
  { code: "KE", name: "Kenya" },
  { code: "KI", name: "Kiribati" },
  { code: "XK", name: "Kosovo" },
  { code: "KW", name: "Kuwait" },
  { code: "KG", name: "Kyrgyzstan" },
  { code: "LA", name: "Laos" },
  { code: "LV", name: "Latvia" },
  { code: "LB", name: "Lebanon" },
  { code: "LS", name: "Lesotho" },
  { code: "LR", name: "Liberia" },
  { code: "LY", name: "Libya" },
  { code: "LI", name: "Liechtenstein" },
  { code: "LT", name: "Lithuania" },
  { code: "LU", name: "Luxembourg" },
  { code: "MO", name: "Macao SAR China" },
  { code: "MG", name: "Madagascar" },
  { code: "MW", name: "Malawi" },
  { code: "MY", name: "Malaysia" },
  { code: "MV", name: "Maldives" },
  { code: "ML", name: "Mali" },
  { code: "MT", name: "Malta" },
  { code: "MH", name: "Marshall Islands" },
  { code: "MQ", name: "Martinique" },
  { code: "MR", name: "Mauritania" },
  { code: "MU", name: "Mauritius" },
  { code: "YT", name: "Mayotte" },
  { code: "MX", name: "Mexico" },
  { code: "FM", name: "Micronesia" },
  { code: "MD", name: "Moldova" },
  { code: "MC", name: "Monaco" },
  { code: "MN", name: "Mongolia" },
  { code: "ME", name: "Montenegro" },
  { code: "MS", name: "Montserrat" },
  { code: "MA", name: "Morocco" },
  { code: "MZ", name: "Mozambique" },
  { code: "MM", name: "Myanmar (Burma)" },
  { code: "NA", name: "Namibia" },
  { code: "NR", name: "Nauru" },
  { code: "NP", name: "Nepal" },
  { code: "NL", name: "Netherlands" },
  { code: "NC", name: "New Caledonia" },
  { code: "NZ", name: "New Zealand" },
  { code: "NI", name: "Nicaragua" },
  { code: "NE", name: "Niger" },
  { code: "NG", name: "Nigeria" },
  { code: "NU", name: "Niue" },
  { code: "KP", name: "North Korea" },
  { code: "MK", name: "North Macedonia" },
  { code: "MP", name: "Northern Mariana Islands" },
  { code: "NO", name: "Norway" },
  { code: "OM", name: "Oman" },
  { code: "PK", name: "Pakistan" },
  { code: "PW", name: "Palau" },
  { code: "PS", name: "Palestinian Territories" },
  { code: "PA", name: "Panama" },
  { code: "PG", name: "Papua New Guinea" },
  { code: "PY", name: "Paraguay" },
  { code: "PE", name: "Peru" },
  { code: "PH", name: "Philippines" },
  { code: "PL", name: "Poland" },
  { code: "PT", name: "Portugal" },
  { code: "PR", name: "Puerto Rico" },
  { code: "QA", name: "Qatar" },
  { code: "RE", name: "Réunion" },
  { code: "RO", name: "Romania" },
  { code: "RU", name: "Russia" },
  { code: "RW", name: "Rwanda" },
  { code: "WS", name: "Samoa" },
  { code: "SM", name: "San Marino" },
  { code: "ST", name: "São Tomé & Príncipe" },
  { code: "SA", name: "Saudi Arabia" },
  { code: "SN", name: "Senegal" },
  { code: "RS", name: "Serbia" },
  { code: "SC", name: "Seychelles" },
  { code: "SL", name: "Sierra Leone" },
  { code: "SG", name: "Singapore" },
  { code: "SX", name: "Sint Maarten" },
  { code: "SK", name: "Slovakia" },
  { code: "SI", name: "Slovenia" },
  { code: "SB", name: "Solomon Islands" },
  { code: "SO", name: "Somalia" },
  { code: "ZA", name: "South Africa" },
  { code: "KR", name: "South Korea" },
  { code: "SS", name: "South Sudan" },
  { code: "ES", name: "Spain" },
  { code: "LK", name: "Sri Lanka" },
  { code: "BL", name: "St. Barthélemy" },
  { code: "SH", name: "St. Helena" },
  { code: "KN", name: "St. Kitts & Nevis" },
  { code: "LC", name: "St. Lucia" },
  { code: "MF", name: "St. Martin" },
  { code: "PM", name: "St. Pierre & Miquelon" },
  { code: "VC", name: "St. Vincent & Grenadines" },
  { code: "SD", name: "Sudan" },
  { code: "SR", name: "Suriname" },
  { code: "SE", name: "Sweden" },
  { code: "CH", name: "Switzerland" },
  { code: "SY", name: "Syria" },
  { code: "TW", name: "Taiwan" },
  { code: "TJ", name: "Tajikistan" },
  { code: "TZ", name: "Tanzania" },
  { code: "TH", name: "Thailand" },
  { code: "TL", name: "Timor-Leste" },
  { code: "TG", name: "Togo" },
  { code: "TK", name: "Tokelau" },
  { code: "TO", name: "Tonga" },
  { code: "TT", name: "Trinidad & Tobago" },
  { code: "TN", name: "Tunisia" },
  { code: "TR", name: "Türkiye" },
  { code: "TM", name: "Turkmenistan" },
  { code: "TC", name: "Turks & Caicos Islands" },
  { code: "TV", name: "Tuvalu" },
  { code: "VI", name: "U.S. Virgin Islands" },
  { code: "UG", name: "Uganda" },
  { code: "UA", name: "Ukraine" },
  { code: "AE", name: "United Arab Emirates" },
  { code: "GB", name: "United Kingdom" },
  { code: "US", name: "United States" },
  { code: "UY", name: "Uruguay" },
  { code: "UZ", name: "Uzbekistan" },
  { code: "VU", name: "Vanuatu" },
  { code: "VA", name: "Vatican City" },
  { code: "VE", name: "Venezuela" },
  { code: "VN", name: "Vietnam" },
  { code: "WF", name: "Wallis & Futuna" },
  { code: "EH", name: "Western Sahara" },
  { code: "YE", name: "Yemen" },
  { code: "ZM", name: "Zambia" },
  { code: "ZW", name: "Zimbabwe" },
].sort((a, b) => a.name.localeCompare(b.name));

/**
 * FOUCH Country Recognition consistency fix — the single lookup every
 * predictor-country display surface (Share Cards, public prediction
 * header) uses to resolve a stored ISO code to its human-readable
 * name. Reuses PREDICTOR_COUNTRIES — the same list the country
 * selector itself is built from — so there is only ever one
 * code-to-name mapping in the app, never a second one. Returns null
 * for a code that isn't in the list (never fabricates a name).
 */
export function getPredictorCountryName(code: string | null, locale: Locale = "en"): string | null {
  if (!code) return null;
  const englishName = PREDICTOR_COUNTRIES.find((country) => country.code === code)?.name ?? null;
  if (!englishName) return null;
  return getLocalizedCountryName(code, englishName, locale);
}

/**
 * i18n v1: the human-readable country name in the viewer's language.
 * English returns the existing English name untouched (so every
 * current English surface — including DB roster names like "Czech
 * Republic" — is byte-for-byte unchanged). Other locales use the
 * platform's Intl.DisplayNames (CLDR data) and fall back to the
 * English name whenever Intl has nothing useful (unknown/unofficial
 * codes such as XK, or a runtime without that locale) — never a raw
 * ISO code. No second country dataset is introduced.
 */
export function getLocalizedCountryName(code: string, englishName: string, locale: Locale): string {
  if (locale === "en") return englishName;
  try {
    const localized = new Intl.DisplayNames([locale], { type: "region" }).of(code);
    if (localized && localized !== code) return localized;
  } catch {
    // Unsupported locale/code in this runtime — fall through to English.
  }
  return englishName;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\countries.ts"
} catch {
    Write-Host "FAILED: src\lib\countries.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\countries.ts"
}

try {
    $path = "src\lib\crowd-picks.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { getEligiblePredictionsForComparison } from "@/lib/predictions-db";
import { computeCommunityTop10 } from "@/lib/community-comparison";
import { resolveParticipantsByIds } from "@/lib/participants";
import type { ParticipantDataStatus } from "@/lib/participants";
import type { Participant } from "@/types/participant";
import type { Locale } from "@/lib/locale";

export interface CrowdTopPick {
  participant: Participant;
  /** % of eligible predictions that picked this participant as their
   * #1 — "who does the crowd have winning", not a Top-10-inclusion
   * rate. Rounded for display only; never re-derives a different
   * ranking than computeCommunityTop10's own points-based order. */
  pct: number;
}

export interface CrowdTopPicks {
  population: number;
  picks: CrowdTopPick[];
}

/**
 * FOUCH Home v1.1 "The Crowd" section — reuses the EXACT same
 * eligibility (getEligiblePredictionsForComparison: is_final = true,
 * scoped by event_slug + data_status, current-version-only) and
 * ranking (computeCommunityTop10, the same function You vs The World
 * uses) as the rest of the product. This is deliberately not a
 * second definition of "the crowd" — it's the same one, just without
 * a specific viewer's own prediction to compare against.
 *
 * Returns null when there's no event to show (never happens for a
 * resolved event, but keeps the caller's null-handling simple) —
 * an empty population returns `{ population: 0, picks: [] }`, which
 * the component renders as the small-sample "IT'S EARLY" state.
 */
export async function getCrowdTopPicks(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
  limit = 5,
  locale: Locale = "en",
): Promise<CrowdTopPicks> {
  const eligible = await getEligiblePredictionsForComparison(eventSlug, dataStatus);
  const population = eligible.length;

  if (population === 0) return { population: 0, picks: [] };

  const ranked = computeCommunityTop10(eligible).slice(0, limit);
  const participantsById = await resolveParticipantsByIds(
    eventSlug,
    ranked.map((entry) => entry.participantId),
    locale,
  );

  const picks: CrowdTopPick[] = [];
  for (const entry of ranked) {
    const participant = participantsById.get(entry.participantId);
    if (!participant) continue; // Resolvable-by-id failure is a data anomaly, not a reason to show a blank row.
    picks.push({
      participant,
      pct: Math.round((entry.firstPlaceCount / population) * 100),
    });
  }

  return { population, picks };
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\crowd-picks.ts"
} catch {
    Write-Host "FAILED: src\lib\crowd-picks.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\crowd-picks.ts"
}

try {
    $path = "src\lib\email-step-copy.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * FOUCH 0.3A.1 — the entire copy decision for EmailStep's heading, in
 * one pure, unit-testable place. Extracted specifically so "create
 * flow says X" and "edit flow says Y" (brief §12 tests 7-8) can be
 * asserted directly, without needing a component-testing setup this
 * codebase doesn't have (no React Testing Library / jsdom-rendering
 * test infra exists for components here — every existing *.test.ts
 * file tests pure logic, not rendered output; this follows the same
 * pattern).
 *
 * "lock your prediction" must never appear here before the actual
 * event lock — a prediction stays editable until prediction_lock_at,
 * so "lock" is no longer the right verb for this step.
 */
export type EmailStepMode = "create" | "edit";

export function getEmailStepHeading(
  mode: EmailStepMode,
  headings: { create: string; edit: string } = {
    create: "Verify your email to save your prediction.",
    edit: "Verify your email to save your changes.",
  },
): string {
  return mode === "edit" ? headings.edit : headings.create;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\email-step-copy.ts"
} catch {
    Write-Host "FAILED: src\lib\email-step-copy.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\email-step-copy.ts"
}

try {
    $path = "src\lib\event-time-display.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Locale } from "@/lib/locale";

/**
 * FOUCH 0.3A.1 â€” pure, DB-free display formatting for the prediction
 * lock instant. Deliberately separate from prediction-lock-logic.ts:
 * that file decides WHETHER predictions are open (authorization,
 * server-time-only); this file only decides HOW to show an already-
 * decided instant to a human, in the event's own timezone rather than
 * the viewer's browser timezone (which is ambiguous for a worldwide
 * audience â€” see FOUCH 0.3A.1 brief Â§1).
 *
 * CRITICAL invariant this file must never violate: formatting a
 * timestamp for display must never change what instant it represents.
 * `new Date(isoDateTime).getTime()` is always used as-is; nothing here
 * re-parses or reinterprets the ISO string as a timezone-less local
 * datetime. See event-time-display.test.ts for a test that proves
 * this directly.
 */

/**
 * Derives a short, human-readable location label from an IANA
 * timezone identifier â€” the last path segment, underscores replaced
 * with spaces. "America/Puerto_Rico" -> "Puerto Rico". This is a
 * generic, zero-configuration derivation (no new "location" field
 * needed) â€” good enough for the single-event scale this product is
 * at; if it ever produces something awkward for a future event, that
 * event can be given a nicer label at that point, not preemptively
 * here.
 */
export function deriveLocationLabel(timeZone: string): string {
  const lastSegment = timeZone.split("/").pop() ?? timeZone;
  return lastSegment.replace(/_/g, " ");
}

/**
 * FOUCH 0.3B Â§13 â€” "Contestant list updated {date}", the restrained
 * replacement for "Demo prediction" on a real (non-demo) event whose
 * roster has verified provenance. Deliberately date-only (no time/
 * timezone) â€” this is about freshness of a roster list, not a
 * lock-timing instant, so it doesn't need event-local precision.
 */
export function formatContestantListUpdated(
  sourceCheckedAtIso: string,
  template = "Contestant list updated {date}",
  locale: Locale = "en",
): string {
  const formatted = new Intl.DateTimeFormat(locale === "es" ? "es" : "en-US", {
    dateStyle: "medium",
    timeZone: "UTC",
  }).format(new Date(sourceCheckedAtIso));
  return template.replace("{date}", formatted);
}

/** "OCT 10" / "10 OCT" — the compact event date on the Home cards. */
export function formatEventDayMonth(eventDate: string, locale: Locale = "en"): string {
  return new Date(`${eventDate}T00:00:00Z`)
    .toLocaleDateString(locale === "es" ? "es" : "en-US", { month: "short", day: "numeric", timeZone: "UTC" })
    .toUpperCase();
}

/**
 * Formats an absolute instant (ISO 8601 string, e.g. from
 * `events.prediction_lock_at`) as an unambiguous, human-readable
 * string in the EVENT's own local timezone â€” never the viewer's
 * browser timezone. Always includes a timezone abbreviation/offset
 * (via Intl's `timeZoneName: "short"`) so the result is never a naked
 * "9:00 PM" with no context (brief Â§3).
 *
 * When `timeZone` is null (event has none configured yet), falls back
 * to an explicit UTC-labeled rendering â€” still unambiguous, never a
 * silently-assumed local time.
 */
export function formatEventLocalLockTime(
  isoDateTime: string,
  timeZone: string | null,
  locale: Locale = "en",
): string {
  const date = new Date(isoDateTime);

  // i18n v1: Spanish uses the platform's own locale-aware pattern
  // (e.g. "10 oct, 12:00 a. m. GMT+7"); English keeps the exact
  // "Oct 10 at 12:00 AM GMT+7" composition below, unchanged. Only the
  // PRESENTATION changes — the instant being formatted never does.
  if (locale !== "en") {
    try {
      const rendered = new Intl.DateTimeFormat(locale, {
        timeZone: timeZone ?? "UTC",
        month: "short",
        day: "numeric",
        hour: "numeric",
        minute: "2-digit",
        timeZoneName: "short",
      }).format(date);
      return timeZone ? `${rendered} (${deriveLocationLabel(timeZone)})` : rendered;
    } catch {
      // Invalid timezone/locale — fall through to the English composition.
    }
  }
  const zoneForFormatting = timeZone ?? "UTC";

  let parts: Intl.DateTimeFormatPart[];
  try {
    const formatter = new Intl.DateTimeFormat("en-US", {
      timeZone: zoneForFormatting,
      month: "short",
      day: "numeric",
      hour: "numeric",
      minute: "2-digit",
      timeZoneName: "short",
    });
    parts = formatter.formatToParts(date);
  } catch {
    // An invalid/unrecognized IANA identifier should never crash the
    // page â€” fall back to explicit UTC, still unambiguous.
    if (zoneForFormatting !== "UTC") return formatEventLocalLockTime(isoDateTime, null);
    throw new Error(`Unable to format date in UTC: ${isoDateTime}`);
  }

  const get = (type: Intl.DateTimeFormatPartTypes) => parts.find((p) => p.type === type)?.value ?? "";
  const rendered = `${get("month")} ${get("day")} at ${get("hour")}:${get("minute")} ${get("dayPeriod")} ${get("timeZoneName")}`.trim();

  if (!timeZone) return rendered;

  const location = deriveLocationLabel(timeZone);
  return `${rendered} (${location})`;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-time-display.ts"
} catch {
    Write-Host "FAILED: src\lib\event-time-display.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-time-display.ts"
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
  if (hardcoded) {
    return {
      status: "demo",
      participants: hardcoded.filter((participant) => participant.isActive).map((p) => localize(p, locale)),
      sourceCheckedAt: null,
    };
  }

  const rows = await getAllEventParticipantRows(slug);
  if (rows.length === 0) return null;

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
  const hardcoded = participantsByEventSlug[eventSlug];

  if (hardcoded) {
    const map = new Map<string, Participant>();
    for (const participant of hardcoded) {
      if (idSet.has(participant.id)) map.set(participant.id, localize(participant, locale));
    }
    return map;
  }

  const rows = await getAllEventParticipantRows(eventSlug);
  const map = new Map<string, Participant>();
  for (const row of rows) {
    if (idSet.has(row.id)) map.set(row.id, localize(toParticipant(row), locale));
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
    $path = "src\lib\predictions-db.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import { generatePublicId } from "@/lib/public-id";
import { getEventBySlug } from "@/lib/events";
import { resolveParticipantsByIds, type ParticipantDataStatus } from "@/lib/participants";
import { classifyInsertConflict } from "@/lib/insert-conflict";
import { isRankingUnchanged } from "@/lib/prediction-version-logic";
import type { FouchEvent } from "@/types/event";
import type { Locale } from "@/lib/locale";
import type { Participant } from "@/types/participant";
import type { EligiblePrediction } from "@/lib/community-comparison";

export interface PredictionRecord {
  /** Internal DB id â€” server-side use only (e.g. self-exclusion from
   * community comparisons). Never send this to the client. */
  id: string;
  publicId: string;
  eventSlug: string;
  nickname: string | null;
  countryCode: string | null;
  dataStatus: ParticipantDataStatus;
  submittedAt: string;
  /** FOUCH 0.3A: whether this prediction has a verified owner. Only
   * ever used server-side to decide whether to offer "EDIT MY TOP
   * 10" â€” never exposed as a raw auth_user_id to the client (see
   * predictions_public, which still never selects auth_user_id). */
  hasVerifiedOwner: boolean;
  /** FOUCH 0.3A: version_number of the current version â€” needed by
   * the edit flow as the optimistic-concurrency baseline. */
  currentVersionNumber: number;
  /** Participant IDs in ranked order â€” index 0 is position #1. */
  rankedParticipantIds: string[];
}

interface InsertPredictionParams {
  eventSlug: string;
  participantIds: string[];
  nickname: string | null;
  countryCode: string | null;
  dataStatus: ParticipantDataStatus;
  deviceToken: string;
  /** Beta Hardening 0.2 Phase C â€” set only by the new verified-lock
   * path. Undefined/omitted preserves the exact pre-Phase-C anonymous
   * insert behavior (legacy predictions are never retroactively
   * touched â€” see FOUCH_IDENTITY_ARCHITECTURE.md). */
  authUserId?: string;
}

export type InsertPredictionResult =
  | { success: true; publicId: string; alreadyExisted: boolean }
  | { success: false; error: string };

const MAX_PUBLIC_ID_ATTEMPTS = 5;
const UNIQUE_VIOLATION = "23505";

export async function insertPrediction(
  params: InsertPredictionParams,
): Promise<InsertPredictionResult> {
  const supabase = getSupabaseServerClient();
  if (!supabase) {
    return { success: false, error: "Submissions aren't available yet — the database isn't configured." };
  }

  for (let attempt = 0; attempt < MAX_PUBLIC_ID_ATTEMPTS; attempt++) {
    const publicId = generatePublicId();

    const { data: prediction, error: insertError } = await supabase
      .from("predictions")
      .insert({
        public_id: publicId,
        event_slug: params.eventSlug,
        nickname: params.nickname,
        country_code: params.countryCode,
        data_status: params.dataStatus,
        device_token: params.deviceToken,
        ...(params.authUserId ? { auth_user_id: params.authUserId } : {}),
      })
      .select("id, public_id")
      .single();

    if (insertError) {
      // A public_id collision is astronomically unlikely (46 bits of
      // entropy) but retrying costs nothing. A conflict on the
      // identity index (Phase C) or the legacy device index both mean
      // "this identity/device already has a prediction for this
      // event" â€” treat either as success and hand back the existing
      // one, so a double-tap, a race, or a retry never looks like a
      // hard failure. See insert-conflict.ts for why the message is
      // classified rather than just checked for "public_id" â€” Phase C
      // adds a second possible unique constraint to distinguish.
      if (insertError.code === UNIQUE_VIOLATION) {
        const conflict = classifyInsertConflict(insertError.message);

        if (conflict === "public_id") continue;

        if (conflict === "identity" && params.authUserId) {
          const existing = await getPredictionByAuthUserId(params.eventSlug, params.authUserId);
          if (existing) {
            return { success: true, publicId: existing.publicId, alreadyExisted: true };
          }
        }

        if (conflict === "device" || conflict === "unknown") {
          const existing = await getPredictionByDeviceToken(params.eventSlug, params.deviceToken);
          if (existing) {
            return { success: true, publicId: existing.publicId, alreadyExisted: true };
          }
        }
      }
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    // FOUCH 0.3A: every prediction, including a first-time submission,
    // is now version 1 of its versioned history â€” not a special case.
    // See createPredictionVersion() below for the same shape used by
    // every later edit.
    const { data: version, error: versionError } = await supabase
      .from("prediction_versions")
      .insert({ prediction_id: prediction.id, version_number: 1 })
      .select("id")
      .single();

    if (versionError || !version) {
      await supabase.from("predictions").delete().eq("id", prediction.id);
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    const items = params.participantIds.map((participantId, index) => ({
      prediction_id: prediction.id,
      version_id: version.id,
      participant_id: participantId,
      predicted_position: index + 1,
    }));

    const { error: itemsError } = await supabase.from("prediction_items").insert(items);

    if (itemsError) {
      // Compensating cleanup â€” Supabase's JS client has no
      // multi-statement transaction here, so we manually undo the
      // parent rows rather than leave an incomplete prediction behind.
      // Deleting `predictions` cascades to `prediction_versions`
      // (on delete cascade), which in turn cascades to any
      // `prediction_items` already inserted for it.
      await supabase.from("predictions").delete().eq("id", prediction.id);
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    const { error: currentVersionError } = await supabase
      .from("predictions")
      .update({ current_version_id: version.id })
      .eq("id", prediction.id);

    if (currentVersionError) {
      await supabase.from("predictions").delete().eq("id", prediction.id);
      return { success: false, error: "We couldn't save your prediction. Please try again." };
    }

    return { success: true, publicId: prediction.public_id, alreadyExisted: false };
  }

  return { success: false, error: "We couldn't generate a unique link. Please try again." };
}

export interface EditablePrediction {
  publicId: string;
  eventSlug: string;
  authUserId: string | null;
  /** Highest version_number that exists for this prediction â€” the
   * next successful edit is version_number = latestVersionNumber + 1. */
  latestVersionNumber: number;
  /** Participant IDs of the CURRENT version, in ranked order â€” used
   * to pre-fill the edit builder. */
  currentRankedParticipantIds: string[];
}

/**
 * The one lookup the edit flow needs before authorizing anything:
 * who owns this prediction (by auth_user_id, never anything the
 * client supplies) and what its current ranking/version number are.
 * Returns null if the prediction, its current version, or its items
 * can't be resolved â€” callers must treat that as "can't edit", never
 * as "treat as new".
 */
export async function getPredictionForEdit(publicId: string): Promise<EditablePrediction | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select("id, public_id, event_slug, auth_user_id, current_version_id")
    .eq("public_id", publicId)
    .single();

  if (error || !prediction || !prediction.current_version_id) return null;

  const { data: currentVersion, error: versionError } = await supabase
    .from("prediction_versions")
    .select("version_number")
    .eq("id", prediction.current_version_id)
    .single();

  if (versionError || !currentVersion) return null;

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("participant_id, predicted_position")
    .eq("version_id", prediction.current_version_id)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return null;

  return {
    publicId: prediction.public_id,
    eventSlug: prediction.event_slug,
    authUserId: prediction.auth_user_id,
    latestVersionNumber: currentVersion.version_number,
    currentRankedParticipantIds: items.map((item) => item.participant_id),
  };
}

export type CreateVersionResult =
  | { success: true; publicId: string; versionNumber: number; unchanged: boolean }
  | { success: false; error: string };

/**
 * Creates a new immutable version for an EXISTING logical prediction
 * and makes it current. Never touches public_id, never creates a new
 * `predictions` row â€” this is exclusively the "edit" path; first
 * submissions go through insertPrediction() above.
 *
 * Idempotency (brief Â§19): if the submitted ranking is identical to
 * the prediction's current version, this is a no-op that returns
 * success without creating a new version â€” the simplest robust
 * defense against a double-click or a network retry re-sending the
 * exact same edit, with no client-supplied idempotency key needed.
 * A retry that lands after a lost response looks identical to the
 * original request, so this naturally covers that case too.
 *
 * Concurrency: `expectedVersionNumber` must match the version number
 * the caller read just before presenting the edit form. A mismatch
 * means someone else's edit (or this same edit, retried, but no
 * longer the current version) landed first â€” reported as a
 * conflict rather than silently overwritten, satisfying "a retry
 * must not accidentally create uncontrolled duplicate versions" from
 * the other direction (never silently stack two edits based on a
 * stale read either).
 */
export async function createPredictionVersion(params: {
  predictionPublicId: string;
  participantIds: string[];
  expectedVersionNumber: number;
  currentRankedParticipantIds: string[];
}): Promise<CreateVersionResult> {
  const supabase = getSupabaseServerClient();
  if (!supabase) {
    return { success: false, error: "Editing isn't available right now — the database isn't configured." };
  }

  const isUnchanged = isRankingUnchanged(params.currentRankedParticipantIds, params.participantIds);

  if (isUnchanged) {
    return {
      success: true,
      publicId: params.predictionPublicId,
      versionNumber: params.expectedVersionNumber,
      unchanged: true,
    };
  }

  const { data: prediction, error: predictionError } = await supabase
    .from("predictions")
    .select("id, current_version_id")
    .eq("public_id", params.predictionPublicId)
    .single();

  if (predictionError || !prediction) {
    return { success: false, error: "We couldn't find that prediction." };
  }

  // Re-check the expected version number against the DB row we just
  // read, not the one the caller assumed â€” closes the gap between
  // "the page loaded the current ranking" and "the save request
  // actually landed", per the concurrency note above.
  const { data: currentVersionRow, error: currentVersionRowError } = await supabase
    .from("prediction_versions")
    .select("version_number")
    .eq("id", prediction.current_version_id)
    .single();

  if (currentVersionRowError || !currentVersionRow) {
    return { success: false, error: "We couldn't verify your prediction's current version." };
  }

  if (currentVersionRow.version_number !== params.expectedVersionNumber) {
    return {
      success: false,
      error: "Your prediction changed elsewhere since you opened this — please reload and try again.",
    };
  }

  const nextVersionNumber = currentVersionRow.version_number + 1;

  const { data: newVersion, error: versionError } = await supabase
    .from("prediction_versions")
    .insert({ prediction_id: prediction.id, version_number: nextVersionNumber })
    .select("id")
    .single();

  if (versionError || !newVersion) {
    // A unique-violation on (prediction_id, version_number) here means
    // a concurrent edit already claimed this exact next version number
    // â€” report as a conflict rather than silently retrying with a
    // higher number, which could race indefinitely under contention.
    return {
      success: false,
      error: "Your prediction changed elsewhere since you opened this — please reload and try again.",
    };
  }

  const items = params.participantIds.map((participantId, index) => ({
    prediction_id: prediction.id,
    version_id: newVersion.id,
    participant_id: participantId,
    predicted_position: index + 1,
  }));

  const { error: itemsError } = await supabase.from("prediction_items").insert(items);

  if (itemsError) {
    // Compensating cleanup, same pattern as insertPrediction(): undo
    // the orphaned version row rather than leave a version with no
    // items behind. current_version_id was never pointed at it, so
    // no reader ever saw this partial state.
    await supabase.from("prediction_versions").delete().eq("id", newVersion.id);
    return { success: false, error: "We couldn't save your changes. Please try again." };
  }

  const { error: updateError } = await supabase
    .from("predictions")
    .update({ current_version_id: newVersion.id })
    .eq("id", prediction.id);

  if (updateError) {
    await supabase.from("prediction_versions").delete().eq("id", newVersion.id);
    return { success: false, error: "We couldn't save your changes. Please try again." };
  }

  return {
    success: true,
    publicId: params.predictionPublicId,
    versionNumber: nextVersionNumber,
    unchanged: false,
  };
}

export async function getPredictionByPublicId(publicId: string): Promise<PredictionRecord | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select(
      "public_id, event_slug, nickname, country_code, data_status, submitted_at, id, current_version_id, auth_user_id",
    )
    .eq("public_id", publicId)
    .single();

  if (error || !prediction || !prediction.current_version_id) return null;

  const { data: currentVersion, error: currentVersionError } = await supabase
    .from("prediction_versions")
    .select("version_number")
    .eq("id", prediction.current_version_id)
    .single();

  if (currentVersionError || !currentVersion) return null;

  // FOUCH 0.3A: always the CURRENT version's items â€” never every
  // version ever saved. This is the one place every public-facing
  // read of "this prediction's ranking" ultimately goes through.
  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("participant_id, predicted_position")
    .eq("version_id", prediction.current_version_id)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return null;

  return {
    id: prediction.id,
    publicId: prediction.public_id,
    eventSlug: prediction.event_slug,
    nickname: prediction.nickname,
    countryCode: prediction.country_code,
    dataStatus: prediction.data_status as ParticipantDataStatus,
    submittedAt: prediction.submitted_at,
    hasVerifiedOwner: prediction.auth_user_id !== null,
    currentVersionNumber: currentVersion.version_number,
    rankedParticipantIds: items.map((item) => item.participant_id),
  };
}

export async function getPredictionByDeviceToken(
  eventSlug: string,
  deviceToken: string,
): Promise<PredictionRecord | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select("public_id")
    .eq("event_slug", eventSlug)
    .eq("device_token", deviceToken)
    .maybeSingle();

  if (error || !prediction) return null;

  return getPredictionByPublicId(prediction.public_id);
}

/**
 * Beta Hardening 0.2 Phase C â€” looks up an existing FINAL prediction
 * by verified identity, the same shape as getPredictionByDeviceToken
 * above, used for the identity unique-constraint conflict path.
 */
export async function getPredictionByAuthUserId(
  eventSlug: string,
  authUserId: string,
): Promise<PredictionRecord | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data: prediction, error } = await supabase
    .from("predictions")
    .select("public_id")
    .eq("event_slug", eventSlug)
    .eq("auth_user_id", authUserId)
    .eq("is_final", true)
    .maybeSingle();

  if (error || !prediction) return null;

  return getPredictionByPublicId(prediction.public_id);
}

/**
 * Beta Hardening 0.2 Phase C â€” feeds the soft, non-blocking
 * same-device/different-identity signal (see insert-conflict.ts's
 * isDeviceIdentityMismatch). Returns only the two fields that
 * function needs â€” never a full PredictionRecord, since this is
 * purely an internal analytics signal, not a user-facing lookup.
 */
export async function getDeviceTokenIdentity(
  eventSlug: string,
  deviceToken: string,
): Promise<{ deviceToken: string; authUserId: string | null } | null> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return null;

  const { data, error } = await supabase
    .from("predictions")
    .select("device_token, auth_user_id")
    .eq("event_slug", eventSlug)
    .eq("device_token", deviceToken)
    .eq("is_final", true)
    .maybeSingle();

  if (error || !data) return null;

  return { deviceToken: data.device_token, authUserId: data.auth_user_id };
}

/**
 * Resolves a stored prediction's participant IDs back into full
 * Participant records (name, country) via the same seed/demo data the
 * builder uses, in the prediction's saved rank order. Returns null if
 * the prediction or any of its referenced participants can no longer
 * be resolved (e.g. seed data changed).
 */
export async function getPredictionWithParticipants(publicId: string, locale: Locale = "en"): Promise<{
  prediction: PredictionRecord;
  event: FouchEvent;
  rankedParticipants: Participant[];
} | null> {
  const prediction = await getPredictionByPublicId(publicId);
  if (!prediction) return null;

  const event = await getEventBySlug(prediction.eventSlug);
  if (!event) return null;

  // FOUCH 0.3B: resolves by id regardless of current status â€” a
  // participant who has since become WITHDRAWN/REPLACED must still
  // render here with their real name/country. Using the active-only
  // getParticipantsForEvent here would silently drop such an entry
  // (or, worse, fail the length check below and 404 the whole public
  // prediction) the moment their status changed after the fact.
  const participantsById = await resolveParticipantsByIds(prediction.eventSlug, prediction.rankedParticipantIds, locale);

  const rankedParticipants = prediction.rankedParticipantIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  if (rankedParticipants.length !== prediction.rankedParticipantIds.length) return null;

  return { prediction, event, rankedParticipants };
}

/**
 * Fetches every ranked-ID list eligible for comparison against a given
 * event + data-status â€” the raw material for community-comparison.ts.
 * Only `id` and `participant_id`/`predicted_position` are selected;
 * nickname, country, and device_token never leave the database for
 * this purpose (see Sprint 3 brief section 22, privacy).
 *
 * "Eligible" here means: same event, same data_status (demo
 * predictions and future verified predictions never mix â€” see
 * section 9), and exactly 10 items. A prediction with a corrupted or
 * incomplete item set is silently excluded rather than crashing the
 * comparison.
 */
export async function getEligiblePredictionsForComparison(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<EligiblePrediction[]> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  // FOUCH 0.3A: `id` here is the logical prediction's key used only to
  // group items below; `current_version_id` is what actually scopes
  // which items count â€” a prediction with 3 saved versions must still
  // contribute exactly ONE eligible ranking (its current one), never
  // three (brief Â§12: "Freddy has v1, v2, v3 â†’ community sample size
  // is 1 prediction, not 3").
  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id, current_version_id")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true)
    .not("current_version_id", "is", null);

  if (error || !predictions || predictions.length === 0) return [];

  const versionIds = predictions.map((p) => p.current_version_id as string);

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, version_id, participant_id, predicted_position")
    .in("version_id", versionIds)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return [];

  const itemsByPrediction = new Map<string, string[]>();
  for (const item of items) {
    const list = itemsByPrediction.get(item.prediction_id) ?? [];
    list.push(item.participant_id);
    itemsByPrediction.set(item.prediction_id, list);
  }

  const eligible: EligiblePrediction[] = [];
  for (const [predictionId, rankedParticipantIds] of itemsByPrediction) {
    // Defensive: a prediction with anything other than exactly 10
    // items is malformed and excluded rather than skewing the
    // comparison (see section 33, edge cases).
    if (rankedParticipantIds.length === 10) {
      eligible.push({ predictionId, rankedParticipantIds });
    }
  }

  return eligible;
}

export interface LeaderboardRawEntry {
  predictionId: string;
  publicId: string;
  nickname: string | null;
  countryCode: string | null;
  rankedParticipantIds: string[];
}

/**
 * Same eligibility filters as getEligiblePredictionsForComparison
 * (event + data_status + is_final=true + exactly 10 items) â€” kept as a
 * near-identical second query, deliberately, rather than reusing that
 * function directly: that function's contract explicitly promises to
 * never select nickname/country (see its comment) so it stays safe to
 * reuse anywhere privacy matters. The leaderboard's whole purpose is
 * to show nickname/country publicly, so it needs its own query rather
 * than weakening that guarantee.
 */
export async function getLeaderboardRawEntries(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<LeaderboardRawEntry[]> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  // FOUCH 0.3A: same current-version-only scoping as
  // getEligiblePredictionsForComparison above â€” a prediction with
  // several saved versions is still exactly one leaderboard entry
  // (brief Â§13), never one entry per version.
  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id, public_id, nickname, country_code, current_version_id")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true)
    .not("current_version_id", "is", null);

  if (error || !predictions || predictions.length === 0) return [];

  const versionIds = predictions.map((p) => p.current_version_id as string);

  const { data: items, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, version_id, participant_id, predicted_position")
    .in("version_id", versionIds)
    .order("predicted_position", { ascending: true });

  if (itemsError || !items) return [];

  const itemsByPrediction = new Map<string, string[]>();
  for (const item of items) {
    const list = itemsByPrediction.get(item.prediction_id) ?? [];
    list.push(item.participant_id);
    itemsByPrediction.set(item.prediction_id, list);
  }

  const entries: LeaderboardRawEntry[] = [];
  for (const prediction of predictions) {
    const rankedParticipantIds = itemsByPrediction.get(prediction.id) ?? [];
    if (rankedParticipantIds.length === 10) {
      entries.push({
        predictionId: prediction.id,
        publicId: prediction.public_id,
        nickname: prediction.nickname,
        countryCode: prediction.country_code,
        rankedParticipantIds,
      });
    }
  }

  return entries;
}

/**
 * Experiment 01 ("Your Crowd Changed") â€” the leanest possible query for
 * this experiment: only each eligible prediction's submission time and
 * #1 (winner) pick, never the full 10-item ranking. Deliberately a
 * separate query rather than reusing getEligiblePredictionsForComparison
 * or getLeaderboardRawEntries â€” those fetch every item of every
 * prediction, which this experiment doesn't need at all.
 *
 * Eligibility mirrors both of those functions exactly: same event_slug,
 * same data_status, is_final = true, and (checked via the items query)
 * exactly 10 items â€” never a different population definition for the
 * same underlying concept of "an eligible prediction."
 */
export async function getWinnerPicksForConsensusChange(
  eventSlug: string,
  dataStatus: ParticipantDataStatus,
): Promise<Array<{ predictionId: string; submittedAt: string; winnerParticipantId: string }>> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  // FOUCH 0.3A: `submitted_at` remains the prediction's ORIGINAL
  // submission time (predictions.submitted_at is never touched by an
  // edit â€” only prediction_versions.created_at records when each
  // version was saved). Experiment 01's semantics with an edited
  // winner pick are addressed separately below (brief Â§17) â€” this
  // function's contract (submission time + CURRENT winner pick) is
  // unchanged here on purpose.
  const { data: predictions, error } = await supabase
    .from("predictions")
    .select("id, submitted_at, current_version_id")
    .eq("event_slug", eventSlug)
    .eq("data_status", dataStatus)
    .eq("is_final", true)
    .not("current_version_id", "is", null);

  if (error || !predictions || predictions.length === 0) return [];

  const versionIds = predictions.map((p) => p.current_version_id as string);

  // Only position 1 (the winner pick) â€” and only from predictions with
  // exactly 10 items, so a malformed/partial prediction never counts as
  // an eligible "winner pick" here either.
  const { data: allItems, error: itemsError } = await supabase
    .from("prediction_items")
    .select("prediction_id, version_id, participant_id, predicted_position")
    .in("version_id", versionIds);

  if (itemsError || !allItems) return [];

  const itemCountByPrediction = new Map<string, number>();
  const winnerByPrediction = new Map<string, string>();
  for (const item of allItems) {
    itemCountByPrediction.set(item.prediction_id, (itemCountByPrediction.get(item.prediction_id) ?? 0) + 1);
    if (item.predicted_position === 1) {
      winnerByPrediction.set(item.prediction_id, item.participant_id);
    }
  }

  const results: Array<{ predictionId: string; submittedAt: string; winnerParticipantId: string }> = [];
  for (const prediction of predictions) {
    const winner = winnerByPrediction.get(prediction.id);
    const itemCount = itemCountByPrediction.get(prediction.id) ?? 0;
    if (winner && itemCount === 10 && prediction.submitted_at) {
      results.push({
        predictionId: prediction.id,
        submittedAt: prediction.submitted_at,
        winnerParticipantId: winner,
      });
    }
  }

  return results;
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\predictions-db.ts"
} catch {
    Write-Host "FAILED: src\lib\predictions-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\predictions-db.ts"
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
    environment: "jsdom",
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

try {
    $path = "src\components\I18nProvider.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { createContext, useContext, type ReactNode } from "react";
import type { Dictionary } from "@/content/types";
import type { Locale } from "@/lib/locale";
import { setAnalyticsLocale } from "@/lib/analytics";

interface I18nValue {
  locale: Locale;
  dict: Dictionary;
}

const I18nContext = createContext<I18nValue | null>(null);

/** Receives the already-resolved locale + dictionary from the server
 * layout, so the first client render is already in the right language
 * (no English-then-Spanish flash). */
export function I18nProvider({ locale, dict, children }: { locale: Locale; dict: Dictionary } & { children: ReactNode }) {
  // Synchronous + idempotent on purpose: child effects (e.g. the landing_view
  // ViewTracker) run BEFORE a parent effect would, and every event needs the
  // locale from the very first capture.
  setAnalyticsLocale(locale);

  return <I18nContext.Provider value={{ locale, dict }}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18nValue {
  const value = useContext(I18nContext);
  if (!value) throw new Error("useI18n must be used inside <I18nProvider>");
  return value;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\I18nProvider.tsx"
} catch {
    Write-Host "FAILED: src\components\I18nProvider.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\I18nProvider.tsx"
}

try {
    $path = "src\components\LanguageSwitcher.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { track } from "@/lib/analytics";
import { useI18n } from "@/components/I18nProvider";
import { LOCALE_COOKIE, LOCALE_COOKIE_MAX_AGE, localizePath, stripLocalePrefix, type Locale } from "@/lib/locale";

/**
 * EN | ES — a plain, keyboard-accessible pair of links/buttons (no
 * flags: language is not country). Choosing a language persists it in
 * a cookie (read server-side by the middleware, so there is no
 * English-then-Spanish flash), fires language_changed, and does a full
 * navigation to the same logical page under the target locale's URL —
 * /p/abc <-> /es/p/abc — which is the same prediction either way.
 */
export function LanguageSwitcher({ eventSlug }: { eventSlug?: string }) {
  const { locale, dict } = useI18n();

  function choose(target: Locale) {
    if (target === locale) return;

    const currentPath = window.location.pathname;
    const logicalPath = stripLocalePrefix(currentPath);

    track("language_changed", {
      from_locale: locale,
      to_locale: target,
      page: logicalPath,
      ...(eventSlug ? { event_slug: eventSlug } : {}),
    });

    document.cookie = `${LOCALE_COOKIE}=${target}; path=/; max-age=${LOCALE_COOKIE_MAX_AGE}; samesite=lax`;
    window.location.assign(`${localizePath(logicalPath, target)}${window.location.search}${window.location.hash}`);
  }

  const options: Array<{ code: Locale; label: string }> = [
    { code: "en", label: "EN" },
    { code: "es", label: "ES" },
  ];

  return (
    <div role="group" aria-label={dict.nav.language} className="flex items-center gap-1 text-xs font-medium tracking-[0.15em]">
      {options.map((option, index) => (
        <span key={option.code} className="flex items-center gap-1">
          {index > 0 ? (
            <span aria-hidden className="text-border-strong">
              |
            </span>
          ) : null}
          <button
            type="button"
            onClick={() => choose(option.code)}
            aria-pressed={locale === option.code}
            lang={option.code}
            className={
              locale === option.code
                ? "rounded px-1 py-0.5 text-text-primary underline underline-offset-4"
                : "rounded px-1 py-0.5 text-text-muted transition-colors hover:text-text-secondary focus-visible:text-text-primary"
            }
          >
            {option.label}
          </button>
        </span>
      ))}
    </div>
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\LanguageSwitcher.tsx"
} catch {
    Write-Host "FAILED: src\components\LanguageSwitcher.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\LanguageSwitcher.tsx"
}

try {
    $path = "src\components\localized-surfaces.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { PredictionCardMarkup } from "@/components/prediction/PredictionCardMarkup";
import { ResultCardMarkup } from "@/components/scoring/ResultCardMarkup";
import { en } from "@/content/en";
import { es } from "@/content/es";
import type { Participant } from "@/types/participant";
import type { ScoreBreakdown } from "@/types/scoring";

const participants = (countryNames: string[]): Participant[] =>
  countryNames.map((countryName, i) => ({
    id: `id-${i}`,
    eventId: "evt",
    displayName: i === 0 ? "HANA DĚDKOVÁ" : `CONTESTANT ${i}`,
    countryCode: "XX",
    countryName,
    sortOrder: i,
    isActive: true,
  }));

const base = {
  eventName: "Miss Grand International 2026",
  nickname: "Perez",
  countryCode: "CV",
  isDemo: false,
};

describe("Prediction Card / Instagram Story markup — locale is presentation only", () => {
  it("English card (Story dimensions 1080x1920) keeps the existing copy", () => {
    const html = renderToStaticMarkup(
      createElement(PredictionCardMarkup, { width: 1080, height: 1920, siteDomain: "joinfouch.com", data: { ...base, rankedParticipants: participants(["Venezuela", "Philippines"]) } }),
    );
    expect(html).toContain("width:1080px;height:1920px");
    expect(html).toContain(en.share.cardHeadline);
    expect(html).toContain(en.share.cardFooter);
    expect(html).toContain("Perez · Cape Verde");
    expect(html).toContain("Philippines");
    expect(html).toContain("joinfouch.com");
  });

  it("Spanish card localizes headline, footer, predictor country and contestant country — never changes the contestant", () => {
    const html = renderToStaticMarkup(
      createElement(PredictionCardMarkup, { width: 1080, height: 1920, siteDomain: "joinfouch.com", data: { ...base, locale: "es", rankedParticipants: participants(["Venezuela", "Filipinas"]) } }),
    );
    expect(html).toContain("HAZ TU PREDICCIÓN.");
    expect(html).toContain("¿CUÁL ES EL TUYO?");
    expect(html).toContain("Perez · Cabo Verde");
    expect(html).toContain("Filipinas");
    expect(html).toContain("HANA DĚDKOVÁ");
    expect(html).toContain("Miss Grand International 2026");
    expect(html).toContain("joinfouch.com");
  });

  it("Post format (1080x1350) localizes the same way", () => {
    const html = renderToStaticMarkup(
      createElement(PredictionCardMarkup, { width: 1080, height: 1350, siteDomain: "joinfouch.com", data: { ...base, locale: "es", rankedParticipants: participants(["Venezuela"]) } }),
    );
    expect(html).toContain("width:1080px;height:1350px");
    expect(html).toContain(es.share.cardFooter);
  });

  it("no private identity information appears in a localized card", () => {
    const html = renderToStaticMarkup(
      createElement(PredictionCardMarkup, { width: 1080, height: 1920, siteDomain: "joinfouch.com", data: { ...base, locale: "es", rankedParticipants: participants(["Venezuela"]) } }),
    );
    expect(html).not.toMatch(/auth_user_id|device_token|@[a-z0-9-]+\./i);
    expect(html).not.toContain("vercel.app");
  });
});

describe("Result Card markup — localized", () => {
  const breakdown = {
    band: "GOOD",
    displayScore: 72,
    score: 72,
    components: {
      winner: { hit: true },
      podium: { hits: 2, total: 3 },
      top5: { hits: 3, total: 5 },
      top10: { hits: 6, total: 10 },
    },
  } as unknown as ScoreBreakdown;

  it("Spanish result card localizes band, labels and footer", () => {
    const html = renderToStaticMarkup(
      createElement(ResultCardMarkup, { width: 1080, height: 1920, siteDomain: "joinfouch.com", data: { eventName: "Miss Grand International 2026", nickname: "Perez", countryCode: "CV", isDemo: false, breakdown, percentile: 80, locale: "es" } as never }),
    );
    expect(html).toContain("BUENA PREDICCIÓN");
    expect(html).toContain("Ganadora");
    expect(html).toContain("Acertaste");
    expect(html).toContain("TOP 20%");
    expect(html).toContain("¿CREES QUE PUEDES SUPERARLO?");
    expect(html).toContain("Perez · Cabo Verde");
  });

  it("English result card is unchanged", () => {
    const html = renderToStaticMarkup(
      createElement(ResultCardMarkup, { width: 1080, height: 1920, siteDomain: "joinfouch.com", data: { eventName: "Miss Grand International 2026", nickname: null, countryCode: null, isDemo: false, breakdown, percentile: 80 } as never }),
    );
    expect(html).toContain("GOOD CALL");
    expect(html).toContain("THINK YOU COULD BEAT IT?");
    expect(html).toContain("TOP 20%");
  });
});

describe("root layout — html lang, canonical, hreflang, canonical domain", () => {
  async function loadLayout(locale: "en" | "es") {
    vi.resetModules();
    vi.doMock("@/lib/i18n-server", () => ({
      getI18n: async () => ({ locale, dict: locale === "es" ? es : en }),
      getLocale: async () => locale,
    }));
    vi.doMock("./../app/globals.css", () => ({}));
    return import("@/app/layout");
  }

  it("<html lang> follows the rendered locale", async () => {
    const enLayout = await loadLayout("en");
    const enEl = (await enLayout.default({ children: null })) as { props: { lang: string } };
    expect(enEl.props.lang).toBe("en");

    const esLayout = await loadLayout("es");
    const esEl = (await esLayout.default({ children: null })) as { props: { lang: string } };
    expect(esEl.props.lang).toBe("es");
  });

  it("metadata: localized title/description, per-locale canonical, hreflang en/es/x-default", async () => {
    const esLayout = await loadLayout("es");
    const md = await esLayout.generateMetadata();
    expect((md.title as { default: string }).default).toBe("FOUCH — Predicciones de entretenimiento");
    expect(md.description).toBe(es.meta.description);
    expect(md.alternates?.canonical).toBe("/es");
    expect(md.alternates?.languages).toEqual({ en: "/", es: "/es", "x-default": "/" });

    const enLayout = await loadLayout("en");
    const enMd = await enLayout.generateMetadata();
    expect((enMd.title as { default: string }).default).toBe("FOUCH — Entertainment Predictions");
    expect(enMd.alternates?.canonical).toBe("/");
  });

  it("OpenGraph URL stays on the canonical origin and never uses the legacy Vercel domain", async () => {
    const esLayout = await loadLayout("es");
    const md = await esLayout.generateMetadata();
    const og = md.openGraph as { url: string; locale: string };
    expect(og.url.endsWith("/es")).toBe(true);
    expect(og.locale).toBe("es_LA");
    expect(JSON.stringify(md)).not.toContain("fouch-tau.vercel.app");
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\components\localized-surfaces.test.ts"
} catch {
    Write-Host "FAILED: src\components\localized-surfaces.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\components\localized-surfaces.test.ts"
}

try {
    $path = "src\lib\analytics-locale.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
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
    $path = "src\lib\country-locale.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { PREDICTOR_COUNTRIES, getLocalizedCountryName, getPredictorCountryName } from "./countries";
import { localizeParticipant } from "./participant-locale";
import type { Participant } from "@/types/participant";

describe("country names render in the viewer's locale", () => {
  it("English returns the existing English name untouched (incl. roster names Intl would rename)", () => {
    expect(getLocalizedCountryName("PH", "Philippines", "en")).toBe("Philippines");
    expect(getLocalizedCountryName("CZ", "Czech Republic", "en")).toBe("Czech Republic");
  });

  it("Spanish uses natural Spanish names", () => {
    expect(getLocalizedCountryName("PH", "Philippines", "es")).toBe("Filipinas");
    expect(getLocalizedCountryName("US", "United States", "es")).toBe("Estados Unidos");
    expect(getLocalizedCountryName("VE", "Venezuela", "es")).toBe("Venezuela");
    expect(getLocalizedCountryName("CL", "Chile", "es")).toBe("Chile");
  });

  it("never exposes a raw ISO code — falls back to the English name when Intl has nothing", () => {
    const xk = getLocalizedCountryName("XK", "Kosovo", "es");
    expect(xk).not.toBe("XK");
    expect(xk.length).toBeGreaterThan(2);
  });

  it("every selectable predictor country resolves to a real name in Spanish (not a bare code)", () => {
    for (const country of PREDICTOR_COUNTRIES) {
      const name = getLocalizedCountryName(country.code, country.name, "es");
      expect(name, country.code).not.toBe(country.code);
      expect(name.length, country.code).toBeGreaterThan(2);
    }
  });

  it("predictor country lookup is locale-aware and still null-safe", () => {
    expect(getPredictorCountryName("PH", "es")).toBe("Filipinas");
    expect(getPredictorCountryName("PH")).toBe("Philippines");
    expect(getPredictorCountryName(null, "es")).toBeNull();
    expect(getPredictorCountryName("ZZ", "es")).toBeNull();
  });
});

describe("localizeParticipant — presentation only, identity untouched", () => {
  const participant: Participant = {
    id: "uuid-1",
    eventId: "evt",
    displayName: "HANA DĚDKOVÁ",
    countryCode: "PH",
    countryName: "Philippines",
    sortOrder: 4,
    isActive: true,
  };

  it("only countryName changes; id, official name, code, status, order are identical", () => {
    const es = localizeParticipant(participant, "es");
    expect(es.countryName).toBe("Filipinas");
    expect({ ...es, countryName: "x" }).toEqual({ ...participant, countryName: "x" });
    expect(es.displayName).toBe("HANA DĚDKOVÁ");
  });

  it("English returns the very same object", () => {
    expect(localizeParticipant(participant, "en")).toBe(participant);
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\country-locale.test.ts"
} catch {
    Write-Host "FAILED: src\lib\country-locale.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\country-locale.test.ts"
}

try {
    $path = "src\lib\event-time-display-locale.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { formatEventLocalLockTime, formatEventDayMonth, formatContestantListUpdated } from "./event-time-display";

const BANGKOK_LOCK = "2026-10-09T17:00:00Z"; // Oct 10 00:00 in Bangkok (GMT+7)

describe("event time display — locale-aware presentation, same instant", () => {
  it("English output is unchanged (default locale)", () => {
    expect(formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok")).toBe(
      formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok", "en"),
    );
    expect(formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok", "en")).toContain("Oct 10 at 12:00 AM");
  });

  it("Spanish uses Spanish month/day-period and keeps the timezone", () => {
    const es = formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok", "es");
    expect(es).toMatch(/10 oct/i);
    expect(es).toMatch(/GMT\+7/);
    expect(es).not.toMatch(/\bAM\b/);
  });

  it("CRITICAL: localizing never changes the underlying instant", () => {
    const before = new Date(BANGKOK_LOCK).getTime();
    formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok", "es");
    formatEventLocalLockTime(BANGKOK_LOCK, "Asia/Bangkok", "en");
    expect(new Date(BANGKOK_LOCK).getTime()).toBe(before);
  });

  it("day/month label: English unchanged, Spanish day-first", () => {
    expect(formatEventDayMonth("2026-10-10", "en")).toBe("OCT 10");
    expect(formatEventDayMonth("2026-10-10", "es")).toMatch(/^10 OCT/);
  });

  it("roster-updated note uses the localized template and date", () => {
    expect(formatContestantListUpdated("2026-09-22T00:00:00Z", "Updated {date}", "en")).toMatch(/^Updated Sep 22, 2026/);
    expect(formatContestantListUpdated("2026-09-22T00:00:00Z", "Actualizada el {date}", "es")).toMatch(/^Actualizada el 22 sept/i);
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-time-display-locale.test.ts"
} catch {
    Write-Host "FAILED: src\lib\event-time-display-locale.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-time-display-locale.test.ts"
}

try {
    $path = "src\lib\i18n-server.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { headers } from "next/headers";
import { DEFAULT_LOCALE, LOCALE_HEADER, PATH_HEADER, isLocale, type Locale } from "@/lib/locale";
import { getDictionary } from "@/lib/i18n";

/** The request locale, set by src/middleware.ts. Falls back to English
 * if the header is somehow absent (e.g. a build-time render). */
export async function getLocale(): Promise<Locale> {
  const value = (await headers()).get(LOCALE_HEADER);
  return isLocale(value) ? value : DEFAULT_LOCALE;
}

/** The original (locale-stripped) request path, e.g. "/p/abc". */
export async function getRequestPath(): Promise<string> {
  return (await headers()).get(PATH_HEADER) ?? "/";
}

export async function getI18n() {
  const locale = await getLocale();
  return { locale, dict: getDictionary(locale) };
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\i18n-server.ts"
} catch {
    Write-Host "FAILED: src\lib\i18n-server.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\i18n-server.ts"
}

try {
    $path = "src\lib\i18n.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { en } from "@/content/en";
import { es } from "@/content/es";
import { getDictionary, fmt } from "./i18n";

function flatten(value: unknown, prefix = ""): Record<string, string> {
  if (typeof value === "string") return { [prefix]: value };
  if (Array.isArray(value)) {
    return value.reduce<Record<string, string>>((acc, item, i) => ({ ...acc, ...flatten(item, `${prefix}[${i}]`) }), {});
  }
  if (value && typeof value === "object") {
    return Object.entries(value).reduce<Record<string, string>>(
      (acc, [k, v]) => ({ ...acc, ...flatten(v, prefix ? `${prefix}.${k}` : k) }),
      {},
    );
  }
  return {};
}
const placeholders = (s: string) => (s.match(/\{\w+\}/g) ?? []).sort();

describe("dictionaries — EN is the source of truth, ES must mirror it", () => {
  const flatEn = flatten(en);
  const flatEs = flatten(es);

  it("Spanish has exactly the same keys as English (no missing, no extra)", () => {
    expect(Object.keys(flatEs).sort()).toEqual(Object.keys(flatEn).sort());
  });

  it("no empty strings in either language", () => {
    for (const [key, value] of [...Object.entries(flatEn), ...Object.entries(flatEs)]) {
      expect(value.trim().length, key).toBeGreaterThan(0);
    }
  });

  it("every template keeps the same {placeholders} in both languages (a translation can't drop {n}/{name})", () => {
    for (const key of Object.keys(flatEn)) {
      const enPh = placeholders(flatEn[key] ?? "");
      const esPh = placeholders(flatEs[key] ?? "");
      // Spanish may legitimately omit {noun} where English needs the configurable entry noun.
      const required = enPh.filter((p) => p !== "{noun}");
      for (const p of required) expect(esPh, `${key} missing ${p}`).toContain(p);
    }
  });

  it("the FOUCH brand name is never translated away", () => {
    expect(es.meta.title).toContain("FOUCH");
    expect(es.footer.disclaimer).toContain("FOUCH");
    expect(es.closing.lineTwo).toContain("FOUCH");
  });

  it("approved Spanish brand copy", () => {
    expect(es.hero.headlineLines.join(" ")).toBe("Haz tu predicción.");
    expect(es.hero.subhead).toBe("Predice. Descubre qué piensa la comunidad. Demuestra que acertaste.");
    expect(es.closing.lineOne).toBe("Todos tienen una opinión.");
    expect(es.closing.lineTwo).toBe("FOUCH guarda el comprobante.");
  });

  it("English metadata matches the product brief", () => {
    expect(en.meta.title).toBe("FOUCH — Entertainment Predictions");
    expect(es.meta.title).toBe("FOUCH — Predicciones de entretenimiento");
  });
});

describe("getDictionary / fmt", () => {
  it("returns the right dictionary per locale", () => {
    expect(getDictionary("en")).toBe(en);
    expect(getDictionary("es")).toBe(es);
  });

  it("fills placeholders and leaves unknown ones intact", () => {
    expect(fmt("Top {n}", { n: 10 })).toBe("Top 10");
    expect(fmt("{a} and {b}", { a: "x" })).toBe("x and {b}");
  });

  it("builder/OTP strings behave identically in structure for both languages", () => {
    expect(fmt(en.builder.yourTop, { n: 10 })).toBe("Your Top 10");
    expect(fmt(es.builder.yourTop, { n: 10 })).toBe("Tu Top 10");
    expect(fmt(es.auth.enterCode, { email: "a@b.co" })).toContain("a@b.co");
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\i18n.test.ts"
} catch {
    Write-Host "FAILED: src\lib\i18n.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\i18n.test.ts"
}

try {
    $path = "src\lib\i18n.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { en } from "@/content/en";
import { es } from "@/content/es";
import type { Dictionary } from "@/content/types";
import type { Locale } from "@/lib/locale";

/** Pure dictionary lookup (edge/client/server safe). English is the
 * fallback dictionary. */
export function getDictionary(locale: Locale): Dictionary {
  return locale === "es" ? es : en;
}

/** Fills {placeholders}: fmt("Top {n}", { n: 10 }) -> "Top 10". */
export function fmt(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (match, key: string) =>
    key in vars ? String(vars[key]) : match,
  );
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\i18n.ts"
} catch {
    Write-Host "FAILED: src\lib\i18n.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\i18n.ts"
}

try {
    $path = "src\lib\language-switch.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { localizePath, stripLocalePrefix, resolveRequestLocale } from "./locale";

/** The exact composition LanguageSwitcher performs on click. */
const switchTo = (currentPath: string, target: "en" | "es") => localizePath(stripLocalePrefix(currentPath), target);

describe("manual language switch", () => {
  it("EN -> ES keeps the same logical page under /es", () => {
    expect(switchTo("/", "es")).toBe("/es");
    expect(switchTo("/predict/miss-grand-international-2026", "es")).toBe("/es/predict/miss-grand-international-2026");
    expect(switchTo("/p/abc123", "es")).toBe("/es/p/abc123");
  });

  it("ES -> EN returns to the unprefixed URL", () => {
    expect(switchTo("/es", "en")).toBe("/");
    expect(switchTo("/es/p/abc123", "en")).toBe("/p/abc123");
  });

  it("switching language never alters the prediction id in the URL", () => {
    expect(stripLocalePrefix(switchTo("/p/vksp2sfqu", "es"))).toBe("/p/vksp2sfqu");
  });

  it("the saved cookie keeps the choice on later unprefixed visits (persistence)", () => {
    expect(resolveRequestLocale({ pathname: "/predict/x", cookieValue: "es", acceptLanguage: "en-US" }).locale).toBe("es");
    expect(resolveRequestLocale({ pathname: "/predict/x", cookieValue: "en", acceptLanguage: "es-CL" }).locale).toBe("en");
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\language-switch.test.ts"
} catch {
    Write-Host "FAILED: src\lib\language-switch.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\language-switch.test.ts"
}

try {
    $path = "src\lib\locale.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import {
  detectLocaleFromAcceptLanguage,
  resolveRequestLocale,
  localizePath,
  stripLocalePrefix,
} from "./locale";

describe("detectLocaleFromAcceptLanguage — browser language, never geography", () => {
  it("defaults to English with no header", () => {
    expect(detectLocaleFromAcceptLanguage(null)).toBe("en");
    expect(detectLocaleFromAcceptLanguage("")).toBe("en");
  });

  it("maps every Spanish variant to Spanish", () => {
    for (const tag of ["es", "es-CL", "es-VE", "es-CO", "es-MX", "es-AR", "es-PE", "ES-es"]) {
      expect(detectLocaleFromAcceptLanguage(tag)).toBe("es");
    }
  });

  it("falls back to English for unsupported languages", () => {
    expect(detectLocaleFromAcceptLanguage("pt-BR")).toBe("en");
    expect(detectLocaleFromAcceptLanguage("fr-FR,de;q=0.8")).toBe("en");
    expect(detectLocaleFromAcceptLanguage("*")).toBe("en");
  });

  it("respects priority: English first stays English, Spanish first becomes Spanish", () => {
    expect(detectLocaleFromAcceptLanguage("en-US,es;q=0.5")).toBe("en");
    expect(detectLocaleFromAcceptLanguage("es-CL,es;q=0.9,en;q=0.8")).toBe("es");
    expect(detectLocaleFromAcceptLanguage("en;q=0.3,es;q=0.9")).toBe("es");
  });

  it("picks the best SUPPORTED language even when an unsupported one is listed first", () => {
    expect(detectLocaleFromAcceptLanguage("pt-BR,es;q=0.8")).toBe("es");
  });
});

describe("resolveRequestLocale — /es URL > cookie > browser > English", () => {
  it("default English rendering for a plain request", () => {
    expect(resolveRequestLocale({ pathname: "/" })).toEqual({ locale: "en", strippedPath: "/", fromPath: false });
  });

  it("Spanish browser preference -> Spanish on the unprefixed URL", () => {
    expect(resolveRequestLocale({ pathname: "/", acceptLanguage: "es-MX,es;q=0.9" }).locale).toBe("es");
  });

  it("unsupported browser language -> English fallback", () => {
    expect(resolveRequestLocale({ pathname: "/", acceptLanguage: "ja-JP" }).locale).toBe("en");
  });

  it("saved cookie beats browser language (manual ES -> EN switch persists)", () => {
    expect(resolveRequestLocale({ pathname: "/", cookieValue: "en", acceptLanguage: "es-CL" }).locale).toBe("en");
  });

  it("saved cookie beats browser language (manual EN -> ES switch persists)", () => {
    expect(resolveRequestLocale({ pathname: "/", cookieValue: "es", acceptLanguage: "en-US" }).locale).toBe("es");
  });

  it("an invalid cookie value is ignored", () => {
    expect(resolveRequestLocale({ pathname: "/", cookieValue: "fr", acceptLanguage: "es" }).locale).toBe("es");
  });

  it("explicit /es URL wins over cookie and strips the prefix so the SAME route serves it", () => {
    const r = resolveRequestLocale({ pathname: "/es/p/abc123", cookieValue: "en", acceptLanguage: "en" });
    expect(r).toEqual({ locale: "es", strippedPath: "/p/abc123", fromPath: true });
  });

  it("/p/[id] and /es/p/[id] resolve to the identical underlying path (same prediction)", () => {
    const en = resolveRequestLocale({ pathname: "/p/abc123" });
    const es = resolveRequestLocale({ pathname: "/es/p/abc123" });
    expect(es.strippedPath).toBe(en.strippedPath);
  });

  it("/es resolves to the root route", () => {
    expect(resolveRequestLocale({ pathname: "/es" }).strippedPath).toBe("/");
  });

  it("does not treat unrelated paths that merely start with 'es' as Spanish", () => {
    expect(resolveRequestLocale({ pathname: "/estimates", acceptLanguage: "en" })).toMatchObject({
      locale: "en",
      strippedPath: "/estimates",
      fromPath: false,
    });
  });
});

describe("localizePath / stripLocalePrefix", () => {
  it("English stays unprefixed, Spanish gets /es", () => {
    expect(localizePath("/", "en")).toBe("/");
    expect(localizePath("/", "es")).toBe("/es");
    expect(localizePath("/p/abc", "en")).toBe("/p/abc");
    expect(localizePath("/p/abc", "es")).toBe("/es/p/abc");
  });

  it("round-trips", () => {
    expect(stripLocalePrefix("/es/events/x")).toBe("/events/x");
    expect(stripLocalePrefix("/es")).toBe("/");
    expect(stripLocalePrefix("/events/x")).toBe("/events/x");
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\locale.test.ts"
} catch {
    Write-Host "FAILED: src\lib\locale.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\locale.test.ts"
}

try {
    $path = "src\lib\locale.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * FOUCH i18n v1 — pure, edge-safe locale rules (no server-only, no
 * next/headers) so the middleware, server components, client
 * components and unit tests all share exactly one implementation.
 *
 * Strategy: ONE application, localized presentation only. English is
 * the default and lives at the unprefixed URL (/p/abc); Spanish lives
 * at /es/... which the middleware rewrites to the very same route
 * files — so /p/abc and /es/p/abc always resolve to the same
 * prediction, and no existing public URL changes.
 */
export const LOCALES = ["en", "es"] as const;
export type Locale = (typeof LOCALES)[number];
export const DEFAULT_LOCALE: Locale = "en";

export const LOCALE_HEADER = "x-fouch-locale";
export const PATH_HEADER = "x-fouch-pathname";
export const LOCALE_COOKIE = "fouch_locale";
export const LOCALE_COOKIE_MAX_AGE = 60 * 60 * 24 * 365;

export function isLocale(value: string | null | undefined): value is Locale {
  return value === "en" || value === "es";
}

/**
 * Browser-language detection ONLY (never IP geolocation — language is
 * not geography). Walks Accept-Language by priority (q-value, then
 * order) and picks the first SUPPORTED language: any es-* -> es, en-*
 * -> en. Everything unsupported is skipped; if nothing supported
 * remains the default (English) applies.
 */
export function detectLocaleFromAcceptLanguage(header: string | null | undefined): Locale {
  if (!header) return DEFAULT_LOCALE;

  const ranked = header
    .split(",")
    .map((part, index) => {
      const [tagRaw, ...params] = part.trim().split(";");
      const qParam = params.find((p) => p.trim().startsWith("q="));
      const q = qParam ? Number.parseFloat(qParam.trim().slice(2)) : 1;
      return { tag: (tagRaw ?? "").trim().toLowerCase(), q: Number.isNaN(q) ? 0 : q, index };
    })
    .filter((entry) => entry.tag && entry.tag !== "*" && entry.q > 0)
    .sort((a, b) => b.q - a.q || a.index - b.index);

  for (const { tag } of ranked) {
    const primary = tag.split("-")[0];
    if (primary === "es") return "es";
    if (primary === "en") return "en";
  }
  return DEFAULT_LOCALE;
}

export interface ResolvedRequestLocale {
  locale: Locale;
  /** The path with any /es prefix removed — what the app routes actually serve. */
  strippedPath: string;
  /** True when the locale came from an explicit /es URL (so the
   * middleware should persist it as the user's preference). */
  fromPath: boolean;
}

/** Locale resolution order: explicit /es URL > saved cookie > browser
 * language > English. */
export function resolveRequestLocale(params: {
  pathname: string;
  cookieValue?: string | null;
  acceptLanguage?: string | null;
}): ResolvedRequestLocale {
  const { pathname, cookieValue, acceptLanguage } = params;

  if (pathname === "/es" || pathname.startsWith("/es/")) {
    return { locale: "es", strippedPath: pathname.slice(3) || "/", fromPath: true };
  }

  if (isLocale(cookieValue)) {
    return { locale: cookieValue, strippedPath: pathname, fromPath: false };
  }

  return {
    locale: detectLocaleFromAcceptLanguage(acceptLanguage),
    strippedPath: pathname,
    fromPath: false,
  };
}

/** Public URL path for a given locale: English unprefixed, Spanish under /es. */
export function localizePath(path: string, locale: Locale): string {
  const clean = path.startsWith("/") ? path : `/${path}`;
  if (locale === "en") return clean;
  return clean === "/" ? "/es" : `/es${clean}`;
}

/** Removes a leading /es so the same logical page can be re-prefixed for another locale. */
export function stripLocalePrefix(path: string): string {
  if (path === "/es") return "/";
  if (path.startsWith("/es/")) return path.slice(3);
  return path;
}

/** Reads the middleware-provided locale header value (route handlers). */
export function localeFromHeaderValue(value: string | null | undefined): Locale {
  return isLocale(value) ? value : DEFAULT_LOCALE;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\locale.ts"
} catch {
    Write-Host "FAILED: src\lib\locale.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\locale.ts"
}

try {
    $path = "src\lib\participant-locale.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import type { Participant } from "@/types/participant";
import type { Locale } from "@/lib/locale";
import { getLocalizedCountryName } from "@/lib/countries";

/**
 * i18n v1 — presentation-only localization of a participant. The id,
 * official displayName, status, and country CODE are never touched;
 * only the human-readable country name changes. (Pure, so it is
 * directly unit-testable; participants.ts is server-only.)
 */
export function localizeParticipant(participant: Participant, locale: Locale): Participant {
  if (locale === "en") return participant;
  return {
    ...participant,
    countryName: getLocalizedCountryName(participant.countryCode, participant.countryName, locale),
  };
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participant-locale.ts"
} catch {
    Write-Host "FAILED: src\lib\participant-locale.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participant-locale.ts"
}

try {
    $path = "src\lib\server-error-i18n.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { translateServerError } from "./server-error-i18n";

describe("translateServerError — display-time localization of server messages", () => {
  it("English passes through untouched", () => {
    expect(translateServerError("That code expired.", "en")).toBe("That code expired.");
  });

  it("translates known server errors to Spanish", () => {
    expect(translateServerError("That code expired.", "es")).toBe("Ese código expiró.");
    expect(translateServerError("Predictions for this event are locked.", "es")).toBe(
      "Las predicciones de este evento están cerradas.",
    );
    expect(translateServerError("We couldn't send a code — try again in a moment.", "es")).toContain("No pudimos enviar");
  });

  it("translates parameterized messages", () => {
    expect(translateServerError("Exactly 10 contestants are required.", "es")).toBe(
      "Se requieren exactamente 10 participantes.",
    );
    expect(translateServerError("Nickname must be 24 characters or fewer.", "es")).toContain("24");
  });

  it("unknown messages fall back to the original text, never blank or a raw error", () => {
    expect(translateServerError("Some brand new error", "es")).toBe("Some brand new error");
  });

  it("null stays null", () => {
    expect(translateServerError(null, "es")).toBeNull();
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\server-error-i18n.test.ts"
} catch {
    Write-Host "FAILED: src\lib\server-error-i18n.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\server-error-i18n.test.ts"
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
    $path = "src\middleware.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { NextResponse, type NextRequest } from "next/server";
import {
  LOCALE_COOKIE,
  LOCALE_COOKIE_MAX_AGE,
  LOCALE_HEADER,
  PATH_HEADER,
  resolveRequestLocale,
} from "@/lib/locale";

/**
 * FOUCH i18n v1. Resolves the request's locale and exposes it to the
 * app via a request header (x-fouch-locale) — server components,
 * server actions and image routes all read that single header.
 *
 *  - /es/...  is REWRITTEN (not redirected) to the unprefixed route,
 *    so /es/p/abc and /p/abc are literally the same route handler and
 *    the same prediction. No existing URL changes or redirects.
 *  - Unprefixed URLs use the saved cookie, else Accept-Language.
 *  - Visiting an explicit /es URL saves the preference (cookie) so
 *    internal unprefixed links keep the language.
 */
export function middleware(request: NextRequest) {
  const { pathname, search } = request.nextUrl;
  const resolved = resolveRequestLocale({
    pathname,
    cookieValue: request.cookies.get(LOCALE_COOKIE)?.value,
    acceptLanguage: request.headers.get("accept-language"),
  });

  const requestHeaders = new Headers(request.headers);
  requestHeaders.set(LOCALE_HEADER, resolved.locale);
  requestHeaders.set(PATH_HEADER, resolved.strippedPath);

  let response: NextResponse;
  if (resolved.fromPath) {
    const url = request.nextUrl.clone();
    url.pathname = resolved.strippedPath;
    url.search = search;
    response = NextResponse.rewrite(url, { request: { headers: requestHeaders } });
    response.cookies.set(LOCALE_COOKIE, resolved.locale, {
      path: "/",
      maxAge: LOCALE_COOKIE_MAX_AGE,
      sameSite: "lax",
    });
  } else {
    response = NextResponse.next({ request: { headers: requestHeaders } });
  }

  return response;
}

export const config = {
  // Everything except Next internals and static files (anything with a dot).
  matcher: ["/((?!_next/|api/|.*\\..*).*)"],
};

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\middleware.ts"
} catch {
    Write-Host "FAILED: src\middleware.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\middleware.ts"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 66 files written successfully." -ForegroundColor Green
}
