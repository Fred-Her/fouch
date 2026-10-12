/**
 * Predictions must never be taken against placeholder (demo) data.
 * A "demo" roster (the hardcoded Miss Universe development list) is
 * not a real lineup: until the official roster is loaded, the event
 * shows "Coming soon" and the server refuses to create predictions
 * for it. Local development can opt back in with
 * ALLOW_DEMO_PREDICTIONS=true (never set it in production).
 */
export function isDemoPredictionBlocked(
  participantDataStatus: "demo" | "verified",
  allowDemo: boolean = process.env.ALLOW_DEMO_PREDICTIONS === "true",
): boolean {
  return participantDataStatus === "demo" && !allowDemo;
}
