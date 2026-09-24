# FOUCH 0.3B — Dynamic Participants + Miss Grand International 2026 — applies all changed/new files.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-0.3b.ps1
$failures = @()

try {
    $path = "scripts\set-official-result.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * Enters (or replaces) the official result for an event, validated
 * before it's ever written. This is the "smallest practical way to
 * enter a result" per research/Sprint 4 §23 — no admin UI, run by
 * hand from a trusted machine with the service-role key available.
 *
 * Usage:
 *   npx tsx scripts/set-official-result.ts
 *
 * To use a different result, edit RESULT below and rerun — the script
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
 * script's situation — so this file deliberately does not import it.
 */
import { createClient } from "@supabase/supabase-js";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { getEventBySlug } from "../src/lib/events";
import { getParticipantsForEvent } from "../src/lib/participants";
import { validateOfficialResult } from "../src/lib/official-result-validation";
import type { OfficialResultInput } from "../src/types/scoring";

// Unlike Next.js, plain `tsx` does not load .env.local automatically —
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
 * FICTIONAL / DEMO RESULT — Miss Universe 2026 has not happened yet.
 * This is for development/testing only, matching the demo participant
 * dataset. Never presented as an official result in the product (the
 * public page and Result Card both read data_status and show a "Demo
 * result" label whenever this is used — see FouchScore.tsx).
 */
const DEMO_RESULT: OfficialResultInput = {
  winner: "demo-co", // Colombia
  firstRunnerUp: "demo-ve", // Venezuela
  secondRunnerUp: "demo-th", // Thailand
  top5Extras: ["demo-ph", "demo-pr"], // Philippines, Puerto Rico
  top10Extras: ["demo-in", "demo-mx", "demo-br", "demo-cl", "demo-es"], // India, Mexico, Brazil, Chile, Spain
};

async function main() {
  const event = getEventBySlug(EVENT_SLUG);
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
      data_status: participantData.status, // "demo" today — never mixed with "verified"
      winner_participant_id: DEMO_RESULT.winner,
      first_runner_up_participant_id: DEMO_RESULT.firstRunnerUp,
      second_runner_up_participant_id: DEMO_RESULT.secondRunnerUp,
      top5_extra_participant_ids: DEMO_RESULT.top5Extras,
      top10_extra_participant_ids: DEMO_RESULT.top10Extras,
      source_note: "Development/demo fixture — not an official result.",
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
// entered) — force fresh server execution on every request rather than
// risk this being treated as a cacheable static/ISR route.
export const dynamic = "force-dynamic";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) return {};

  const participantData = await getParticipantsForEvent(slug);
  const isDemo = participantData?.status === "demo";

  return {
    title: `${event.name} Predictions Leaderboard | FOUCH`,
    description: isDemo
      ? "A demo FOUCH predictions leaderboard — not an official result."
      : "See how FOUCH predictions ranked after the result.",
    // Demo leaderboards should never be indexed as if they were real —
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

  const event = getEventBySlug(slug);
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
          Demo leaderboard — not an official outcome
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
                  ? ` · Top ${Math.max(1, Math.round(100 - leaderboard.viewer.percentile.percentile))}%`
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
    $path = "src\app\p\[publicId]\edit\page.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { notFound, redirect } from "next/navigation";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { EditPredictionFlow } from "@/components/prediction/EditPredictionFlow";

/**
 * FOUCH 0.3A — the edit entry point. This route is intentionally
 * unreachable in a way that actually matters for two cases, checked
 * server-side (never just hidden in the UI, since a direct URL visit
 * bypasses any client-side hiding):
 *
 *  - legacy anonymous prediction (no verified owner) — there is no
 *    identity to authorize an edit against, and this sprint adds no
 *    way to claim one, so editing is simply never offered;
 *  - the event has passed prediction_lock_at — editing closes at
 *    lock, full stop.
 *
 * Both redirect back to the public page rather than 404 — the
 * prediction itself is real and viewable, only editing isn't
 * available. The actual SAVE action (verify-actions.ts) independently
 * re-checks both of these server-side again at save time — this
 * page's checks are only about whether to show the builder at all,
 * never the authorization boundary itself.
 */
export default async function EditPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;

  if (!prediction.hasVerifiedOwner) {
    redirect(`/p/${publicId}`);
  }

  const lockConfig = await getEventLockConfig(event.slug);
  if (!isPredictionWindowOpen(lockConfig, Date.now())) {
    redirect(`/p/${publicId}`);
  }

  const participantData = await getParticipantsForEvent(event.slug);
  if (!participantData) notFound();

  const requiredCount = Math.min(10, participantData.participants.length);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <h1 className="font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-1 text-sm text-text-secondary">Edit your Top {requiredCount}</p>

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
  const record = await getPredictionWithParticipants(publicId);
  if (!record) return {};

  const title = record.prediction.nickname
    ? `${record.prediction.nickname}'s Top 10 — ${record.event.name}`
    : `A Top 10 prediction — ${record.event.name}`;
  const description = "See the prediction, then make your own call.";

  return {
    title,
    description,
    // Sprint 2 decision: public prediction pages are reachable via
    // link but intentionally not indexed — we don't want thousands of
    // thin user-generated pages in search results. `follow` so the
    // "Make your Top 10" CTA is still crawlable back to the real
    // product pages.
    robots: { index: false, follow: true },
    openGraph: {
      title,
      description,
      url: `${siteUrl}/p/${publicId}`,
      images: [`${siteUrl}/p/${publicId}/opengraph-image`],
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
  const record = await getPredictionWithParticipants(publicId);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;
  const heading = prediction.nickname ? `${prediction.nickname}'s Top 10` : "Someone's Top 10";

  // Cheap existence check only (no percentile/breakdown work) — used
  // purely to decide share-CTA hierarchy (Sprint 4.1 §7-8). FouchScore
  // below independently does the full scored computation; this is a
  // second, lightweight read of the same result row, not duplicated
  // scoring logic.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);
  const hasResult = Boolean(official);

  // FOUCH 0.3A: editing is offered only for a verified prediction
  // while the event is still open — fetched fresh on every page view
  // from the single authoritative source, never cached/assumed.
  const lockConfig = await getEventLockConfig(event.slug);
  const isPredictionOpen = isPredictionWindowOpen(lockConfig, Date.now());
  const canEdit = prediction.hasVerifiedOwner && isPredictionOpen;
  const showLockedNotice = prediction.hasVerifiedOwner && !isPredictionOpen;

  // FOUCH 0.3B §13: "Contestant list updated {date}" for a real,
  // non-demo event with verified-roster provenance — never "Demo
  // prediction" for one of these. Null (no participant rows checked
  // yet, or a hardcoded/demo event) simply shows nothing extra here.
  const participantData = await getParticipantsForEvent(event.slug);
  const sourceCheckedAt = participantData?.sourceCheckedAt ?? null;

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-2 font-display text-xl uppercase tracking-tight text-text-primary">
        {heading}
      </p>

      {prediction.countryCode ? (
        <p className="mt-1 text-sm text-text-muted"><CountryFlag countryCode={prediction.countryCode} /></p>
      ) : null}

      {prediction.dataStatus === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo prediction — not the official lineup
        </p>
      ) : sourceCheckedAt ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          {formatContestantListUpdated(sourceCheckedAt)}
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
  const event = getEventBySlug(input.eventSlug);
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
  // — never cached, never trusted from the client.
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
 * — a submitted prediction is immutable in Sprint 2.
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
  const event = getEventBySlug(slug);
  if (!event) return {};

  return {
    title: `Build your Top 10 — ${event.name}`,
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
  const event = getEventBySlug(slug);
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
            Demo participant data — not the official lineup
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
  const event = getEventBySlug(slug);
  if (!event) return {};

  return { title: `Your Top 10 — ${event.name}` };
}

const REQUIRED_SELECTIONS = 10;

export default async function ReviewPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = getEventBySlug(slug);
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
 * Beta Hardening 0.2 Phase C — the verified-lock flow.
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
 * this event — that check only happens AFTER verification succeeds
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
    // transient failure) — never surface raw error internals, but no
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
       * insert failed transiently — lets the client retry the lock
       * step alone, without a new OTP (frozen retry semantics). */
      accessToken?: string;
    };

/** Shared by verifyEmailAndLockPrediction and retryLockWithVerifiedSession
 * — re-validates the entire payload server-side (never weaker than the
 * existing anonymous submitPrediction() path) and attempts the insert
 * with the now-known auth_user_id. */
async function validateAndLock(
  authUserId: string,
  payload: LockPredictionPayload,
): Promise<VerifyAndLockResult> {
  const event = getEventBySlug(payload.eventSlug);
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
  // Supabase, the single authoritative source — never from
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

  // Soft signal only — computed BEFORE the insert (so it reflects
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
 * user-facing action — sequential, not one shared database
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
 * verification — never requires a new code, per the frozen retry
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
 * FOUCH 0.3A — Editable Predictions.
 *
 * Deliberately mirrors the Lock flow above almost exactly: same
 * email → OTP → verify shape, same accessToken-based retry-without-
 * new-code semantics, because the identity architecture is frozen
 * (Beta Hardening 0.2 rules are unchanged, see brief §3). The only
 * new thing editing needs on top of that is OWNERSHIP authorization
 * — see validateAndEdit below.
 *
 * Legacy scope (explicit product decision, not inferred): a
 * prediction with auth_user_id = null has no verified identity to
 * authorize an edit against, and this sprint introduces no mechanism
 * to retroactively claim one via nickname, device_token, a
 * later-entered email, public_id, or anything else. Such predictions
 * remain fully public/readable/scoreable forever, exactly as today —
 * they are simply never editable. The UI never even offers "EDIT MY
 * TOP 10" for them (see PublicPredictionPage), but the server check
 * below is the actual authorization boundary, not the UI.
 * ------------------------------------------------------------------ */

export interface EditPredictionPayload {
  publicId: string;
  participantIds: string[];
  /** The version_number the client read just before opening the edit
   * builder — used as an optimistic-concurrency check, see
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
       * save step failed transiently — lets the client retry the save
       * step alone, without a new OTP (same frozen retry semantics as
       * the lock flow). Never present for not_owner/locked/conflict —
       * those are never worth retrying with the same input. */
      accessToken?: string;
    };

/**
 * Shared by verifyEmailAndEditPrediction and
 * retryEditWithVerifiedSession. Every authorization and timing check
 * here is independent server-side state — nothing the client supplies
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

  // The critical authorization check (brief §10-11, reconfirmed for
  // legacy scope): the verified auth_user_id from THIS session must
  // match the prediction's stored auth_user_id exactly. See
  // isAuthorizedToEdit's own doc for why this single, pure check is
  // the entire ownership rule — no nickname/device_token/public_id/
  // email-based claiming exists anywhere in this codebase.
  if (!isAuthorizedToEdit(editable.authUserId, authUserId)) {
    return {
      success: false,
      error: "This isn't your prediction.",
      failureReason: "not_owner",
    };
  }

  const event = getEventBySlug(editable.eventSlug);
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

  // Re-fetched fresh, right now, from Supabase — the one and only
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
 * The main verified-edit entry point — verifies the OTP, then
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
  // transiently — never for not_owner/locked/conflict/validation,
  // none of which a bare retry with the same input would fix.
  if (!result.success && result.failureReason === "edit_failed" && data.session) {
    return { ...result, accessToken: data.session.access_token };
  }

  return result;
}

/**
 * Retries only the save step after a transient failure, reusing the
 * access token from the original OTP verification — mirrors
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
    $path = "src\components\FeaturedEvent.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { getParticipantsForEvent } from "@/lib/participants";
import { getOfficialResult } from "@/lib/results-db";
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
  // driven, never hardcoded to a specific slug — it only appears once
  // an official/demo result genuinely exists to rank against.
  const participantData = await getParticipantsForEvent(event.slug);
  const hasLeaderboard = participantData
    ? Boolean(await getOfficialResult(event.slug, participantData.status))
    : false;

  // Decorative only — a preview of the ranking mechanic, not real input.
  const previewSlots = [1, 2, 3];

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
          <span className="block text-3xl sm:text-4xl">Miss Universe</span>
          <span className="block text-7xl font-semibold tracking-tight sm:text-8xl">
            2026
          </span>
        </h2>

        <p className="mt-4 text-sm uppercase tracking-[0.15em] text-text-muted">
          {dayMonth} · {event.subtitle}
        </p>

        <p className="mt-8 text-lg text-text-secondary">{dictionary.featuredEvent.prompt}</p>

        {/* Decorative preview of the ranking mechanic — not interactive. */}
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
              View leaderboard →
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

type Step = "edit" | "email" | "otp";

/**
 * FOUCH 0.3A — reuses the SAME ranking primitives as
 * PredictionBuilder.tsx (TopTenList, ParticipantBrowser) and the SAME
 * verification primitives as ReviewContent.tsx (EmailStep, OtpStep) —
 * deliberately not a second, independent builder. The only real
 * difference from PredictionBuilder is persistence: this component's
 * ranking state starts from the prediction's CURRENT version (passed
 * in from the server) and is never written to localStorage — there is
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
  /** Only currently-selectable (ACTIVE) contestants — what
   * ParticipantBrowser offers to pick from. */
  allParticipants: Participant[];
  /** FOUCH 0.3B: the CURRENT ranking resolved regardless of status —
   * may include a WITHDRAWN/REPLACED entry (isActive: false), which
   * must still display with its real name so it can be seen and
   * explicitly swapped out, never silently dropped from the list. */
  initialRankedParticipants: Participant[];
  requiredCount: number;
  expectedVersionNumber: number;
  predictionLockAt: string | null;
  /** FOUCH 0.3A.1 — IANA timezone identifier for the event, used only
   * for unambiguous display of predictionLockAt (see
   * event-time-display.ts). */
  predictionTimezone: string | null;
}) {
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
  // current ranking already contains — this is what lets a
  // WITHDRAWN/REPLACED entry the user hasn't removed yet keep
  // resolving to its real name (isActive: false) instead of vanishing
  // from the Top N the moment its status changed. ParticipantBrowser
  // below still only ever offers `allParticipants` (active-only) to
  // pick from, so a removed inactive entry can only be replaced by a
  // currently-active contestant — never re-added.
  const participantsById = new Map(
    [...allParticipants, ...initialRankedParticipants].map((participant) => [participant.id, participant]),
  );

  const rankedParticipants = selectedIds
    .map((id) => participantsById.get(id))
    .filter((participant): participant is Participant => Boolean(participant));

  const isComplete = selectedIds.length >= requiredCount;
  // FOUCH 0.3B §7: a saved version can never include a participant
  // who is no longer ACTIVE — checked client-side here purely to
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
          You can update your picks until {formatEventLocalLockTime(predictionLockAt, predictionTimezone)}.
        </p>
      ) : null}

      {step === "edit" ? (
        <div className="lg:grid lg:grid-cols-[380px_1fr] lg:gap-10">
          <section aria-label="Your Top 10" className="lg:sticky lg:top-20 lg:self-start">
            <h2 className="font-display text-lg text-text-primary">Your Top {requiredCount}</h2>
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
                  Save my Top {requiredCount}
                </button>
                {hasUnavailableSelection ? (
                  <p className="mt-2 text-xs text-text-muted">
                    Replace the contestant marked &quot;Replace&quot; with a current one to save your changes.
                  </p>
                ) : null}
              </>
            ) : null}
          </section>

          <section aria-label="All contestants" className="mt-10 lg:mt-0">
            <h2 className="font-display text-lg text-text-primary">All contestants</h2>
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
              {otpError}
            </p>
          ) : null}
          <button
            type="button"
            disabled={otpSubmitting}
            onClick={handleRetry}
            className="mt-4 inline-flex w-full items-center justify-center rounded bg-accent px-6 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong disabled:cursor-not-allowed disabled:opacity-60 sm:w-auto"
          >
            {otpSubmitting ? "Trying again…" : "Try again"}
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
    $path = "src\components\prediction\TopTenList.tsx"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
