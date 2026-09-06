import type { Metadata } from "next";
import { notFound } from "next/navigation";
import Link from "next/link";
import { en } from "@/content/en";
import { getEventBySlug } from "@/lib/events";

export async function generateMetadata({
  params,
}: {
  params: Promise<{ slug: string }>;
}): Promise<Metadata> {
  const { slug } = await params;
  const event = getEventBySlug(slug);
  if (!event) return {};

  return {
    title: event.name,
    description: en.hero.subhead,
  };
}

export default async function EventPage({
  params,
}: {
  params: Promise<{ slug: string }>;
}) {
  const { slug } = await params;
  const event = getEventBySlug(slug);

  if (!event) notFound();

  return (
    <main className="mx-auto max-w-content px-6 py-16">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        ← {en.eventPage.back}
      </Link>

      <h1 className="mt-6 font-display text-3xl text-text-primary">{event.name}</h1>
      {event.subtitle ? (
        <p className="mt-2 text-sm text-text-muted">{event.subtitle}</p>
      ) : null}

      <div className="mt-10 rounded-md border border-border bg-surface p-6">
        <p className="text-text-secondary">{en.eventPage.comingSoon}</p>
      </div>
    </main>
  );
}
