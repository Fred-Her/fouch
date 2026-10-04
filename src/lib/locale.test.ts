import { describe, it, expect } from "vitest";
import {
  detectLocaleFromAcceptLanguage,
  resolveRequestLocale,
  localizePath,
  stripLocalePrefix,
} from "./locale";

describe("detectLocaleFromAcceptLanguage — browser language, never geography", () => {
  it("defaults to English with no header", () => {
    expect(detectLocaleFromAcceptLanguage(null)).toBe("en");
    expect(detectLocaleFromAcceptLanguage("")).toBe("en");
  });

  it("maps every Spanish variant to Spanish", () => {
    for (const tag of ["es", "es-CL", "es-VE", "es-CO", "es-MX", "es-AR", "es-PE", "ES-es"]) {
      expect(detectLocaleFromAcceptLanguage(tag)).toBe("es");
    }
  });

  it("falls back to English for unsupported languages", () => {
    expect(detectLocaleFromAcceptLanguage("pt-BR")).toBe("en");
    expect(detectLocaleFromAcceptLanguage("fr-FR,de;q=0.8")).toBe("en");
    expect(detectLocaleFromAcceptLanguage("*")).toBe("en");
  });

  it("respects priority: English first stays English, Spanish first becomes Spanish", () => {
    expect(detectLocaleFromAcceptLanguage("en-US,es;q=0.5")).toBe("en");
    expect(detectLocaleFromAcceptLanguage("es-CL,es;q=0.9,en;q=0.8")).toBe("es");
    expect(detectLocaleFromAcceptLanguage("en;q=0.3,es;q=0.9")).toBe("es");
  });

  it("picks the best SUPPORTED language even when an unsupported one is listed first", () => {
    expect(detectLocaleFromAcceptLanguage("pt-BR,es;q=0.8")).toBe("es");
  });
});

describe("resolveRequestLocale — /es URL > cookie > browser > English", () => {
  it("default English rendering for a plain request", () => {
    expect(resolveRequestLocale({ pathname: "/" })).toEqual({ locale: "en", strippedPath: "/", fromPath: false });
  });

  it("Spanish browser preference -> Spanish on the unprefixed URL", () => {
    expect(resolveRequestLocale({ pathname: "/", acceptLanguage: "es-MX,es;q=0.9" }).locale).toBe("es");
  });

  it("unsupported browser language -> English fallback", () => {
    expect(resolveRequestLocale({ pathname: "/", acceptLanguage: "ja-JP" }).locale).toBe("en");
  });

  it("saved cookie beats browser language (manual ES -> EN switch persists)", () => {
    expect(resolveRequestLocale({ pathname: "/", cookieValue: "en", acceptLanguage: "es-CL" }).locale).toBe("en");
  });

  it("saved cookie beats browser language (manual EN -> ES switch persists)", () => {
    expect(resolveRequestLocale({ pathname: "/", cookieValue: "es", acceptLanguage: "en-US" }).locale).toBe("es");
  });

  it("an invalid cookie value is ignored", () => {
    expect(resolveRequestLocale({ pathname: "/", cookieValue: "fr", acceptLanguage: "es" }).locale).toBe("es");
  });

  it("explicit /es URL wins over cookie and strips the prefix so the SAME route serves it", () => {
    const r = resolveRequestLocale({ pathname: "/es/p/abc123", cookieValue: "en", acceptLanguage: "en" });
    expect(r).toEqual({ locale: "es", strippedPath: "/p/abc123", fromPath: true });
  });

  it("/p/[id] and /es/p/[id] resolve to the identical underlying path (same prediction)", () => {
    const en = resolveRequestLocale({ pathname: "/p/abc123" });
    const es = resolveRequestLocale({ pathname: "/es/p/abc123" });
    expect(es.strippedPath).toBe(en.strippedPath);
  });

  it("/es resolves to the root route", () => {
    expect(resolveRequestLocale({ pathname: "/es" }).strippedPath).toBe("/");
  });

  it("does not treat unrelated paths that merely start with 'es' as Spanish", () => {
    expect(resolveRequestLocale({ pathname: "/estimates", acceptLanguage: "en" })).toMatchObject({
      locale: "en",
      strippedPath: "/estimates",
      fromPath: false,
    });
  });
});

describe("localizePath / stripLocalePrefix", () => {
  it("English stays unprefixed, Spanish gets /es", () => {
    expect(localizePath("/", "en")).toBe("/");
    expect(localizePath("/", "es")).toBe("/es");
    expect(localizePath("/p/abc", "en")).toBe("/p/abc");
    expect(localizePath("/p/abc", "es")).toBe("/es/p/abc");
  });

  it("round-trips", () => {
    expect(stripLocalePrefix("/es/events/x")).toBe("/events/x");
    expect(stripLocalePrefix("/es")).toBe("/");
    expect(stripLocalePrefix("/events/x")).toBe("/events/x");
  });
});
