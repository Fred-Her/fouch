import { ImageResponse } from "next/og";

export const runtime = "edge";
export const size = { width: 64, height: 64 };
export const contentType = "image/png";

export default function Icon() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          backgroundColor: "#141318",
          color: "#F2EFE6",
          fontFamily: "Georgia, serif",
          fontSize: 38,
        }}
      >
        F
      </div>
    ),
    { ...size },
  );
}
