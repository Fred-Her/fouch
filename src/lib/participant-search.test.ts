import { describe, it, expect } from "vitest";
import { matchesParticipantSearch, normalizeForSearch } from "./participant-search";

const p = (displayName: string, countryName: string) => ({ displayName, countryName });

describe("participant search ignores accents and case", () => {
  it("normalizes accents, case and special letters", () => {
    expect(normalizeForSearch("MARÍA")).toBe("maria");
    expect(normalizeForSearch("Curaçao")).toBe("curacao");
    expect(normalizeForSearch("Türkiye")).toBe("turkiye");
    expect(normalizeForSearch("Alara Erıç")).toBe("alara eric");
    expect(normalizeForSearch("Nguyễn")).toBe("nguyen");
    expect(normalizeForSearch("Đ")).toBe("d");
  });

  it("Spanish users typing without accents still find the country", () => {
    expect(matchesParticipantSearch(p("LUREN MÁRQUEZ", "Perú"), "peru")).toBe(true);
    expect(matchesParticipantSearch(p("MARÍA VARGAS", "México"), "mexico")).toBe(true);
    expect(matchesParticipantSearch(p("GABRIELA GONZÁLEZ", "Panamá"), "panama")).toBe(true);
    expect(matchesParticipantSearch(p("BIANTY GOMPERTS", "Curazao"), "curacao")).toBe(false); // different word, no false positive
  });

  it("finds by contestant name without accents", () => {
    expect(matchesParticipantSearch(p("MARÍA ADELINA CASTILLO", "Guatemala"), "maria")).toBe(true);
    expect(matchesParticipantSearch(p("DOMINGA LÓPEZ", "Chile"), "lopez")).toBe(true);
  });

  it("typing WITH accents works too", () => {
    expect(matchesParticipantSearch(p("LUREN MÁRQUEZ", "Perú"), "perú")).toBe(true);
    expect(matchesParticipantSearch(p("LUREN MÁRQUEZ", "Perú"), "MÁRQUEZ")).toBe(true);
  });

  it("an empty query matches everyone; a non-matching one matches nobody", () => {
    expect(matchesParticipantSearch(p("A", "B"), "")).toBe(true);
    expect(matchesParticipantSearch(p("A", "B"), "   ")).toBe(true);
    expect(matchesParticipantSearch(p("LUREN MÁRQUEZ", "Perú"), "zzz")).toBe(false);
  });

  it("substring search keeps working (country search behavior unchanged)", () => {
    expect(matchesParticipantSearch(p("CLARA VEGAS", "Venezuela"), "venez")).toBe(true);
    expect(matchesParticipantSearch(p("CLARA VEGAS", "Venezuela"), "veg")).toBe(true);
  });
});