"use client";

import { ChevronUp, ChevronDown, X } from "lucide-react";
import { CountryFlag } from "@/components/CountryFlag";
import type { Participant } from "@/types/participant";

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
  if (rankedParticipants.length === 0) {
    return (
      <p className="rounded border border-dashed border-border-strong px-4 py-6 text-sm text-text-muted">
        Tap a country below to give it position 01.
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
            {participant.displayName}
          </span>
          {!participant.isActive ? (
            <span
              className="shrink-0 rounded border border-accent-strong px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-accent-strong"
              title="No longer available — remove and pick a current contestant to save changes."
            >
              Replace
            </span>
          ) : null}

          <div className="flex items-center gap-0.5">
            <button
              type="button"
              onClick={() => onMoveUp(index)}
              disabled={index === 0}
              aria-label={`Move ${participant.displayName} up, currently position ${index + 1} of ${requiredCount}`}
              className="rounded p-2 text-text-secondary transition-colors hover:bg-surface-raised disabled:opacity-30"
            >
              <ChevronUp className="h-4 w-4" aria-hidden />
            </button>
            <button
              type="button"
              onClick={() => onMoveDown(index)}
              disabled={index === rankedParticipants.length - 1}
              aria-label={`Move ${participant.displayName} down, currently position ${index + 1} of ${requiredCount}`}
              className="rounded p-2 text-text-secondary transition-colors hover:bg-surface-raised disabled:opacity-30"
            >
              <ChevronDown className="h-4 w-4" aria-hidden />
            </button>
            <button
              type="button"
              onClick={() => onRemove(participant.id)}
              aria-label={`Remove ${participant.displayName} from your Top ${requiredCount}`}
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

  // FOUCH 0.3B: resolves every participant id this section could
  // possibly render — the viewer's own winner pick AND whatever ids
  // appear in the community aggregate (sameWinner/boldestPick/
  // communityTop10) — regardless of current status. Any of those ids
  // could belong to someone else's prediction referencing a country
  // whose delegate has since become WITHDRAWN/REPLACED; this must
  // still resolve to a real name/country, never silently vanish.
  const idsToResolve = new Set<string>();
  if (comparison.sameWinner) idsToResolve.add(comparison.sameWinner.participantId);
  if (comparison.boldestPick) idsToResolve.add(comparison.boldestPick.participantId);
  for (const entry of comparison.communityTop10) idsToResolve.add(entry.participantId);

  const participantsById = await resolveParticipantsByIds(event.slug, Array.from(idsToResolve));

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
        You vs the World
      </p>

      {prediction.dataStatus === "demo" ? (
        <p className="mt-2 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo community data — not official {pluralNoun}
        </p>
      ) : null}

      {mode === "none" ? (
        <div className="mt-6">
          <p className="font-display text-xl text-text-primary">You&apos;re early.</p>
          <p className="mt-1 text-sm text-text-secondary">Be the first to set the pace.</p>
          <ShareYourCallCta />
        </div>
      ) : (
        <div className="mt-8 space-y-10">
          {bucket === "1_4" ? (
            <p className="text-sm text-text-muted">
              The crowd is just forming — {comparison.population} other{" "}
              {comparison.population === 1 ? pluralNoun.slice(0, -1) : pluralNoun} in so far.
            </p>
          ) : null}
          {bucket === "5_9" ? (
            <p className="text-xs uppercase tracking-[0.15em] text-text-muted">
              Early signal · based on {comparison.population} other predictions
            </p>
          ) : null}

          {comparison.sameWinner ? (
            <div>
              <p className="font-display text-6xl text-accent-strong">
                {formatRatio(comparison.sameWinner.count, comparison.population, mode)}
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Same winner
              </p>
              <p className="mt-2 text-text-primary">
                <CountryFlag
                  countryCode={participantsById.get(comparison.sameWinner.participantId)?.countryCode}
                />{" "}
                {participantsById.get(comparison.sameWinner.participantId)?.displayName} —{" "}
                {comparison.sameWinner.count === 0
                  ? "nobody else made the same call."
                  : mode === "count"
                    ? `${comparison.sameWinner.count} of ${comparison.population} other predictions agree.`
                    : `${formatPct(comparison.sameWinner.pct)} of the world agrees. Based on ${comparison.population} other predictions.`}
              </p>
            </div>
          ) : null}

          {comparison.top3Match ? (
            <div>
              <p className="font-display text-6xl text-accent-strong">
                {comparison.top3Match.overlap} / 3
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Top 3 match
              </p>
              <p className="mt-2 text-text-primary">
                You share {comparison.top3Match.overlap} of your top 3 with the world.
              </p>
            </div>
          ) : null}

          {comparison.boldestPick ? (
            <div>
              <p className="font-display text-4xl text-text-primary">
                <CountryFlag
                  countryCode={participantsById.get(comparison.boldestPick.participantId)?.countryCode}
                />{" "}
                {participantsById.get(comparison.boldestPick.participantId)?.displayName}
              </p>
              <p className="mt-1 text-sm uppercase tracking-[0.15em] text-text-secondary">
                Your boldest call
              </p>
              <p className="mt-2 text-text-primary">
                {mode === "count"
                  ? `Only ${comparison.boldestPick.count} of ${comparison.population} other predictions have this in their top 10.`
                  : `Only ${formatPct(comparison.boldestPick.inclusionPct)} of other predictions have this in their top 10.`}
              </p>
            </div>
          ) : null}

          {comparison.communityTop10.length > 0 ? (
            <div>
              <p className="font-display text-xl text-text-primary">The world&apos;s top 10</p>
              <p className="mt-1 text-xs text-text-muted">
                Ranked by how high each pick appears across predictions.
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
                      <span className="flex-1 text-sm text-text-primary">
                        {participant.displayName}
                      </span>
                      <span className="text-right text-xs text-text-muted">
                        {formatRatio(entry.top10Count, comparison.population, mode)} picked
                        <br />
                        avg #{entry.averagePosition.toFixed(1)}
                      </span>
                    </li>
                  );
                })}
              </ol>
              <p className="mt-2 text-xs text-text-muted">
                Based on {comparison.population} other prediction
                {comparison.population === 1 ? "" : "s"}.
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
import type { ScoreBand } from "@/types/scoring";
import { FouchScoreTracker } from "./FouchScoreTracker";
import { ShareActions } from "@/components/prediction/ShareActions";
import { TrackedLink } from "@/components/TrackedLink";

const BAND_LABEL: Record<ScoreBand, string> = {
  MISSED_IT: "Missed it",
  FAIR: "Fair call",
  GOOD: "Good call",
  EXCELLENT: "Excellent call",
  ELITE: "Elite call",
};

/** "8.333..." -> "8.3", "25.0" -> "25" — one decimal, no trailing ".0". */
function formatPoints(value: number): string {
  const rounded = Math.round(value * 10) / 10;
  return Number.isInteger(rounded) ? String(rounded) : rounded.toFixed(1);
}

/**
 * Renders nothing (returns null) when there's no official result yet —
 * the pre-result experience is unchanged, never a fabricated score.
 * Server Component: fetches + scores server-side, only the final
 * numbers reach the client (via the tracker's props, not raw data).
 *
 * Sprint 4.1: UI clarity only. Every number below comes straight from
 * the existing score engine's ScoreBreakdown — nothing here
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
  const result = await getPredictionScore(
    prediction.id,
    prediction.rankedParticipantIds,
    event.slug,
    prediction.dataStatus,
  );
  if (!result) return null;

  // Re-reads the same official-result row already used inside
  // getPredictionScore, purely to display who the actual winner was —
  // no scoring logic is duplicated, only a read.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);

  // FOUCH 0.3B: resolves regardless of current participant status —
  // both the user's own historical winner pick and the official
  // result's winner id must still render even if that country's
  // delegate has since become WITHDRAWN/REPLACED.
  const idsToResolve = new Set<string>();
  if (prediction.rankedParticipantIds[0]) idsToResolve.add(prediction.rankedParticipantIds[0]);
  if (official) idsToResolve.add(official.winner);

  const participantsById = await resolveParticipantsByIds(event.slug, Array.from(idsToResolve));
  const userWinnerPick = prediction.rankedParticipantIds[0]
    ? participantsById.get(prediction.rankedParticipantIds[0])
    : undefined;
  const actualWinner = official ? participantsById.get(official.winner) : undefined;
  const pluralNoun = getEntryNoun(event, true);
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

      <p className="text-xs font-medium uppercase tracking-[0.15em] text-text-muted">Fouch score</p>

      {prediction.dataStatus === "demo" ? (
        <p className="mt-2 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo result — not an official outcome
        </p>
      ) : null}

      <p className="mt-3 font-display text-7xl text-accent-strong">{breakdown.displayScore}</p>
      <p className="mt-1 font-display text-2xl uppercase tracking-tight text-text-primary">
        {BAND_LABEL[breakdown.band]}
      </p>

      {percentile.percentile !== null ? (
        <p className="mt-2 text-sm text-text-secondary">
          You beat {Math.round(percentile.percentile)}% of {pluralNoun === "picks" ? "predictions" : pluralNoun} for
          this event, based on {percentile.population} other predictions.
        </p>
      ) : (
        <p className="mt-2 text-xs text-text-muted">
          World ranking unlocks at {MIN_PERCENTILE_SAMPLE} predictions.
        </p>
      )}

      <dl className="mt-6 space-y-3 text-sm">
        <div className="border-b border-border pb-3">
          <dt className="flex items-center justify-between">
            <span className="text-text-secondary">Winner</span>
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
                  </>
                ) : (
                  "Correct"
                )}
              </span>
            ) : (
              <div className="space-y-1 text-text-primary">
                <p className="flex items-center gap-1.5">
                  <span className="text-text-muted">✗ Missed — your pick:</span>
                  {userWinnerPick ? (
                    <>
                      <CountryFlag countryCode={userWinnerPick.countryCode} />
                      {userWinnerPick.displayName}
                    </>
                  ) : (
                    "—"
                  )}
                </p>
                {actualWinner ? (
                  <p className="flex items-center gap-1.5 text-text-secondary">
                    <span className="text-text-muted">Actual:</span>
                    <CountryFlag countryCode={actualWinner.countryCode} />
                    {actualWinner.displayName}
                  </p>
                ) : null}
              </div>
            )}
          </dd>
        </div>

        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Podium</dt>
          <dd className="text-text-primary">
            {podium.hits} of {podium.total} · {formatPoints(podium.earned)} / {podium.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Top 5</dt>
          <dd className="text-text-primary">
            {top5.hits} of {top5.total} · {formatPoints(top5.earned)} / {top5.max}
          </dd>
        </div>
        <div className="flex items-center justify-between border-b border-border pb-3">
          <dt className="text-text-secondary">Top 10</dt>
          <dd className="text-text-primary">
            {top10.hits} of {top10.total} · {formatPoints(top10.earned)} / {top10.max}
          </dd>
        </div>
        <div>
          <div className="flex items-center justify-between">
            <dt className="text-text-secondary">Ranking</dt>
            <dd className="text-text-primary">
              {formatPoints(ranking.earned)} / {ranking.max}
            </dd>
          </div>
          <p className="mt-1 text-xs text-text-muted">How close your picks were to the official finish.</p>
        </div>
      </dl>

      <div className="mt-8">
        <TrackedLink
          href={`/events/${event.slug}/leaderboard?from=${publicId}`}
          event="leaderboard_from_score_clicked"
          eventProperties={{ event_slug: event.slug }}
          className="inline-flex items-center justify-center rounded border border-border-strong px-6 py-3 text-sm font-medium text-text-primary transition-colors hover:border-accent hover:text-accent-strong"
        >
          See where you finished
        </TrackedLink>
      </div>

      <div className="mt-8">
        <p className="font-display text-lg text-text-primary">Share your result</p>
        <div className="mt-3">
          <ShareActions
            variant="result"
            eventSlug={event.slug}
            publicUrl={`${siteUrl}/p/${publicId}`}
            storyCardUrl={`/p/${publicId}/result-card/story`}
            postCardUrl={`/p/${publicId}/result-card/post`}
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

/**
 * Experiment 01 ("Your Crowd Changed") — FOUCH_EXPERIMENT_01.md.
 * Renders nothing whenever the movement isn't eligible (small sample,
 * or change under MIN_MOVEMENT_POINTS) — silence is the correct,
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

  const result = await getConsensusChangeForPrediction(
    prediction.id,
    prediction.submittedAt,
    winnerId,
    event.slug,
    prediction.dataStatus,
  );
  if (!result.eligible || !result.direction) return null;

  // FOUCH 0.3B: resolves regardless of current status — winnerId
  // comes from the community's aggregate winner picks and may
  // reference a participant who has since become
  // WITHDRAWN/REPLACED.
  const participantsById = await resolveParticipantsByIds(event.slug, [winnerId]);
  const winner = participantsById.get(winnerId);
  if (!winner) return null;

  const arrow = result.direction === "toward" ? "↑" : "↓";
  const sign = result.changePoints > 0 ? "+" : "";
  const directionCopy =
    result.direction === "toward"
      ? "The crowd is moving toward your call."
      : "The crowd is moving away from your call.";

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
        Your crowd changed
      </p>

      <div className="mt-3 flex items-center gap-2">
        <CountryFlag countryCode={winner.countryCode} className="text-2xl" />
        <span className="font-display text-xl text-text-primary">{winner.displayName}</span>
      </div>

      <p className="mt-2 font-display text-4xl text-accent-strong">
        {Math.round(result.thenSupport)}% → {Math.round(result.nowSupport)}%
      </p>
      <p className="mt-1 text-sm text-text-secondary">
        {arrow} {sign}
        {Math.round(result.changePoints)} pts
      </p>

      <p className="mt-3 text-text-primary">{directionCopy}</p>
      <p className="mt-2 text-xs text-text-muted">Based on community predictions since your call.</p>
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
    $path = "src\lib\event-time-display.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { formatEventLocalLockTime, deriveLocationLabel, formatContestantListUpdated } from "./event-time-display";

const MISS_UNIVERSE_LOCK_AT = "2026-11-24T00:00:00Z";

describe("deriveLocationLabel — generic IANA-id -> human label, no new config field", () => {
  it("derives 'Puerto Rico' from 'America/Puerto_Rico'", () => {
    expect(deriveLocationLabel("America/Puerto_Rico")).toBe("Puerto Rico");
  });

  it("derives 'Santiago' from 'America/Santiago'", () => {
    expect(deriveLocationLabel("America/Santiago")).toBe("Santiago");
  });

  it("falls back to the raw identifier if there is no '/' segment", () => {
    expect(deriveLocationLabel("UTC")).toBe("UTC");
  });
});

describe("formatEventLocalLockTime — unambiguous, event-local, never a naked time", () => {
  it("resolves the Miss Universe 2026 lock instant correctly in Puerto Rico event time", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    // 2026-11-24T00:00:00Z is 2026-11-23 20:00 in America/Puerto_Rico
    // (AST, UTC-4 year-round — Puerto Rico does not observe DST).
    expect(result).toBe("Nov 23 at 8:00 PM AST (Puerto Rico)");
  });

  it("always includes a timezone abbreviation — never a naked time with no context", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    expect(result).toMatch(/[A-Z]{2,5}/); // AST, UTC, GMT+N, etc. — some abbreviation/offset token
    expect(result).not.toBe("8:00 PM");
    expect(result).not.toBe("9:00 PM");
  });

  it("always includes the human-readable location context in parentheses", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    expect(result).toContain("(Puerto Rico)");
  });

  it("falls back to an explicit UTC-labeled rendering when timezone is null — never a silently-assumed local time", () => {
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, null);
    expect(result).toBe("Nov 24 at 12:00 AM UTC");
    expect(result).not.toContain("(");
  });

  it("falls back to UTC gracefully for an invalid/unrecognized IANA identifier, never throws", () => {
    expect(() => formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "Not/ARealZone")).not.toThrow();
    const result = formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "Not/ARealZone");
    expect(result).toBe("Nov 24 at 12:00 AM UTC");
  });

  it("CRITICAL: formatting for display never changes the absolute instant the ISO string represents — same instant, different timezone displays, both parse back to the identical epoch millisecond", () => {
    const epochBefore = new Date(MISS_UNIVERSE_LOCK_AT).getTime();

    // Render in three different timezones — none of this touches the
    // original string or reinterprets it as timezone-less.
    formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Puerto_Rico");
    formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, "America/Santiago");
    formatEventLocalLockTime(MISS_UNIVERSE_LOCK_AT, null);

    const epochAfter = new Date(MISS_UNIVERSE_LOCK_AT).getTime();
    expect(epochAfter).toBe(epochBefore);

    // The instant itself, independent of any display formatting, is
    // exactly what server-side lock enforcement compares against
    // (see prediction-lock-logic.test.ts) — proving here that display
    // formatting is a pure read, never a mutation of that instant.
    expect(epochBefore).toBe(Date.parse(MISS_UNIVERSE_LOCK_AT));
  });
});

describe("formatContestantListUpdated — FOUCH 0.3B §13 restrained roster-freshness copy", () => {
  it("renders a plain, human date — never the word 'demo'", () => {
    const result = formatContestantListUpdated("2026-09-20T12:00:00Z");
    expect(result).toBe("Contestant list updated Sep 20, 2026");
    expect(result.toLowerCase()).not.toContain("demo");
  });

  it("never claims completeness — no 'official lineup' or 'complete' wording", () => {
    const result = formatContestantListUpdated("2026-09-20T12:00:00Z");
    expect(result.toLowerCase()).not.toContain("official lineup");
    expect(result.toLowerCase()).not.toContain("complete");
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-time-display.test.ts"
} catch {
    Write-Host "FAILED: src\lib\event-time-display.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-time-display.test.ts"
}

try {
    $path = "src\lib\event-time-display.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * FOUCH 0.3A.1 — pure, DB-free display formatting for the prediction
 * lock instant. Deliberately separate from prediction-lock-logic.ts:
 * that file decides WHETHER predictions are open (authorization,
 * server-time-only); this file only decides HOW to show an already-
 * decided instant to a human, in the event's own timezone rather than
 * the viewer's browser timezone (which is ambiguous for a worldwide
 * audience — see FOUCH 0.3A.1 brief §1).
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
 * timezone identifier — the last path segment, underscores replaced
 * with spaces. "America/Puerto_Rico" -> "Puerto Rico". This is a
 * generic, zero-configuration derivation (no new "location" field
 * needed) — good enough for the single-event scale this product is
 * at; if it ever produces something awkward for a future event, that
 * event can be given a nicer label at that point, not preemptively
 * here.
 */
export function deriveLocationLabel(timeZone: string): string {
  const lastSegment = timeZone.split("/").pop() ?? timeZone;
  return lastSegment.replace(/_/g, " ");
}

/**
 * FOUCH 0.3B §13 — "Contestant list updated {date}", the restrained
 * replacement for "Demo prediction" on a real (non-demo) event whose
 * roster has verified provenance. Deliberately date-only (no time/
 * timezone) — this is about freshness of a roster list, not a
 * lock-timing instant, so it doesn't need event-local precision.
 */
export function formatContestantListUpdated(sourceCheckedAtIso: string): string {
  const formatted = new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeZone: "UTC" }).format(
    new Date(sourceCheckedAtIso),
  );
  return `Contestant list updated ${formatted}`;
}

