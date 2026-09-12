import { ImageResponse } from "next/og";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getPredictionScore } from "@/lib/scoring-service";
import { ResultCardMarkup } from "@/components/scoring/ResultCardMarkup";
import { siteUrl } from "@/lib/site";

export const runtime = "edge";

const WIDTH = 1080;
const HEIGHT = 1350;

export async function GET(
  _request: Request,
  { params }: { params: Promise<{ publicId: string }> },
) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) return new Response("Prediction not found", { status: 404 });

  const result = await getPredictionScore(
    record.prediction.id,
    record.prediction.rankedParticipantIds,
    record.event.slug,
    record.prediction.dataStatus,
  );
  if (!result) return new Response("No official result yet", { status: 404 });

  return new ImageResponse(
    (
      <ResultCardMarkup
        width={WIDTH}
        height={HEIGHT}
        siteDomain={siteUrl.replace(/^https?:\/\//, "")}
        data={{
          eventName: record.event.name,
          nickname: record.prediction.nickname,
          countryCode: record.prediction.countryCode,
          isDemo: record.prediction.dataStatus === "demo",
          breakdown: result.breakdown,
          percentile: result.percentile.percentile,
        }}
      />
    ),
    { width: WIDTH, height: HEIGHT },
  );
}