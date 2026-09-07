import type { Participant } from "@/types/participant";

export interface CardData {
  eventName: string;
  nickname: string | null;
  countryCode: string | null;
  isDemo: boolean;
  rankedParticipants: Participant[];
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
 * A small country-code badge is the robust substitute: no emoji font
 * dependency, no network fetch, renders identically everywhere.
 */
function CountryBadge({ code, fontSize }: { code: string; fontSize: number }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        fontSize,
        fontWeight: 700,
        letterSpacing: 1,
        color: TEXT_MUTED,
      }}
    >
      {code}
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
  const whoBy = data.nickname
    ? `${data.nickname}${data.countryCode ? ` · ${data.countryCode}` : ""}`
    : data.countryCode;

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
              DEMO
            </div>
          ) : null}
        </div>
        <div style={{ display: "flex", fontSize: 46 * scale, fontWeight: 700, marginTop: 18 }}>
          MAKE YOUR CALL.
        </div>
        <div style={{ display: "flex", fontSize: 30, color: TEXT_MUTED, marginTop: 8 }}>
          {data.eventName}
        </div>
        {whoBy ? (
          <div style={{ display: "flex", fontSize: 28, color: ACCENT_STRONG, marginTop: 10 }}>
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
            <CountryBadge code={participant.countryCode} fontSize={26 * scale} />
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
              <CountryBadge code={participant.countryCode} fontSize={20} />
            </div>
          ))}
        </div>
      ) : null}

      {/* Footer */}
      <div style={{ display: "flex", flexDirection: "column", marginTop: "auto" }}>
        <div style={{ display: "flex", fontSize: 34, fontWeight: 700 }}>WHO YOU GOT?</div>
        <div style={{ display: "flex", fontSize: 24, color: TEXT_MUTED, marginTop: 6 }}>
          {siteDomain}
        </div>
      </div>
    </div>
  );
}