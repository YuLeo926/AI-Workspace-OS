Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$PolicyLibrary = Join-Path $RepoRoot "scripts\WorkspacePolicy.ps1"
$CheckPolicy = Join-Path $RepoRoot "scripts\check-workspace-policy.ps1"
$tempRoot = New-TestDirectory -Prefix "ai-workspace-os-policy-tests-"
$sourceMarker = "SYNTHETIC_POLICY_SECRET_MUST_NOT_LEAK"

function New-ValidPolicy {
    return [ordered]@{
        protocol_version = "0.2"
        policy_revision = 1
        default_write = "deny"
        human_override_role = "workspace_owner"
        roles = @(
            [ordered]@{ id = "workspace_owner"; description = "Human owner $sourceMarker"; status = "active" },
            [ordered]@{ id = "worker"; description = "Scoped worker"; status = "active" },
            [ordered]@{ id = "former_worker"; description = "Historical role"; status = "retired" }
        )
        ownership = @(
            [ordered]@{ path = "work-area/"; owner = "worker"; actions = @("create", "modify", "append", "delete", "move") },
            [ordered]@{ path = "work-area/reviews/"; owner = "workspace_owner"; actions = @("modify", "append") },
            [ordered]@{ path = "README.md"; owner = "workspace_owner"; actions = @("modify") }
        )
        standing_permissions = @(
            [ordered]@{ path = "_ops_log/agent_action_log.jsonl"; role = "worker"; actions = @("append") }
        )
        protected_paths = @(
            [ordered]@{ path = "workspace-policy.json"; required_role = "workspace_owner" }
        )
        handoff = [ordered]@{ max_review_window_days = 14; enforce_expiry = $true }
    }
}

function Write-Policy {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Policy,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $path = Join-Path $tempRoot $Name
    Write-Utf8NoBom -Path $path -Content ($Policy | ConvertTo-Json -Depth 10)
    return $path
}

function Get-PolicySummary {
    param([object]$Result)
    return ($Result.Output | Out-String | ConvertFrom-Json)
}

function Assert-PolicyIssue {
    param(
        [object]$Result,
        [string]$Code,
        [string]$Context
    )

    Assert-ExitCode $Result 1 $Context
    $summary = Get-PolicySummary -Result $Result
    Assert-True (-not $summary.ok) "$Context should fail"
    Assert-True (@($summary.errors | Where-Object { $_.code -eq $Code }).Count -gt 0) "$Context missing issue code $Code"
    foreach ($issue in @($summary.errors) + @($summary.warnings)) {
        Assert-Equal @($issue.PSObject.Properties.Name).Count 3 "$Context issue property count"
        Assert-Equal $issue.PSObject.Properties.Name[0] "code" "$Context issue code property"
        Assert-Equal $issue.PSObject.Properties.Name[1] "line" "$Context issue line property"
        Assert-Equal $issue.PSObject.Properties.Name[2] "message" "$Context issue message property"
    }
    return $summary
}

function Invoke-PolicyCheck {
    param([string]$Path)
    return Invoke-TestScript -ScriptPath $CheckPolicy -Arguments @("-Path", $Path, "-ParseSafe")
}

