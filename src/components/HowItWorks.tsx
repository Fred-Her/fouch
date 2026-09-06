import type { Dictionary } from "@/content/types";

export function HowItWorks({ dictionary }: { dictionary: Dictionary }) {
  return (
    <section className="mx-auto max-w-content px-6 py-16 sm:py-20">
      <div className="grid gap-10 sm:grid-cols-3 sm:gap-6">
        {dictionary.howItWorks.steps.map((step, index) => (
          <div key={step.title}>
            <p className="font-display text-4xl text-border-strong">
              {String(index + 1).padStart(2, "0")}
            </p>
            <p className="mt-2 font-display text-2xl uppercase tracking-tight text-text-primary">
              {step.title}
            </p>
            <p className="mt-1 text-sm text-text-secondary">{step.body}</p>
          </div>
        ))}
      </div>
    </section>
  );
}