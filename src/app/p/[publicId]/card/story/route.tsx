import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { PredictionCardMarkup } from "@/components/prediction/PredictionCardMarkup";
import { siteUrl } from "@/lib/site";

export const runtime = "edge";

const WIDTH = 1080;
const HEIGHT = 1920;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ publicId: string }> },
) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);

  if (!record) {
    return new Response("Prediction not found", { status: 404 });
  }

  return new ImageResponse(
    (
      <PredictionCardMarkup
        width={WIDTH}
        height={HEIGHT}
        siteDomain={siteUrl.replace(/^https?:\/\//, "")}
        data={{
          eventName: record.event.name,
          nickname: record.prediction.nickname,
          countryCode: record.prediction.countryCode,
          isDemo: record.prediction.dataStatus === "demo",
          rankedParticipants: record.rankedParticipants,
        }}
      />
    ),
    { width: WIDTH, height: HEIGHT },
  );
}