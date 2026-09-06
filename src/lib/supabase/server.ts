import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Server-only Supabase client. Imports "server-only" so any accidental
 * import from a Client Component fails the build loudly instead of
 * leaking a service-role key to the browser bundle.
 *
 * Prefers the service-role key (for trusted server-side reads/writes)
 * and falls back to the anon key if it isn't set. Returns null — never
 * throws — when neither is configured, since Sprint 0's homepage reads
 * from seed data (src/lib/events.ts), not from Postgres yet.
 */
export function getSupabaseServerClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !key) return null;

  return createClient(url, key, {
    auth: { persistSession: false },
  });
}
