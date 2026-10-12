# FOUCH 0.3B Home Multi-Event Rendering Fix — events table drives Featured + Upcoming, no per-event hardcode.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-home-multievent-fix.ps1
$failures = @()

try {
    $path = "scripts\set-official-result.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Enters (or replaces) the official result for an event, validated
 * before it's ever written. This is the "smallest practical way to
 * enter a result" per research/Sprint 4 Â§23 â€” no admin UI, run by
 * hand from a trusted machine with the service-role key available.
 *
 * Usage:
 *   npx tsx scripts/set-official-result.ts
 *
 * To use a different result, edit RESULT below and rerun â€” the script
 * validates every participant ID before writing anything.
 *
 * SAFETY: this uses the service-role key directly, bypassing RLS.
 * Never run this against production without reviewing RESULT first.
 *
 * NOTE: this file builds its own Supabase client instead of importing
 * src/lib/supabase/server.ts, which is intentionally marked
 * "server-only" so it can never be imported from a Client Component
 * inside the Next.js app. That guard throws when run outside Next's
 * own build pipeline (e.g. via plain `tsx`), which is exactly this
 * script's situation â€” so this file deliberately does not import it.
 */
import { createClient } from "@supabase/supabase-js";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { getEventBySlug } from "../src/lib/events";
import { getParticipantsForEvent } from "../src/lib/participants";
import { validateOfficialResult } from "../src/lib/official-result-validation";
import type { OfficialResultInput } from "../src/types/scoring";

// Unlike Next.js, plain `tsx` does not load .env.local automatically â€”
// so this script loads it itself, with no new dependency required.
function loadEnvLocal() {
  const path = resolve(process.cwd(), ".env.local");
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, "utf-8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim();
    if (!(key in process.env)) process.env[key] = value;
  }
}
loadEnvLocal();

const EVENT_SLUG = "miss-universe-2026";

/**
 * FICTIONAL / DEMO RESULT â€” Miss Universe 2026 has not happened yet.
 * This is for development/testing only, matching the demo participant
 * dataset. Never presented as an official result in the product (the
 * public page and Result Card both read data_status and show a "Demo
 * result" label whenever this is used â€” see FouchScore.tsx).
 */
const DEMO_RESULT: OfficialResultInput = {
  winner: "demo-co", // Colombia
  firstRunnerUp: "demo-ve", // Venezuela
  secondRunnerUp: "demo-th", // Thailand
  top5Extras: ["demo-ph", "demo-pr"], // Philippines, Puerto Rico
  top10Extras: ["demo-in", "demo-mx", "demo-br", "demo-cl", "demo-es"], // India, Mexico, Brazil, Chile, Spain
};

async function main() {
  const event = await getEventBySlug(EVENT_SLUG);
  if (!event) {
    console.error(`Event not found: ${EVENT_SLUG}`);
    process.exit(1);
  }

  const participantData = await getParticipantsForEvent(EVENT_SLUG);
  if (!participantData) {
    console.error(`No participants configured for: ${EVENT_SLUG}`);
    process.exit(1);
  }

  const validation = validateOfficialResult(DEMO_RESULT, participantData.participants);
  if (!validation.valid) {
    console.error(`Result rejected: ${validation.error}`);
    process.exit(1);
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error(
      "Supabase isn't configured (missing NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in .env.local).",
    );
    process.exit(1);
  }
  const supabase = createClient(url, key);

  const { error } = await supabase.from("event_results").upsert(
    {
      event_slug: EVENT_SLUG,
      data_status: participantData.status, // "demo" today â€” never mixed with "verified"
      winner_participant_id: DEMO_RESULT.winner,
      first_runner_up_participant_id: DEMO_RESULT.firstRunnerUp,
      second_runner_up_participant_id: DEMO_RESULT.secondRunnerUp,
      top5_extra_participant_ids: DEMO_RESULT.top5Extras,
      top10_extra_participant_ids: DEMO_RESULT.top10Extras,
      source_note: "Development/demo fixture â€” not an official result.",
      updated_at: new Date().toISOString(),
    },
    { onConflict: "event_slug,data_status" },
  );

  if (error) {
    console.error("Failed to write result:", error.message);
    process.exit(1);
  }

  console.log(`OK: official result set for ${EVENT_SLUG} (data_status=${participantData.status}).`);
}

