import { ImageResponse } from "next/og";
import { flagEmoji } from "@/lib/flags";
import { getPredictionWithParticipants } from "@/lib/predictions-db";

export const runtime = "edge";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default async function OpengraphImage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);

  const ink = "#141318";
  const accent = "#A6342E";
  const textPrimary = "#F2EFE6";
  const textMuted = "#A39FB0";

  if (!record) {
    return new ImageResponse(
      (
        <div
          style={{
            width: "100%",
            height: "100%",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            backgroundColor: ink,
            color: textPrimary,
            fontFamily: "Georgia, serif",
            fontSize: 48,
          }}
        >
          FOUCH
        </div>
      ),
      { ...size },
    );
  }

  const top3 = record.rankedParticipants.slice(0, 3);
  const heading = record.prediction.nickname ? `${record.prediction.nickname}'s Top 10` : "A Top 10 prediction";

  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "60px 70px",
          backgroundColor: ink,
          color: textPrimary,
          fontFamily: "Georgia, serif",
        }}
      >
        <div style={{ display: "flex", fontSize: 26, letterSpacing: 4, color: accent }}>FOUCH</div>
        <div style={{ display: "flex", fontSize: 46, marginTop: 12 }}>{heading}</div>
        <div style={{ display: "flex", fontSize: 26, color: textMuted, marginTop: 6 }}>
          {record.event.name}
        </div>
        <div style={{ display: "flex", marginTop: 30, gap: 24 }}>
          {top3.map((participant, index) => (
            <div key={participant.id} style={{ display: "flex", alignItems: "center", fontSize: 28 }}>
              <span style={{ display: "flex", color: accent, marginRight: 10 }}>{index + 1}</span>
              <span style={{ display: "flex", marginRight: 8 }}>{flagEmoji(participant.countryCode)}</span>
              <span style={{ display: "flex" }}>{participant.displayName}</span>
            </div>
          ))}
        </div>
      </div>
    ),
    { ...size },
  );
}