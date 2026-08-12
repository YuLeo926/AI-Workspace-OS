Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$CheckWorkspace = Join-Path $RepoRoot "scripts\check-workspace.ps1"
$Starter = Join-Path $RepoRoot "starter-workspace"
$Example = Join-Path $RepoRoot "examples\solo-business-workspace"
$tempRoot = New-TestDirectory -Prefix "ai-workspace-os-check-workspace-tests-"

function Get-ParseSafeSummary {
    param($Result)

    return ($Result.Output | Out-String | ConvertFrom-Json)
}

function Copy-WorkspaceFixture {
    param(
        [string]$Source,
        [string]$Name
    )

    $destination = Join-Path $tempRoot $Name
    Copy-Item -LiteralPath $Source -Destination $destination -Recurse
    return $destination
}

function Assert-ExactProperties {
    param(
        [object]$InputObject,
        [string[]]$Expected,
        [string]$Context
    )

    $actual = @($InputObject.PSObject.Properties.Name)
    Assert-Equal $actual.Count $Expected.Count "$Context property count"
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        Assert-Equal $actual[$index] $Expected[$index] "$Context property at index $index"
    }
}

function Assert-ContainsIssue {
    param(
        [object[]]$Issues,
        [string]$Code,
        [string]$Path,
        [string]$Context
    )

    $matches = @($Issues | Where-Object { $_.code -eq $Code -and $_.path -eq $Path })
    Assert-True ($matches.Count -gt 0) "$Context missing $Code at $Path"
}

function Assert-NoAbsoluteLeak {
    param(
        $Result,
        [string]$WorkspaceRoot,
        [string]$Marker,
        [string]$Context
    )

    $output = $Result.Output | Out-String
    Assert-True (-not $output.Contains($WorkspaceRoot)) "$Context leaked the absolute workspace root"
    Assert-True (-not $output.Contains($Marker)) "$Context leaked file content"
}

$validHandoff = @"
# Agent Handoff

Updated At: 2026-06-18T08:00:00Z
Review By: 2026-06-25T08:00:00Z

## Current Role
worker

## Workspace Boundary
area/

## Required Reading Order
index, week, handoff

## Hard Constraints
Respect ownership boundaries.

## Current State
Ready.

## Next Step
Continue the planned task.

## Pending Decisions
None.
"@

$validLogEntry = '{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"worker","action":"validate fixture","target":"fixture","approval_state":"not_required","files_changed":[],"rollback_hint":"remove fixture","note":"synthetic"}'

