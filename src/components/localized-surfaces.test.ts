import { describe, it, expect, vi } from "vitest";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { PredictionCardMarkup } from "@/components/prediction/PredictionCardMarkup";
import { ResultCardMarkup } from "@/components/scoring/ResultCardMarkup";
import { en } from "@/content/en";
import { es } from "@/content/es";
import type { Participant } from "@/types/participant";
import type { ScoreBreakdown } from "@/types/scoring";

const participants = (countryNames: string[]): Participant[] =>
  countryNames.map((countryName, i) => ({
    id: `id-${i}`,
    eventId: "evt",
    displayName: i === 0 ? "HANA DĚDKOVÁ" : `CONTESTANT ${i}`,
    countryCode: "XX",
    countryName,
    sortOrder: i,
    isActive: true,
  }));

const base = {
  eventName: "Miss Grand International 2026",
  nickname: "Perez",
  countryCode: "CV",
  isDemo: false,
};

describe("Prediction Card / Instagram Story markup — locale is presentation only", () => {
  it("English card (Story dimensions 1080x1920) keeps the existing copy", () => {
    const html = renderToStaticMarkup(
      createElement(PredictionCardMarkup, { width: 1080, height: 1920, siteDomain: "joinfouch.com", data: { ...base, rankedParticipants: participants(["Venezuela", "Philippines"]) } }),
    );
    expect(html).toContain("width:1080px;height:1920px");
    expect(html).toContain(en.share.cardHeadline);
    expect(html).toContain(en.share.cardFooter);
    expect(html).toContain("Perez · Cape Verde");
    expect(html).toContain("Philippines");
    expect(html).toContain("joinfouch.com");
  });

  it("Spanish card localizes headline, footer, predictor country and contestant country — never changes the contestant", () => {
    const html = renderToStaticMarkup(
      createElement(PredictionCardMarkup, { width: 1080, height: 1920, siteDomain: "joinfouch.com", data: { ...base, locale: "es", rankedParticipants: participants(["Venezuela", "Filipinas"]) } }),
    );
    expect(html).toContain("HAZ TU PREDICCIÓN.");
    expect(html).toContain("¿CUÁL ES EL TUYO?");
    expect(html).toContain("Perez · Cabo Verde");
    expect(html).toContain("Filipinas");
    expect(html).toContain("HANA DĚDKOVÁ");
    expect(html).toContain("Miss Grand International 2026");
    expect(html).toContain("joinfouch.com");
  });

  it("Post format (1080x1350) localizes the same way", () => {
    const html = renderToStaticMarkup(
      createElement(PredictionCardMarkup, { width: 1080, height: 1350, siteDomain: "joinfouch.com", data: { ...base, locale: "es", rankedParticipants: participants(["Venezuela"]) } }),
    );
    expect(html).toContain("width:1080px;height:1350px");
    expect(html).toContain(es.share.cardFooter);
  });

  it("no private identity information appears in a localized card", () => {
    const html = renderToStaticMarkup(
      createElement(PredictionCardMarkup, { width: 1080, height: 1920, siteDomain: "joinfouch.com", data: { ...base, locale: "es", rankedParticipants: participants(["Venezuela"]) } }),
    );
    expect(html).not.toMatch(/auth_user_id|device_token|@[a-z0-9-]+\./i);
    expect(html).not.toContain("vercel.app");
  });
});

describe("Result Card markup — localized", () => {
  const breakdown = {
    band: "GOOD",
    displayScore: 72,
    score: 72,
    components: {
      winner: { hit: true },
      podium: { hits: 2, total: 3 },
      top5: { hits: 3, total: 5 },
      top10: { hits: 6, total: 10 },
    },
  } as unknown as ScoreBreakdown;

  it("Spanish result card localizes band, labels and footer", () => {
    const html = renderToStaticMarkup(
      createElement(ResultCardMarkup, { width: 1080, height: 1920, siteDomain: "joinfouch.com", data: { eventName: "Miss Grand International 2026", nickname: "Perez", countryCode: "CV", isDemo: false, breakdown, percentile: 80, locale: "es" } as never }),
    );
    expect(html).toContain("BUENA PREDICCIÓN");
    expect(html).toContain("Ganadora");
    expect(html).toContain("Acertaste");
    expect(html).toContain("TOP 20%");
    expect(html).toContain("¿CREES QUE PUEDES SUPERARLO?");
    expect(html).toContain("Perez · Cabo Verde");
  });

  it("English result card is unchanged", () => {
    const html = renderToStaticMarkup(
      createElement(ResultCardMarkup, { width: 1080, height: 1920, siteDomain: "joinfouch.com", data: { eventName: "Miss Grand International 2026", nickname: null, countryCode: null, isDemo: false, breakdown, percentile: 80 } as never }),
    );
    expect(html).toContain("GOOD CALL");
    expect(html).toContain("THINK YOU COULD BEAT IT?");
    expect(html).toContain("TOP 20%");
  });
});

describe("root layout — html lang, canonical, hreflang, canonical domain", () => {
  async function loadLayout(locale: "en" | "es") {
    vi.resetModules();
    vi.doMock("@/lib/i18n-server", () => ({
      getI18n: async () => ({ locale, dict: locale === "es" ? es : en }),
      getLocale: async () => locale,
    }));
    vi.doMock("./../app/globals.css", () => ({}));
    return import("@/app/layout");
  }

  it("<html lang> follows the rendered locale", async () => {
    const enLayout = await loadLayout("en");
    const enEl = (await enLayout.default({ children: null })) as { props: { lang: string } };
    expect(enEl.props.lang).toBe("en");

    const esLayout = await loadLayout("es");
    const esEl = (await esLayout.default({ children: null })) as { props: { lang: string } };
    expect(esEl.props.lang).toBe("es");
  });

  it("metadata: localized title/description, per-locale canonical, hreflang en/es/x-default", async () => {
    const esLayout = await loadLayout("es");
    const md = await esLayout.generateMetadata();
    expect((md.title as { default: string }).default).toBe("FOUCH — Predicciones de entretenimiento");
    expect(md.description).toBe(es.meta.description);
    expect(md.alternates?.canonical).toBe("/es");
    expect(md.alternates?.languages).toEqual({ en: "/", es: "/es", "x-default": "/" });

    const enLayout = await loadLayout("en");
    const enMd = await enLayout.generateMetadata();
    expect((enMd.title as { default: string }).default).toBe("FOUCH — Entertainment Predictions");
    expect(enMd.alternates?.canonical).toBe("/");
  });

  it("OpenGraph URL stays on the canonical origin and never uses the legacy Vercel domain", async () => {
    const esLayout = await loadLayout("es");
    const md = await esLayout.generateMetadata();
    const og = md.openGraph as { url: string; locale: string };
    expect(og.url.endsWith("/es")).toBe(true);
    expect(og.locale).toBe("es_LA");
    expect(JSON.stringify(md)).not.toContain("fouch-tau.vercel.app");
  });
});
