﻿﻿import { describe, it, expect } from "vitest";
import { validateSubmission } from "./prediction-validation";
import type { FouchEvent } from "@/types/event";
import type { Participant } from "@/types/participant";
import type { EventLockConfig } from "./prediction-lock-logic";

const EVENT: FouchEvent = {
  id: "seed-1",
  slug: "miss-universe-2026",
  name: "Miss Universe 2026",
  category: "pageant",
  status: "upcoming",
  eventDate: "2026-11-24",
  isFeatured: true,
};

function makeParticipant(id: string): Participant {
  return {
    id,
    eventId: EVENT.id,
    displayName: `Contestant ${id}`,
    countryCode: "CL",
    countryName: "Chile",
    sortOrder: 0,
    isActive: true,
  };
}

const PARTICIPANTS = Array.from({ length: 12 }, (_, i) => makeParticipant(`p${i + 1}`));
const TOP_10 = PARTICIPANTS.slice(0, 10).map((p) => p.id);

describe("validateSubmission — participant/ranking rules (unchanged by FOUCH 0.3A)", () => {
  it("accepts a valid, complete, unique Top 10", () => {
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(true);
  });

  it("rejects a ranking with the wrong count", () => {
    const result = validateSubmission({ participantIds: TOP_10.slice(0, 5) }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(false);
  });

  it("rejects duplicate participants", () => {
    const withDuplicate = [...TOP_10.slice(0, 9), TOP_10[0] as string];
    const result = validateSubmission({ participantIds: withDuplicate }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(false);
  });

  it("rejects an unknown participant id", () => {
    const withUnknown = [...TOP_10.slice(0, 9), "not-a-real-id"];
    const result = validateSubmission({ participantIds: withUnknown }, EVENT, PARTICIPANTS, 10, null);
    expect(result.valid).toBe(false);
  });
});

describe("validateSubmission — FOUCH 0.3A lock timing, driven entirely by the passed-in lockConfig + now", () => {
  const LOCK_AT = "2026-11-24T00:00:00Z";
  const LOCK_MS = Date.parse(LOCK_AT);

  it("allows a submission/edit one second before lock", () => {
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, lockConfig, LOCK_MS - 1000);
    expect(result.valid).toBe(true);
  });

  it("rejects a submission/edit exactly at the lock instant", () => {
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, lockConfig, LOCK_MS);
    expect(result.valid).toBe(false);
    expect(result.valid || result.error).toContain("locked");
  });

  it("rejects a submission/edit after the lock instant", () => {
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    const result = validateSubmission(
      { participantIds: TOP_10 },
      EVENT,
      PARTICIPANTS,
      10,
      lockConfig,
      LOCK_MS + 1000,
    );
    expect(result.valid).toBe(false);
  });

  it("with no lockConfig at all, never rejects for timing (matches pre-0.3A unrestricted behavior)", () => {
    const result = validateSubmission({ participantIds: TOP_10 }, EVENT, PARTICIPANTS, 10, null, LOCK_MS + 100000);
    expect(result.valid).toBe(true);
  });

  it("never reads timing from the `event` (FouchEvent) argument — that type no longer even has lock fields, so this test simply documents that validateSubmission's timing decision is fully determined by lockConfig+now", () => {
    const eventWithoutLockFields = { ...EVENT } as FouchEvent;
    expect("predictionLockAt" in eventWithoutLockFields).toBe(false);
    const lockConfig: EventLockConfig = { predictionOpenAt: null, predictionLockAt: LOCK_AT, timezone: null };
    const result = validateSubmission(
      { participantIds: TOP_10 },
      eventWithoutLockFields,
      PARTICIPANTS,
      10,
      lockConfig,
      LOCK_MS + 1,
    );
    expect(result.valid).toBe(false);
  });
});
