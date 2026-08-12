Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$PolicyLibrary = Join-Path $RepoRoot "scripts\WorkspacePolicy.ps1"
$CheckDelegations = Join-Path $RepoRoot "scripts\check-delegations.ps1"
$tempRoot = New-TestDirectory -Prefix "ai-workspace-os-delegation-tests-"
$referenceTime = [DateTimeOffset]::Parse("2026-08-12T12:00:00Z")
$sourceMarker = "SYNTHETIC_DELEGATION_NOTE_MUST_NOT_LEAK"

function New-ValidPolicy {
    param([int]$Revision = 1)

    return [ordered]@{
        protocol_version = "0.2"
        policy_revision = $Revision
        default_write = "deny"
        human_override_role = "workspace_owner"
        roles = @(
            [ordered]@{ id = "workspace_owner"; description = "Human owner"; status = "active" },
            [ordered]@{ id = "worker"; description = "Direct owner"; status = "active" },
            [ordered]@{ id = "reviewer"; description = "Scoped reviewer"; status = "active" },
            [ordered]@{ id = "auditor"; description = "Append-only auditor"; status = "active" },
            [ordered]@{ id = "former_worker"; description = "Historical grantor"; status = "retired" },
            [ordered]@{ id = "former_reviewer"; description = "Historical grantee"; status = "retired" }
        )
        ownership = @(
            [ordered]@{ path = "work-area/"; owner = "worker"; actions = @("create", "modify", "append", "delete", "move") },
            [ordered]@{ path = "work-area/reviews/"; owner = "workspace_owner"; actions = @("modify", "append") },
            [ordered]@{ path = "README.md"; owner = "workspace_owner"; actions = @("modify") }
        )
        standing_permissions = @(
            [ordered]@{ path = "_ops_log/agent_action_log.jsonl"; role = "auditor"; actions = @("append") }
        )
        protected_paths = @(
            [ordered]@{ path = "workspace-policy.json"; required_role = "workspace_owner" }
        )
        handoff = [ordered]@{ max_review_window_days = 14; enforce_expiry = $true }
    }
}

function New-Grant {
    param(
        [string]$Id = "DLG-001",
        [int]$Revision = 1,
        [string]$Grantor = "worker",
        [string]$Grantee = "reviewer",
        [string]$TaskId = "TASK-001",
        [object]$Paths = @("work-area/report.md"),
        [object]$Actions = @("modify"),
        [string]$IssuedAt = "2026-08-12T08:00:00Z",
        [string]$ExpiresAt = "2026-08-13T08:00:00Z"
    )

    return [ordered]@{
        event = "grant"
        delegation_id = $Id
        policy_revision = $Revision
        grantor_role = $Grantor
        grantee_role = $Grantee
        task_id = $TaskId
        paths = $Paths
        actions = $Actions
        issued_at = $IssuedAt
        expires_at = $ExpiresAt
        note = $sourceMarker
    }
}

function New-Revoke {
    param(
        [string]$Id = "DLG-001",
        [string]$RevokedBy = "worker",
        [string]$Timestamp = "2026-08-12T10:00:00Z"
    )

    return [ordered]@{
        event = "revoke"
        delegation_id = $Id
        revoked_by_role = $RevokedBy
        timestamp = $Timestamp
        reason = "Synthetic scope change"
    }
}

function Write-Policy {
    param([System.Collections.IDictionary]$Policy, [string]$Name)

    $path = Join-Path $tempRoot $Name
    Write-Utf8NoBom -Path $path -Content ($Policy | ConvertTo-Json -Depth 10)
    return $path
}

function Write-Ledger {
    param([object[]]$Events, [string]$Name)

    $path = Join-Path $tempRoot $Name
    $lines = @($Events | ForEach-Object { $_ | ConvertTo-Json -Depth 10 -Compress })
    Write-Utf8NoBom -Path $path -Content ($lines -join "`n")
    return $path
}

function Invoke-DelegationCheck {
    param([string]$LedgerPath, [string]$PolicyPath)

    return Invoke-TestScript -ScriptPath $CheckDelegations -Arguments @(
        "-Path", $LedgerPath,
        "-PolicyPath", $PolicyPath,
        "-ReferenceTime", $referenceTime.ToString("o"),
        "-ParseSafe"
    )
}

function Get-DelegationSummary {
    param([object]$Result)
    return ($Result.Output | Out-String | ConvertFrom-Json)
}

