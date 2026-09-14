/**
 * Beta Hardening 0.2 — Phase B manual test harness.
 *
 * Proves Supabase Email OTP works, end to end, with a REAL email
 * inbox. Deliberately NOT wired into the FOUCH app — this never
 * touches the `predictions` table, never runs during a normal user
 * session, and is not imported by any product code.
 *
 * Usage:
 *   npx tsx scripts/test-otp-auth.ts you@example.com
 *
 * Uses the PUBLIC anon key on purpose — signInWithOtp/verifyOtp are
 * genuine end-user operations, exactly what an anonymous visitor's
 * browser would call. This script does not need (and does not use)
 * the service-role key at all.
 */
import { createClient } from "@supabase/supabase-js";
import { createInterface } from "node:readline/promises";
import { readFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";

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

async function main() {
  const email = process.argv[2];
  if (!email) {
    console.error("Usage: npx tsx scripts/test-otp-auth.ts you@example.com");
    process.exit(1);
  }

  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url || !anonKey) {
    console.error("Missing NEXT_PUBLIC_SUPABASE_URL / NEXT_PUBLIC_SUPABASE_ANON_KEY in .env.local");
    process.exit(1);
  }

  const supabase = createClient(url, anonKey);

  console.log(`Requesting an OTP for ${email} ...`);
  const { error: sendError } = await supabase.auth.signInWithOtp({
    email,
    options: { shouldCreateUser: true },
  });

  if (sendError) {
    console.error("FAILED to request OTP:", sendError.message);
    process.exit(1);
  }
  console.log("OK: OTP requested. Check the inbox for a numeric code (not a link).");
  console.log("If the email contains a clickable link instead of a 6-digit code,");
  console.log("the Magic Link template has not been edited yet — see Phase B doc, step 'Email template'.");

  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const code = (await rl.question("Enter the 6-digit code from the email: ")).trim();
  rl.close();

  console.log("Verifying code ...");
  const { data, error: verifyError } = await supabase.auth.verifyOtp({
    email,
    token: code,
    type: "email",
  });

  if (verifyError) {
    console.error("FAILED to verify OTP:", verifyError.message);
    process.exit(1);
  }

  console.log("OK: verified.");
  console.log("auth_user_id (UUID):", data.user?.id);
  console.log("Session present:", Boolean(data.session));
  console.log("");
  console.log("Run this script again with the SAME email to confirm the SAME");
  console.log("auth_user_id is returned (Test D from the Phase B brief).");
  console.log("");
  console.log("No row was written to the predictions table by this script.");
}

main();