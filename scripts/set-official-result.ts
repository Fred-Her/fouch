/**
 * Enters (or replaces) the official result for an event, validated
 * before it's ever written. This is the "smallest practical way to
 * enter a result" per research/Sprint 4 Â§23 â€” no admin UI, run by
 * hand from a trusted machine with the service-role key available.
 *
 * Usage:
 *   npx tsx scripts/set-official-result.ts
 *
 * To use a different result, edit RESULT below and rerun â€” the script
 * validates every participant ID before writing anything.
 *
 * SAFETY: this uses the service-role key directly, bypassing RLS.
 * Never run this against production without reviewing RESULT first.
 *
 * NOTE: this file builds its own Supabase client instead of importing
 * src/lib/supabase/server.ts, which is intentionally marked
 * "server-only" so it can never be imported from a Client Component
 * inside the Next.js app. That guard throws when run outside Next's
 * own build pipeline (e.g. via plain `tsx`), which is exactly this
 * script's situation â€” so this file deliberately does not import it.
 */
import { createClient } from "@supabase/supabase-js";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { getEventBySlug } from "../src/lib/events";
import { getParticipantsForEvent } from "../src/lib/participants";
import { validateOfficialResult } from "../src/lib/official-result-validation";
import type { OfficialResultInput } from "../src/types/scoring";

// Unlike Next.js, plain `tsx` does not load .env.local automatically â€”
// so this script loads it itself, with no new dependency required.
function loadEnvLocal() {
  const path = resolve(process.cwd(), ".env.local");
  if (!existsSync(path)) return;
  for (const line of readFileSync(path, "utf-8").split("\n")) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const eq = trimmed.indexOf("=");
    if (eq === -1) continue;
    const key = trimmed.slice(0, eq).trim();
    const value = trimmed.slice(eq + 1).trim();
    if (!(key in process.env)) process.env[key] = value;
  }
}
loadEnvLocal();

const EVENT_SLUG = "miss-universe-2026";

/**
 * FICTIONAL / DEMO RESULT â€” Miss Universe 2026 has not happened yet.
 * This is for development/testing only, matching the demo participant
 * dataset. Never presented as an official result in the product (the
 * public page and Result Card both read data_status and show a "Demo
 * result" label whenever this is used â€” see FouchScore.tsx).
 */
const DEMO_RESULT: OfficialResultInput = {
  winner: "demo-co", // Colombia
  firstRunnerUp: "demo-ve", // Venezuela
  secondRunnerUp: "demo-th", // Thailand
  top5Extras: ["demo-ph", "demo-pr"], // Philippines, Puerto Rico
  top10Extras: ["demo-in", "demo-mx", "demo-br", "demo-cl", "demo-es"], // India, Mexico, Brazil, Chile, Spain
};

async function main() {
  const event = getEventBySlug(EVENT_SLUG);
  if (!event) {
    console.error(`Event not found: ${EVENT_SLUG}`);
    process.exit(1);
  }

  const participantData = await getParticipantsForEvent(EVENT_SLUG);
  if (!participantData) {
    console.error(`No participants configured for: ${EVENT_SLUG}`);
    process.exit(1);
  }

  const validation = validateOfficialResult(DEMO_RESULT, participantData.participants);
  if (!validation.valid) {
    console.error(`Result rejected: ${validation.error}`);
    process.exit(1);
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    console.error(
      "Supabase isn't configured (missing NEXT_PUBLIC_SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in .env.local).",
    );
    process.exit(1);
  }
  const supabase = createClient(url, key);

  const { error } = await supabase.from("event_results").upsert(
    {
      event_slug: EVENT_SLUG,
      data_status: participantData.status, // "demo" today â€” never mixed with "verified"
      winner_participant_id: DEMO_RESULT.winner,
      first_runner_up_participant_id: DEMO_RESULT.firstRunnerUp,
      second_runner_up_participant_id: DEMO_RESULT.secondRunnerUp,
      top5_extra_participant_ids: DEMO_RESULT.top5Extras,
      top10_extra_participant_ids: DEMO_RESULT.top10Extras,
      source_note: "Development/demo fixture â€” not an official result.",
      updated_at: new Date().toISOString(),
    },
    { onConflict: "event_slug,data_status" },
  );

  if (error) {
    console.error("Failed to write result:", error.message);
    process.exit(1);
  }

  console.log(`OK: official result set for ${EVENT_SLUG} (data_status=${participantData.status}).`);
}

main();