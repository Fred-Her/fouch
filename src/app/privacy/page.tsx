import type { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
  title: "Privacy | FOUCH",
  description: "What FOUCH collects, why, and what stays public.",
};

export default function PrivacyPage() {
  return (
    <main className="mx-auto max-w-content px-6 py-12">
      <Link href="/" className="text-sm text-text-secondary hover:text-text-primary">
        FOUCH
      </Link>
      <h1 className="mt-6 font-display text-3xl text-text-primary">Privacy</h1>
      <p className="mt-2 text-sm text-text-muted">Last updated for the FOUCH beta.</p>

      <div className="mt-8 space-y-6 text-sm text-text-secondary">
        <section>
          <h2 className="font-display text-lg text-text-primary">What we collect</h2>
          <p className="mt-2">
            To lock a prediction, we ask for your email address, which we use only to verify
            that your call is real and to prevent one person from locking multiple predictions
            for the same event. Your email is managed by our authentication provider (Supabase)
            and is never made public.
          </p>
          <p className="mt-2">
            You may optionally add a nickname and country — both are shown publicly alongside
            your prediction if you provide them.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">What&apos;s public</h2>
          <p className="mt-2">
            Your prediction itself — the ranking you submit, your nickname (or &quot;Anonymous&quot;
            if you don&apos;t provide one), your country, and your score once results are
            available — is public and accessible to anyone with the link. Your email is never
            part of that public page.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">Analytics</h2>
          <p className="mt-2">
            We use basic product analytics to understand how people use FOUCH (e.g. whether a
            prediction was completed, whether a result was shared). These events never include
            your email or any other personally identifying information.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">No gambling, no money</h2>
          <p className="mt-2">
            FOUCH is an entertainment prediction game. There is no monetary betting and no cash
            prizes.
          </p>
        </section>

        <section>
          <h2 className="font-display text-lg text-text-primary">Questions or deletion requests</h2>
          <p className="mt-2">
            FOUCH is currently a small beta. If you&apos;d like your data removed, reach out
            through the feedback link on the site and we&apos;ll handle it directly.
          </p>
        </section>
      </div>
    </main>
  );
}