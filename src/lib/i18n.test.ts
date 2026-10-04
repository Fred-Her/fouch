import { describe, it, expect } from "vitest";
import { en } from "@/content/en";
import { es } from "@/content/es";
import { getDictionary, fmt } from "./i18n";

function flatten(value: unknown, prefix = ""): Record<string, string> {
  if (typeof value === "string") return { [prefix]: value };
  if (Array.isArray(value)) {
    return value.reduce<Record<string, string>>((acc, item, i) => ({ ...acc, ...flatten(item, `${prefix}[${i}]`) }), {});
  }
  if (value && typeof value === "object") {
    return Object.entries(value).reduce<Record<string, string>>(
      (acc, [k, v]) => ({ ...acc, ...flatten(v, prefix ? `${prefix}.${k}` : k) }),
      {},
    );
  }
  return {};
}
const placeholders = (s: string) => (s.match(/\{\w+\}/g) ?? []).sort();

describe("dictionaries — EN is the source of truth, ES must mirror it", () => {
  const flatEn = flatten(en);
  const flatEs = flatten(es);

  it("Spanish has exactly the same keys as English (no missing, no extra)", () => {
    expect(Object.keys(flatEs).sort()).toEqual(Object.keys(flatEn).sort());
  });

  it("no empty strings in either language", () => {
    for (const [key, value] of [...Object.entries(flatEn), ...Object.entries(flatEs)]) {
      expect(value.trim().length, key).toBeGreaterThan(0);
    }
  });

  it("every template keeps the same {placeholders} in both languages (a translation can't drop {n}/{name})", () => {
    for (const key of Object.keys(flatEn)) {
      const enPh = placeholders(flatEn[key] ?? "");
      const esPh = placeholders(flatEs[key] ?? "");
      // Spanish may legitimately omit {noun} where English needs the configurable entry noun.
      const required = enPh.filter((p) => p !== "{noun}");
      for (const p of required) expect(esPh, `${key} missing ${p}`).toContain(p);
    }
  });

  it("the FOUCH brand name is never translated away", () => {
    expect(es.meta.title).toContain("FOUCH");
    expect(es.footer.disclaimer).toContain("FOUCH");
    expect(es.closing.lineTwo).toContain("FOUCH");
  });

  it("approved Spanish brand copy", () => {
    expect(es.hero.headlineLines.join(" ")).toBe("Haz tu predicción.");
    expect(es.hero.subhead).toBe("Predice. Descubre qué piensa la comunidad. Demuestra que acertaste.");
    expect(es.closing.lineOne).toBe("Todos tienen una opinión.");
    expect(es.closing.lineTwo).toBe("FOUCH guarda el comprobante.");
  });

  it("English metadata matches the product brief", () => {
    expect(en.meta.title).toBe("FOUCH — Entertainment Predictions");
    expect(es.meta.title).toBe("FOUCH — Predicciones de entretenimiento");
  });
});

describe("getDictionary / fmt", () => {
  it("returns the right dictionary per locale", () => {
    expect(getDictionary("en")).toBe(en);
    expect(getDictionary("es")).toBe(es);
  });

  it("fills placeholders and leaves unknown ones intact", () => {
    expect(fmt("Top {n}", { n: 10 })).toBe("Top 10");
    expect(fmt("{a} and {b}", { a: "x" })).toBe("x and {b}");
  });

  it("builder/OTP strings behave identically in structure for both languages", () => {
    expect(fmt(en.builder.yourTop, { n: 10 })).toBe("Your Top 10");
    expect(fmt(es.builder.yourTop, { n: 10 })).toBe("Tu Top 10");
    expect(fmt(es.auth.enterCode, { email: "a@b.co" })).toContain("a@b.co");
  });
});