function Assert-DelegationIssue {
    param(
        [object]$Result,
        [string]$Code,
        [string]$Context
    )

    Assert-ExitCode $Result 1 $Context
    $summary = Get-DelegationSummary -Result $Result
    Assert-True (-not $summary.ok) "$Context should fail"
    $actualCodes = @($summary.errors | ForEach-Object { $_.code }) -join ", "
    Assert-True (@($summary.errors | Where-Object { $_.code -eq $Code }).Count -gt 0) "$Context missing issue code $Code. Actual codes: $actualCodes"
    foreach ($issue in @($summary.errors) + @($summary.warnings)) {
        Assert-Equal @($issue.PSObject.Properties.Name).Count 3 "$Context issue property count"
        Assert-Equal $issue.PSObject.Properties.Name[0] "code" "$Context issue code property"
        Assert-Equal $issue.PSObject.Properties.Name[1] "line" "$Context issue line property"
        Assert-Equal $issue.PSObject.Properties.Name[2] "message" "$Context issue message property"
    }
    return $summary
}

try {
    Assert-True (Test-Path -LiteralPath $PolicyLibrary -PathType Leaf) "Missing policy library: $PolicyLibrary"
    Assert-True (Test-Path -LiteralPath $CheckDelegations -PathType Leaf) "Missing delegation checker: $CheckDelegations"

    $policyPath = Write-Policy -Policy (New-ValidPolicy) -Name "policy.json"

    $emptyPath = Join-Path $tempRoot "empty.jsonl"
    Write-Utf8NoBom -Path $emptyPath -Content ""
    $emptyResult = Invoke-DelegationCheck -LedgerPath $emptyPath -PolicyPath $policyPath
    Assert-ExitCode $emptyResult 0 "Empty ledger"
    $emptySummary = Get-DelegationSummary -Result $emptyResult
    Assert-True $emptySummary.ok "Empty ledger should pass"
    Assert-Equal $emptySummary.grantCount 0 "Empty ledger grant count"
    Assert-Equal $emptySummary.revocationCount 0 "Empty ledger revocation count"
    Assert-Equal $emptySummary.activeGrantCount 0 "Empty ledger active grant count"

    $activePath = Write-Ledger -Events @((New-Grant)) -Name "active.jsonl"
    $activeResult = Invoke-DelegationCheck -LedgerPath $activePath -PolicyPath $policyPath
    Assert-ExitCode $activeResult 0 "Active grant"
    $activeSummary = Get-DelegationSummary -Result $activeResult
    Assert-Equal $activeSummary.grantCount 1 "Active grant count"
    Assert-Equal $activeSummary.activeGrantCount 1 "Active current grant count"

    $historyPath = Write-Ledger -Events @((New-Grant), (New-Revoke)) -Name "valid-history.jsonl"
    $historyResult = Invoke-DelegationCheck -LedgerPath $historyPath -PolicyPath $policyPath
    Assert-ExitCode $historyResult 0 "Valid grant and revoke history"
    $historySummary = Get-DelegationSummary -Result $historyResult
    Assert-Equal $historySummary.grantCount 1 "History grant count"
    Assert-Equal $historySummary.revocationCount 1 "History revocation count"
    Assert-Equal $historySummary.activeGrantCount 0 "Revoked grant should be inactive"
    $historyOutput = $historyResult.Output | Out-String
    Assert-True (-not $historyOutput.Contains($tempRoot)) "Parse-safe output leaked an absolute fixture path"
    Assert-True (-not $historyOutput.Contains($sourceMarker)) "Parse-safe output leaked a source note"

    $missingResult = Invoke-DelegationCheck -LedgerPath (Join-Path $tempRoot "missing.jsonl") -PolicyPath $policyPath
    Assert-DelegationIssue -Result $missingResult -Code "missing_file" -Context "Missing ledger" | Out-Null

    $invalidPolicyPath = Join-Path $tempRoot "invalid-policy.json"
    Write-Utf8NoBom -Path $invalidPolicyPath -Content "{}"
    $invalidPolicyResult = Invoke-DelegationCheck -LedgerPath $emptyPath -PolicyPath $invalidPolicyPath
    $invalidPolicySummary = Assert-DelegationIssue -Result $invalidPolicyResult -Code "policy_invalid" -Context "Invalid policy"
    Assert-Equal @($invalidPolicySummary.errors).Count 1 "Invalid policy should fail closed with one safe issue"

    $bomPath = Join-Path $tempRoot "bom.jsonl"
    Write-Utf8Bom -Path $bomPath -Content ((New-Grant) | ConvertTo-Json -Depth 10 -Compress)
    $bomResult = Invoke-DelegationCheck -LedgerPath $bomPath -PolicyPath $policyPath
    Assert-ExitCode $bomResult 0 "BOM ledger warning"
    $bomSummary = Get-DelegationSummary -Result $bomResult
    Assert-True $bomSummary.ok "BOM warning should not invalidate the ledger"
    Assert-True (@($bomSummary.warnings | Where-Object { $_.code -eq "utf8_bom" }).Count -eq 1) "BOM warning missing"

    $invalidUtf8Path = Join-Path $tempRoot "invalid-utf8.jsonl"
    [IO.File]::WriteAllBytes($invalidUtf8Path, [byte[]]@(0x7B, 0x22, 0x78, 0x22, 0x3A, 0xFF, 0x7D))
    Assert-DelegationIssue -Result (Invoke-DelegationCheck -LedgerPath $invalidUtf8Path -PolicyPath $policyPath) -Code "invalid_utf8" -Context "Invalid UTF-8" | Out-Null

    $rawFixtures = @(
        @{ Name = "blank-line.jsonl"; Content = ((New-Grant) | ConvertTo-Json -Depth 10 -Compress) + "`n`n"; Code = "blank_line" },
        @{ Name = "nul-byte.jsonl"; Content = '{"event":"grant"}' + [char]0; Code = "nul_byte" },
        @{ Name = "malformed.jsonl"; Content = '{"event":"grant"'; Code = "malformed_json" },
        @{ Name = "array-root.jsonl"; Content = '[]'; Code = "invalid_root_type" },
        @{ Name = "unknown-event.jsonl"; Content = '{"event":"extend"}'; Code = "unknown_event" }
    )
    foreach ($fixture in $rawFixtures) {
        $path = Join-Path $tempRoot $fixture.Name
        if ($fixture.Code -eq "nul_byte") {
            [IO.File]::WriteAllBytes($path, [byte[]]@(0x7B, 0x00, 0x7D))
        }
        else {
            Write-Utf8NoBom -Path $path -Content $fixture.Content
        }
        Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Fixture was not written: $($fixture.Name)"
        Assert-DelegationIssue -Result (Invoke-DelegationCheck -LedgerPath $path -PolicyPath $policyPath) -Code $fixture.Code -Context $fixture.Name | Out-Null
    }

    $grantMutations = @(
        @{ Name = "missing-field"; Code = "missing_required_field"; Apply = { param($e) $e.Remove("note") } },
        @{ Name = "unknown-field"; Code = "unknown_delegation_field"; Apply = { param($e) $e.Add("extra", "value") } },
        @{ Name = "invalid-id"; Code = "invalid_field_type"; Apply = { param($e) $e.delegation_id = "" } },
        @{ Name = "revision-type"; Code = "invalid_policy_revision"; Apply = { param($e) $e.policy_revision = "1" } },
        @{ Name = "paths-scalar"; Code = "invalid_paths"; Apply = { param($e) $e.paths = "work-area/report.md" } },
        @{ Name = "actions-scalar"; Code = "invalid_actions"; Apply = { param($e) $e.actions = "modify" } },
        @{ Name = "duplicate-path"; Code = "duplicate_delegation_path"; Apply = { param($e) $e.paths = @("work-area/report.md", "work-area/report.md") } },
        @{ Name = "invalid-path"; Code = "invalid_delegation_path"; Apply = { param($e) $e.paths = @("../outside.md") } },
        @{ Name = "duplicate-action"; Code = "duplicate_delegation_action"; Apply = { param($e) $e.actions = @("modify", "modify") } },
        @{ Name = "unknown-action"; Code = "unsupported_action"; Apply = { param($e) $e.actions = @("execute") } },
        @{ Name = "invalid-issued"; Code = "invalid_timestamp"; Apply = { param($e) $e.issued_at = "2026-08-12" } },
        @{ Name = "invalid-expires"; Code = "invalid_timestamp"; Apply = { param($e) $e.expires_at = "2026-08-13T08:00:00" } },
        @{ Name = "note-type"; Code = "invalid_field_type"; Apply = { param($e) $e.note = 1 } },
        @{ Name = "unknown-role"; Code = "unknown_role"; Apply = { param($e) $e.grantee_role = "missing_role" } },
        @{ Name = "retired-current-role"; Code = "inactive_role"; Apply = { param($e) $e.grantee_role = "former_reviewer" } },
        @{ Name = "self-delegation"; Code = "self_delegation"; Apply = { param($e) $e.grantee_role = "worker" } },
        @{ Name = "wrong-owner"; Code = "invalid_grantor_scope"; Apply = { param($e) $e.grantor_role = "reviewer" } },
        @{ Name = "nested-owner-expansion"; Code = "invalid_grantor_scope"; Apply = { param($e) $e.paths = @("work-area/") } },
        @{ Name = "action-expansion"; Code = "invalid_grantor_scope"; Apply = { param($e) $e.paths = @("work-area/reviews/note.md"); $e.grantor_role = "workspace_owner"; $e.actions = @("delete") } },
        @{ Name = "standing-authority"; Code = "invalid_grantor_scope"; Apply = { param($e) $e.grantor_role = "auditor"; $e.paths = @("_ops_log/agent_action_log.jsonl"); $e.actions = @("append") } },
        @{ Name = "invalid-expiry-order"; Code = "invalid_expiry_order"; Apply = { param($e) $e.expires_at = $e.issued_at } }
    )
    foreach ($mutation in $grantMutations) {
        $grant = New-Grant
        & $mutation.Apply $grant
        $path = Write-Ledger -Events @($grant) -Name ($mutation.Name + ".jsonl")
        Assert-DelegationIssue -Result (Invoke-DelegationCheck -LedgerPath $path -PolicyPath $policyPath) -Code $mutation.Code -Context $mutation.Name | Out-Null
    }

    $duplicateIdPath = Write-Ledger -Events @((New-Grant), (New-Grant -ExpiresAt "2026-08-14T08:00:00Z")) -Name "duplicate-id.jsonl"
    Assert-DelegationIssue -Result (Invoke-DelegationCheck -LedgerPath $duplicateIdPath -PolicyPath $policyPath) -Code "duplicate_delegation_id" -Context "Duplicate delegation ID" | Out-Null

    $transitivePath = Write-Ledger -Events @(
        (New-Grant -Id "DLG-TRANSITIVE-1"),
        (New-Grant -Id "DLG-TRANSITIVE-2" -Grantor "reviewer" -Grantee "auditor")
    ) -Name "transitive.jsonl"
    Assert-DelegationIssue -Result (Invoke-DelegationCheck -LedgerPath $transitivePath -PolicyPath $policyPath) -Code "invalid_grantor_scope" -Context "Transitive delegation" | Out-Null

    $revokeFixtures = @(
        @{ Name = "unknown-revoke"; Events = @((New-Revoke -Id "DLG-UNKNOWN")); Code = "unknown_delegation_id" },
        @{ Name = "repeated-revoke"; Events = @((New-Grant), (New-Revoke), (New-Revoke -Timestamp "2026-08-12T11:00:00Z")); Code = "repeated_revocation" },
        @{ Name = "unauthorized-revoke"; Events = @((New-Grant), (New-Revoke -RevokedBy "reviewer")); Code = "unauthorized_revocation" },
        @{ Name = "early-revoke"; Events = @((New-Grant), (New-Revoke -Timestamp "2026-08-12T07:59:59Z")); Code = "invalid_revocation_order" }
    )
    foreach ($fixture in $revokeFixtures) {
        $path = Write-Ledger -Events $fixture.Events -Name ($fixture.Name + ".jsonl")
        Assert-DelegationIssue -Result (Invoke-DelegationCheck -LedgerPath $path -PolicyPath $policyPath) -Code $fixture.Code -Context $fixture.Name | Out-Null
    }

    $unknownRevokeField = New-Revoke
    $unknownRevokeField.Add("extra", "value")
    $unknownRevokeFieldPath = Write-Ledger -Events @((New-Grant), $unknownRevokeField) -Name "unknown-revoke-field.jsonl"
    Assert-DelegationIssue -Result (Invoke-DelegationCheck -LedgerPath $unknownRevokeFieldPath -PolicyPath $policyPath) -Code "unknown_delegation_field" -Context "Unknown revoke field" | Out-Null

    $overrideRevokePath = Write-Ledger -Events @((New-Grant), (New-Revoke -RevokedBy "workspace_owner")) -Name "override-revoke.jsonl"
    Assert-ExitCode (Invoke-DelegationCheck -LedgerPath $overrideRevokePath -PolicyPath $policyPath) 0 "Human override revocation"

    $expiredPath = Write-Ledger -Events @((New-Grant -IssuedAt "2026-08-10T08:00:00Z" -ExpiresAt "2026-08-11T08:00:00Z")) -Name "expired.jsonl"
    $expiredResult = Invoke-DelegationCheck -LedgerPath $expiredPath -PolicyPath $policyPath
    Assert-ExitCode $expiredResult 0 "Expired current-revision history"
    Assert-Equal (Get-DelegationSummary -Result $expiredResult).activeGrantCount 0 "Expired grant should be inactive"

    $futureGrantPath = Write-Ledger -Events @(
        (New-Grant -IssuedAt "2026-08-13T08:00:00Z" -ExpiresAt "2026-08-14T08:00:00Z")
    ) -Name "future-grant.jsonl"
    $futureGrantResult = Invoke-DelegationCheck -LedgerPath $futureGrantPath -PolicyPath $policyPath
    Assert-ExitCode $futureGrantResult 0 "Future grant history"
    Assert-Equal (Get-DelegationSummary -Result $futureGrantResult).activeGrantCount 0 "A grant must not activate before issued_at"

    $futureRevokePath = Write-Ledger -Events @(
        (New-Grant),
        (New-Revoke -Timestamp "2026-08-12T13:00:00Z")
    ) -Name "future-revoke.jsonl"
    $futureRevokeResult = Invoke-DelegationCheck -LedgerPath $futureRevokePath -PolicyPath $policyPath
    Assert-ExitCode $futureRevokeResult 0 "Future revocation history"
    Assert-Equal (Get-DelegationSummary -Result $futureRevokeResult).activeGrantCount 1 "A revocation must not take effect before its timestamp"

    $revisionTwoPath = Write-Policy -Policy (New-ValidPolicy -Revision 2) -Name "policy-revision-two.json"
    $staleActivePath = Write-Ledger -Events @((New-Grant -Revision 1)) -Name "stale-active-revision.jsonl"
    $staleActiveResult = Invoke-DelegationCheck -LedgerPath $staleActivePath -PolicyPath $revisionTwoPath
    Assert-ExitCode $staleActiveResult 0 "Time-valid old-revision grant history"
    $staleActiveSummary = Get-DelegationSummary -Result $staleActiveResult
    Assert-True $staleActiveSummary.ok "Old-revision grant should remain valid history"
    Assert-Equal $staleActiveSummary.activeGrantCount 0 "Old-revision grant must not authorize writes"
    Assert-True (@($staleActiveSummary.warnings | Where-Object { $_.code -eq "stale_policy_revision" }).Count -eq 1) "Old-revision grant should warn once"

    $historicalGrant = New-Grant -Revision 1 -Grantor "former_worker" -Grantee "former_reviewer" -IssuedAt "2026-08-09T08:00:00Z" -ExpiresAt "2026-08-10T08:00:00Z"
    $oldExpiredPath = Write-Ledger -Events @($historicalGrant) -Name "old-expired.jsonl"
    Assert-ExitCode (Invoke-DelegationCheck -LedgerPath $oldExpiredPath -PolicyPath $revisionTwoPath) 0 "Expired old-revision retired-role history"

    $oldRevokedGrant = New-Grant -Revision 1 -Grantor "former_worker" -Grantee "former_reviewer" -IssuedAt "2026-08-12T08:00:00Z" -ExpiresAt "2026-08-13T08:00:00Z"
    $oldRevokedPath = Write-Ledger -Events @($oldRevokedGrant, (New-Revoke -RevokedBy "workspace_owner")) -Name "old-revoked.jsonl"
    Assert-ExitCode (Invoke-DelegationCheck -LedgerPath $oldRevokedPath -PolicyPath $revisionTwoPath) 0 "Revoked old-revision retired-role history"

    . $PolicyLibrary
    Assert-True ($null -ne (Get-Command Read-DelegationLedger -ErrorAction SilentlyContinue)) "Read-DelegationLedger was not exported by the shared policy library"
    $policyResult = Read-WorkspacePolicy -Path $policyPath
    $ledgerResult = Read-DelegationLedger -Path $historyPath -Policy $policyResult.policy -ReferenceTime $referenceTime
    Assert-True $ledgerResult.ok "Reusable ledger reader should accept valid history"
    Assert-Equal @($ledgerResult.PSObject.Properties.Name).Count 5 "Ledger reader property count"
    Assert-Equal $ledgerResult.PSObject.Properties.Name[0] "grants" "Ledger reader grants property"
    Assert-Equal $ledgerResult.PSObject.Properties.Name[1] "revocations" "Ledger reader revocations property"
    Assert-Equal $ledgerResult.PSObject.Properties.Name[2] "errors" "Ledger reader errors property"
    Assert-Equal $ledgerResult.PSObject.Properties.Name[3] "warnings" "Ledger reader warnings property"
    Assert-Equal $ledgerResult.PSObject.Properties.Name[4] "ok" "Ledger reader ok property"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host "delegations.tests.ps1 passed"
