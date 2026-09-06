# Sprint 0.1 — applies all visual-polish file changes.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-sprint01.ps1

$path = "src\lib\site.ts"
$content = @'
/**
 * Central source of truth for the site's absolute URL.
 *
 * Resolution order:
 * 1. NEXT_PUBLIC_SITE_URL — set this once we own a real custom domain.
 * 2. VERCEL_PROJECT_PRODUCTION_URL — Vercel's stable alias for
 *    "current production" (e.g. fouch-tau.vercel.app). Preferred over
 *    VERCEL_URL, which changes per-deployment.
 * 3. VERCEL_URL — this specific deployment's URL, as a last resort.
 * 4. localhost — local dev.
 *
 * Every check is an explicit truthy `if`, not `??` — Vercel can create
 * NEXT_PUBLIC_SITE_URL as an empty string (not undefined) when it
 * auto-detects env vars from .env.example, and `??` only falls back on
 * null/undefined, which would let an empty string slip through and
 * break `new URL("")` at build time.
 */
function resolveSiteUrl(): string {
  if (process.env.NEXT_PUBLIC_SITE_URL) {
    return process.env.NEXT_PUBLIC_SITE_URL;
  }
  if (process.env.VERCEL_PROJECT_PRODUCTION_URL) {
    return `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}`;
  }
  if (process.env.VERCEL_URL) {
    return `https://${process.env.VERCEL_URL}`;
  }
  return "http://localhost:3000";
}

export const siteUrl = resolveSiteUrl();
'@
Set-Content -Path $path -Value $content -Encoding UTF8 -NoNewline
Write-Host "Updated: src\lib\site.ts"

