"use client";

import { createContext, useContext, type ReactNode } from "react";
import type { Dictionary } from "@/content/types";
import type { Locale } from "@/lib/locale";
import { setAnalyticsLocale } from "@/lib/analytics";

interface I18nValue {
  locale: Locale;
  dict: Dictionary;
}

const I18nContext = createContext<I18nValue | null>(null);

/** Receives the already-resolved locale + dictionary from the server
 * layout, so the first client render is already in the right language
 * (no English-then-Spanish flash). */
export function I18nProvider({ locale, dict, children }: { locale: Locale; dict: Dictionary } & { children: ReactNode }) {
  // Synchronous + idempotent on purpose: child effects (e.g. the landing_view
  // ViewTracker) run BEFORE a parent effect would, and every event needs the
  // locale from the very first capture.
  setAnalyticsLocale(locale);

  return <I18nContext.Provider value={{ locale, dict }}>{children}</I18nContext.Provider>;
}

export function useI18n(): I18nValue {
  const value = useContext(I18nContext);
  if (!value) throw new Error("useI18n must be used inside <I18nProvider>");
  return value;
}
