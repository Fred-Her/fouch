import { CountryFlag } from "@/components/CountryFlag";
import { TrackedLink } from "@/components/TrackedLink";
import type { LeaderboardEntry } from "@/lib/leaderboard";

export function LeaderboardRow({
  entry,
  eventSlug,
  isViewer,
  prominent,
}: {
  entry: LeaderboardEntry;
  eventSlug: string;
  isViewer: boolean;
  /** Top 3 get slightly stronger typography — restrained, no medals. */
  prominent: boolean;
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
        {isViewer ? <span className="ml-2 text-xs uppercase tracking-wide text-accent-strong">You</span> : null}
      </span>
      <span className={`font-display text-text-primary ${prominent ? "text-2xl" : "text-base"}`}>
        {entry.score}
      </span>
    </TrackedLink>
  );
}