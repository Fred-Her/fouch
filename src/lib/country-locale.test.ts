import { describe, it, expect } from "vitest";
import { PREDICTOR_COUNTRIES, getLocalizedCountryName, getPredictorCountryName } from "./countries";
import { localizeParticipant, sortParticipantsByCountry } from "./participant-locale";
import type { Participant } from "@/types/participant";

describe("country names render in the viewer's locale", () => {
  it("English returns the existing English name untouched (incl. roster names Intl would rename)", () => {
    expect(getLocalizedCountryName("PH", "Philippines", "en")).toBe("Philippines");
    expect(getLocalizedCountryName("CZ", "Czech Republic", "en")).toBe("Czech Republic");
  });

  it("Spanish uses natural Spanish names", () => {
    expect(getLocalizedCountryName("PH", "Philippines", "es")).toBe("Filipinas");
    expect(getLocalizedCountryName("US", "United States", "es")).toBe("Estados Unidos");
    expect(getLocalizedCountryName("VE", "Venezuela", "es")).toBe("Venezuela");
    expect(getLocalizedCountryName("CL", "Chile", "es")).toBe("Chile");
  });

  it("regions with an awkward CLDR long name use the natural short form in Spanish, nothing else changes", () => {
    expect(getLocalizedCountryName("HK", "Hong Kong", "es")).toBe("Hong Kong");
    expect(getLocalizedCountryName("PS", "Palestine", "es")).toBe("Palestina");
    expect(getLocalizedCountryName("US", "United States", "es")).toBe("Estados Unidos");
  });

  it("never exposes a raw ISO code — falls back to the English name when Intl has nothing", () => {
    const xk = getLocalizedCountryName("XK", "Kosovo", "es");
    expect(xk).not.toBe("XK");
    expect(xk.length).toBeGreaterThan(2);
  });

  it("every selectable predictor country resolves to a real name in Spanish (not a bare code)", () => {
    for (const country of PREDICTOR_COUNTRIES) {
      const name = getLocalizedCountryName(country.code, country.name, "es");
      expect(name, country.code).not.toBe(country.code);
      expect(name.length, country.code).toBeGreaterThan(2);
    }
  });

  it("predictor country lookup is locale-aware and still null-safe", () => {
    expect(getPredictorCountryName("PH", "es")).toBe("Filipinas");
    expect(getPredictorCountryName("PH")).toBe("Philippines");
    expect(getPredictorCountryName(null, "es")).toBeNull();
    expect(getPredictorCountryName("ZZ", "es")).toBeNull();
  });
});

describe("localizeParticipant — presentation only, identity untouched", () => {
  const participant: Participant = {
    id: "uuid-1",
    eventId: "evt",
    displayName: "HANA DĚDKOVÁ",
    countryCode: "PH",
    countryName: "Philippines",
    sortOrder: 4,
    isActive: true,
  };

  it("only countryName changes; id, official name, code, status, order are identical", () => {
    const es = localizeParticipant(participant, "es");
    expect(es.countryName).toBe("Filipinas");
    expect({ ...es, countryName: "x" }).toEqual({ ...participant, countryName: "x" });
    expect(es.displayName).toBe("HANA DĚDKOVÁ");
  });

  it("English returns the very same object", () => {
    expect(localizeParticipant(participant, "en")).toBe(participant);
  });
});

describe("sortParticipantsByCountry — new delegates land in their alphabetical place", () => {
  const make = (id: string, name: string, code: string, country: string): Participant => ({
    id, eventId: "e", displayName: name, countryCode: code, countryName: country, sortOrder: 0, isActive: true,
  });
  const roster = [
    make("1", "VENEZUELAN", "VE", "Venezuela"),
    make("2", "COLOMBIAN", "CO", "Colombia"),
    make("3", "ARGENTINE", "AR", "Argentina"),
    make("4", "HONG KONG", "HK", "Hong Kong"),
  ];

  it("sorts by country name, so a delegate added later (Colombia, Hong Kong) is not appended at the end", () => {
    expect(sortParticipantsByCountry(roster, "en").map((x) => x.countryName)).toEqual([
      "Argentina", "Colombia", "Hong Kong", "Venezuela",
    ]);
  });

  it("sorts by the country name in the viewer's language", () => {
    const es = roster.map((x) => localizeParticipant(x, "es"));
    expect(sortParticipantsByCountry(es, "es").map((x) => x.countryName)).toEqual([
      "Argentina", "Colombia", "Hong Kong", "Venezuela",
    ]);
  });

  it("accents don't break the order (Perú sorts with P, not after Z)", () => {
    const list = [make("1", "A", "ZA", "Zambia"), make("2", "B", "PE", "Perú"), make("3", "C", "PA", "Panamá")];
    expect(sortParticipantsByCountry(list, "es").map((x) => x.countryName)).toEqual(["Panamá", "Perú", "Zambia"]);
  });

  it("is stable on ties (same country -> contestant name) and never mutates its input", () => {
    const tie = [make("1", "BETA", "XX", "Same"), make("2", "ALPHA", "XX", "Same")];
    const before = JSON.stringify(tie);
    expect(sortParticipantsByCountry(tie, "en").map((x) => x.displayName)).toEqual(["ALPHA", "BETA"]);
    expect(JSON.stringify(tie)).toBe(before);
  });
});
