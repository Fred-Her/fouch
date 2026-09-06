import { createClient, type SupabaseClient } from "@supabase/supabase-js";

let browserClient: SupabaseClient | null = null;

/**
 * Browser-safe Supabase client. Only ever uses the public URL + anon key
 * (both NEXT_PUBLIC_*, safe to ship to the client). Returns null instead
 * of throwing when env vars are absent, so Sprint 0 — which has no
 * Supabase-backed features yet — never crashes local dev or the build
 * because a project hasn't been provisioned.
 */
export function getSupabaseBrowserClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) return null;

  if (!browserClient) {
    browserClient = createClient(url, anonKey);
  }

  return browserClient;
}
