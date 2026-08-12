Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$CheckAuthorization = Join-Path $RepoRoot "scripts\check-write-authorization.ps1"
$PolicyLibrary = Join-Path $RepoRoot "scripts\WorkspacePolicy.ps1"
$tempRoot = New-TestDirectory -Prefix "ai-workspace-os-authorization-tests-"
$workspace = Join-Path $tempRoot "workspace"
$referenceTime = "2026-08-12T12:00:00Z"
$sourceMarker = "SYNTHETIC_AUTH_SOURCE_MUST_NOT_LEAK"
$ledgerMarker = "SYNTHETIC_LEDGER_NOTE_MUST_NOT_LEAK"

function New-AuthorizationPolicy {
    param([int]$Revision = 1)

    return [ordered]@{
        protocol_version = "0.2"
        policy_revision = $Revision
        default_write = "deny"
        human_override_role = "workspace_owner"
        roles = @(
            [ordered]@{ id = "workspace_owner"; description = "Human owner $sourceMarker"; status = "active" },
            [ordered]@{ id = "worker"; description = "Direct owner"; status = "active" },
            [ordered]@{ id = "reviewer"; description = "Delegated reviewer"; status = "active" },
            [ordered]@{ id = "auditor"; description = "Append-only auditor"; status = "active" },
            [ordered]@{ id = "former_worker"; description = "Retired role"; status = "retired" }
        )
        ownership = @(
            [ordered]@{ path = "work-area/"; owner = "worker"; actions = @("create", "modify", "append", "delete", "move") },
            [ordered]@{ path = "work-area/reviews/"; owner = "workspace_owner"; actions = @("modify", "move") },
            [ordered]@{ path = "archive/"; owner = "workspace_owner"; actions = @("create", "modify", "append", "delete", "move") },
            [ordered]@{ path = "README.md"; owner = "workspace_owner"; actions = @("modify") },
            [ordered]@{ path = "workspace-policy.json"; owner = "workspace_owner"; actions = @("modify") }
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

function New-AuthorizationGrant {
    param(
        [string]$Id = "DLG-001",
        [int]$Revision = 1,
        [string]$Grantor = "worker",
        [string]$Grantee = "reviewer",
        [string]$Task = "TASK-001",
        [string[]]$Paths = @("work-area/report.md"),
        [string[]]$Actions = @("modify"),
        [string]$IssuedAt = "2026-08-12T08:00:00Z",
        [string]$ExpiresAt = "2026-08-13T08:00:00Z"
    )

    return [ordered]@{
        event = "grant"
        delegation_id = $Id
        policy_revision = $Revision
        grantor_role = $Grantor
        grantee_role = $Grantee
        task_id = $Task
        paths = @($Paths)
        actions = @($Actions)
        issued_at = $IssuedAt
        expires_at = $ExpiresAt
        note = $ledgerMarker
    }
}

function New-AuthorizationRevoke {
    param([string]$Id = "DLG-001", [string]$Role = "worker")
    return [ordered]@{
        event = "revoke"
        delegation_id = $Id
        revoked_by_role = $Role
        timestamp = "2026-08-12T10:00:00Z"
        reason = $ledgerMarker
    }
}

function Write-AuthorizationWorkspace {
    param([object[]]$Events = @(), [object]$Policy = (New-AuthorizationPolicy))

    if (Test-Path -LiteralPath $workspace) {
        Remove-Item -LiteralPath $workspace -Recurse -Force
    }
    New-Item -ItemType Directory -Path (Join-Path $workspace "_ops_log") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $workspace "work-area\reviews") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $workspace "archive") -Force | Out-Null
    Write-Utf8NoBom -Path (Join-Path $workspace "workspace-policy.json") -Content ($Policy | ConvertTo-Json -Depth 10 -Compress)
    $lines = @($Events | ForEach-Object { $_ | ConvertTo-Json -Depth 10 -Compress })
    Write-Utf8NoBom -Path (Join-Path $workspace "_ops_log\delegations.jsonl") -Content ($lines -join "`n")
    Write-Utf8NoBom -Path (Join-Path $workspace "work-area\report.md") -Content "synthetic"
    Write-Utf8NoBom -Path (Join-Path $workspace "work-area\reviews\review.md") -Content "synthetic"
}

function Invoke-Authorization {
    param(
        [string]$ActorRole = "reviewer",
        [string]$TaskId = "TASK-001",
        [string]$Action = "modify",
        [string]$TargetPath = "work-area/report.md",
        [AllowNull()][string]$DestinationPath = $null,
        [string]$WorkspacePath = $workspace
    )

    $arguments = @(
        "-WorkspacePath", $WorkspacePath,
        "-ActorRole", $ActorRole,
        "-TaskId", $TaskId,
        "-Action", $Action,
        "-TargetPath", $TargetPath,
        "-ReferenceTime", $referenceTime,
        "-ParseSafe"
    )
    if (-not [string]::IsNullOrEmpty($DestinationPath)) {
        $arguments += @("-DestinationPath", $DestinationPath)
    }
    return Invoke-TestScript -ScriptPath $CheckAuthorization -Arguments $arguments
}

function Get-AuthorizationSummary {
    param([object]$Result)
    return (($Result.Output | Out-String) | ConvertFrom-Json)
}

function Assert-Decision {
    param([object]$Result, [int]$ExitCode, [string]$Decision, [string]$Reason, [string]$Context)
    Assert-ExitCode $Result $ExitCode $Context
    $summary = Get-AuthorizationSummary -Result $Result
    Assert-Equal $summary.decision $Decision "$Context decision"
    Assert-Equal $summary.reasonCode $Reason "$Context reason"
    Assert-Equal @($summary.PSObject.Properties.Name).Count 9 "$Context output field count"
    foreach ($field in @("decision", "reasonCode", "actorRole", "taskId", "action", "targetPath", "destinationPath", "ownerRole", "delegationIds")) {
        Assert-True ($null -ne $summary.PSObject.Properties[$field]) "$Context missing field $field"
    }
    $output = $Result.Output | Out-String
    Assert-True (-not $output.Contains($workspace)) "$Context leaked workspace path"
    Assert-True (-not $output.Contains($sourceMarker)) "$Context leaked policy source"
    Assert-True (-not $output.Contains($ledgerMarker)) "$Context leaked ledger source"
    return $summary
}

function Get-WorkspaceFingerprint {
    $rows = foreach ($item in Get-ChildItem -LiteralPath $workspace -Force -Recurse | Sort-Object FullName) {
        $relative = $item.FullName.Substring($workspace.Length).TrimStart('\', '/') -replace '\\', '/'
        if ($item.PSIsContainer) {
            "D|$relative"
        }
        else {
            "F|$relative|$((Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash)"
        }
    }
    return ($rows -join "`n")
}

Assert-True (Test-Path -LiteralPath $CheckAuthorization -PathType Leaf) "Authorization checker is missing"

try {
    Write-AuthorizationWorkspace
    Assert-Decision (Invoke-Authorization -ActorRole "worker") 0 "allow" "direct_owner" "Direct owner" | Out-Null
    Assert-Decision (Invoke-Authorization -ActorRole "auditor" -Action "append" -TargetPath "_ops_log/agent_action_log.jsonl") 0 "allow" "standing_permission" "Standing permission" | Out-Null
    Assert-Decision (Invoke-Authorization) 2 "needs_approval" "missing_delegation" "Missing grant" | Out-Null
    Assert-Decision (Invoke-Authorization -ActorRole "workspace_owner") 2 "needs_approval" "missing_delegation" "Human override is not a wildcard" | Out-Null
    Assert-Decision (Invoke-Authorization -ActorRole "unknown") 1 "deny" "unknown_role" "Unknown role" | Out-Null
    Assert-Decision (Invoke-Authorization -ActorRole "former_worker") 1 "deny" "inactive_role" "Retired role" | Out-Null
    Assert-Decision (Invoke-Authorization -Action "execute") 1 "deny" "unsupported_action" "Unknown action" | Out-Null
    Assert-Decision (Invoke-Authorization -TargetPath "unowned/file.md") 1 "deny" "unowned_path" "Unowned path" | Out-Null
    Assert-Decision (Invoke-Authorization -ActorRole "worker" -Action "create" -TargetPath "README.md") 1 "deny" "action_not_owned" "Disallowed owner action" | Out-Null
    Assert-Decision (Invoke-Authorization -ActorRole "worker" -TargetPath "workspace-policy.json") 1 "deny" "protected_path" "Protected path" | Out-Null
    Assert-Decision (Invoke-Authorization -ActorRole "workspace_owner" -TargetPath "workspace-policy.json") 0 "allow" "direct_owner" "Protected direct owner" | Out-Null

    Write-AuthorizationWorkspace -Events @((New-AuthorizationGrant))
    $grantSummary = Assert-Decision (Invoke-Authorization) 0 "allow" "active_delegation" "Active grant"
    Assert-Equal @($grantSummary.delegationIds).Count 1 "Active grant evidence count"
    Assert-Equal @($grantSummary.delegationIds)[0] "DLG-001" "Active grant evidence"

    Write-AuthorizationWorkspace -Events @((New-AuthorizationGrant -Grantor "workspace_owner" -Paths @("archive/")))
    Assert-Decision (Invoke-Authorization -TargetPath "archive/nested/new.md") 0 "allow" "active_delegation" "Directory grant" | Out-Null
    Assert-Decision (Invoke-Authorization -TargetPath "archive-other/new.md") 1 "deny" "unowned_path" "Directory grant boundary" | Out-Null

    Write-AuthorizationWorkspace -Events @((New-AuthorizationGrant -ExpiresAt "2026-08-12T11:00:00Z"))
    Assert-Decision (Invoke-Authorization) 2 "needs_approval" "expired_delegation" "Expired grant" | Out-Null

    Write-AuthorizationWorkspace -Events @((New-AuthorizationGrant), (New-AuthorizationRevoke))
    Assert-Decision (Invoke-Authorization) 2 "needs_approval" "revoked_delegation" "Revoked grant" | Out-Null

    Write-AuthorizationWorkspace -Events @((New-AuthorizationGrant -Revision 2))
    . $PolicyLibrary
    $policyResult = Read-WorkspacePolicy -Path (Join-Path $workspace "workspace-policy.json")
    $ledgerResult = Read-DelegationLedger -Path (Join-Path $workspace "_ops_log\delegations.jsonl") -Policy $policyResult.policy -ReferenceTime ([DateTimeOffset]::Parse($referenceTime))
    Assert-True $ledgerResult.ok "A stale-revision grant must remain valid history"
    Assert-True (@($ledgerResult.warnings | Where-Object { $_.code -eq "stale_policy_revision" }).Count -eq 1) "Stale revision must produce a warning"
    Assert-True (-not $ledgerResult.grants[0].active) "Stale revision must be inactive"
    Assert-Decision (Invoke-Authorization) 2 "needs_approval" "stale_policy_revision" "Stale grant" | Out-Null

    Write-AuthorizationWorkspace -Events @(
        (New-AuthorizationGrant -Id "DLG-SOURCE" -Paths @("work-area/report.md") -Actions @("move")),
        (New-AuthorizationGrant -Id "DLG-DEST" -Grantor "workspace_owner" -Paths @("archive/new.md") -Actions @("move"))
    )
    $moveSummary = Assert-Decision (Invoke-Authorization -Action "move" -DestinationPath "archive/new.md") 0 "allow" "active_delegation" "Move with two grants"
    Assert-Equal @($moveSummary.delegationIds).Count 2 "Move evidence count"
    Assert-Equal @($moveSummary.delegationIds)[0] "DLG-SOURCE" "Move source evidence"
    Assert-Equal @($moveSummary.delegationIds)[1] "DLG-DEST" "Move destination evidence"
    Assert-Decision (Invoke-Authorization -Action "move") 1 "deny" "missing_destination" "Move missing destination" | Out-Null
    Assert-Decision (Invoke-Authorization -Action "move" -DestinationPath "unowned/new.md") 1 "deny" "unowned_path" "Move denied leg" | Out-Null
    Assert-Decision (Invoke-Authorization -Action "move" -DestinationPath "work-area/reviews/new.md") 2 "needs_approval" "missing_delegation" "Move approval leg" | Out-Null

    foreach ($invalidPath in @(".", "..", "../outside.md", "/absolute.md", "C:/outside.md", "https://example.invalid/file", "work-area\report.md")) {
        Assert-Decision (Invoke-Authorization -TargetPath $invalidPath) 1 "deny" "invalid_target_path" "Invalid path '$invalidPath'" | Out-Null
    }
    Assert-Decision (Invoke-Authorization -TargetPath "Work-area/report.md") 1 "deny" "unowned_path" "Case-sensitive path" | Out-Null

    Write-AuthorizationWorkspace -Events @((New-AuthorizationGrant))
    $before = Get-WorkspaceFingerprint
    Assert-Decision (Invoke-Authorization) 0 "allow" "active_delegation" "Read-only check" | Out-Null
    $after = Get-WorkspaceFingerprint
    Assert-Equal $after $before "Authorization checker must not write"

    $outside = Join-Path $tempRoot "outside"
    New-Item -ItemType Directory -Path $outside -Force | Out-Null
    $link = Join-Path $workspace "work-area\escape"
    $linkCreated = $false
    $isWindowsPlatform = ($PSVersionTable.PSEdition -eq "Desktop" -or $env:OS -eq "Windows_NT")
    if ($isWindowsPlatform) {
        try {
            New-Item -ItemType Junction -Path $link -Target $outside -ErrorAction Stop | Out-Null
            $linkCreated = $true
        }
        catch {
            try {
                New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop | Out-Null
                $linkCreated = $true
            }
            catch {
                Write-Host "Reparse-point test skipped: platform did not permit link creation."
            }
        }
    }
    else {
        try {
            New-Item -ItemType SymbolicLink -Path $link -Target $outside -ErrorAction Stop | Out-Null
            $linkCreated = $true
        }
        catch {
            Write-Host "Symbolic-link test skipped: platform did not permit link creation."
        }
    }
    if ($linkCreated) {
        Assert-Decision (Invoke-Authorization -ActorRole "worker" -Action "create" -TargetPath "work-area/escape/new.md") 1 "deny" "reparse_point" "Reparse-point escape" | Out-Null
        Remove-Item -LiteralPath $link -Force
    }

    Write-AuthorizationWorkspace
    Write-Utf8NoBom -Path (Join-Path $workspace "_ops_log\delegations.jsonl") -Content "{invalid"
    Assert-Decision (Invoke-Authorization) 1 "deny" "ledger_invalid" "Malformed ledger" | Out-Null

    Write-AuthorizationWorkspace
    Write-Utf8NoBom -Path (Join-Path $workspace "workspace-policy.json") -Content "{invalid"
    Assert-Decision (Invoke-Authorization) 1 "deny" "policy_invalid" "Malformed policy" | Out-Null
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host "write-authorization.tests.ps1 passed"
