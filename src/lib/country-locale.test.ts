import { describe, it, expect } from "vitest";
import { PREDICTOR_COUNTRIES, getLocalizedCountryName, getPredictorCountryName } from "./countries";
import { localizeParticipant } from "./participant-locale";
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
