import { describe, it, expect } from "vitest";
import { translateServerError } from "./server-error-i18n";

describe("translateServerError — display-time localization of server messages", () => {
  it("English passes through untouched", () => {
    expect(translateServerError("That code expired.", "en")).toBe("That code expired.");
  });

  it("translates known server errors to Spanish", () => {
    expect(translateServerError("That code expired.", "es")).toBe("Ese código expiró.");
    expect(translateServerError("Predictions for this event are locked.", "es")).toBe(
      "Las predicciones de este evento están cerradas.",
    );
    expect(translateServerError("We couldn't send a code — try again in a moment.", "es")).toContain("No pudimos enviar");
  });

  it("translates parameterized messages", () => {
    expect(translateServerError("Exactly 10 contestants are required.", "es")).toBe(
      "Se requieren exactamente 10 participantes.",
    );
    expect(translateServerError("Nickname must be 24 characters or fewer.", "es")).toContain("24");
  });

  it("unknown messages fall back to the original text, never blank or a raw error", () => {
    expect(translateServerError("Some brand new error", "es")).toBe("Some brand new error");
  });

  it("null stays null", () => {
    expect(translateServerError(null, "es")).toBeNull();
  });
});
