import { redirect, notFound } from "next/navigation";
import { getEventBySlug } from "@/lib/events";

/**
 * `/events/[slug]` predates the Prediction Builder (Sprint 0's
 * "coming soon" placeholder). Now that `/predict/[slug]` is real, this
 * route would just be a stale duplicate of the homepage's featured
 * event card — so it redirects straight to the builder instead of
 * carrying copy that's no longer true.
 */
export default async function EventPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) notFound();

  redirect(`/predict/${slug}`);
}