# FOUCH — Fix: demo predictions no longer hold the "one prediction per event" slot.
# Symptom: saving a REAL Miss Universe prediction redirected to the user's old demo prediction.
# Run from the project root: powershell -ExecutionPolicy Bypass -File apply-demo-slot-fix.ps1
$failures = @()
$utf8 = New-Object System.Text.UTF8Encoding($false)

function Write-NewFile($path, $content) {
    $dir = Split-Path -LiteralPath $path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path (Get-Location) $path), $content, $utf8)
}

try {
    Write-NewFile "supabase\migrations\0012_demo_predictions_dont_hold_slot.sql" @'
-- FOUCH 0012 — demo predictions must not occupy the "one final prediction per verified identity
-- per event" slot.
--
-- Bug: Miss Universe 2026 launched as a demo event; the 8 demo predictions (data_status='demo',
-- some owned by a verified identity) kept holding the (event_slug, auth_user_id) slot. When their
-- owner saved a REAL prediction for the same event, the insert hit
-- predictions_one_final_per_identity and the app answered with the old demo prediction.
--
-- Fix: the uniqueness rule applies only to non-demo predictions. Nothing is deleted or edited;
-- existing rows are untouched. Safe to re-run.
begin;
drop index if exists predictions_one_final_per_identity;
create unique index predictions_one_final_per_identity
  on predictions (event_slug, auth_user_id)
  where auth_user_id is not null and is_final = true and data_status <> 'demo';
commit;
'@
    Write-Host "OK  migration 0012"
} catch { $failures += "migration: $_" }

try {
    Write-NewFile "src\lib\demo-predictions-dont-hold-slot.test.ts" @'
import { describe, expect, it, vi, beforeEach } from "vitest";

/**
 * Regression: a verified user's old DEMO prediction (Miss Universe 2026 launched as a demo
 * event) used to be treated as "your prediction for this event", so saving a real one sent them
 * to the demo page. Every identity/device lookup must now exclude data_status = 'demo'.
 */
const calls: Array<[string, string, unknown]> = [];

function chain(): unknown {
  const q: Record<string, unknown> = {};
  for (const m of ["select", "eq", "neq"]) {
    q[m] = (col: string, val: unknown) => {
      calls.push([m, col, val]);
      return q;
    };
  }
  q.maybeSingle = async () => ({ data: null, error: null });
  return q;
}

vi.mock("server-only", () => ({}));
vi.mock("@/lib/supabase/server", () => ({
  getSupabaseServerClient: () => ({ from: () => chain() }),
}));

import {
  getPredictionByAuthUserId,
  getPredictionByDeviceToken,
  getDeviceTokenIdentity,
} from "@/lib/predictions-db";

describe("demo predictions do not hold the event slot", () => {
  beforeEach(() => {
    calls.length = 0;
  });

  it.each([
    ["getPredictionByDeviceToken", () => getPredictionByDeviceToken("miss-universe-2026", "dev")],
    ["getPredictionByAuthUserId", () => getPredictionByAuthUserId("miss-universe-2026", "user")],
    ["getDeviceTokenIdentity", () => getDeviceTokenIdentity("miss-universe-2026", "dev")],
  ])("%s excludes data_status = demo", async (_name, run) => {
    await run();
    expect(calls).toContainEqual(["neq", "data_status", "demo"]);
  });
});
'@
    Write-Host "OK  regression test"
} catch { $failures += "test: $_" }

try {
    $path = Join-Path (Get-Location) "src\lib\predictions-db.ts"
    $text = [System.IO.File]::ReadAllText($path, $utf8)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $edits = @(
        @{ old = ".eq(`"device_token`", deviceToken)$nl    .maybeSingle();"; new = ".eq(`"device_token`", deviceToken)$nl    .neq(`"data_status`", `"demo`")$nl    .maybeSingle();" },
        @{ old = ".eq(`"auth_user_id`", authUserId)$nl    .eq(`"is_final`", true)$nl    .maybeSingle();"; new = ".eq(`"auth_user_id`", authUserId)$nl    .eq(`"is_final`", true)$nl    .neq(`"data_status`", `"demo`")$nl    .maybeSingle();" },
        @{ old = ".eq(`"device_token`", deviceToken)$nl    .eq(`"is_final`", true)$nl    .maybeSingle();"; new = ".eq(`"device_token`", deviceToken)$nl    .eq(`"is_final`", true)$nl    .neq(`"data_status`", `"demo`")$nl    .maybeSingle();" }
    )
    foreach ($e in $edits) {
        $count = ([regex]::Matches($text, [regex]::Escape($e.old))).Count
        if ($count -ne 1) { throw "expected exactly 1 match, found $count for: $($e.old)" }
        $text = $text.Replace($e.old, $e.new)
    }
    [System.IO.File]::WriteAllText($path, $text, $utf8)
    Write-Host "OK  predictions-db.ts (3 lookups exclude demo)"
} catch { $failures += "predictions-db.ts: $_" }

if ($failures.Count -gt 0) {
    Write-Host ""; Write-Host "FAILED:" -ForegroundColor Red
    $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}
Write-Host ""; Write-Host "Done. Next: npx tsc --noEmit ; npx vitest run ; then commit and push." -ForegroundColor Green
