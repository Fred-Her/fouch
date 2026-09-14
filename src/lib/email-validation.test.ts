import { describe, it, expect } from "vitest";
import { normalizeEmail, isValidEmail } from "./email-validation";

describe("normalizeEmail", () => {
  it("trims whitespace and lowercases", () => {
    expect(normalizeEmail("  Fred@Example.COM  ")).toBe("fred@example.com");
  });
});

describe("isValidEmail", () => {
  it.each([
    "fred@example.com",
    "fred.h@example.co",
    "fred+test@example.com",
  ])("accepts a well-formed address: %s", (email) => {
    expect(isValidEmail(email)).toBe(true);
  });

  it.each([
    "",
    "   ",
    "not-an-email",
    "missing-domain@",
    "@missing-local.com",
    "no-at-sign.com",
    "spaces in@email.com",
  ])("rejects a malformed address: %s", (email) => {
    expect(isValidEmail(email)).toBe(false);
  });

  it("rejects an address longer than 254 characters", () => {
    const long = `${"a".repeat(250)}@b.com`;
    expect(isValidEmail(long)).toBe(false);
  });

  it("is case-insensitive about validity (normalizes before checking)", () => {
    expect(isValidEmail("  FRED@EXAMPLE.COM  ")).toBe(true);
  });
});