/**
 * Formats an absolute instant (ISO 8601 string, e.g. from
 * `events.prediction_lock_at`) as an unambiguous, human-readable
 * string in the EVENT's own local timezone — never the viewer's
 * browser timezone. Always includes a timezone abbreviation/offset
 * (via Intl's `timeZoneName: "short"`) so the result is never a naked
 * "9:00 PM" with no context (brief §3).
 *
 * When `timeZone` is null (event has none configured yet), falls back
 * to an explicit UTC-labeled rendering — still unambiguous, never a
 * silently-assumed local time.
 */
export function formatEventLocalLockTime(isoDateTime: string, timeZone: string | null): string {
  const date = new Date(isoDateTime);
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
    // page — fall back to explicit UTC, still unambiguous.
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
import { getAllEventParticipantRows, type EventParticipantRow } from "@/lib/event-participants-db";

/**
 * DEMO / DEVELOPMENT DATA — NOT the official Miss Universe 2026 lineup.
 *
 * The full, verified list of national delegates for Miss Universe 2026
 * is not yet finalized/confirmed by the organization at the time of
 * writing. Rather than invent an official-looking roster, this is a
 * clearly-marked demo set of real countries, used only to test the
 * Top 10 mechanic. See `getParticipantsForEvent`'s returned `status`
 * field — the UI must surface "Demo participant data" whenever it is
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
  /** FOUCH 0.3B §13: the most recent `source_checked_at` across this
   * event's ACTIVE participants, for the "Contestant list updated
   * {date}" copy — never used for a "demo" event (always null there;
   * Miss Universe's hardcoded seed has no provenance concept at all).
   * Null for a verified event with no source-checked participants
   * yet (e.g. Miss Grand before its roster import — see
   * FOUCH_EVENT_PARTICIPANTS_IMPORT.md). */
  sourceCheckedAt: string | null;
}

