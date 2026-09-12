import type { ScoreBreakdown, ScoreBand } from "@/types/scoring";

export interface ResultCardData {
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

const BAND_LABEL: Record<ScoreBand, string> = {
  MISSED_IT: "Missed it",
  FAIR: "Fair call",
  GOOD: "Good call",
  EXCELLENT: "Excellent call",
  ELITE: "Elite call",
};

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
  const whoBy = data.nickname
    ? `${data.nickname}${data.countryCode ? ` · ${data.countryCode}` : ""}`
    : data.countryCode;
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
        <div style={{ display: "flex", fontSize: 26, color: ACCENT_STRONG, marginTop: 8 }}>{whoBy}</div>
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
        {BAND_LABEL[breakdown.band].toUpperCase()}
      </div>

      {/* Breakdown */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: 64 * scale, gap: 28 * scale }}>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Winner</div>
          <div style={{ display: "flex", color: breakdown.components.winner.hit ? ACCENT_STRONG : TEXT_MUTED }}>
            {breakdown.components.winner.hit ? "Correct" : "Missed"}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Podium</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.podium.hits} / {breakdown.components.podium.total}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Top 5</div>
          <div style={{ display: "flex" }}>
            {breakdown.components.top5.hits} / {breakdown.components.top5.total}
          </div>
        </div>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 34 * scale }}>
          <div style={{ display: "flex" }}>Top 10</div>
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
          <div style={{ display: "flex", fontSize: 30 * scale, color: TEXT_MUTED }}>TOP {100 - Math.round(data.percentile)}%</div>
          <div style={{ display: "flex", fontSize: 38 * scale, fontWeight: 700 }}>WORLDWIDE</div>
        </div>
      ) : null}

      {/* Footer */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: "auto" }}>
        <div style={{ display: "flex", fontSize: 34, fontWeight: 700 }}>THINK YOU COULD BEAT IT?</div>
        <div style={{ display: "flex", fontSize: 24, color: TEXT_MUTED, marginTop: 6 }}>{siteDomain}</div>
      </div>
    </div>
  );
}