try {
    Assert-True (Test-Path -LiteralPath $CheckWorkspace -PathType Leaf) "Missing script: $CheckWorkspace"

    $summaryFields = @(
        "path", "exists", "policy", "delegations", "handoffs", "opsLogs", "adrCount",
        "errors", "warnings", "strict", "ok"
    )
    $issueFields = @("source", "path", "code", "line", "message")
    $childFields = @("path", "ok", "errorCount", "warningCount")

    $starterResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $Starter, "-ParseSafe")
    Assert-ExitCode $starterResult 0 "Starter default"
    $starterSummary = Get-ParseSafeSummary $starterResult
    Assert-ExactProperties -InputObject $starterSummary -Expected $summaryFields -Context "Starter summary"
    Assert-Equal $starterSummary.path "." "Starter summary path"
    Assert-True ($starterSummary.exists -eq $true) "Starter should exist"
    Assert-True ($starterSummary.ok -eq $true) "Starter default should pass"
    Assert-True ($starterSummary.strict -eq $false) "Starter default should not be strict"
    Assert-True (@($starterSummary.warnings).Count -gt 0) "Starter should warn"
    Assert-ContainsIssue -Issues @($starterSummary.warnings) -Code "unresolved_placeholder" -Path "00_WORKSPACE_INDEX.md" -Context "Starter"
    Assert-ContainsIssue -Issues @($starterSummary.warnings) -Code "no_adr" -Path "00_DECISIONS" -Context "Starter"
    Assert-ExactProperties -InputObject $starterSummary.policy -Expected $childFields -Context "Starter policy result"
    Assert-ExactProperties -InputObject $starterSummary.delegations -Expected $childFields -Context "Starter delegation result"
    Assert-True ($starterSummary.policy.ok -eq $true) "Starter policy should pass"
    Assert-True ($starterSummary.delegations.ok -eq $true) "Starter delegation ledger should pass"
    Assert-Equal @($starterSummary.handoffs).Count 1 "Starter handoff count"
    Assert-Equal @($starterSummary.opsLogs).Count 1 "Starter ops log count"
    Assert-ExactProperties -InputObject @($starterSummary.handoffs)[0] -Expected $childFields -Context "Handoff result"
    Assert-ExactProperties -InputObject @($starterSummary.opsLogs)[0] -Expected $childFields -Context "Ops log result"
    foreach ($issue in @($starterSummary.errors) + @($starterSummary.warnings)) {
        Assert-ExactProperties -InputObject $issue -Expected $issueFields -Context "Aggregate issue"
        Assert-True (-not [IO.Path]::IsPathRooted([string]$issue.path)) "Aggregate issue path must be relative"
        Assert-True (-not ([string]$issue.path).Contains("\")) "Aggregate issue path must use / separators"
    }
    Assert-NoAbsoluteLeak -Result $starterResult -WorkspaceRoot $Starter -Marker "{{WORKSPACE_PURPOSE}}" -Context "Starter parse-safe output"

    $strictStarter = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $Starter, "-ParseSafe", "-Strict")
    Assert-ExitCode $strictStarter 1 "Starter strict"
    $strictStarterSummary = Get-ParseSafeSummary $strictStarter
    Assert-True ($strictStarterSummary.strict -eq $true) "Strict starter should report strict=true"
    Assert-True ($strictStarterSummary.ok -eq $false) "Strict starter should fail on warnings"

    $exampleResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $Example, "-ParseSafe", "-Strict")
    Assert-ExitCode $exampleResult 0 "Example strict"
    $exampleSummary = Get-ParseSafeSummary $exampleResult
    Assert-True ($exampleSummary.ok -eq $true) "Example strict should pass"
    Assert-Equal @($exampleSummary.errors).Count 0 "Example error count"
    Assert-Equal @($exampleSummary.warnings).Count 0 "Example warning count"
    Assert-True ($exampleSummary.policy.ok -eq $true) "Example policy should pass"
    Assert-True ($exampleSummary.delegations.ok -eq $true) "Example delegation history should pass"
    Assert-Equal $exampleSummary.adrCount 1 "Example ADR count"
    Assert-Equal @($exampleSummary.handoffs).Count 2 "Example recursive handoff count"
    Assert-Equal @($exampleSummary.opsLogs).Count 1 "Example recursive ops log count"

    $missingPath = Join-Path $tempRoot "does-not-exist"
    $missingResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $missingPath, "-ParseSafe")
    Assert-ExitCode $missingResult 1 "Missing workspace"
    $missingSummary = Get-ParseSafeSummary $missingResult
    Assert-True ($missingSummary.exists -eq $false) "Missing workspace should report exists=false"
    Assert-ContainsIssue -Issues @($missingSummary.errors) -Code "missing_workspace" -Path "." -Context "Missing workspace"
    Assert-NoAbsoluteLeak -Result $missingResult -WorkspaceRoot $missingPath -Marker "unused-marker" -Context "Missing workspace output"

    $filePath = Join-Path $tempRoot "workspace-file.txt"
    Write-Utf8NoBom -Path $filePath -Content "synthetic file"
    $fileResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $filePath, "-ParseSafe")
    Assert-ExitCode $fileResult 1 "Workspace path is a file"
    $fileSummary = Get-ParseSafeSummary $fileResult
    Assert-True ($fileSummary.exists -eq $true) "File workspace should report exists=true"
    Assert-ContainsIssue -Issues @($fileSummary.errors) -Code "workspace_not_directory" -Path "." -Context "File workspace"

    $missingCore = Copy-WorkspaceFixture -Source $Example -Name "missing-core"
    Remove-Item -LiteralPath (Join-Path $missingCore "00_THIS_WEEK.md")
    Remove-Item -LiteralPath (Join-Path $missingCore "_ops_log") -Recurse
    $missingCoreResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $missingCore, "-ParseSafe")
    Assert-ExitCode $missingCoreResult 1 "Missing core paths"
    $missingCoreSummary = Get-ParseSafeSummary $missingCoreResult
    Assert-ContainsIssue -Issues @($missingCoreSummary.errors) -Code "missing_core_file" -Path "00_THIS_WEEK.md" -Context "Missing core file"
    Assert-ContainsIssue -Issues @($missingCoreSummary.errors) -Code "missing_core_directory" -Path "_ops_log" -Context "Missing core directory"
    Assert-ContainsIssue -Issues @($missingCoreSummary.errors) -Code "missing_core_file" -Path "_ops_log/agent_action_log.jsonl" -Context "Missing root log"
    Assert-ContainsIssue -Issues @($missingCoreSummary.errors) -Code "missing_core_file" -Path "_ops_log/delegations.jsonl" -Context "Missing delegation log"

    $missingEntry = Copy-WorkspaceFixture -Source $Example -Name "missing-entry"
    Remove-Item -LiteralPath (Join-Path $missingEntry "AGENTS.md")
    Remove-Item -LiteralPath (Join-Path $missingEntry ".ai-workspace-os") -Recurse -Force
    $missingEntryResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $missingEntry, "-ParseSafe")
    Assert-ExitCode $missingEntryResult 1 "Missing native entry files"
    $missingEntrySummary = Get-ParseSafeSummary $missingEntryResult
    Assert-ContainsIssue -Issues @($missingEntrySummary.errors) -Code "missing_core_file" -Path "AGENTS.md" -Context "Missing AGENTS entry"
    Assert-ContainsIssue -Issues @($missingEntrySummary.errors) -Code "missing_core_directory" -Path ".ai-workspace-os" -Context "Missing local validators"

    $invalidPolicy = Copy-WorkspaceFixture -Source $Example -Name "invalid-policy"
    $policyMarker = "SYNTHETIC_POLICY_SOURCE_MUST_NOT_LEAK"
    Write-Utf8NoBom -Path (Join-Path $invalidPolicy "workspace-policy.json") -Content ('{"' + $policyMarker + '":')
    $invalidPolicyResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $invalidPolicy, "-ParseSafe")
    Assert-ExitCode $invalidPolicyResult 1 "Invalid policy aggregation"
    $invalidPolicySummary = Get-ParseSafeSummary $invalidPolicyResult
    Assert-ContainsIssue -Issues @($invalidPolicySummary.errors) -Code "malformed_json" -Path "workspace-policy.json" -Context "Invalid policy"
    Assert-NoAbsoluteLeak -Result $invalidPolicyResult -WorkspaceRoot $invalidPolicy -Marker $policyMarker -Context "Invalid policy output"

    $invalidDelegation = Copy-WorkspaceFixture -Source $Example -Name "invalid-delegation"
    $delegationMarker = "SYNTHETIC_DELEGATION_SOURCE_MUST_NOT_LEAK"
    Write-Utf8NoBom -Path (Join-Path $invalidDelegation "_ops_log\delegations.jsonl") -Content ('{"' + $delegationMarker + '":')
    $invalidDelegationResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $invalidDelegation, "-ParseSafe")
    Assert-ExitCode $invalidDelegationResult 1 "Invalid delegation aggregation"
    $invalidDelegationSummary = Get-ParseSafeSummary $invalidDelegationResult
    Assert-ContainsIssue -Issues @($invalidDelegationSummary.errors) -Code "malformed_json" -Path "_ops_log/delegations.jsonl" -Context "Invalid delegation"
    Assert-NoAbsoluteLeak -Result $invalidDelegationResult -WorkspaceRoot $invalidDelegation -Marker $delegationMarker -Context "Invalid delegation output"

    $policySummaryMutations = @(
        @{ Name = "missing-summary-markers"; Code = "invalid_policy_summary"; Apply = { param($text) $text.Replace("<!-- BEGIN POLICY SUMMARY -->", "<!-- POLICY SUMMARY -->") } },
        @{ Name = "malformed-summary-row"; Code = "invalid_policy_summary"; Apply = { param($text) $text.Replace('| `business/product/` | `worker` |', '| business/product/ | worker |') } },
        @{ Name = "duplicate-summary-row"; Code = "invalid_policy_summary"; Apply = { param($text) $text.Replace('| `business/product/` | `worker` |', "| ``business/product/`` | ``worker`` |`n| ``business/product/`` | ``worker`` |") } },
        @{ Name = "missing-summary-pair"; Code = "policy_index_drift"; Apply = { param($text) $text.Replace("| ``business/product/`` | ``worker`` |`n", "") } },
        @{ Name = "extra-summary-pair"; Code = "policy_index_drift"; Apply = { param($text) $text.Replace("<!-- END POLICY SUMMARY -->", "| ``synthetic-extra/`` | ``worker`` |`n<!-- END POLICY SUMMARY -->") } }
    )
    foreach ($fixture in $policySummaryMutations) {
        $driftWorkspace = Copy-WorkspaceFixture -Source $Example -Name $fixture.Name
        $indexPath = Join-Path $driftWorkspace "00_WORKSPACE_INDEX.md"
        $indexText = Read-Utf8Strict -Path $indexPath
        Write-Utf8NoBom -Path $indexPath -Content (& $fixture.Apply $indexText)
        $driftResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $driftWorkspace, "-ParseSafe")
        Assert-ExitCode $driftResult 0 $fixture.Name
        $driftSummary = Get-ParseSafeSummary $driftResult
        Assert-ContainsIssue -Issues @($driftSummary.warnings) -Code $fixture.Code -Path "00_WORKSPACE_INDEX.md" -Context $fixture.Name
        $driftStrict = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $driftWorkspace, "-ParseSafe", "-Strict")
        Assert-ExitCode $driftStrict 1 ($fixture.Name + " strict")
    }

    $unknownPlaceholder = Copy-WorkspaceFixture -Source $Example -Name "unknown-placeholder"
    Add-Content -LiteralPath (Join-Path $unknownPlaceholder "_rules.md") -Value "`n{{UNRECOGNIZED_TOKEN}}" -Encoding Ascii
    New-Item -ItemType Directory -Path (Join-Path $unknownPlaceholder "nested") | Out-Null
    Write-Utf8NoBom -Path (Join-Path $unknownPlaceholder "nested\ignored.md") -Content "{{WORKSPACE_PURPOSE}}"
    $unknownResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $unknownPlaceholder, "-ParseSafe")
    Assert-ExitCode $unknownResult 0 "Unknown root placeholder warning"
    $unknownSummary = Get-ParseSafeSummary $unknownResult
    Assert-ContainsIssue -Issues @($unknownSummary.warnings) -Code "unknown_placeholder" -Path "_rules.md" -Context "Unknown placeholder"
    Assert-True (-not (@($unknownSummary.warnings | Where-Object { $_.path -eq "nested/ignored.md" }).Count -gt 0)) "Nested Markdown placeholders must not be scanned"
    $unknownStrict = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $unknownPlaceholder, "-ParseSafe", "-Strict")
    Assert-ExitCode $unknownStrict 1 "Unknown placeholder strict"

    $warningWorkspace = Copy-WorkspaceFixture -Source $Example -Name "nested-warnings"
    $warningArea = Join-Path $warningWorkspace "area"
    $warningLogDirectory = Join-Path $warningArea "_ops_log"
    New-Item -ItemType Directory -Path $warningLogDirectory -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $warningArea "00_agent_handoff.md") -Content ($validHandoff + "`n`n## History`nSynthetic archive marker.`n")
    Write-Utf8Bom -Path (Join-Path $warningLogDirectory "agent_action_log.jsonl") -Content ($validLogEntry + "`n")
    $warningResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $warningWorkspace, "-ParseSafe")
    Assert-ExitCode $warningResult 0 "Nested warnings default"
    $warningSummary = Get-ParseSafeSummary $warningResult
    Assert-ContainsIssue -Issues @($warningSummary.warnings) -Code "history_heading" -Path "area/00_agent_handoff.md" -Context "Nested handoff warning"
    Assert-ContainsIssue -Issues @($warningSummary.warnings) -Code "utf8_bom" -Path "area/_ops_log/agent_action_log.jsonl" -Context "Nested log warning"
    $warningHandoff = @($warningSummary.handoffs | Where-Object { $_.path -eq "area/00_agent_handoff.md" })[0]
    $warningLog = @($warningSummary.opsLogs | Where-Object { $_.path -eq "area/_ops_log/agent_action_log.jsonl" })[0]
    Assert-Equal $warningHandoff.errorCount 0 "Nested warning handoff error count"
    Assert-True ($warningHandoff.warningCount -gt 0) "Nested warning handoff warning count"
    Assert-Equal $warningLog.errorCount 0 "Nested warning log error count"
    Assert-True ($warningLog.warningCount -gt 0) "Nested warning log warning count"
    $warningStrict = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $warningWorkspace, "-ParseSafe", "-Strict")
    Assert-ExitCode $warningStrict 1 "Nested warnings strict"

    $errorWorkspace = Copy-WorkspaceFixture -Source $Example -Name "nested-errors"
    $errorArea = Join-Path $errorWorkspace "area"
    $errorLogDirectory = Join-Path $errorArea "_ops_log"
    New-Item -ItemType Directory -Path $errorLogDirectory -Force | Out-Null
    $privateMarker = "PRIVATE_FIXTURE_CONTENT_DO_NOT_EMIT"
    Write-Utf8NoBom -Path (Join-Path $errorArea "00_agent_handoff.md") -Content ("# " + $privateMarker + "`n")
    Write-Utf8NoBom -Path (Join-Path $errorLogDirectory "agent_action_log.jsonl") -Content ('{"' + $privateMarker + '":' + "`n")
    $errorResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $errorWorkspace, "-ParseSafe")
    Assert-ExitCode $errorResult 1 "Nested errors"
    $errorSummary = Get-ParseSafeSummary $errorResult
    Assert-ContainsIssue -Issues @($errorSummary.errors) -Code "missing_section" -Path "area/00_agent_handoff.md" -Context "Nested handoff error"
    Assert-ContainsIssue -Issues @($errorSummary.errors) -Code "malformed_json" -Path "area/_ops_log/agent_action_log.jsonl" -Context "Nested log error"
    Assert-NoAbsoluteLeak -Result $errorResult -WorkspaceRoot $errorWorkspace -Marker $privateMarker -Context "Nested error parse-safe output"
    foreach ($entry in @($errorSummary.handoffs) + @($errorSummary.opsLogs)) {
        Assert-True (-not ([string]$entry.path).Contains("\")) "Child result path must use / separators"
        Assert-True (-not [IO.Path]::IsPathRooted([string]$entry.path)) "Child result path must be relative"
    }

    $reparseWorkspace = Copy-WorkspaceFixture -Source $Example -Name "reparse-workspace"
    $reparseTarget = Join-Path $tempRoot "reparse-target"
    New-Item -ItemType Directory -Path $reparseTarget | Out-Null
    Write-Utf8NoBom -Path (Join-Path $reparseTarget "00_agent_handoff.md") -Content "# invalid external handoff"
    $junctionPath = Join-Path $reparseWorkspace "linked-area"
    $junctionCreated = $false
    try {
        New-Item -ItemType Junction -Path $junctionPath -Target $reparseTarget -ErrorAction Stop | Out-Null
        $junctionCreated = $true
    }
    catch {
        # Junction creation can be unavailable in constrained Windows environments.
    }
    if ($junctionCreated) {
        $reparseResult = Invoke-TestScript -ScriptPath $CheckWorkspace -Arguments @("-Path", $reparseWorkspace, "-ParseSafe", "-Strict")
        Assert-ExitCode $reparseResult 0 "Reparse-point directory traversal"
        $reparseSummary = Get-ParseSafeSummary $reparseResult
        Assert-True (-not (@($reparseSummary.handoffs.path) -contains "linked-area/00_agent_handoff.md")) "Reparse-point handoff must not be discovered"
    }

    $missingValidatorRoot = Join-Path $tempRoot "missing-validator-repo"
    $missingValidatorScripts = Join-Path $missingValidatorRoot "scripts"
    New-Item -ItemType Directory -Path $missingValidatorScripts -Force | Out-Null
    Copy-Item -LiteralPath $CheckWorkspace -Destination (Join-Path $missingValidatorScripts "check-workspace.ps1")
    $missingValidatorWorkspace = Copy-WorkspaceFixture -Source $Example -Name "missing-validator-workspace"
    $missingValidatorResult = Invoke-TestScript -ScriptPath (Join-Path $missingValidatorScripts "check-workspace.ps1") -Arguments @("-Path", $missingValidatorWorkspace, "-ParseSafe")
    Assert-ExitCode $missingValidatorResult 1 "Missing child validator"
    $missingValidatorSummary = Get-ParseSafeSummary $missingValidatorResult
    Assert-True (@($missingValidatorSummary.errors.code) -contains "child_validator_failed") "Missing child validator should be reported"

    $invalidValidatorRoot = Join-Path $tempRoot "invalid-validator-repo"
    $invalidValidatorScripts = Join-Path $invalidValidatorRoot "scripts"
    New-Item -ItemType Directory -Path $invalidValidatorScripts -Force | Out-Null
    Copy-Item -LiteralPath $CheckWorkspace -Destination (Join-Path $invalidValidatorScripts "check-workspace.ps1")
    Write-Utf8NoBom -Path (Join-Path $invalidValidatorScripts "check-handoff-size.ps1") -Content "Write-Output 'not-json'`nexit 0`n"
    Write-Utf8NoBom -Path (Join-Path $invalidValidatorScripts "check-ops-log.ps1") -Content "Write-Output 'not-json'`nexit 0`n"
    $invalidValidatorWorkspace = Copy-WorkspaceFixture -Source $Example -Name "invalid-validator-workspace"
    $invalidValidatorResult = Invoke-TestScript -ScriptPath (Join-Path $invalidValidatorScripts "check-workspace.ps1") -Arguments @("-Path", $invalidValidatorWorkspace, "-ParseSafe")
    Assert-ExitCode $invalidValidatorResult 1 "Invalid child validator output"
    $invalidValidatorSummary = Get-ParseSafeSummary $invalidValidatorResult
    Assert-True (@($invalidValidatorSummary.errors.code) -contains "invalid_validator_output") "Invalid child validator output should be reported"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
