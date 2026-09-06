import { ImageResponse } from "next/og";

export const runtime = "edge";
export const alt = "Fouch — Make your call.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

export default function OpengraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "center",
          padding: "80px",
          backgroundColor: "#141318",
          color: "#F2EFE6",
          fontFamily: "Georgia, serif",
        }}
      >
        <div style={{ display: "flex", fontSize: 32, letterSpacing: 6, color: "#A6342E" }}>
          FOUCH
        </div>
        <div style={{ display: "flex", fontSize: 72, marginTop: 24, lineHeight: 1.1 }}>
          Make your call.
        </div>
        <div style={{ display: "flex", fontSize: 28, marginTop: 24, color: "#A39FB0" }}>
          Predict entertainment&apos;s biggest moments.
        </div>
      </div>
    ),
    { ...size },
  );
}
