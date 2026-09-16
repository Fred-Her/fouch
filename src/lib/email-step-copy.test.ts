﻿import { describe, it, expect } from "vitest";
import { getEmailStepHeading } from "./email-step-copy";

describe("getEmailStepHeading — FOUCH 0.3A.1 copy correction", () => {
  it("create flow says 'save your prediction', never 'lock your prediction'", () => {
    const heading = getEmailStepHeading("create");
    expect(heading).toBe("Verify your email to save your prediction.");
    expect(heading.toLowerCase()).not.toContain("lock your prediction");
  });

  it("edit flow says 'save your changes', never 'lock your prediction'", () => {
    const heading = getEmailStepHeading("edit");
    expect(heading).toBe("Verify your email to save your changes.");
    expect(heading.toLowerCase()).not.toContain("lock your prediction");
  });

  it("neither mode ever mentions locking, since a prediction stays editable until the event's actual lock instant", () => {
    expect(getEmailStepHeading("create").toLowerCase()).not.toContain("lock");
    expect(getEmailStepHeading("edit").toLowerCase()).not.toContain("lock");
  });
});
