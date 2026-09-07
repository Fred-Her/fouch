import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { getEventBySlug } from "@/lib/events";
import { getParticipantsForEvent } from "@/lib/participants";
import { ReviewContent } from "@/components/prediction/ReviewContent";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) return {};

  return { title: `Your Top 10 â€” ${event.name}` };
}

const REQUIRED_SELECTIONS = 10;

export default async function ReviewPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) notFound();

  const participantData = getParticipantsForEvent(slug);
  if (!participantData || participantData.participants.length === 0) notFound();

  const requiredCount = Math.min(REQUIRED_SELECTIONS, participantData.participants.length);

  return (
    <main className="mx-auto max-w-content px-6 py-8">
      <Link
        href={`/predict/${slug}`}
        className="text-sm text-text-secondary hover:text-text-primary"
      >
        â† Back to builder
      </Link>

      <p className="mt-6 font-display text-sm tracking-[0.2em] text-text-muted">FOUCH</p>
      <h1 className="mt-1 font-display text-2xl text-text-primary sm:text-3xl">{event.name}</h1>
      <p className="mt-3 font-display text-xl uppercase tracking-tight text-text-primary">
        Your Top {requiredCount}
      </p>

      <div className="mt-8">
        <ReviewContent
          eventSlug={slug}
          participants={participantData.participants}
          requiredCount={requiredCount}
        />
      </div>
    </main>
  );
}