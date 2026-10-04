import { describe, it, expect } from "vitest";
import { localizePath, stripLocalePrefix, resolveRequestLocale } from "./locale";

/** The exact composition LanguageSwitcher performs on click. */
const switchTo = (currentPath: string, target: "en" | "es") => localizePath(stripLocalePrefix(currentPath), target);

describe("manual language switch", () => {
  it("EN -> ES keeps the same logical page under /es", () => {
    expect(switchTo("/", "es")).toBe("/es");
    expect(switchTo("/predict/miss-grand-international-2026", "es")).toBe("/es/predict/miss-grand-international-2026");
    expect(switchTo("/p/abc123", "es")).toBe("/es/p/abc123");
  });

  it("ES -> EN returns to the unprefixed URL", () => {
    expect(switchTo("/es", "en")).toBe("/");
    expect(switchTo("/es/p/abc123", "en")).toBe("/p/abc123");
  });

  it("switching language never alters the prediction id in the URL", () => {
    expect(stripLocalePrefix(switchTo("/p/vksp2sfqu", "es"))).toBe("/p/vksp2sfqu");
  });

  it("the saved cookie keeps the choice on later unprefixed visits (persistence)", () => {
    expect(resolveRequestLocale({ pathname: "/predict/x", cookieValue: "es", acceptLanguage: "en-US" }).locale).toBe("es");
    expect(resolveRequestLocale({ pathname: "/predict/x", cookieValue: "en", acceptLanguage: "es-CL" }).locale).toBe("en");
  });
});
