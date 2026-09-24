import { describe, it, expect } from "vitest";
import { isSelectableStatus } from "./participant-status";

describe("isSelectableStatus â€” the entire new-prediction selectability rule", () => {
  it("ACTIVE is selectable", () => {
    expect(isSelectableStatus("ACTIVE")).toBe(true);
  });

  it("PENDING is not selectable â€” identity not yet confirmed", () => {
    expect(isSelectableStatus("PENDING")).toBe(false);
  });

  it("WITHDRAWN is not selectable for a new prediction", () => {
    expect(isSelectableStatus("WITHDRAWN")).toBe(false);
  });

  it("REPLACED is not selectable for a new prediction", () => {
    expect(isSelectableStatus("REPLACED")).toBe(false);
  });

  it("only ACTIVE is ever true â€” a single boolean check the whole system shares", () => {
    const statuses: Array<Parameters<typeof isSelectableStatus>[0]> = [
      "ACTIVE",
      "PENDING",
      "WITHDRAWN",
      "REPLACED",
    ];
    const selectable = statuses.filter((s) => isSelectableStatus(s));
    expect(selectable).toEqual(["ACTIVE"]);
  });
});
