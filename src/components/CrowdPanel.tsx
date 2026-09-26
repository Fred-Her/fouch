import Link from "next/link";
import { CountryFlag } from "@/components/CountryFlag";
import { getSampleSizeBucket } from "@/lib/community-comparison";
import type { CrowdTopPicks } from "@/lib/crowd-picks";

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
}: {
  crowd: CrowdTopPicks;
  eventSlug: string;
  predictHref: string;
}) {
  const bucket = getSampleSizeBucket(crowd.population);
  const isEarly = bucket === "0" || bucket === "1_4";

  return (
    <div className="relative overflow-hidden rounded-lg border border-white/10 bg-white/[0.03] p-6 backdrop-blur-sm">
      <span className="absolute inset-x-0 top-0 h-px bg-gradient-to-r from-transparent via-accent/60 to-transparent" aria-hidden />

      <div className="flex items-center gap-2">
        <span aria-hidden className="h-1.5 w-1.5 rounded-full bg-accent" />
        <p className="text-xs font-medium uppercase tracking-[0.25em] text-text-secondary">The Crowd</p>
      </div>

      {isEarly ? (
        <>
          <p className="mt-5 font-display text-3xl uppercase tracking-tight text-text-primary">
            It&apos;s early.
          </p>
          <p className="mt-3 text-sm text-text-secondary">
            The first calls are coming in. Make yours before the crowd starts taking shape.
          </p>
          <Link
            href={predictHref}
            className="mt-6 inline-flex items-center gap-1 text-sm font-medium text-accent-strong hover:text-accent"
          >
            Make your call →
          </Link>
        </>
      ) : (
        <>
          <div className="mt-3 flex items-center justify-between">
            <p className="text-sm text-text-secondary">Who does the crowd have winning?</p>
            <Link
              href={`/events/${eventSlug}/leaderboard`}
              className="shrink-0 text-xs text-text-muted hover:text-text-secondary"
            >
              View all →
            </Link>
          </div>

          <ol className="mt-5 space-y-3.5">
            {crowd.picks.map((pick, index) => (
              <li key={pick.participant.id} className="flex items-center gap-3">
                <span className="font-display w-4 shrink-0 text-sm text-text-muted">{index + 1}</span>
                <CountryFlag countryCode={pick.participant.countryCode} className="h-4 w-6 shrink-0 rounded-sm" />
                <span className="flex-1 truncate text-sm text-text-primary">{pick.participant.displayName}</span>
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

          <p className="mt-5 text-xs text-text-muted">Based on {crowd.population} predictions</p>
        </>
      )}
    </div>
  );
}
