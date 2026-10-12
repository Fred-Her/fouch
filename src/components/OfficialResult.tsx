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
