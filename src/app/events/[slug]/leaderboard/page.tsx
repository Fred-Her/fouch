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

  const participantData = getParticipantsForEvent(slug);
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

  const participantData = getParticipantsForEvent(slug);
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