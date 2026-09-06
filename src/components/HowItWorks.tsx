import type { Dictionary } from "@/content/types";

export function HowItWorks({ dictionary }: { dictionary: Dictionary }) {
  return (
    <section className="mx-auto max-w-content px-6 pb-20">
      <h2 className="font-display text-xl text-text-primary">
        {dictionary.howItWorks.title}
      </h2>
      <ol className="mt-6 grid gap-6 sm:grid-cols-3">
        {dictionary.howItWorks.steps.map((step, index) => (
          <li key={step.title} className="border-t border-border pt-4">
            <span className="text-sm text-text-muted">{index + 1}</span>
            <p className="mt-1 font-display text-lg text-text-primary">{step.title}</p>
            <p className="mt-1 text-sm text-text-secondary">{step.body}</p>
          </li>
        ))}
      </ol>
    </section>
  );
}
