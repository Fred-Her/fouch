import Link from "next/link";
import type { Dictionary } from "@/content/types";
import { LanguageSwitcher } from "./LanguageSwitcher";

export function Footer({ dictionary }: { dictionary: Dictionary }) {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto max-w-content px-6 py-8">
        <p className="font-display text-base font-semibold tracking-[0.12em] text-text-primary">
          FOUCH
        </p>
        <p className="mt-1 text-sm text-text-muted">{dictionary.footer.tagline}</p>
        <p className="mt-1 text-xs text-text-muted">
          {dictionary.footer.disclaimer}
        </p>
        <div className="mt-3 flex gap-4 text-xs text-text-muted">
          <Link href="/privacy" className="underline hover:text-text-secondary">
            {dictionary.footer.privacy}
          </Link>
          <Link href="/terms" className="underline hover:text-text-secondary">
            {dictionary.footer.terms}
          </Link>
          <span aria-hidden className="text-border-strong">
            ·
          </span>
          <LanguageSwitcher />
        </div>
      </div>
    </footer>
  );
}