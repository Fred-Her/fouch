import { describe, it, expect } from "vitest";
import { classifyInsertConflict, isDeviceIdentityMismatch } from "./insert-conflict";

describe("classifyInsertConflict — using the exact Postgres messages confirmed in Phase A", () => {
  it("classifies a public_id collision", () => {
    expect(
      classifyInsertConflict('duplicate key value violates unique constraint "predictions_public_id_key"'),
    ).toBe("public_id");
  });

  it("classifies an identity (auth_user_id) collision", () => {
    expect(
      classifyInsertConflict(
        'duplicate key value violates unique constraint "predictions_one_final_per_identity"',
      ),
    ).toBe("identity");
  });

  it("classifies a device_token collision", () => {
    expect(
      classifyInsertConflict('duplicate key value violates unique constraint "predictions_event_device_unique"'),
    ).toBe("device");
  });

  it("falls back to unknown for an unrecognized message", () => {
    expect(classifyInsertConflict("some other database error")).toBe("unknown");
  });
});

describe("isDeviceIdentityMismatch — the soft, non-blocking signal", () => {
  it("is false when there is no existing prediction on this device", () => {
    expect(isDeviceIdentityMismatch(null, { deviceToken: "d1", authUserId: "alice" })).toBe(false);
  });

  it("is false when the device tokens differ (not the same physical device)", () => {
    expect(
      isDeviceIdentityMismatch(
        { deviceToken: "d1", authUserId: "alice" },
        { deviceToken: "d2", authUserId: "bob" },
      ),
    ).toBe(false);
  });

  it("is true for the Person A / Person B case: same device, different verified identities", () => {
    expect(
      isDeviceIdentityMismatch(
        { deviceToken: "shared-laptop", authUserId: "alice" },
        { deviceToken: "shared-laptop", authUserId: "bob" },
      ),
    ).toBe(true);
  });

  it("is false for the SAME identity on the same device (that's the hard rule's job, not this signal)", () => {
    expect(
      isDeviceIdentityMismatch(
        { deviceToken: "shared-laptop", authUserId: "alice" },
        { deviceToken: "shared-laptop", authUserId: "alice" },
      ),
    ).toBe(false);
  });

  it("is false when either side is anonymous (null auth_user_id) — never flags legacy rows", () => {
    expect(
      isDeviceIdentityMismatch(
        { deviceToken: "shared-laptop", authUserId: null },
        { deviceToken: "shared-laptop", authUserId: "bob" },
      ),
    ).toBe(false);
    expect(
      isDeviceIdentityMismatch(
        { deviceToken: "shared-laptop", authUserId: "alice" },
        { deviceToken: "shared-laptop", authUserId: null },
      ),
    ).toBe(false);
  });
});