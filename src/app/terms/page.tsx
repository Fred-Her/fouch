import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Terms | FOUCH",
  description: "The basics of using FOUCH during its beta.",
};

export default function TermsPage() {
  return (
    <main className="mx-auto max-w-content px-6 py-12">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>
      <h1 className="mt-6 font-display text-3xl text-text-primary">Terms</h1>
      <p className="mt-2 text-sm text-text-muted">Last updated for the FOUCH beta.</p>

      <div className="mt-8 space-y-6 text-sm text-text-secondary">
        <section>
          <h2 className="font-display text-lg text-text-primary">What FOUCH is</h2>
          <p className="mt-2">
            FOUCH is an entertainment prediction game for fans. It is an independent project and
            is not affiliated with, endorsed by, or connected to Miss Universe or any pageant
            organization.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">No betting, no prizes</h2>
          <p className="mt-2">
            FOUCH involves no monetary betting or wagering, and there are no guaranteed prizes
            for participating.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">Your content</h2>
          <p className="mt-2">
            Your prediction, nickname, and country (if provided) are shown publicly. Please
            don&apos;t submit anything abusive, offensive, or that impersonates someone else — we
            may remove content that violates this.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">One prediction per person, per event</h2>
          <p className="mt-2">
            We verify your email to keep the game fair — one verified identity may lock one final
            prediction per event.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">Beta availability</h2>
          <p className="mt-2">
            FOUCH is in active beta. Features, availability, and the service itself may change
            without notice, and we don&apos;t guarantee uptime during this period.
          </p>
        </section>
      </div>
    </main>
  );
}