main();
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     scripts\set-official-result.ts"
} catch {
    Write-Host "FAILED: scripts\set-official-result.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "scripts\set-official-result.ts"
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

  const participantData = await getParticipantsForEvent(slug);
  const isDemo = participantData?.status === "demo";

  return {
    title: `${event.name} Predictions Leaderboard | FOUCH`,
    description: isDemo
      ? "A demo FOUCH predictions leaderboard â€” not an official result."
      : "See how FOUCH predictions ranked after the result.",
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

  const event = await getEventBySlug(slug);
  if (!event) notFound();

  const participantData = await getParticipantsForEvent(slug);
  if (!participantData) notFound();

  const leaderboard = await getEventLeaderboard(slug, participantData.status, from);
  const pluralNoun = getEntryNoun(event, true);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-1 font-display text-xl uppercase tracking-tight text-text-primary">
        Event leaderboard
      </p>
      <p className="mt-2 text-sm text-text-secondary">See who called it best.</p>

      {participantData.status === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo leaderboard â€” not an official outcome
        </p>
      ) : null}

      {leaderboard.status === "no_result" ? (
        <div className="mt-10 rounded border border-border bg-surface p-6">
          <p className="font-display text-xl text-text-primary">Leaderboard locked</p>
          <p className="mt-2 text-sm text-text-secondary">
            Results will appear here once {event.name} has been scored.
          </p>
          <Link
            href={`/predict/${slug}`}
            className="mt-5 inline-flex items-center justify-center rounded bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            Make your call
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
            <p className="text-sm text-text-muted">No scored predictions yet.</p>
          ) : leaderboard.totalCount === 1 ? (
            <p className="text-sm text-text-muted">First call on the board.</p>
          ) : leaderboard.totalCount <= 4 ? (
            <p className="text-sm text-text-muted">The leaderboard is just getting started.</p>
          ) : null}

          {leaderboard.viewer ? (
            <div className="mt-6 rounded border border-accent/40 bg-accent/10 p-5">
              <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-secondary">
                Your finish
              </p>
              <p className="mt-2 font-display text-4xl text-accent-strong">
                #{leaderboard.viewer.entry.rank} of {leaderboard.totalCount}
              </p>
              <p className="mt-1 text-sm text-text-secondary">
                Fouch score {leaderboard.viewer.entry.score}
                {leaderboard.viewer.percentile.percentile !== null
                  ? ` Â· Top ${Math.max(1, Math.round(100 - leaderboard.viewer.percentile.percentile))}%`
                  : ""}
              </p>
              {leaderboard.viewer.percentile.percentile === null ? (
                <p className="mt-1 text-xs text-text-muted">
                  World ranking unlocks at {MIN_PERCENTILE_SAMPLE} predictions.
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
                  />
                </li>
              ))}
            </ol>
          ) : null}

          {leaderboard.viewer && leaderboard.viewer.neighbors.length > 0 ? (
            <div className="mt-8 border-t border-border pt-6">
              <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">
                Your neighborhood
              </p>
              <ol className="mt-3 space-y-2">
                {leaderboard.viewer.neighbors.map((entry) => (
                  <li key={entry.publicId}>
                    <LeaderboardRow
                      entry={entry}
                      eventSlug={slug}
                      isViewer={entry.publicId === from}
                      prominent={false}
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
    $path = "src\app\events\[slug]\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { redirect, notFound } from "next/navigation";
import { getEventBySlug } from "@/lib/events";

/**
 * `/events/[slug]` predates the Prediction Builder (Sprint 0's
 * "coming soon" placeholder). Now that `/predict/[slug]` is real, this
 * route would just be a stale duplicate of the homepage's featured
 * event card — so it redirects straight to the builder instead of
 * carrying copy that's no longer true.
 */
export default async function EventPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
  if (!event) notFound();

  redirect(`/predict/${slug}`);
}
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\app\events\[slug]\page.tsx"
} catch {
    Write-Host "FAILED: src\app\events\[slug]\page.tsx -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\app\events\[slug]\page.tsx"
}

try {
    $path = "src\app\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { en } from "@/content/en";
import { getFeaturedEvent, getSecondaryUpcomingEvents } from "@/lib/events";
import { Nav } from "@/components/Nav";
import { Hero } from "@/components/Hero";
import { FeaturedEvent } from "@/components/FeaturedEvent";
import { UpcomingEvents } from "@/components/UpcomingEvents";
import { HowItWorks } from "@/components/HowItWorks";
import { Footer } from "@/components/Footer";
import { ViewTracker } from "@/components/ViewTracker";

// Sprint 5.1: FeaturedEvent checks live result state (for the secondary
// leaderboard link) — force fresh execution so that check is never
// baked into a static build and left stale until the next deploy.
export const dynamic = "force-dynamic";

export default async function Home() {
  const featuredEvent = await getFeaturedEvent();
  const upcomingEvents = await getSecondaryUpcomingEvents(featuredEvent?.slug ?? null);

  return (
    <>
      <ViewTracker event="landing_view" />
      <Nav />
      <main>
        <Hero dictionary={en} eventSlug={featuredEvent?.slug ?? null} />
        {featuredEvent ? (
          <FeaturedEvent event={featuredEvent} dictionary={en} />
        ) : null}
        <UpcomingEvents events={upcomingEvents} dictionary={en} />
        <HowItWorks dictionary={en} />
      </main>
      <Footer dictionary={en} />
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

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
  if (!event) return {};

  return {
    title: `Build your Top 10 â€” ${event.name}`,
    description: "Choose the 10 contestants you think will go furthest.",
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
  const event = await getEventBySlug(slug);
  if (!event) notFound();

  const participantData = await getParticipantsForEvent(slug);
  if (!participantData || participantData.participants.length === 0) {
    return (
      <main className="mx-auto max-w-content px-6 py-16">
        <Link
          href="/"
          className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          Back to Fouch
        </Link>
        <p className="mt-8 text-text-secondary">
          No participants are available for this event yet. Check back soon.
        </p>
      </main>
    );
  }

  const { status, participants, sourceCheckedAt } = participantData;
  const requiredCount = Math.min(REQUIRED_SELECTIONS, participants.length);

  return (
    <main>
      <div className="mx-auto max-w-content px-6 pt-8">
        <Link
          href="/"
          className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
        >
          <ArrowLeft className="h-4 w-4" aria-hidden />
          Back to Fouch
        </Link>

        <p className="mt-6 font-display text-sm tracking-[0.2em] text-text-muted">FOUCH</p>
        <h1 className="mt-1 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
        <p className="mt-3 font-display text-xl uppercase tracking-tight text-text-primary">
          Build your Top {requiredCount}
        </p>
        <p className="mt-2 max-w-md text-sm text-text-secondary">
          Choose the {requiredCount} contestants you think will go furthest.
        </p>

        {status === "demo" ? (
          <p className="mt-4 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
            Demo participant data â€” not the official lineup
          </p>
        ) : sourceCheckedAt ? (
          <p className="mt-4 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
            {formatContestantListUpdated(sourceCheckedAt)}
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

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
  if (!event) return {};

  return { title: `Your Top 10 â€” ${event.name}` };
}

const REQUIRED_SELECTIONS = 10;

export default async function ReviewPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = await getEventBySlug(slug);
  if (!event) notFound();

  const participantData = await getParticipantsForEvent(slug);
  if (!participantData || participantData.participants.length === 0) notFound();

  const requiredCount = Math.min(REQUIRED_SELECTIONS, participantData.participants.length);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link
        href={`/predict/${slug}`}
        className="inline-flex items-center gap-1.5 text-sm text-text-secondary hover:text-text-primary"
      >
        <ArrowLeft className="h-4 w-4" aria-hidden />
        Back to builder
      </Link>

      <p className="mt-6 font-display text-sm tracking-[0.2em] text-text-muted">FOUCH</p>
      <h1 className="mt-1 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-3 font-display text-xl uppercase tracking-tight text-text-primary">
        Your Top {requiredCount}
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
    return { success: false, error: "Verification isn't available right now â€” try again shortly." };
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
    return { success: false, error: "We couldn't send a code â€” try again in a moment." };
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
      error: "We couldn't lock your prediction. Your Top 10 is still saved â€” try again.",
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
      error: "Verification isn't available right now â€” try again shortly.",
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
      error: "Verification isn't available right now â€” try again shortly.",
      failureReason: "session_expired",
    };
  }

  const { data, error } = await supabase.auth.getUser(accessToken);

  if (error || !data.user) {
    return {
      success: false,
      error: "Your verification expired â€” please request a new code.",
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
      error: "We couldn't save your changes. Your Top 10 is still what it was â€” try again.",
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
      error: "Verification isn't available right now â€” try again shortly.",
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
      error: "Verification isn't available right now â€” try again shortly.",
      failureReason: "session_expired",
    };
  }

  const { data, error } = await supabase.auth.getUser(accessToken);

  if (error || !data.user) {
    return {
      success: false,
      error: "Your verification expired â€” please request a new code.",
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
    $path = "src\components\FeaturedEvent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { getParticipantsForEvent } from "@/lib/participants";
import { getOfficialResult } from "@/lib/results-db";
import { splitEventNameYear } from "@/lib/event-name-split";
import { TrackedLink } from "./TrackedLink";

const statusLabel: Record<FouchEvent["status"], string> = {
  upcoming: "Upcoming",
  open: "Open",
  live: "Live",
  completed: "Completed",
};

export async function FeaturedEvent({
  event,
  dictionary,
}: {
  event: FouchEvent;
  dictionary: Dictionary;
}) {
  const date = new Date(`${event.eventDate}T00:00:00Z`);
  const dayMonth = date
    .toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })
    .toUpperCase();

  // Sprint 5.1: the secondary leaderboard link is event/result-state
  // driven, never hardcoded to a specific slug â€” it only appears once
  // an official/demo result genuinely exists to rank against.
  const participantData = await getParticipantsForEvent(event.slug);
  const hasLeaderboard = participantData
    ? Boolean(await getOfficialResult(event.slug, participantData.status))
    : false;

  // Decorative only â€” a preview of the ranking mechanic, not real input.
  const previewSlots = [1, 2, 3];

  const { primary, year } = splitEventNameYear(event.name);

  return (
    <section
      id="featured-event"
      className="relative scroll-mt-20 overflow-hidden border-y border-border bg-surface py-14 sm:py-20"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute -right-24 top-1/2 h-96 w-96 -translate-y-1/2 rounded-full bg-accent/10 blur-3xl"
      />

      <div className="relative mx-auto max-w-content px-6">
        <div className="flex items-center gap-2">
          <span
            aria-hidden
            className={
              event.status === "live"
                ? "h-1.5 w-1.5 rounded-full bg-accent animate-pulse motion-reduce:animate-none"
                : "h-1.5 w-1.5 rounded-full bg-text-muted"
            }
          />
          <span className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
            {statusLabel[event.status]}
          </span>
        </div>

        <h2 className="mt-5 font-display leading-[0.95] text-text-primary">
          <span className="block text-3xl sm:text-4xl">{primary}</span>
          {year ? (
            <span className="block text-7xl font-semibold tracking-tight sm:text-8xl">{year}</span>
          ) : null}
        </h2>

        <p className="mt-4 text-sm uppercase tracking-[0.15em] text-text-muted">
          {dayMonth} · {event.subtitle}
        </p>

        <p className="mt-8 text-lg text-text-secondary">{dictionary.featuredEvent.prompt}</p>

        {/* Decorative preview of the ranking mechanic â€” not interactive. */}
        <div aria-hidden className="mt-6 max-w-xs space-y-2">
          {previewSlots.map((slot) => (
            <div key={slot} className="flex items-center gap-3">
              <span className="font-display text-sm text-text-muted">
                {String(slot).padStart(2, "0")}
              </span>
              <span className="h-px flex-1 bg-border-strong" />
            </div>
          ))}
        </div>

        <div className="mt-8 flex flex-wrap items-center gap-x-6 gap-y-3">
          <TrackedLink
            href={`/predict/${event.slug}`}
            event="featured_event_clicked"
            eventProperties={{ slug: event.slug }}
            className="group inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
          >
            {dictionary.featuredEvent.cta}
            <ArrowRight
              className="h-4 w-4 transition-transform group-hover:translate-x-0.5"
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
              View leaderboard â†’
            </TrackedLink>
          ) : null}
        </div>
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
    $path = "src\components\UpcomingEvents.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { splitEventNameYear } from "@/lib/event-name-split";
import { TrackedLink } from "./TrackedLink";

/**
 * FOUCH 0.3B Home Multi-Event Rendering Fix — the Home's secondary
 * "Upcoming" section, for any event that isn't the current Featured
 * one. Renders name/date/subtitle/CTA entirely from each event's own
 * data (via the same generic splitEventNameYear FeaturedEvent uses) —
 * no per-event branching, so this needs no changes when a third event
 * is added later.
 */
export function UpcomingEvents({ events, dictionary }: { events: FouchEvent[]; dictionary: Dictionary }) {
  if (events.length === 0) return null;

  return (
    <section className="border-t border-border bg-surface py-14 sm:py-20">
      <div className="mx-auto max-w-content px-6">
        {events.map((event) => {
          const { primary, year } = splitEventNameYear(event.name);
          const date = new Date(`${event.eventDate}T00:00:00Z`);
          const dayMonth = date
            .toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })
            .toUpperCase();

          return (
            <div key={event.slug} className="mb-10 last:mb-0">
              <div className="flex items-center gap-2">
                <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-text-muted" />
                <span className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
                  {dictionary.featuredEvent.eyebrowUpcoming}
                </span>
              </div>

              <h3 className="mt-4 font-display leading-[0.95] text-text-primary">
                <span className="block text-2xl sm:text-3xl">{primary}</span>
                {year ? (
                  <span className="block text-5xl font-semibold tracking-tight sm:text-6xl">{year}</span>
                ) : null}
              </h3>

              <p className="mt-3 text-sm uppercase tracking-[0.15em] text-text-muted">
                {dayMonth} · {event.subtitle}
              </p>

              <TrackedLink
                href={`/predict/${event.slug}`}
                event="featured_event_clicked"
                eventProperties={{ slug: event.slug, source: "upcoming_secondary" }}
                className="group mt-6 inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
              >
                {dictionary.featuredEvent.cta}
                <ArrowRight className="h-4 w-4 transition-transform group-hover:translate-x-0.5" aria-hidden />
              </TrackedLink>
            </div>
          );
        })}
      </div>
    </section>
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
import { getEventBySlugFromDb, getFeaturedEventFromDb, getUpcomingEventsFromDb } from "@/lib/events-db";

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
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\events.ts"
} catch {
    Write-Host "FAILED: src\lib\events.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\events.ts"
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
    return { success: false, error: "Submissions aren't available yet â€” the database isn't configured." };
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
    return { success: false, error: "Editing isn't available right now â€” the database isn't configured." };
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
      error: "Your prediction changed elsewhere since you opened this â€” please reload and try again.",
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
      error: "Your prediction changed elsewhere since you opened this â€” please reload and try again.",
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
export async function getPredictionWithParticipants(publicId: string): Promise<{
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
  const participantsById = await resolveParticipantsByIds(prediction.eventSlug, prediction.rankedParticipantIds);

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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-name-split.ts"
} catch {
    Write-Host "FAILED: src\lib\event-name-split.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-name-split.ts"
}

try {
    $path = "src\lib\event-name-split.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { splitEventNameYear } from "./event-name-split";

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

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-name-split.test.ts"
} catch {
    Write-Host "FAILED: src\lib\event-name-split.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-name-split.test.ts"
}

try {
    $path = "src\lib\featured-event-logic.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * FOUCH 0.3B Event Resolution Fix — the entire "which event is
 * featured" decision, in one pure, DB-free place. Extracted
 * specifically so the tie-break behavior (more than one row with
 * is_featured = true, which must never happen by product intent but
 * is not enforced by a DB constraint — see this fix's report for why)
 * is deterministic and directly testable, without needing a live
 * Supabase client.
 *
 * The real DB query (getFeaturedEventFromDb in events-db.ts) mirrors
 * this exact tie-break by ordering on `slug` ascending before
 * limiting to 1 row, so this function's behavior and the live query's
 * behavior can never drift apart.
 */
export interface FeaturedCandidate {
  slug: string;
  isFeatured: boolean;
}

/**
 * Returns the slug of the featured event, or null if none is
 * currently featured. If more than one candidate has isFeatured
 * true — a data-entry mistake, not a supported state — picks the one
 * with the alphabetically first slug, deterministically, rather than
 * an arbitrary/unstable choice.
 */
export function pickFeaturedEventSlug(candidates: FeaturedCandidate[]): string | null {
  const featured = candidates.filter((c) => c.isFeatured);
  if (featured.length === 0) return null;
  const sorted = [...featured].sort((a, b) => a.slug.localeCompare(b.slug));
  return sorted[0]?.slug ?? null;
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\featured-event-logic.ts"
} catch {
    Write-Host "FAILED: src\lib\featured-event-logic.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\featured-event-logic.ts"
}

try {
    $path = "src\lib\featured-event-logic.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { pickFeaturedEventSlug } from "./featured-event-logic";

describe("pickFeaturedEventSlug — FOUCH 0.3B Event Resolution Fix", () => {
  it("returns null when no event is featured", () => {
    expect(
      pickFeaturedEventSlug([
        { slug: "miss-universe-2026", isFeatured: false },
        { slug: "miss-grand-international-2026", isFeatured: false },
      ]),
    ).toBeNull();
  });

  it("returns the one featured event's slug", () => {
    expect(
      pickFeaturedEventSlug([
        { slug: "miss-universe-2026", isFeatured: false },
        { slug: "miss-grand-international-2026", isFeatured: true },
      ]),
    ).toBe("miss-grand-international-2026");
  });

  it("Miss Grand featured, Miss Universe upcoming secondary — the exact target state for this fix", () => {
    const slug = pickFeaturedEventSlug([
      { slug: "miss-grand-international-2026", isFeatured: true },
      { slug: "miss-universe-2026", isFeatured: false },
    ]);
    expect(slug).toBe("miss-grand-international-2026");
  });

  it("CRITICAL: if more than one event is ever marked featured (a data-entry mistake, not a supported state), picks deterministically — the alphabetically first slug — never an arbitrary/unstable choice", () => {
    const first = pickFeaturedEventSlug([
      { slug: "miss-universe-2026", isFeatured: true },
      { slug: "miss-grand-international-2026", isFeatured: true },
    ]);
    const second = pickFeaturedEventSlug([
      { slug: "miss-grand-international-2026", isFeatured: true },
      { slug: "miss-universe-2026", isFeatured: true },
    ]);
    // Same input set, different array order — must resolve to the
    // SAME slug both times (order-independent), and it must be the
    // alphabetically-first one.
    expect(first).toBe("miss-grand-international-2026");
    expect(second).toBe("miss-grand-international-2026");
  });

  it("empty candidate list returns null, never throws", () => {
    expect(() => pickFeaturedEventSlug([])).not.toThrow();
    expect(pickFeaturedEventSlug([])).toBeNull();
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\featured-event-logic.test.ts"
} catch {
    Write-Host "FAILED: src\lib\featured-event-logic.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\featured-event-logic.test.ts"
}

try {
    $path = "supabase\imports\set-featured-event.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- FOUCH 0.3B Event Resolution Fix — set the Home's featured event.
--
-- Plain data update, not a schema migration — no new column, no new
-- table. Run this in the SQL Editor once the code deploy that makes
-- `events` the source of truth for getEventBySlug/getFeaturedEvent is
-- live (otherwise the old hardcoded array would still be what the
-- Home reads, and this change would have no visible effect yet).
--
-- Does not touch prediction_lock_at, timezone, roster, or anything
-- else on either event row.

update events set is_featured = true where slug = 'miss-grand-international-2026';
update events set is_featured = false where slug = 'miss-universe-2026';

-- Verify exactly one event is featured afterward:
-- select slug, is_featured from events order by slug;
-- Expected: miss-grand-international-2026 = true, miss-universe-2026 = false.

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\imports\set-featured-event.sql"
} catch {
    Write-Host "FAILED: supabase\imports\set-featured-event.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\imports\set-featured-event.sql"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 19 files written successfully." -ForegroundColor Green
}
