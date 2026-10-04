import Link from "next/link";
import { LanguageSwitcher } from "./LanguageSwitcher";

export function Nav() {
  return (
    <header className="border-b border-border">
      <div className="mx-auto flex max-w-content items-center justify-between px-6 py-5">
        <Link
          href="/"
          className="font-display text-xl font-semibold tracking-[0.12em] text-text-primary"
        >
          FOUCH
        </Link>
        <LanguageSwitcher />
      </div>
    </header>
  );
}