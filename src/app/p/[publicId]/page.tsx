import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { CountryFlag } from "@/components/CountryFlag";
import { siteUrl } from "@/lib/site";
import { getPredictionWithParticipants } from "@/lib/predictions-db";
import { getParticipantsForEvent } from "@/lib/participants";
import { getEventLockConfig, isPredictionWindowOpen } from "@/lib/events-db";
import { getOfficialResult } from "@/lib/results-db";
import { formatContestantListUpdated } from "@/lib/event-time-display";
import { PublicPredictionView } from "@/components/prediction/PublicPredictionView";
import { YouVsTheWorld } from "@/components/prediction/YouVsTheWorld";
import { FouchScore } from "@/components/scoring/FouchScore";
import { YourCrowdChanged } from "@/components/scoring/YourCrowdChanged";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ publicId: string }>;
}): Promise<Metadata> {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) return {};

  const title = record.prediction.nickname
    ? `${record.prediction.nickname}'s Top 10 â€” ${record.event.name}`
    : `A Top 10 prediction â€” ${record.event.name}`;
  const description = "See the prediction, then make your own call.";

  return {
    title,
    description,
    // Sprint 2 decision: public prediction pages are reachable via
    // link but intentionally not indexed â€” we don't want thousands of
    // thin user-generated pages in search results. `follow` so the
    // "Make your Top 10" CTA is still crawlable back to the real
    // product pages.
    robots: { index: false, follow: true },
    openGraph: {
      title,
      description,
      url: `${siteUrl}/p/${publicId}`,
      images: [`${siteUrl}/p/${publicId}/opengraph-image`],
    },
    twitter: {
      card: "summary_large_image",
      title,
      description,
    },
  };
}

export default async function PublicPredictionPage({
  params,
}: {
  params: Promise<{ publicId: string }>;
}) {
  const { publicId } = await params;
  const record = await getPredictionWithParticipants(publicId);
  if (!record) notFound();

  const { prediction, event, rankedParticipants } = record;
  const heading = prediction.nickname ? `${prediction.nickname}'s Top 10` : "Someone's Top 10";

  // Cheap existence check only (no percentile/breakdown work) â€” used
  // purely to decide share-CTA hierarchy (Sprint 4.1 Â§7-8). FouchScore
  // below independently does the full scored computation; this is a
  // second, lightweight read of the same result row, not duplicated
  // scoring logic.
  const official = await getOfficialResult(event.slug, prediction.dataStatus);
  const hasResult = Boolean(official);

  // FOUCH 0.3A: editing is offered only for a verified prediction
  // while the event is still open â€” fetched fresh on every page view
  // from the single authoritative source, never cached/assumed.
  const lockConfig = await getEventLockConfig(event.slug);
  const isPredictionOpen = isPredictionWindowOpen(lockConfig, Date.now());
  const canEdit = prediction.hasVerifiedOwner && isPredictionOpen;
  const showLockedNotice = prediction.hasVerifiedOwner && !isPredictionOpen;

  // FOUCH 0.3B Â§13: "Contestant list updated {date}" for a real,
  // non-demo event with verified-roster provenance â€” never "Demo
  // prediction" for one of these. Null (no participant rows checked
  // yet, or a hardcoded/demo event) simply shows nothing extra here.
  const participantData = await getParticipantsForEvent(event.slug);
  const sourceCheckedAt = participantData?.sourceCheckedAt ?? null;

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>

      <h1 className="mt-6 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-2 font-display text-xl uppercase tracking-tight text-text-primary">
        {heading}
      </p>

      {prediction.countryCode ? (
        <p className="mt-1 text-sm text-text-muted"><CountryFlag countryCode={prediction.countryCode} /></p>
      ) : null}

      {prediction.dataStatus === "demo" ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          Demo prediction â€” not the official lineup
        </p>
      ) : sourceCheckedAt ? (
        <p className="mt-3 inline-block rounded border border-border-strong px-2 py-1 text-xs text-text-muted">
          {formatContestantListUpdated(sourceCheckedAt)}
        </p>
      ) : null}

      <PublicPredictionView
        eventSlug={event.slug}
        publicId={publicId}
        rankedParticipants={rankedParticipants}
        hasResult={hasResult}
        canEdit={canEdit}
        showLockedNotice={showLockedNotice}
        predictionLockAt={lockConfig?.predictionLockAt ?? null}
        predictionTimezone={lockConfig?.timezone ?? null}
        fouchScore={<FouchScore prediction={prediction} event={event} publicId={publicId} />}
        youVsTheWorld={<YouVsTheWorld prediction={prediction} event={event} />}
        yourCrowdChanged={<YourCrowdChanged prediction={prediction} event={event} />}
      />
    </main>
  );
}