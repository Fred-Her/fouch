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
