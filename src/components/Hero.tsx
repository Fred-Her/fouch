import type { Dictionary } from "@/content/types";

export function Hero({ dictionary }: { dictionary: Dictionary }) {
  return (
    <section className="mx-auto max-w-content px-6 pb-14 pt-16 sm:pb-20 sm:pt-24">
      <h1 className="font-display text-4xl leading-[1.1] text-text-primary sm:text-5xl">
        {dictionary.hero.headline}
      </h1>
      <p className="mt-5 max-w-md text-lg text-text-secondary">
        {dictionary.hero.subhead}
      </p>
      <a
        href="#featured-event"
        className="mt-8 inline-flex items-center justify-center rounded border border-accent bg-accent px-6 py-3 text-sm font-medium text-on-accent transition-colors hover:bg-accent-strong hover:border-accent-strong"
      >
        {dictionary.hero.cta}
      </a>
    </section>
  );
}