try {
    Assert-True (Test-Path -LiteralPath $PolicyLibrary -PathType Leaf) "Missing policy library: $PolicyLibrary"
    Assert-True (Test-Path -LiteralPath $CheckPolicy -PathType Leaf) "Missing policy checker: $CheckPolicy"

    $validPath = Write-Policy -Policy (New-ValidPolicy) -Name "valid-policy.json"
    $validResult = Invoke-PolicyCheck -Path $validPath
    Assert-ExitCode $validResult 0 "Valid policy"
    $validSummary = Get-PolicySummary -Result $validResult
    Assert-True $validSummary.ok "Valid policy should pass"
    Assert-Equal @($validSummary.errors).Count 0 "Valid policy errors"
    Assert-Equal @($validSummary.warnings).Count 0 "Valid policy warnings"
    Assert-Equal $validSummary.protocolVersion "0.2" "Valid policy protocol"
    Assert-Equal $validSummary.policyRevision 1 "Valid policy revision"
    $validOutput = $validResult.Output | Out-String
    Assert-True (-not $validOutput.Contains($tempRoot)) "Parse-safe output leaked the absolute fixture path"
    Assert-True (-not $validOutput.Contains($sourceMarker)) "Parse-safe output leaked source JSON content"

    $missingResult = Invoke-PolicyCheck -Path (Join-Path $tempRoot "missing.json")
    Assert-PolicyIssue -Result $missingResult -Code "missing_file" -Context "Missing policy" | Out-Null

    $invalidUtf8Path = Join-Path $tempRoot "invalid-utf8.json"
    [IO.File]::WriteAllBytes($invalidUtf8Path, [byte[]]@(0x7B, 0x22, 0x78, 0x22, 0x3A, 0xFF, 0x7D))
    Assert-PolicyIssue -Result (Invoke-PolicyCheck -Path $invalidUtf8Path) -Code "invalid_utf8" -Context "Invalid UTF-8" | Out-Null

    $bomPath = Join-Path $tempRoot "bom.json"
    Write-Utf8Bom -Path $bomPath -Content ((New-ValidPolicy) | ConvertTo-Json -Depth 10)
    Assert-PolicyIssue -Result (Invoke-PolicyCheck -Path $bomPath) -Code "utf8_bom" -Context "UTF-8 BOM" | Out-Null

    $malformedPath = Join-Path $tempRoot "malformed.json"
    Write-Utf8NoBom -Path $malformedPath -Content ('{"fixture":"' + $sourceMarker + '"')
    $malformedResult = Invoke-PolicyCheck -Path $malformedPath
    Assert-PolicyIssue -Result $malformedResult -Code "malformed_json" -Context "Malformed JSON" | Out-Null
    Assert-True (-not (($malformedResult.Output | Out-String).Contains($sourceMarker))) "Malformed output leaked source JSON"

    foreach ($rootFixture in @(
        @{ Name = "array-root.json"; Json = "[]" },
        @{ Name = "scalar-root.json"; Json = '"text"' }
    )) {
        $rootPath = Join-Path $tempRoot $rootFixture.Name
        Write-Utf8NoBom -Path $rootPath -Content $rootFixture.Json
        Assert-PolicyIssue -Result (Invoke-PolicyCheck -Path $rootPath) -Code "invalid_root_type" -Context $rootFixture.Name | Out-Null
    }

    $mutations = @(
        @{ Name = "protocol"; Code = "unsupported_protocol_version"; Apply = { param($p) $p.protocol_version = "0.3" } },
        @{ Name = "revision-zero"; Code = "invalid_policy_revision"; Apply = { param($p) $p.policy_revision = 0 } },
        @{ Name = "revision-fraction"; Code = "invalid_policy_revision"; Apply = { param($p) $p.policy_revision = 1.5 } },
        @{ Name = "default-write"; Code = "invalid_default_write"; Apply = { param($p) $p.default_write = "allow" } },
        @{ Name = "unknown-top-level-field"; Code = "unknown_policy_field"; Apply = { param($p) $p.Add("extra", "value") } },
        @{ Name = "unknown-role-field"; Code = "unknown_policy_field"; Apply = { param($p) $p.roles[0].Add("extra", "value") } },
        @{ Name = "unknown-ownership-field"; Code = "unknown_policy_field"; Apply = { param($p) $p.ownership[0].Add("extra", "value") } },
        @{ Name = "unknown-standing-field"; Code = "unknown_policy_field"; Apply = { param($p) $p.standing_permissions[0].Add("extra", "value") } },
        @{ Name = "unknown-protected-field"; Code = "unknown_policy_field"; Apply = { param($p) $p.protected_paths[0].Add("extra", "value") } },
        @{ Name = "unknown-handoff-field"; Code = "unknown_policy_field"; Apply = { param($p) $p.handoff.Add("extra", "value") } },
        @{ Name = "duplicate-role"; Code = "duplicate_role"; Apply = { param($p) $p.roles += [ordered]@{ id = "worker"; description = "Duplicate"; status = "active" } } },
        @{ Name = "invalid-role-status"; Code = "invalid_role_status"; Apply = { param($p) $p.roles[1].status = "disabled" } },
        @{ Name = "unknown-override"; Code = "invalid_human_override_role"; Apply = { param($p) $p.human_override_role = "unknown" } },
        @{ Name = "retired-override"; Code = "invalid_human_override_role"; Apply = { param($p) $p.human_override_role = "former_worker" } },
        @{ Name = "unknown-owner"; Code = "unknown_role"; Apply = { param($p) $p.ownership[0].owner = "unknown" } },
        @{ Name = "retired-owner"; Code = "inactive_role"; Apply = { param($p) $p.ownership[0].owner = "former_worker" } },
        @{ Name = "invalid-path"; Code = "invalid_policy_path"; Apply = { param($p) $p.ownership[0].path = "../outside/" } },
        @{ Name = "backslash-path"; Code = "invalid_policy_path"; Apply = { param($p) $p.ownership[0].path = "work-area\child/" } },
        @{ Name = "duplicate-ownership"; Code = "duplicate_ownership"; Apply = { param($p) $p.ownership += [ordered]@{ path = "work-area/"; owner = "workspace_owner"; actions = @("modify") } } },
        @{ Name = "unknown-action"; Code = "unsupported_action"; Apply = { param($p) $p.ownership[0].actions = @("execute") } },
        @{ Name = "scalar-actions"; Code = "invalid_actions"; Apply = { param($p) $p.ownership[0].actions = "modify" } },
        @{ Name = "empty-actions"; Code = "invalid_actions"; Apply = { param($p) $p.ownership[0].actions = @() } },
        @{ Name = "unknown-standing-role"; Code = "unknown_role"; Apply = { param($p) $p.standing_permissions[0].role = "unknown" } },
        @{ Name = "retired-standing-role"; Code = "inactive_role"; Apply = { param($p) $p.standing_permissions[0].role = "former_worker" } },
        @{ Name = "duplicate-standing"; Code = "duplicate_standing_permission"; Apply = { param($p) $p.standing_permissions += [ordered]@{ path = "_ops_log/agent_action_log.jsonl"; role = "worker"; actions = @("append") } } },
        @{ Name = "standing-protected-overlap"; Code = "standing_permission_protected_overlap"; Apply = { param($p) $p.standing_permissions[0].path = "workspace-policy.json" } },
        @{ Name = "standing-directory"; Code = "invalid_standing_path"; Apply = { param($p) $p.standing_permissions[0].path = "_ops_log/" } },
        @{ Name = "standing-non-append"; Code = "invalid_standing_actions"; Apply = { param($p) $p.standing_permissions[0].actions = @("modify") } },
        @{ Name = "unknown-protected-role"; Code = "unknown_role"; Apply = { param($p) $p.protected_paths[0].required_role = "unknown" } },
        @{ Name = "retired-protected-role"; Code = "inactive_role"; Apply = { param($p) $p.protected_paths[0].required_role = "former_worker" } },
        @{ Name = "policy-protected-by-worker"; Code = "invalid_policy_protection"; Apply = { param($p) $p.protected_paths[0].required_role = "worker" } },
        @{ Name = "invalid-handoff-days"; Code = "invalid_handoff_settings"; Apply = { param($p) $p.handoff.max_review_window_days = 0 } },
        @{ Name = "invalid-handoff-expiry"; Code = "invalid_handoff_settings"; Apply = { param($p) $p.handoff.enforce_expiry = "true" } }
    )

    foreach ($mutation in $mutations) {
        $policy = New-ValidPolicy
        & $mutation.Apply $policy
        $path = Write-Policy -Policy $policy -Name ($mutation.Name + ".json")
        Assert-PolicyIssue -Result (Invoke-PolicyCheck -Path $path) -Code $mutation.Code -Context $mutation.Name | Out-Null
    }

    $rawFixtures = @(
        @{ Name = "roles-scalar.json"; Code = "invalid_roles"; Replace = '"roles":"worker"' },
        @{ Name = "ownership-scalar.json"; Code = "invalid_ownership"; Replace = '"ownership":{}' },
        @{ Name = "standing-scalar.json"; Code = "invalid_standing_permissions"; Replace = '"standing_permissions":{}' },
        @{ Name = "protected-scalar.json"; Code = "invalid_protected_paths"; Replace = '"protected_paths":{}' }
    )
    $baseJson = (New-ValidPolicy) | ConvertTo-Json -Depth 10 -Compress
    foreach ($fixture in $rawFixtures) {
        $propertyName = ($fixture.Replace -split ':')[0]
        $json = [regex]::Replace($baseJson, [regex]::Escape($propertyName) + ':\[[^\]]*\]', $fixture.Replace, 1)
        if ($fixture.Name -eq "roles-scalar.json") {
            $json = [regex]::Replace($baseJson, '"roles":\[.*?\],"ownership"', '"roles":"worker","ownership"', 1)
        }
        elseif ($fixture.Name -eq "ownership-scalar.json") {
            $json = [regex]::Replace($baseJson, '"ownership":\[.*?\],"standing_permissions"', '"ownership":{},"standing_permissions"', 1)
        }
        elseif ($fixture.Name -eq "standing-scalar.json") {
            $json = [regex]::Replace($baseJson, '"standing_permissions":\[.*?\],"protected_paths"', '"standing_permissions":{},"protected_paths"', 1)
        }
        elseif ($fixture.Name -eq "protected-scalar.json") {
            $json = [regex]::Replace($baseJson, '"protected_paths":\[.*?\],"handoff"', '"protected_paths":{},"handoff"', 1)
        }
        $path = Join-Path $tempRoot $fixture.Name
        Write-Utf8NoBom -Path $path -Content $json
        Assert-PolicyIssue -Result (Invoke-PolicyCheck -Path $path) -Code $fixture.Code -Context $fixture.Name | Out-Null
    }

    . $PolicyLibrary
    $readResult = Read-WorkspacePolicy -Path $validPath
    Assert-True $readResult.ok "Read-WorkspacePolicy should return a valid result"
    Assert-Equal @($readResult.PSObject.Properties.Name).Count 4 "Read result property count"
    Assert-Equal $readResult.PSObject.Properties.Name[0] "policy" "Read result policy property"
    Assert-Equal $readResult.PSObject.Properties.Name[1] "errors" "Read result errors property"
    Assert-Equal $readResult.PSObject.Properties.Name[2] "warnings" "Read result warnings property"
    Assert-Equal $readResult.PSObject.Properties.Name[3] "ok" "Read result ok property"

    Assert-Equal (ConvertTo-WorkspaceRelativePolicyPath -Path "work-area/report.md") "work-area/report.md" "Normalized policy path"
    foreach ($invalidPath in @("", ".", "./work-area", "work-area//report.md", "work-area/../report.md", "C:/outside", "/outside", "https://example.invalid/path", "work-area\report.md")) {
        $threw = $false
        try { ConvertTo-WorkspaceRelativePolicyPath -Path $invalidPath | Out-Null } catch { $threw = $true }
        Assert-True $threw "Invalid policy path should throw: $invalidPath"
    }

    $nestedOwner = Get-PolicyOwnerMatch -Policy $readResult.policy -RelativePath "work-area/reviews/note.md"
    Assert-Equal $nestedOwner.owner "workspace_owner" "Most-specific directory ownership"
    $parentOwner = Get-PolicyOwnerMatch -Policy $readResult.policy -RelativePath "work-area/report.md"
    Assert-Equal $parentOwner.owner "worker" "Parent directory ownership"
    $fileOwner = Get-PolicyOwnerMatch -Policy $readResult.policy -RelativePath "README.md"
    Assert-Equal $fileOwner.owner "workspace_owner" "Exact file ownership"
    Assert-True ($null -eq (Get-PolicyOwnerMatch -Policy $readResult.policy -RelativePath "README.md/child")) "File ownership must not cover descendants"
    Assert-True ($null -eq (Get-PolicyOwnerMatch -Policy $readResult.policy -RelativePath "Work-area/report.md")) "Ownership matching must be case-sensitive"
    Assert-True (Test-StandingPermission -Policy $readResult.policy -Role "worker" -Action "append" -RelativePath "_ops_log/agent_action_log.jsonl") "Standing permission should match"
    Assert-True (-not (Test-StandingPermission -Policy $readResult.policy -Role "Worker" -Action "append" -RelativePath "_ops_log/agent_action_log.jsonl")) "Standing role comparison must be case-sensitive"
    Assert-True (-not (Test-StandingPermission -Policy $readResult.policy -Role "worker" -Action "modify" -RelativePath "_ops_log/agent_action_log.jsonl")) "Standing action must match exactly"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Host "workspace-policy.tests.ps1 passed"
