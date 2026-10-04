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