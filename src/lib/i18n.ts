import { en } from "@/content/en";
import { es } from "@/content/es";
import type { Dictionary } from "@/content/types";
import type { Locale } from "@/lib/locale";

/** Pure dictionary lookup (edge/client/server safe). English is the
 * fallback dictionary. */
export function getDictionary(locale: Locale): Dictionary {
  return locale === "es" ? es : en;
}

/** Fills {placeholders}: fmt("Top {n}", { n: 10 }) -> "Top 10". */
export function fmt(template: string, vars: Record<string, string | number>): string {
  return template.replace(/\{(\w+)\}/g, (match, key: string) =>
    key in vars ? String(vars[key]) : match,
  );
}
