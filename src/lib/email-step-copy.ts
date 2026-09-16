﻿/**
 * FOUCH 0.3A.1 — the entire copy decision for EmailStep's heading, in
 * one pure, unit-testable place. Extracted specifically so "create
 * flow says X" and "edit flow says Y" (brief §12 tests 7-8) can be
 * asserted directly, without needing a component-testing setup this
 * codebase doesn't have (no React Testing Library / jsdom-rendering
 * test infra exists for components here — every existing *.test.ts
 * file tests pure logic, not rendered output; this follows the same
 * pattern).
 *
 * "lock your prediction" must never appear here before the actual
 * event lock — a prediction stays editable until prediction_lock_at,
 * so "lock" is no longer the right verb for this step.
 */
export type EmailStepMode = "create" | "edit";

export function getEmailStepHeading(mode: EmailStepMode): string {
  if (mode === "edit") return "Verify your email to save your changes.";
  return "Verify your email to save your prediction.";
}
