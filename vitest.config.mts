import { defineConfig } from "vitest/config";
import { resolve } from "node:path";

// Vitest doesn't read tsconfig "paths" automatically. Previous test
// files avoided this by only using relative imports; leaderboard.ts
// needs the project's standard "@/..." alias (src/lib/scoring), so
// this maps it the same way Next.js already does via tsconfig.json.
export default defineConfig({
  resolve: {
    alias: {
      "@": resolve(__dirname, "./src"),
    },
  },
});