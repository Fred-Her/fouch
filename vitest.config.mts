import { defineConfig } from "vitest/config";

// Vitest doesn't read tsconfig "paths" automatically. Previous test
// files avoided this by only using relative imports; leaderboard.ts
// needs the project's standard "@/..." alias (src/lib/scoring), so
// this maps it the same way Next.js already does via tsconfig.json.
//
// environment: "jsdom" — Beta Hardening 0.1 added tests that touch
// `window`/`sessionStorage` (attribution.ts, analytics.ts). jsdom is a
// safe superset for the existing pure-Node tests too (scoring,
// leaderboard, community-comparison never reference window).
export default defineConfig({
  test: {
    environment: "jsdom",
  },
  resolve: {
    alias: {
      "@": new URL("./src", import.meta.url).pathname,
    },
  },
});