$path = "src\app\layout.tsx"
$content = @'
import type { Metadata } from "next";
import { en } from "@/content/en";
import { siteUrl } from "@/lib/site";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(siteUrl),
  alternates: {
    canonical: "/",
  },
  title: {
    default: en.meta.title,
    template: "%s · Fouch",
  },
  description: en.meta.description,
  openGraph: {
    title: en.meta.title,
    description: en.meta.description,
    url: siteUrl,
    siteName: "Fouch",
    locale: "en_US",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: en.meta.title,
    description: en.meta.description,
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
'@
Set-Content -Path $path -Value $content -Encoding UTF8 -NoNewline
Write-Host "Updated: src\app\layout.tsx"

$path = ".env.example"
$content = @'
# Copy this file to .env.local and fill in real values.
# Never commit .env.local — it's already in .gitignore.

# --- Supabase --------------------------------------------------------
# Public — safe to expose to the browser.
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
# Server-only — NEVER prefix with NEXT_PUBLIC_, never import outside
# src/lib/supabase/server.ts.
SUPABASE_SERVICE_ROLE_KEY=

# --- Site --------------------------------------------------------------
# Only set this once we own a real custom domain. Until then, leave it
# unset — src/lib/site.ts automatically falls back to Vercel's stable
# production URL (e.g. fouch-tau.vercel.app), so metadata/OG/sitemap
# never incorrectly point at a domain we don't control.
NEXT_PUBLIC_SITE_URL=

# --- Analytics (optional, future) --------------------------------------
# Leave unset locally. Analytics silently no-ops when absent.
NEXT_PUBLIC_ANALYTICS_ENABLED=
NEXT_PUBLIC_POSTHOG_KEY=
NEXT_PUBLIC_POSTHOG_HOST=
'@
Set-Content -Path $path -Value $content -Encoding UTF8 -NoNewline
Write-Host "Updated: .env.example"

$path = "src\components\Hero.tsx"
$content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";

export function Hero({ dictionary }: { dictionary: Dictionary }) {
  return (
    <section className="relative overflow-hidden">
      {/* Subtle decorative glow — not neon, not animated, just enough to
          suggest something is about to happen behind the headline. */}
      <div
        aria-hidden
        className="pointer-events-none absolute -top-40 left-1/2 h-[32rem] w-[32rem] -translate-x-1/2 rounded-full bg-accent/10 blur-3xl"
      />

      <div className="relative mx-auto max-w-content px-6 pb-12 pt-14 sm:pb-16 sm:pt-24">
        <p className="font-display text-sm tracking-[0.2em] text-text-muted">FOUCH</p>

        <h1 className="mt-4 font-display text-[3.25rem] font-semibold uppercase leading-[0.95] tracking-tight text-text-primary sm:text-7xl">
          Make
          <br />
          your
          <br />
          call.
        </h1>

        <p className="mt-6 max-w-sm text-lg text-text-secondary">
          {dictionary.hero.subhead}
        </p>

        <a
          href="#featured-event"
          className="group mt-9 inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent shadow-[0_0_0_1px_rgba(166,52,46,0.4)] transition-colors hover:bg-accent-strong"
        >
          {dictionary.hero.cta}
          <ArrowRight
            className="h-4 w-4 transition-transform group-hover:translate-x-0.5"
            aria-hidden
          />
        </a>
      </div>
    </section>
  );
}
'@
Set-Content -Path $path -Value $content -Encoding UTF8 -NoNewline
Write-Host "Updated: src\components\Hero.tsx"

$path = "src\components\FeaturedEvent.tsx"
$content = @'
import { ArrowRight } from "lucide-react";
import type { Dictionary } from "@/content/types";
import type { FouchEvent } from "@/types/event";
import { TrackedLink } from "./TrackedLink";

const statusLabel: Record<FouchEvent["status"], string> = {
  upcoming: "Upcoming",
  open: "Open",
  live: "Live",
  completed: "Completed",
};

export function FeaturedEvent({
  event,
  dictionary,
}: {
  event: FouchEvent;
  dictionary: Dictionary;
}) {
  const date = new Date(`${event.eventDate}T00:00:00Z`);
  const dayMonth = date
    .toLocaleDateString("en-US", { month: "short", day: "numeric", timeZone: "UTC" })
    .toUpperCase();

  // Decorative only — a preview of the ranking mechanic, not real input.
  const previewSlots = [1, 2, 3];

  return (
    <section
      id="featured-event"
      className="relative scroll-mt-20 overflow-hidden border-y border-border bg-surface py-14 sm:py-20"
    >
      <div
        aria-hidden
        className="pointer-events-none absolute -right-24 top-1/2 h-96 w-96 -translate-y-1/2 rounded-full bg-accent/10 blur-3xl"
      />

      <div className="relative mx-auto max-w-content px-6">
        <div className="flex items-center gap-2">
          <span
            aria-hidden
            className={
              event.status === "live"
                ? "h-1.5 w-1.5 rounded-full bg-accent animate-pulse motion-reduce:animate-none"
                : "h-1.5 w-1.5 rounded-full bg-text-muted"
            }
          />
          <span className="text-xs font-medium uppercase tracking-[0.2em] text-text-secondary">
            {statusLabel[event.status]}
          </span>
        </div>

        <h2 className="mt-5 font-display leading-[0.95] text-text-primary">
          <span className="block text-3xl sm:text-4xl">Miss Universe</span>
          <span className="block text-7xl font-semibold tracking-tight sm:text-8xl">
            2026
          </span>
        </h2>

        <p className="mt-4 text-sm uppercase tracking-[0.15em] text-text-muted">
          {dayMonth} · {event.subtitle}
        </p>

        <p className="mt-8 text-lg text-text-secondary">{dictionary.featuredEvent.prompt}</p>

        {/* Decorative preview of the ranking mechanic — not interactive. */}
        <div aria-hidden className="mt-6 max-w-xs space-y-2">
          {previewSlots.map((slot) => (
            <div key={slot} className="flex items-center gap-3">
              <span className="font-display text-sm text-text-muted">
                {String(slot).padStart(2, "0")}
              </span>
              <span className="h-px flex-1 bg-border-strong" />
            </div>
          ))}
        </div>

        <TrackedLink
          href={`/events/${event.slug}`}
          event="featured_event_clicked"
          eventProperties={{ slug: event.slug }}
          className="group mt-8 inline-flex items-center gap-2 rounded bg-accent px-7 py-4 text-base font-medium text-on-accent transition-colors hover:bg-accent-strong"
        >
          {dictionary.featuredEvent.cta}
          <ArrowRight
            className="h-4 w-4 transition-transform group-hover:translate-x-0.5"
            aria-hidden
          />
        </TrackedLink>
      </div>
    </section>
  );
}
'@
Set-Content -Path $path -Value $content -Encoding UTF8 -NoNewline
Write-Host "Updated: src\components\FeaturedEvent.tsx"

$path = "src\components\HowItWorks.tsx"
$content = @'
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
'@
Set-Content -Path $path -Value $content -Encoding UTF8 -NoNewline
Write-Host "Updated: src\components\HowItWorks.tsx"

$path = "src\components\Nav.tsx"
$content = @'
import Link from "next/link";

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
        {/*
          Sprint 0 intentionally has no other nav items: no login button
          (auth doesn't exist yet), no links to pages that aren't built.
        */}
      </div>
    </header>
  );
}
'@
Set-Content -Path $path -Value $content -Encoding UTF8 -NoNewline
Write-Host "Updated: src\components\Nav.tsx"

$path = "src\components\Footer.tsx"
$content = @'
import type { Dictionary } from "@/content/types";

export function Footer({ dictionary }: { dictionary: Dictionary }) {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto max-w-content px-6 py-8">
        <p className="font-display text-base font-semibold tracking-[0.12em] text-text-primary">
          FOUCH
        </p>
        <p className="mt-1 text-sm text-text-muted">{dictionary.footer.tagline}</p>
      </div>
    </footer>
  );
}
'@
Set-Content -Path $path -Value $content -Encoding UTF8 -NoNewline
Write-Host "Updated: src\components\Footer.tsx"
