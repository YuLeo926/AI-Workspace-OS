Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$CheckHandoff = Join-Path $RepoRoot "scripts\check-handoff-size.ps1"
$tempRoot = New-TestDirectory -Prefix "ai-workspace-os-handoff-tests-"

try {
    Assert-True (Test-Path -LiteralPath $CheckHandoff) "Missing script: $CheckHandoff"

    $validContent = @"
# Agent Handoff

Updated At: 2026-08-12T08:00:00Z
Review By: 2026-08-19T08:00:00Z

## Current Role
worker

## Workspace Boundary
business/

## Required Reading Order
index, week, handoff

## Hard Constraints
Do not cross ownership boundaries.

## Current State
Ready.

## Next Step
Draft the next file.

## Pending Decisions
None.
"@

    $validHandoff = Join-Path $tempRoot "valid-handoff.md"
    [IO.File]::WriteAllText($validHandoff, $validContent, (New-Object Text.UTF8Encoding($false)))

    $validHandoffResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $validHandoff,
        "-ReferenceTime", "2026-08-13T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $validHandoffResult 0 "Valid handoff"
    $validHandoffSummary = ($validHandoffResult.Output | Out-String | ConvertFrom-Json)
    Assert-True ($validHandoffSummary.ok -eq $true) "Valid handoff should report ok=true"
    Assert-Equal @($validHandoffSummary.errors).Count 0 "Valid handoff should have no errors"
    Assert-Equal @($validHandoffSummary.warnings).Count 0 "Valid handoff should have no warnings"
    Assert-Equal $validHandoffSummary.updatedAt "2026-08-12T08:00:00Z" "Valid handoff should report Updated At"
    Assert-Equal $validHandoffSummary.reviewBy "2026-08-19T08:00:00Z" "Valid handoff should report Review By"

    $offsetHandoff = Join-Path $tempRoot "offset-handoff.md"
    [IO.File]::WriteAllText(
        $offsetHandoff,
        ($validContent.Replace("2026-08-12T08:00:00Z", "2026-08-12T16:00:00+08:00").Replace("2026-08-19T08:00:00Z", "2026-08-19T16:00:00+08:00")),
        (New-Object Text.UTF8Encoding($false))
    )
    $offsetResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $offsetHandoff,
        "-ReferenceTime", "2026-08-13T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $offsetResult 0 "Numeric-offset timestamps"
    $offsetSummary = ($offsetResult.Output | Out-String | ConvertFrom-Json)
    Assert-Equal @($offsetSummary.errors).Count 0 "Numeric-offset timestamps should be valid"

    $missingUpdatedHandoff = Join-Path $tempRoot "missing-updated-handoff.md"
    [IO.File]::WriteAllText(
        $missingUpdatedHandoff,
        ($validContent.Replace("Updated At: 2026-08-12T08:00:00Z`n", "")),
        (New-Object Text.UTF8Encoding($false))
    )
    $missingUpdatedResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $missingUpdatedHandoff,
        "-ReferenceTime", "2026-08-13T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $missingUpdatedResult 1 "Missing Updated At"
    $missingUpdatedSummary = ($missingUpdatedResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($missingUpdatedSummary.errors.code) -contains "missing_updated_at") "Missing Updated At error missing"

    $missingReviewHandoff = Join-Path $tempRoot "missing-review-handoff.md"
    [IO.File]::WriteAllText(
        $missingReviewHandoff,
        ($validContent.Replace("Review By: 2026-08-19T08:00:00Z`n", "")),
        (New-Object Text.UTF8Encoding($false))
    )
    $missingReviewResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $missingReviewHandoff,
        "-ReferenceTime", "2026-08-13T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $missingReviewResult 1 "Missing Review By"
    $missingReviewSummary = ($missingReviewResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($missingReviewSummary.errors.code) -contains "missing_review_by") "Missing Review By error missing"

    $duplicateHandoff = Join-Path $tempRoot "duplicate-review-field-handoff.md"
    [IO.File]::WriteAllText(
        $duplicateHandoff,
        ($validContent.Replace("Review By: 2026-08-19T08:00:00Z", "Review By: 2026-08-19T08:00:00Z`nReview By: 2026-08-20T08:00:00Z")),
        (New-Object Text.UTF8Encoding($false))
    )
    $duplicateResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $duplicateHandoff,
        "-ReferenceTime", "2026-08-13T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $duplicateResult 1 "Duplicate review field"
    $duplicateSummary = ($duplicateResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($duplicateSummary.errors.code) -contains "duplicate_review_field") "Duplicate review field error missing"

    $invalidUpdatedHandoff = Join-Path $tempRoot "invalid-updated-handoff.md"
    [IO.File]::WriteAllText(
        $invalidUpdatedHandoff,
        ($validContent.Replace("2026-08-12T08:00:00Z", "not-a-timestamp")),
        (New-Object Text.UTF8Encoding($false))
    )
    $invalidUpdatedResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $invalidUpdatedHandoff,
        "-ReferenceTime", "2026-08-13T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $invalidUpdatedResult 1 "Invalid Updated At"
    $invalidUpdatedSummary = ($invalidUpdatedResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($invalidUpdatedSummary.errors.code) -contains "invalid_updated_at") "Invalid Updated At error missing"

    $missingOffsetHandoff = Join-Path $tempRoot "missing-offset-handoff.md"
    [IO.File]::WriteAllText(
        $missingOffsetHandoff,
        ($validContent.Replace("2026-08-19T08:00:00Z", "2026-08-19T08:00:00")),
        (New-Object Text.UTF8Encoding($false))
    )
    $missingOffsetResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $missingOffsetHandoff,
        "-ReferenceTime", "2026-08-13T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $missingOffsetResult 1 "Review By without offset"
    $missingOffsetSummary = ($missingOffsetResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($missingOffsetSummary.errors.code) -contains "invalid_review_by") "Missing Review By offset error missing"

    $invalidOrderHandoff = Join-Path $tempRoot "invalid-order-handoff.md"
    [IO.File]::WriteAllText(
        $invalidOrderHandoff,
        ($validContent.Replace("2026-08-19T08:00:00Z", "2026-08-12T08:00:00Z")),
        (New-Object Text.UTF8Encoding($false))
    )
    $invalidOrderResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $invalidOrderHandoff,
        "-ReferenceTime", "2026-08-13T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $invalidOrderResult 1 "Invalid review order"
    $invalidOrderSummary = ($invalidOrderResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($invalidOrderSummary.errors.code) -contains "invalid_review_order") "Invalid review order error missing"

    $reviewWindowResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $validHandoff,
        "-MaxReviewWindowDays", "3",
        "-ReferenceTime", "2026-08-13T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $reviewWindowResult 1 "Review window exceeded"
    $reviewWindowSummary = ($reviewWindowResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($reviewWindowSummary.errors.code) -contains "review_window_exceeded") "Review window exceeded error missing"

    $expiredResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $validHandoff,
        "-ReferenceTime", "2026-08-20T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $expiredResult 0 "Expired handoff warning"
    $expiredSummary = ($expiredResult.Output | Out-String | ConvertFrom-Json)
    Assert-True ($expiredSummary.ok -eq $true) "Expiry warning should keep focused checker ok=true"
    Assert-True (@($expiredSummary.warnings.code) -contains "handoff_review_expired") "Expired handoff warning missing"

    $expiryDisabledResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $validHandoff,
        "-EnforceExpiry", "false",
        "-ReferenceTime", "2026-08-20T08:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $expiryDisabledResult 0 "Expiry enforcement disabled"
    $expiryDisabledSummary = ($expiryDisabledResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($expiryDisabledSummary.warnings | ForEach-Object { $_.code }) -notcontains "handoff_review_expired") "Disabled expiry should not create a warning"

    $starterHandoff = Join-Path $RepoRoot "starter-workspace\00_agent_handoff.md"
    $starterContent = Get-Content -Raw -Encoding UTF8 -LiteralPath $starterHandoff
    Assert-Equal ([regex]::Matches($starterContent, "(?m)^Updated At: \{\{UPDATED_AT\}\}$").Count) 1 "Starter should contain one Updated At placeholder"
    Assert-Equal ([regex]::Matches($starterContent, "(?m)^Review By: \{\{REVIEW_BY\}\}$").Count) 1 "Starter should contain one Review By placeholder"
    $starterResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $starterHandoff,
        "-ReferenceTime", "2026-08-12T09:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $starterResult 0 "Starter review placeholders"
    $starterSummary = ($starterResult.Output | Out-String | ConvertFrom-Json)
    Assert-True $starterSummary.ok "Starter review placeholders should remain setup warnings"
    Assert-Equal @($starterSummary.errors).Count 0 "Starter review placeholders should not be errors"
    Assert-True (@($starterSummary.warnings.code) -contains "unresolved_review_placeholder") "Starter review placeholder warning missing"

    $misplacedHandoff = Join-Path $tempRoot "misplaced-review-fields.md"
    $misplacedContent = $validContent.Replace(
        "Updated At: 2026-08-12T08:00:00Z`nReview By: 2026-08-19T08:00:00Z`n`n",
        ""
    ) + "`nUpdated At: 2026-08-12T08:00:00Z`nReview By: 2026-08-19T08:00:00Z`n"
    Write-Utf8NoBom -Path $misplacedHandoff -Content $misplacedContent
    $misplacedResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $misplacedHandoff,
        "-ReferenceTime", "2026-08-12T09:00:00Z",
        "-ParseSafe"
    )
    Assert-ExitCode $misplacedResult 1 "Misplaced review fields"
    $misplacedSummary = ($misplacedResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($misplacedSummary.errors.code) -contains "invalid_review_field_location") "Misplaced review field error missing"

    $exampleHandoffs = @(
        (Join-Path $RepoRoot "examples\solo-business-workspace\00_agent_handoff.md"),
        (Join-Path $RepoRoot "examples\solo-business-workspace\business\00_agent_handoff.md")
    )
    foreach ($exampleHandoff in $exampleHandoffs) {
        $exampleResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
            "-Path", $exampleHandoff,
            "-EnforceExpiry", "false",
            "-ReferenceTime", "2030-01-01T00:00:00Z",
            "-ParseSafe"
        )
        Assert-ExitCode $exampleResult 0 "Fixed public example handoff"
        $exampleSummary = ($exampleResult.Output | Out-String | ConvertFrom-Json)
        Assert-Equal @($exampleSummary.errors).Count 0 "Fixed public example should have no freshness errors"
        Assert-True (@($exampleSummary.warnings | ForEach-Object { $_.code }) -notcontains "handoff_review_expired") "Fixed public example should suppress expiry warnings"
    }

    $historyHandoff = Join-Path $tempRoot "history-handoff.md"
    [IO.File]::WriteAllText(
        $historyHandoff,
        ($validContent + "`n`n## History`nArchived details."),
        (New-Object Text.UTF8Encoding($false))
    )
    $historyResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @("-Path", $historyHandoff, "-ParseSafe")
    Assert-ExitCode $historyResult 0 "History warning"
    $historySummary = ($historyResult.Output | Out-String | ConvertFrom-Json)
    Assert-True ($historySummary.ok -eq $true) "History warning should keep ok=true"
    Assert-Equal @($historySummary.errors).Count 0 "History warning should not create errors"
    Assert-True (@($historySummary.warnings.code) -contains "history_heading") "History warning missing"
    Assert-True (@($historySummary.historyWarnings) -contains "history heading") "Compatibility history warning missing"

    $datedLogHandoff = Join-Path $tempRoot "dated-log-handoff.md"
    [IO.File]::WriteAllText(
        $datedLogHandoff,
        ($validContent + "`n`n## 2026-01-01 Notes`nArchived details."),
        (New-Object Text.UTF8Encoding($false))
    )
    $datedLogResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @("-Path", $datedLogHandoff, "-ParseSafe")
    Assert-ExitCode $datedLogResult 0 "Dated log warning"
    $datedLogSummary = ($datedLogResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($datedLogSummary.warnings.code) -contains "dated_log_heading") "Dated log warning missing"
    Assert-True (@($datedLogSummary.historyWarnings) -contains "dated log heading") "Compatibility dated log warning missing"

    $timelineHandoff = Join-Path $tempRoot "timeline-handoff.md"
    [IO.File]::WriteAllText(
        $timelineHandoff,
        ($validContent + "`n`nToday the draft was reviewed, then the state was updated."),
        (New-Object Text.UTF8Encoding($false))
    )
    $timelineResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @("-Path", $timelineHandoff, "-ParseSafe")
    Assert-ExitCode $timelineResult 0 "Timeline wording warning"
    $timelineSummary = ($timelineResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($timelineSummary.warnings.code) -contains "timeline_wording") "Timeline wording warning missing"
    Assert-True (@($timelineSummary.historyWarnings) -contains "long timeline wording") "Compatibility timeline warning missing"

    $bomHandoff = Join-Path $tempRoot "bom-handoff.md"
    [IO.File]::WriteAllText($bomHandoff, $validContent, (New-Object Text.UTF8Encoding($true)))
    $bomResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @("-Path", $bomHandoff, "-ParseSafe")
    Assert-ExitCode $bomResult 0 "BOM warning"
    $bomSummary = ($bomResult.Output | Out-String | ConvertFrom-Json)
    Assert-True ($bomSummary.ok -eq $true) "BOM warning should keep ok=true"
    Assert-True ($bomSummary.bomFound -eq $true) "BOM compatibility field should be true"
    Assert-True (@($bomSummary.warnings.code) -contains "utf8_bom") "BOM warning missing"

    $nulHandoff = Join-Path $tempRoot "nul-handoff.md"
    [IO.File]::WriteAllText(
        $nulHandoff,
        ($validContent + [char]0),
        (New-Object Text.UTF8Encoding($false))
    )
    $nulResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @("-Path", $nulHandoff, "-ParseSafe")
    Assert-ExitCode $nulResult 1 "NUL error"
    $nulSummary = ($nulResult.Output | Out-String | ConvertFrom-Json)
    Assert-True ($nulSummary.ok -eq $false) "NUL should report ok=false"
    Assert-True ($nulSummary.nulFound -eq $true) "NUL compatibility field should be true"
    Assert-True (@($nulSummary.errors.code) -contains "nul_byte") "NUL error missing"
    $nulIssue = @($nulSummary.errors | Where-Object { $_.code -eq "nul_byte" })[0]
    Assert-True ($null -eq $nulIssue.line) "NUL file-level issue should report line=null"

    $maxLinesResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $validHandoff,
        "-MaxLines", "10",
        "-ParseSafe"
    )
    Assert-ExitCode $maxLinesResult 1 "MaxLines error"
    $maxLinesSummary = ($maxLinesResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($maxLinesSummary.errors.code) -contains "max_lines_exceeded") "MaxLines error missing"

    $maxBytesResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @(
        "-Path", $validHandoff,
        "-MaxBytes", "100",
        "-ParseSafe"
    )
    Assert-ExitCode $maxBytesResult 1 "MaxBytes error"
    $maxBytesSummary = ($maxBytesResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($maxBytesSummary.errors.code) -contains "max_bytes_exceeded") "MaxBytes error missing"

    $invalidHandoff = Join-Path $tempRoot "invalid-handoff.md"
    @"
