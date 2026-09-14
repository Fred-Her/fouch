import "server-only";
import { createClient, type SupabaseClient } from "@supabase/supabase-js";

/**
 * Server-only, STATELESS Supabase Auth client for the email OTP flow.
 * Deliberately separate from getSupabaseServerClient() (which prefers
 * the service-role key): signInWithOtp/verifyOtp are genuine end-user
 * operations, exactly what an anonymous visitor's own browser would
 * call — using service-role for these would be semantically wrong,
 * even though it happens to run server-side here.
 *
 * `persistSession: false` because this project deliberately doesn't
 * build cookie/session infrastructure (no @supabase/ssr, no
 * middleware) — see FOUCH_IDENTITY_ARCHITECTURE.md's "Session
 * strategy". Each call gets a fresh, stateless client; the one piece
 * of session data that matters (the access token, for retrying a
 * failed insert without a new OTP) is threaded through explicitly by
 * the calling server action, not persisted implicitly.
 */
export function getSupabaseAuthClient(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  if (!url || !anonKey) return null;

  return createClient(url, anonKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}