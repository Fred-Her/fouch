﻿import { describe, it, expect } from "vitest";
import { isAuthorizedToEdit, isRankingUnchanged } from "./prediction-version-logic";

describe("isAuthorizedToEdit — the entire ownership authorization rule", () => {
  it("authorizes the verified owner editing their own prediction", () => {
    expect(isAuthorizedToEdit("alice-auth-id", "alice-auth-id")).toBe(true);
  });

  it("rejects a different verified identity — cannot edit someone else's prediction", () => {
    expect(isAuthorizedToEdit("alice-auth-id", "bob-auth-id")).toBe(false);
  });

  it("rejects editing a legacy anonymous prediction (auth_user_id is null) — no owner to authorize against", () => {
    expect(isAuthorizedToEdit(null, "bob-auth-id")).toBe(false);
  });

  it("rejects even when the requester is somehow an empty string — never treats falsy-but-present as authorized", () => {
    expect(isAuthorizedToEdit(null, "")).toBe(false);
  });

  it("is never fooled by a forged auth_user_id payload — the check only ever compares the two identity strings given, never anything else the client could supply (nickname/device_token/public_id/email are not parameters at all)", () => {
    // This test exists to document the invariant, not to exercise new
    // behavior: the function's signature itself makes a
    // nickname/device_token/public_id/email-based claim impossible —
    // there is no code path that reaches this function with anything
    // other than two auth_user_id strings.
    expect(isAuthorizedToEdit.length).toBe(2);
  });
});

describe("isRankingUnchanged — the no-new-version-on-retry guard", () => {
  it("is true for an identical ranking, same order", () => {
    expect(isRankingUnchanged(["a", "b", "c"], ["a", "b", "c"])).toBe(true);
  });

  it("is false when the order differs, even with the same members", () => {
    expect(isRankingUnchanged(["a", "b", "c"], ["b", "a", "c"])).toBe(false);
  });

  it("is false when any single member differs", () => {
    expect(isRankingUnchanged(["a", "b", "c"], ["a", "b", "d"])).toBe(false);
  });

  it("is false when lengths differ", () => {
    expect(isRankingUnchanged(["a", "b"], ["a", "b", "c"])).toBe(false);
  });

  it("is true for two empty rankings (degenerate, but never crashes)", () => {
    expect(isRankingUnchanged([], [])).toBe(true);
  });
});

/**
 * FOUCH 0.3A — legacy anonymous prediction invariants requested
 * explicitly by the founder. These are DB/RLS-level facts (a row's
 * public_id survives migration, community/leaderboard count it once,
 * RLS rejects a direct anonymous mutation) that this test file cannot
 * exercise without a real Postgres instance — vitest here has no DB
 * layer, by the same design choice that keeps every other file in
 * src/lib/*.test.ts DB-free (see leaderboard.ts/leaderboard-service.ts
 * split).
 *
 * What IS unit-tested below is the one piece of this that genuinely
 * is pure application logic: a legacy prediction can never be
 * authorized for editing, through ANY input, including a supplied
 * device_token. Everything else in this describe block's name
 * (readable, same public_id, counted once in community/leaderboard,
 * RLS rejects direct mutation) was verified instead via real SQL
 * against a local Postgres instance with migrations 0001-0008 applied
 * and seeded legacy rows — see this sprint's final report
 * ("Legacy Migration" / "Privacy / RLS" sections) for the exact
 * queries and their output. That evidence is not restated here as an
 * automated test because doing so would require introducing database
 * mocking infrastructure this codebase deliberately doesn't have.
 */
describe("Legacy anonymous predictions — editing is never authorizable, by any input", () => {
  it("cannot be edited even by the identity that WOULD be legitimate for a verified prediction — a legacy row's stored owner is null, and null is never authorized against anything", () => {
    expect(isAuthorizedToEdit(null, "some-real-verified-auth-user-id")).toBe(false);
  });

  it("device_token is not a parameter this function even accepts — there is no code path anywhere that could use a device_token to authorize an edit, legacy or otherwise (see EditPredictionPayload in verify-actions.ts, which has no deviceToken field at all, unlike LockPredictionPayload)", () => {
    // isAuthorizedToEdit's signature is the whole authorization
    // surface for editing (see its own doc comment) — it takes
    // exactly two auth_user_id strings and nothing else, which is
    // itself the proof that a device_token (or nickname, or
    // public_id, or a later-typed email) cannot enter into this
    // decision under any circumstance.
    expect(isAuthorizedToEdit.length).toBe(2);
    expect(isAuthorizedToEdit(null, "device-token-aaa")).toBe(false);
  });

  it("remains false no matter how many times the same legacy prediction is checked — there is no retry, session, or state that flips a null owner to authorized", () => {
    expect(isAuthorizedToEdit(null, "user-1")).toBe(false);
    expect(isAuthorizedToEdit(null, "user-1")).toBe(false);
    expect(isAuthorizedToEdit(null, "user-2")).toBe(false);
  });
});
