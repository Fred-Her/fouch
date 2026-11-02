# FOUCH — Fix: long country names on the share card (e.g. "República Democrática del Congo") were cut to a stray ">…".
# Now they wrap and stay fully readable. Run from the project root:
#   powershell -ExecutionPolicy Bypass -File apply-card-country-fix.ps1
$failures = @()
$utf8 = New-Object System.Text.UTF8Encoding($false)
try {
    $path = Join-Path (Get-Location) "src\components\prediction\PredictionCardMarkup.tsx"
    $text = [System.IO.File]::ReadAllText($path, $utf8)
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $edits = @(
        @{ old = "        maxWidth,$nl        overflow: `"hidden`",$nl        whiteSpace: `"nowrap`",$nl        textOverflow: `"ellipsis`",$nl      }}$nl    >$nl      {name}";
           new = "        maxWidth,$nl        textAlign: `"right`",$nl        lineHeight: 1.15,$nl        whiteSpace: `"normal`",$nl      }}$nl    >$nl      {name}" },
        @{ old = "<CountryBadge name={participant.countryName} fontSize={20} maxWidth={170} />";
           new = "<CountryBadge name={participant.countryName} fontSize={20} maxWidth={300} />" }
    )
    foreach ($e in $edits) {
        $count = ([regex]::Matches($text, [regex]::Escape($e.old))).Count
        if ($count -ne 1) { throw "expected exactly 1 match, found $count for: $($e.old)" }
        $text = $text.Replace($e.old, $e.new)
    }
    [System.IO.File]::WriteAllText($path, $text, $utf8)
    Write-Host "OK  PredictionCardMarkup.tsx"
} catch { $failures += "PredictionCardMarkup.tsx: $_" }
if ($failures.Count -gt 0) { Write-Host "FAILED:" -ForegroundColor Red; $failures | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }; exit 1 }
Write-Host "Done. Next: npx tsc --noEmit ; npx vitest run ; then commit and push." -ForegroundColor Green