# Agent Handoff

Updated At: 2026-08-12T08:00:00Z
Review By: 2026-08-19T08:00:00Z

## Current Role
worker

## Workspace Boundary
business/
"@ | Set-Content -LiteralPath $invalidHandoff -Encoding UTF8

    $invalidHandoffResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @("-Path", $invalidHandoff, "-ParseSafe")
    Assert-ExitCode $invalidHandoffResult 1 "Invalid handoff"
    $invalidHandoffSummary = ($invalidHandoffResult.Output | Out-String | ConvertFrom-Json)
    Assert-True ($invalidHandoffSummary.missingSections.Count -gt 0) "Invalid handoff should report missing sections"
    Assert-True (@($invalidHandoffSummary.errors.code) -contains "missing_section") "Missing section error missing"

    $missingHandoff = Join-Path $tempRoot "missing-handoff.md"
    $missingResult = Invoke-TestScript -ScriptPath $CheckHandoff -Arguments @("-Path", $missingHandoff, "-ParseSafe")
    Assert-ExitCode $missingResult 1 "Missing file error"
    $missingSummary = ($missingResult.Output | Out-String | ConvertFrom-Json)
    Assert-True (@($missingSummary.errors.code) -contains "missing_file") "Missing file error missing"
    $missingIssue = @($missingSummary.errors | Where-Object { $_.code -eq "missing_file" })[0]
    Assert-True ($null -eq $missingIssue.line) "Missing file issue should report line=null"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
