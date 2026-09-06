# Fouch

Fouch is a worldwide social entertainment-prediction platform. The core
loop is **Predict → Compete → Score → Share**. The initial wedge is
pageants, but the architecture and brand are deliberately
category-agnostic — future categories include Eurovision, the Oscars,
the Grammys, and other entertainment competitions.

This repository is currently at **Sprint 0 / Foundation**: the public
homepage and technical foundation, not the product itself.

## Stack

- [Next.js](https://nextjs.org) (App Router) + TypeScript
- [Tailwind CSS](https://tailwindcss.com)
- [Supabase](https://supabase.com) / PostgreSQL (prepared, not yet load-bearing — see below)
- [Vercel](https://vercel.com) for hosting

## Prerequisites

- Node.js 20+
- npm

## Local setup

```bash
npm install
cp .env.example .env.local   # fill in values if you have them — see below
npm run dev
```

Open http://localhost:3000.

**Nothing in `.env.local` is required to run Sprint 0.** The homepage
reads from a typed seed event in `src/lib/events.ts`, not from
Supabase, so the app runs with zero configuration.

## Environment variables

See `.env.example` for the full list. Summary:

| Variable | Required for Sprint 0? | Notes |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | No | Public Supabase project URL. |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | No | Public anon key, safe for the browser. |
| `SUPABASE_SERVICE_ROLE_KEY` | No | **Server-only.** Never prefix with `NEXT_PUBLIC_`. Only imported from `src/lib/supabase/server.ts`, which is marked `server-only`. |
| `NEXT_PUBLIC_SITE_URL` | No (has a fallback) | Used for absolute URLs in metadata, OG, sitemap, robots. |
| `NEXT_PUBLIC_ANALYTICS_ENABLED` / `NEXT_PUBLIC_POSTHOG_KEY` | No | Analytics silently no-ops until these exist — see `src/lib/analytics.ts`. |

## Supabase setup (when you're ready to use it)

1. Create a Supabase project.
2. Run the migration in `supabase/migrations/0001_init.sql` (via the
   Supabase SQL editor, or the Supabase CLI: `supabase db push`).
3. Copy the project URL and anon key into `.env.local`.

The `events` table this migration creates is **not yet read by the
app** — Sprint 0 intentionally uses static seed data so the homepage
has zero external dependencies. Swapping `src/lib/events.ts` for a
Supabase query is future work, and the function signatures
(`getFeaturedEvent`, `getEventBySlug`) are already shaped so that swap
doesn't touch any component.

## Commands

```bash
npm run dev        # local development
npm run lint        # ESLint
npx tsc --noEmit    # TypeScript check
npm run build       # production build
npm run start        # run the production build locally
```

## Deployment

Deployed on Vercel. Connect this repository in the Vercel dashboard
(or `vercel --prod` from the CLI) — no project-specific build
configuration is required beyond the environment variables above (all
optional for Sprint 0).

## Sprint 0 scope

**Built:**
- Next.js + TypeScript + Tailwind foundation
- Design tokens (background, surface, text hierarchy, border, accent,
  success, warning) in `src/app/globals.css`
- Homepage: nav, hero ("Make your call."), one honestly-represented
  featured event (Miss Universe 2026, real public date/venue — no
  fabricated prediction counts or popularity stats), "how it works"
- `/events/[slug]` — minimal, honest "coming soon" page for the
  featured event, so the CTA has somewhere real to go
- SEO foundation: metadata, OpenGraph image, Twitter card, robots.txt,
  sitemap.xml, generated favicon
- Category-agnostic `Event` type and seed data
- Supabase client scaffolding (browser + server) and one migration for
  `events` — not yet wired to the UI
- Analytics seam (`src/lib/analytics.ts`) with three event names
  defined, no provider installed yet
- i18n foundation: all UI copy lives in `src/content/{en,es,pt}.ts`
  behind a shared `Dictionary` type. **Only English is live** — es/pt
  are translated and structurally ready, not yet routed.

**Deliberately deferred (not built):**
Authentication, login/signup, user profiles, the Prediction Builder,
drag-and-drop ranking, the scoring engine, leaderboards, AI
predictions, private leagues, friend battles, badges, achievements,
notifications, payments, admin dashboard, real-time infrastructure,
the full Prediction Card sharing system, and regional/community
analytics. These are later sprints.

## Next recommended step

Sprint 1: build the Prediction Builder (Top 10 ranking flow) for the
featured event, with local-only state first and persistence to
Supabase second.
