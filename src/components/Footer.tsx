import Link from "next/link";
import type { Dictionary } from "@/content/types";

export function Footer({ dictionary }: { dictionary: Dictionary }) {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto max-w-content px-6 py-8">
        <p className="font-display text-base font-semibold tracking-[0.12em] text-text-primary">
          FOUCH
        </p>
        <p className="mt-1 text-sm text-text-muted">{dictionary.footer.tagline}</p>
        <p className="mt-1 text-xs text-text-muted">
          FOUCH is an independent fan prediction game — not affiliated with Miss Universe.
        </p>
        <div className="mt-3 flex gap-4 text-xs text-text-muted">
          <Link href="/privacy" className="underline hover:text-text-secondary">
            Privacy
          </Link>
          <Link href="/terms" className="underline hover:text-text-secondary">
            Terms
          </Link>
        </div>
      </div>
    </footer>
  );
}