function toParticipant(row: EventParticipantRow): Participant {
  return {
    // Stable identity (0.3B §6): the DB row's own uuid, never derived
    // from name/position/status/country — see migration 0010.
    id: row.id,
    eventId: row.eventSlug,
    // A PENDING row has no confirmed contestant_name yet — never
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
 * version of an edited one) — exactly the same contract this function
 * has always had: only ever returns participants a person may
 * currently choose. Every existing caller (builder, review,
 * validateSubmission's activeParticipants, edit's requiredCount) can
 * keep assuming that, unchanged — the only difference from before
 * 0.3B is that resolving a database-driven event's roster requires an
 * await now.
 *
 * PENDING/WITHDRAWN/REPLACED participants are deliberately excluded
 * here — see resolveParticipantsByIds below for the separate,
 * status-blind lookup that historical rendering needs instead.
 */
export async function getParticipantsForEvent(slug: string): Promise<ParticipantsForEvent | null> {
  const hardcoded = participantsByEventSlug[slug];
  if (hardcoded) {
    return {
      status: "demo",
      participants: hardcoded.filter((participant) => participant.isActive),
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
    participants: active.map(toParticipant),
    sourceCheckedAt,
  };
}

/**
 * Resolves a specific set of participant IDs to display info
 * REGARDLESS of current status — the one place historical rendering
 * (a saved prediction's ranking, its share card, its winner pick for
 * scoring/consensus) must go through instead of
 * getParticipantsForEvent above. A WITHDRAWN or REPLACED participant
 * still resolves here with its real name/country (isActive: false),
 * exactly so an existing prediction never silently loses an entry
 * just because that country's delegate later changed (brief §7).
 *
 * For Miss Universe's hardcoded roster this is equivalent to the
 * active-only lookup (every hardcoded entry is always active), so
 * behavior there is unchanged.
 */
export async function resolveParticipantsByIds(
  eventSlug: string,
  participantIds: string[],
): Promise<Map<string, Participant>> {
  const idSet = new Set(participantIds);
  const hardcoded = participantsByEventSlug[eventSlug];

  if (hardcoded) {
    const map = new Map<string, Participant>();
    for (const participant of hardcoded) {
      if (idSet.has(participant.id)) map.set(participant.id, participant);
    }
    return map;
  }

  const rows = await getAllEventParticipantRows(eventSlug);
  const map = new Map<string, Participant>();
  for (const row of rows) {
    if (idSet.has(row.id)) map.set(row.id, toParticipant(row));
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
import type { Participant } from "@/types/participant";
import type { EligiblePrediction } from "@/lib/community-comparison";

export interface PredictionRecord {
  /** Internal DB id — server-side use only (e.g. self-exclusion from
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
   * 10" — never exposed as a raw auth_user_id to the client (see
   * predictions_public, which still never selects auth_user_id). */
  hasVerifiedOwner: boolean;
  /** FOUCH 0.3A: version_number of the current version — needed by
   * the edit flow as the optimistic-concurrency baseline. */
  currentVersionNumber: number;
  /** Participant IDs in ranked order — index 0 is position #1. */
  rankedParticipantIds: string[];
}

interface InsertPredictionParams {
  eventSlug: string;
  participantIds: string[];
  nickname: string | null;
  countryCode: string | null;
  dataStatus: ParticipantDataStatus;
  deviceToken: string;
  /** Beta Hardening 0.2 Phase C — set only by the new verified-lock
   * path. Undefined/omitted preserves the exact pre-Phase-C anonymous
   * insert behavior (legacy predictions are never retroactively
   * touched — see FOUCH_IDENTITY_ARCHITECTURE.md). */
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
      // event" — treat either as success and hand back the existing
      // one, so a double-tap, a race, or a retry never looks like a
      // hard failure. See insert-conflict.ts for why the message is
      // classified rather than just checked for "public_id" — Phase C
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
    // is now version 1 of its versioned history — not a special case.
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
      // Compensating cleanup — Supabase's JS client has no
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
  /** Highest version_number that exists for this prediction — the
   * next successful edit is version_number = latestVersionNumber + 1. */
  latestVersionNumber: number;
  /** Participant IDs of the CURRENT version, in ranked order — used
   * to pre-fill the edit builder. */
  currentRankedParticipantIds: string[];
}

/**
 * The one lookup the edit flow needs before authorizing anything:
 * who owns this prediction (by auth_user_id, never anything the
 * client supplies) and what its current ranking/version number are.
 * Returns null if the prediction, its current version, or its items
 * can't be resolved — callers must treat that as "can't edit", never
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
 * `predictions` row — this is exclusively the "edit" path; first
 * submissions go through insertPrediction() above.
 *
 * Idempotency (brief §19): if the submitted ranking is identical to
 * the prediction's current version, this is a no-op that returns
 * success without creating a new version — the simplest robust
 * defense against a double-click or a network retry re-sending the
 * exact same edit, with no client-supplied idempotency key needed.
 * A retry that lands after a lost response looks identical to the
 * original request, so this naturally covers that case too.
 *
 * Concurrency: `expectedVersionNumber` must match the version number
 * the caller read just before presenting the edit form. A mismatch
 * means someone else's edit (or this same edit, retried, but no
 * longer the current version) landed first — reported as a
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
  // read, not the one the caller assumed — closes the gap between
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
    // — report as a conflict rather than silently retrying with a
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

  // FOUCH 0.3A: always the CURRENT version's items — never every
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
 * Beta Hardening 0.2 Phase C — looks up an existing FINAL prediction
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
 * Beta Hardening 0.2 Phase C — feeds the soft, non-blocking
 * same-device/different-identity signal (see insert-conflict.ts's
 * isDeviceIdentityMismatch). Returns only the two fields that
 * function needs — never a full PredictionRecord, since this is
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

  const event = getEventBySlug(prediction.eventSlug);
  if (!event) return null;

  // FOUCH 0.3B: resolves by id regardless of current status — a
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
 * event + data-status — the raw material for community-comparison.ts.
 * Only `id` and `participant_id`/`predicted_position` are selected;
 * nickname, country, and device_token never leave the database for
 * this purpose (see Sprint 3 brief section 22, privacy).
 *
 * "Eligible" here means: same event, same data_status (demo
 * predictions and future verified predictions never mix — see
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
  // which items count — a prediction with 3 saved versions must still
  // contribute exactly ONE eligible ranking (its current one), never
  // three (brief §12: "Freddy has v1, v2, v3 → community sample size
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
 * (event + data_status + is_final=true + exactly 10 items) — kept as a
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
  // getEligiblePredictionsForComparison above — a prediction with
  // several saved versions is still exactly one leaderboard entry
  // (brief §13), never one entry per version.
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
 * Experiment 01 ("Your Crowd Changed") — the leanest possible query for
 * this experiment: only each eligible prediction's submission time and
 * #1 (winner) pick, never the full 10-item ranking. Deliberately a
 * separate query rather than reusing getEligiblePredictionsForComparison
 * or getLeaderboardRawEntries — those fetch every item of every
 * prediction, which this experiment doesn't need at all.
 *
 * Eligibility mirrors both of those functions exactly: same event_slug,
 * same data_status, is_final = true, and (checked via the items query)
 * exactly 10 items — never a different population definition for the
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
  // edit — only prediction_versions.created_at records when each
  // version was saved). Experiment 01's semantics with an edited
  // winner pick are addressed separately below (brief §17) — this
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

  // Only position 1 (the winner pick) — and only from predictions with
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
    $path = "supabase\migrations\0006_identity_phase_c_cutover.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- Beta Hardening 0.2 — Phase C cutover migration.
--
-- ============================================================
-- GATE 2 CLOSED — ALREADY APPLIED TO PRODUCTION.
-- This migration was applied in the same controlled release as the
-- verified-lock application code (Gate 1 + Gate 2, deployed together)
-- per the sequencing in FOUCH_DATABASE_MIGRATION_PLAN.md and
-- FOUCH_BETA_HARDENING_02_PHASE_C.md's cutover procedure. It is kept
-- here, unchanged, as the historical record of that cutover — do not
-- re-run it or modify the index it drops as part of FOUCH 0.3A.
-- ============================================================
--
-- Purpose: drop the old (event_slug, device_token) unique index. Once
-- this runs, device_token is purely the soft, non-blocking signal
-- described in FOUCH_IDENTITY_ARCHITECTURE.md — the hard duplicate
-- rule becomes exclusively predictions_one_final_per_identity
-- (already live since Phase A).
--
-- This migration does NOT:
--   - drop the device_token column (kept, as a descriptive field)
--   - alter auth_user_id or its index
--   - modify any existing row
--   - touch predictions_public, event_results, or prediction_items

drop index if exists predictions_event_device_unique;

-- Rollback (only if needed — see FOUCH_BETA_HARDENING_02_PHASE_C.md's
-- rollback plan): restores the exact original constraint.
--
-- create unique index if not exists predictions_event_device_unique
--   on predictions (event_slug, device_token);
'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0006_identity_phase_c_cutover.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0006_identity_phase_c_cutover.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0006_identity_phase_c_cutover.sql"
}

try {
    $path = "supabase\migrations\0007_event_lock_config.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- FOUCH 0.3A — event lock configuration moves from application code
-- into the real `events` table (created but unused since 0001_init.sql).
--
-- Why: prediction_lock_at previously lived as a hardcoded ISO string
-- in src/lib/events.ts (see FouchEvent.predictionLockAt). That worked
-- for a single hardcoded event but violates the requirement that
-- editable predictions be event-driven and never trust anything
-- other than server/database time. This migration makes Supabase
-- `events.prediction_lock_at` the SINGLE authoritative source for
-- lock enforcement going forward. src/lib/events.ts may continue to
-- provide display-only metadata (name, subtitle, hero asset) for now
-- — it is no longer consulted for lock/open timing.
--
-- Additive and idempotent:
--   - ADD COLUMN IF NOT EXISTS for both new columns.
--   - The Miss Universe 2026 row is written with INSERT ... ON
--     CONFLICT (slug) DO UPDATE, so running this against an
--     environment that already has the row (manually inserted or
--     from a previous partial run) safely updates it in place
--     instead of creating a duplicate event.
--
-- Scope: intentionally limited to what 0.3A needs. This does not
-- introduce event administration, dynamic participants, or any
-- second/third event beyond keeping Miss Universe 2026 accurate.

alter table events
  add column if not exists prediction_open_at timestamptz;

alter table events
  add column if not exists prediction_lock_at timestamptz;

comment on column events.prediction_lock_at is
  'Authoritative lock time for this event''s predictions (FOUCH 0.3A). '
  'Server-side code must read this column — never src/lib/events.ts — '
  'and must compare it against server/database time, never client time.';

comment on column events.prediction_open_at is
  'Authoritative open time for this event''s predictions (FOUCH 0.3A), '
  'mirroring prediction_lock_at. Null means "no open-time restriction".';

-- Seed/update the one real event this product currently supports.
-- Values match the existing src/lib/events.ts seed exactly (same
-- slug, same lock instant) — this migration relocates the value, it
-- does not change it.
insert into events (
  slug,
  name,
  category,
  status,
  event_date,
  is_featured,
  subtitle,
  prediction_open_at,
  prediction_lock_at
)
values (
  'miss-universe-2026',
  'Miss Universe 2026',
  'pageant',
  'upcoming',
  '2026-11-24',
  true,
  'José Miguel Agrelot Coliseum, San Juan, Puerto Rico',
  null,
  '2026-11-24T00:00:00Z'
)
on conflict (slug) do update
set
  prediction_open_at = excluded.prediction_open_at,
  prediction_lock_at = excluded.prediction_lock_at;
-- Deliberately only prediction_open_at/prediction_lock_at are
-- overwritten on conflict — if a row already exists with different
-- name/subtitle/status (e.g. a founder edited it manually), this
-- migration must not clobber that. Lock config is the only thing
-- 0.3A needs to be authoritative in the database.

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0007_event_lock_config.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0007_event_lock_config.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0007_event_lock_config.sql"
}

try {
    $path = "supabase\migrations\0008_prediction_versions.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- FOUCH 0.3A — Editable Predictions & Version History.
--
-- ============================================================
-- DO NOT RUN THIS AGAINST PRODUCTION YET.
-- Prepared for local verification and founder review only. See
-- FOUCH_0_3A brief §22 (Migration Safety) — this sprint has a
-- deployment gate; production application is a separate, explicit
-- founder decision.
-- ============================================================
--
-- Model: `predictions` remains the LOGICAL entity — one row per
-- identity/event (its existing uniqueness rules from Phase A/C are
-- completely untouched: predictions_one_final_per_identity still
-- enforces one final logical prediction per (event_slug,
-- auth_user_id), and public_id/auth_user_id/device_token/is_final all
-- keep their exact current meaning and columns).
--
-- New: `prediction_versions` holds one IMMUTABLE snapshot per save.
-- `predictions.current_version_id` points at whichever version is
-- currently authoritative. `prediction_items` — previously scoped
-- directly to a prediction — is rescoped to a specific version, since
-- a ranking is a property of a version, not of the logical prediction
-- itself. `prediction_id` is kept on prediction_items as a
-- denormalized convenience column (not required for correctness,
-- useful for "all items ever submitted for this prediction" queries),
-- but nothing in 0.3A relies on it for "current" reads — those always
-- go through predictions.current_version_id.
--
-- Invariants this migration establishes:
--   - old versions are never overwritten (prediction_versions rows
--     are never updated by application code after insert)
--   - one logical prediction per identity/event (unchanged, enforced
--     the same way it always was)
--   - public_id is untouched — it lives on `predictions`, never
--     duplicated onto versions
--   - current version is resolvable in one step via
--     predictions.current_version_id
--   - every existing row gets a real version 1, so no prediction is
--     ever without a resolvable current version after this migration

create table if not exists prediction_versions (
  id uuid primary key default gen_random_uuid(),
  prediction_id uuid not null references predictions(id) on delete cascade,
  version_number integer not null check (version_number >= 1),
  created_at timestamptz not null default now(),
  unique (prediction_id, version_number)
);

create index if not exists prediction_versions_prediction_id_idx
  on prediction_versions (prediction_id);

alter table predictions
  add column if not exists current_version_id uuid references prediction_versions(id);

-- prediction_items moves from being scoped to a prediction to being
-- scoped to a specific version. Added nullable first so existing rows
-- aren't rejected; backfilled below; tightened to NOT NULL afterward.
alter table prediction_items
  add column if not exists version_id uuid references prediction_versions(id) on delete cascade;

-- ------------------------------------------------------------------
-- Legacy data migration: give every existing prediction a version 1
-- that is byte-for-byte what it already had, and make it current.
-- Idempotent: re-running this migration is safe because the WHERE
-- clauses below only touch predictions that don't have a
-- current_version_id yet — a prediction already migrated is skipped
-- entirely on a second run, never given a duplicate version 1.
-- ------------------------------------------------------------------

insert into prediction_versions (prediction_id, version_number, created_at)
select p.id, 1, p.submitted_at
from predictions p
where p.current_version_id is null
  and not exists (
    select 1 from prediction_versions pv where pv.prediction_id = p.id
  );

-- Point every existing item at its prediction's (now-created) version 1.
update prediction_items pi
set version_id = pv.id
from prediction_versions pv
where pv.prediction_id = pi.prediction_id
  and pv.version_number = 1
  and pi.version_id is null;

-- Make every prediction's current_version_id point at its version 1.
update predictions p
set current_version_id = pv.id
from prediction_versions pv
where pv.prediction_id = p.id
  and pv.version_number = 1
  and p.current_version_id is null;

-- ------------------------------------------------------------------
-- Tighten constraints now that backfill is complete.
-- ------------------------------------------------------------------

-- Defensive check before tightening — surfaces as a migration failure
-- (not a silent data-integrity gap) if anything above didn't reach
-- every row, e.g. a prediction with zero items.
do $$
declare
  orphaned_items integer;
  predictions_without_current integer;
begin
  select count(*) into orphaned_items from prediction_items where version_id is null;
  if orphaned_items > 0 then
    raise exception 'FOUCH 0.3A migration: % prediction_items rows have no version_id after backfill', orphaned_items;
  end if;

  select count(*) into predictions_without_current from predictions where current_version_id is null;
  if predictions_without_current > 0 then
    raise exception 'FOUCH 0.3A migration: % predictions rows have no current_version_id after backfill', predictions_without_current;
  end if;
end $$;

alter table prediction_items
  alter column version_id set not null;

-- Replace the old prediction-scoped uniqueness with version-scoped
-- uniqueness — a ranking is unique within a version, not within the
-- logical prediction as a whole (two versions of the same prediction
-- may legitimately reuse the same participant/position). Dropping the
-- CONSTRAINT (not a bare DROP INDEX — Postgres refuses to drop a
-- constraint's backing index directly) also drops its backing index.
-- Constraint names below are Postgres's default naming for the
-- inline `unique (a, b)` declarations in 0002_predictions.sql
-- (verified against a real Postgres instance, same as insert-conflict.ts's
-- constraint-name comment).
alter table prediction_items
  drop constraint if exists prediction_items_prediction_id_participant_id_key;
alter table prediction_items
  drop constraint if exists prediction_items_prediction_id_predicted_position_key;

-- Plain ADD CONSTRAINT has no IF NOT EXISTS in Postgres, so this is
-- guarded explicitly to keep the whole migration safely re-runnable.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'prediction_items_version_id_participant_id_key'
  ) then
    alter table prediction_items
      add constraint prediction_items_version_id_participant_id_key
        unique (version_id, participant_id);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'prediction_items_version_id_predicted_position_key'
  ) then
    alter table prediction_items
      add constraint prediction_items_version_id_predicted_position_key
        unique (version_id, predicted_position);
  end if;
end $$;

create index if not exists prediction_items_version_id_idx on prediction_items (version_id);

-- ------------------------------------------------------------------
-- RLS: version history is private/internal for now (brief §6) — no
-- version history UI in this sprint, and prediction_versions carries
-- no reader-facing information on its own (no ranking, just
-- version_number/created_at), but it is not granted to anon/
-- authenticated at all, matching "historical versions are private".
-- prediction_items keeps its existing public-read policy unchanged —
-- reading it publicly was always fine (it's how the public prediction
-- page and every scoring/leaderboard query already work), and that
-- policy has no notion of "current" to begin with; the application
-- layer is what filters to current-version items via
-- predictions.current_version_id, exactly as it already filters by
-- is_final = true today.
-- ------------------------------------------------------------------

alter table prediction_versions enable row level security;
-- No select/insert/update/delete policy for anon/authenticated is
-- defined — with RLS enabled and no matching policy, all access
-- through the anon/authenticated roles is denied. Only the
-- service-role key (server-side only, same as every other write path
-- in this codebase) can read or write this table.

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0008_prediction_versions.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0008_prediction_versions.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0008_prediction_versions.sql"
}

try {
    $path = "supabase\migrations\0009_event_timezone.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- FOUCH 0.3A.1 — event timezone for unambiguous lock-time display.
--
-- Why: prediction_lock_at is correctly an absolute instant
-- (timestamptz), but displaying it as a naked local time ("9:00 PM")
-- is ambiguous for a worldwide audience — a viewer in Chile, Spain, or
-- Thailand would read it in their OWN browser's timezone, which has
-- nothing to do with when the actual event airs. This migration adds
-- the event's own canonical timezone so the UI can render the lock
-- instant in EVENT-local time with an unambiguous abbreviation,
-- instead of the viewer's local time.
--
-- This is presentational only. It does NOT change, reinterpret, or
-- widen prediction_lock_at itself — that column remains the sole
-- authoritative instant, compared against server time exactly as
-- before (see src/lib/prediction-lock-logic.ts, untouched by this
-- migration). See src/lib/event-time-display.ts for the pure,
-- separately-tested formatting function that consumes this column.
--
-- Additive and idempotent: ADD COLUMN IF NOT EXISTS, and the UPDATE
-- below only touches the one row this product currently has, by slug
-- — safe to re-run.

alter table events
  add column if not exists timezone text;

comment on column events.timezone is
  'IANA timezone identifier (e.g. "America/Puerto_Rico") for this '
  'event''s canonical local time — display-only. Never store an '
  'abbreviation ("AST") or fixed offset ("GMT-4") here; those are '
  'derived at render time via Intl.DateTimeFormat. Null means the UI '
  'falls back to an unambiguous UTC-labeled display.';

update events
set timezone = 'America/Puerto_Rico'
where slug = 'miss-universe-2026';

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0009_event_timezone.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0009_event_timezone.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0009_event_timezone.sql"
}

try {
    $path = "FOUCH_EVENT_PARTICIPANTS_IMPORT.md"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
# FOUCH 0.3B — Event Participants Import & Update Workflow

No admin panel, no CMS, no scraper. This is a documented, founder/developer-run
SQL workflow against Supabase's SQL Editor — the same tool already used for
every migration in this project. Nothing here requires a Next.js deploy.

Status for Miss Grand International 2026 as of this sprint:
**PENDING OFFICIAL ROSTER IMPORT** — `missgrandinternational.com/contestants/`
blocked automated access during this sprint's investigation, and this sprint's
explicit instruction is to never substitute Wikipedia/fan-page data for the
production seed. The event row exists (migration 0011); zero
`event_participants` rows exist yet. Use the templates below once you have
the verified roster (e.g. by viewing the official site yourself in a normal
browser, which is not bot-blocked).

## 1. Add a new participant (country confirmed, delegate confirmed)

```sql
insert into event_participants
  (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at, notes)
values
  ('miss-grand-international-2026', 'BR', 'Brazil', 'Jane Doe', 'ACTIVE',
   'https://missgrandinternational.com/contestants/', now(), null);
```

## 2. Add a country slot with no confirmed delegate yet (PENDING)

Never invent a name. Leave `contestant_name` null and `status` = `'PENDING'`.

```sql
insert into event_participants
  (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at)
values
  ('miss-grand-international-2026', 'PY', 'Paraguay', null, 'PENDING',
   'https://missgrandinternational.com/contestants/', now());
```

## 3. Confirm a PENDING slot's delegate (PENDING → ACTIVE)

```sql
update event_participants
set contestant_name = 'Jane Doe',
    status = 'ACTIVE',
    source_checked_at = now(),
    updated_at = now()
where event_slug = 'miss-grand-international-2026'
  and country_code = 'PY'
  and status = 'PENDING';
```

## 4. Mark a participant WITHDRAWN

Never delete the row — existing predictions may reference its `id`.

```sql
update event_participants
set status = 'WITHDRAWN',
    source_checked_at = now(),
    updated_at = now()
where event_slug = 'miss-grand-international-2026'
  and country_code = 'BR'
  and status = 'ACTIVE';
```

## 5. Replace a participant (delegate change for the same country)

Two steps — mark the old row REPLACED, then insert the new delegate as a
**separate row with its own new id**. Never edit the old row's name in place.

```sql
update event_participants
set status = 'REPLACED',
    source_checked_at = now(),
    updated_at = now(),
    notes = 'Superseded by a new delegate — see the new ACTIVE row for Brazil.'
where event_slug = 'miss-grand-international-2026'
  and country_code = 'BR'
  and status = 'ACTIVE';

insert into event_participants
  (event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at)
values
  ('miss-grand-international-2026', 'BR', 'Brazil', 'New Delegate Name', 'ACTIVE',
   'https://missgrandinternational.com/contestants/', now());
```

The unique index `event_participants_one_current_slot_per_country` guarantees
at most one ACTIVE-or-PENDING row per country at a time — running the insert
before withdrawing the old row will fail loudly (constraint violation)
instead of silently creating two current slots for the same country.

## 6. Sanity checks after any change

```sql
-- One current (ACTIVE/PENDING) slot per country, at most:
select event_slug, country_code, count(*)
from event_participants
where status in ('ACTIVE', 'PENDING')
group by event_slug, country_code
having count(*) > 1;
-- Must return zero rows.

-- Current roster snapshot:
select country_name, contestant_name, status, source_checked_at
from event_participants
where event_slug = 'miss-grand-international-2026'
order by country_name;
```

## What this workflow does NOT do

- Never deletes prediction history — `prediction_items.participant_id` is a
  plain text column with no foreign key to this table (by design, see
  migration 0010's comment), so nothing here can ever cascade into a
  prediction.
- Never changes a historical participant's `id` — REPLACED/WITHDRAWN rows are
  kept forever, exactly as saved predictions already reference them.
- Never requires rebuilding or redeploying the Next.js app — the builder and
  every rendering path read this table live on every request.

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     FOUCH_EVENT_PARTICIPANTS_IMPORT.md"
} catch {
    Write-Host "FAILED: FOUCH_EVENT_PARTICIPANTS_IMPORT.md -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "FOUCH_EVENT_PARTICIPANTS_IMPORT.md"
}

try {
    $path = "src\lib\event-participants-db.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import "server-only";
import { getSupabaseServerClient } from "@/lib/supabase/server";
import type { EventParticipantStatus } from "@/lib/participant-status";

export interface EventParticipantRow {
  id: string;
  eventSlug: string;
  countryCode: string;
  countryName: string;
  contestantName: string | null;
  status: EventParticipantStatus;
  sourceUrl: string | null;
  sourceCheckedAt: string | null;
}

/**
 * All rows for an event, every status included — the raw material
 * both getParticipantsForEvent (filters to ACTIVE) and
 * resolveParticipantsByIds (no filter, for rendering history) build
 * on top of. Returns [] (never null) when the event has no DB-backed
 * participants at all, or when Supabase isn't configured — callers
 * that need to distinguish "event doesn't exist" from "event exists
 * with zero rows" do so via the `events` table itself, not this.
 */
export async function getAllEventParticipantRows(eventSlug: string): Promise<EventParticipantRow[]> {
  const supabase = getSupabaseServerClient();
  if (!supabase) return [];

  const { data, error } = await supabase
    .from("event_participants")
    .select("id, event_slug, country_code, country_name, contestant_name, status, source_url, source_checked_at")
    .eq("event_slug", eventSlug);

  if (error || !data) return [];

  return data.map((row) => ({
    id: row.id,
    eventSlug: row.event_slug,
    countryCode: row.country_code,
    countryName: row.country_name,
    contestantName: row.contestant_name,
    status: row.status as EventParticipantStatus,
    sourceUrl: row.source_url,
    sourceCheckedAt: row.source_checked_at,
  }));
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\event-participants-db.ts"
} catch {
    Write-Host "FAILED: src\lib\event-participants-db.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\event-participants-db.ts"
}

try {
    $path = "src\lib\participant-status.test.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
import { describe, it, expect } from "vitest";
import { isSelectableStatus } from "./participant-status";

describe("isSelectableStatus — the entire new-prediction selectability rule", () => {
  it("ACTIVE is selectable", () => {
    expect(isSelectableStatus("ACTIVE")).toBe(true);
  });

  it("PENDING is not selectable — identity not yet confirmed", () => {
    expect(isSelectableStatus("PENDING")).toBe(false);
  });

  it("WITHDRAWN is not selectable for a new prediction", () => {
    expect(isSelectableStatus("WITHDRAWN")).toBe(false);
  });

  it("REPLACED is not selectable for a new prediction", () => {
    expect(isSelectableStatus("REPLACED")).toBe(false);
  });

  it("only ACTIVE is ever true — a single boolean check the whole system shares", () => {
    const statuses: Array<Parameters<typeof isSelectableStatus>[0]> = [
      "ACTIVE",
      "PENDING",
      "WITHDRAWN",
      "REPLACED",
    ];
    const selectable = statuses.filter((s) => isSelectableStatus(s));
    expect(selectable).toEqual(["ACTIVE"]);
  });
});

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participant-status.test.ts"
} catch {
    Write-Host "FAILED: src\lib\participant-status.test.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participant-status.test.ts"
}

try {
    $path = "src\lib\participant-status.ts"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
/**
 * FOUCH 0.3B — the entire participant status model, in one small,
 * pure, DB-free place. Every rule about which statuses are
 * selectable for a NEW prediction lives here — nowhere else decides
 * this independently, so builder/validation/tests all agree by
 * construction.
 */
export type EventParticipantStatus = "ACTIVE" | "PENDING" | "WITHDRAWN" | "REPLACED";

/**
 * Only ACTIVE participants may be chosen for a new Top 10 (or a new
 * version of an edited one). PENDING (identity not yet confirmed),
 * WITHDRAWN, and REPLACED are all excluded — the same one boolean
 * check the whole system relies on to keep "is this a valid pick"
 * uniform everywhere.
 */
export function isSelectableStatus(status: EventParticipantStatus): boolean {
  return status === "ACTIVE";
}

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     src\lib\participant-status.ts"
} catch {
    Write-Host "FAILED: src\lib\participant-status.ts -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "src\lib\participant-status.ts"
}

try {
    $path = "supabase\migrations\0010_event_participants.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- FOUCH 0.3B — Dynamic Participants & Miss Grand International 2026.
--
-- ============================================================
-- DO NOT RUN THIS AGAINST PRODUCTION YET.
-- Prepared for local verification and founder review only.
-- ============================================================
--
-- Why a new table instead of touching prediction_items: this
-- codebase's prediction_items.participant_id is (and remains) a
-- plain TEXT column with NO foreign key — it never enforced
-- referential integrity against any participant table, for either
-- event. That means Miss Universe 2026's existing hardcoded
-- `demo-<code>` IDs (src/lib/participants.ts) need ZERO migration:
-- they keep working exactly as before, completely untouched by this
-- sprint. This migration only adds a NEW, separate source for events
-- that want database-driven participants — starting with Miss Grand
-- International 2026 — without retrofitting or risking Miss
-- Universe's already-live predictions.
--
-- Stable identity (brief §6): `id` is a server-generated uuid,
-- never derived from name/position/status/country text. A country
-- whose delegate changes gets a NEW row (new id) for the replacement
-- — the original row is kept, marked REPLACED, never mutated in
-- place and never deleted. This is exactly what makes historical
-- prediction_items.participant_id values (which reference a specific
-- id, stored as opaque text) stay resolvable forever, regardless of
-- what happens to that country's delegate later.

create table if not exists event_participants (
  id uuid primary key default gen_random_uuid(),
  event_slug text not null references events(slug),
  country_code text not null,
  country_name text not null,
  -- Null exactly when the official source lists the country/slot but
  -- has not yet named a confirmed delegate (status must be PENDING
  -- whenever this is null — enforced below).
  contestant_name text,
  status text not null check (status in ('ACTIVE', 'PENDING', 'WITHDRAWN', 'REPLACED')),
  source_url text,
  source_checked_at timestamptz,
  -- Optional short provenance note (brief §12) — e.g. "confirmed via
  -- official site country page" or "superseded by <id> on withdrawal".
  -- Free text, never parsed by application code.
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- The one real rule: a name may be absent ONLY while PENDING. Once
-- ACTIVE/WITHDRAWN/REPLACED, a contestant_name is required — the
-- import workflow can set a provisional name on a PENDING row before
-- flipping it to ACTIVE if it wants to, but never invents a name.
-- Plain ADD CONSTRAINT has no IF NOT EXISTS in Postgres, so this is
-- guarded explicitly to keep the whole migration safely re-runnable
-- (same pattern as migration 0008).
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'event_participants_name_required_unless_pending'
  ) then
    alter table event_participants
      add constraint event_participants_name_required_unless_pending
      check (contestant_name is not null or status = 'PENDING');
  end if;
end $$;

-- Only one CURRENT (selectable-or-pending) slot per country per
-- event — WITHDRAWN/REPLACED rows are historical and explicitly
-- excluded from this constraint, so a country can accumulate any
-- number of past delegates over time without ever colliding.
create unique index if not exists event_participants_one_current_slot_per_country
  on event_participants (event_slug, country_code)
  where status in ('ACTIVE', 'PENDING');

create index if not exists event_participants_event_slug_idx
  on event_participants (event_slug);

-- ------------------------------------------------------------------
-- RLS: publicly readable (a historical prediction referencing a
-- WITHDRAWN/REPLACED participant must still resolve its name/country
-- for any visitor viewing that public prediction — see brief §7),
-- but never writable by anon/authenticated. Participant maintenance
-- is a trusted, server-side-only workflow (brief §11/§20) — same
-- pattern as every other write path in this codebase (service-role
-- key only, never a client-side privileged write).
-- ------------------------------------------------------------------

alter table event_participants enable row level security;

drop policy if exists "event participants are publicly readable" on event_participants;
create policy "event participants are publicly readable"
  on event_participants for select
  using (true);

-- No insert/update/delete policy for anon/authenticated — with RLS
-- enabled and no matching policy, those operations are denied by
-- default, exactly like predictions/prediction_items/prediction_versions.

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0010_event_participants.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0010_event_participants.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0010_event_participants.sql"
}

try {
    $path = "supabase\migrations\0011_miss_grand_international_2026.sql"
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $content = @'
-- FOUCH 0.3B — seed the Miss Grand International 2026 event row.
--
-- ============================================================
-- DO NOT RUN THIS AGAINST PRODUCTION YET.
-- ============================================================
--
-- Deliberately does NOT insert any event_participants rows. Per
-- explicit founder instruction, the official roster is NOT scraped,
-- guessed, or backfilled from secondary sources (Wikipedia, fan
-- pages) in this sprint — missgrandinternational.com/contestants/
-- blocked automated access during this sprint's investigation.
-- Participant rows are added later via the documented import
-- workflow (see FOUCH_EVENT_PARTICIPANTS_IMPORT.md) once the founder
-- supplies the verified roster. Status: PENDING OFFICIAL ROSTER
-- IMPORT.
--
-- prediction_lock_at: the confirmed final date is 10 October 2026 in
-- Bangkok, Thailand (multiple corroborating sources), but no
-- authoritative exact start TIME for the final show was verified
-- during this sprint. Per this sprint's own instruction ("choose a
-- safe temporary configuration clearly marked as requiring founder
-- confirmation... never silently invent a competition start time"),
-- this uses the conservative placeholder of the START of the event's
-- own calendar day in Asia/Bangkok (2026-10-10T00:00:00 local =
-- 2026-10-09T17:00:00Z) — safely before any results could exist,
-- exactly the same reasoning already used for Miss Universe 2026's
-- seed. This MUST be reviewed and confirmed/corrected by the founder
-- once an authoritative start time is available — see notes column.

insert into events (
  slug,
  name,
  category,
  status,
  event_date,
  is_featured,
  subtitle,
  timezone,
  prediction_open_at,
  prediction_lock_at
)
values (
  'miss-grand-international-2026',
  'Miss Grand International 2026',
  'pageant',
  'upcoming',
  '2026-10-10',
  true,
  'Bangkok, Thailand',
  'Asia/Bangkok',
  null,
  '2026-10-09T17:00:00Z' -- PLACEHOLDER — start of event-local calendar day; confirm exact final start time.
)
on conflict (slug) do update
set
  timezone = excluded.timezone;
-- Only `timezone` is overwritten on conflict, same conservative
-- pattern as 0007 — if this event row already exists with a founder-
-- reviewed prediction_lock_at, this migration must never clobber it.

'@
    Set-Content -LiteralPath $path -Value $content -Encoding UTF8 -NoNewline -ErrorAction Stop
    Write-Host "OK:     supabase\migrations\0011_miss_grand_international_2026.sql"
} catch {
    Write-Host "FAILED: supabase\migrations\0011_miss_grand_international_2026.sql -- $($_.Exception.Message)" -ForegroundColor Red
    $failures += "supabase\migrations\0011_miss_grand_international_2026.sql"
}

if ($failures.Count -gt 0) {
    Write-Host ""
    Write-Host "$($failures.Count) file(s) failed." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "All 28 files written successfully." -ForegroundColor Green
}
