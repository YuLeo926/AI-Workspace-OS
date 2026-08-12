[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$WorkspacePath,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$ActorRole,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$TaskId,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$Action,
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string]$TargetPath,
    [AllowNull()]
    [AllowEmptyString()]
    [string]$DestinationPath,
    [DateTimeOffset]$ReferenceTime = [DateTimeOffset]::UtcNow,
    [switch]$ParseSafe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "WorkspacePolicy.ps1")

function New-AuthorizationLegResult {
    param(
        [Parameter(Mandatory = $true)][string]$Decision,
        [Parameter(Mandatory = $true)][string]$ReasonCode,
        [AllowNull()][string]$OwnerRole = $null,
        [string[]]$DelegationIds = @()
    )

    return [pscustomobject][ordered]@{
        decision = $Decision
        reasonCode = $ReasonCode
        ownerRole = $OwnerRole
        delegationIds = @($DelegationIds)
    }
}

function Test-AuthorizationString {
    param([AllowNull()][string]$Value)

    return (
        $null -ne $Value -and
        -not [string]::IsNullOrWhiteSpace($Value) -and
        [string]::Equals($Value, $Value.Trim(), [StringComparison]::Ordinal) -and
        $Value.IndexOf([char]0) -lt 0
    )
}

function Test-AuthorizationFilesystemLink {
    param([Parameter(Mandatory = $true)][object]$Item)

    if (($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        return $true
    }

    $linkTypeProperty = $Item.PSObject.Properties["LinkType"]
    if ($null -ne $linkTypeProperty -and -not [string]::IsNullOrWhiteSpace([string]$linkTypeProperty.Value)) {
        return $true
    }

    $targetProperty = $Item.PSObject.Properties["Target"]
    return (
        $null -ne $targetProperty -and
        -not [string]::IsNullOrWhiteSpace(([string[]]@($targetProperty.Value) -join ""))
    )
}

function Test-AuthorizationFilesystemPath {
    param(
        [Parameter(Mandatory = $true)][string]$WorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    try {
        $platformPath = $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
        $candidate = [IO.Path]::GetFullPath((Join-Path $WorkspaceRoot $platformPath))
        $rootPrefix = $WorkspaceRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $candidate.StartsWith($rootPrefix, [StringComparison]::Ordinal)) {
            return $false
        }

        $current = $WorkspaceRoot
        foreach ($segment in @($RelativePath.TrimEnd('/').Split('/'))) {
            $current = Join-Path $current $segment
            if (-not (Test-Path -LiteralPath $current)) {
                break
            }
            $item = Get-Item -LiteralPath $current -Force
            if (Test-AuthorizationFilesystemLink -Item $item) {
                return $false
            }
        }
    }
    catch {
        return $false
    }

    return $true
}

function Get-ProtectedPathMatch {
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $best = $null
    $bestLength = -1
    foreach ($entry in @($Policy.protected_paths)) {
        $policyPath = [string]$entry.path
        if (
            (Test-WorkspacePolicyPathMatch -PolicyPath $policyPath -RelativePath $RelativePath) -and
            $policyPath.Length -gt $bestLength
        ) {
            $best = $entry
            $bestLength = $policyPath.Length
        }
    }
    return $best
}

function Test-AuthorizationGrantPath {
    param(
        [Parameter(Mandatory = $true)][object]$Grant,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    foreach ($grantPath in @($Grant.paths)) {
        if (Test-WorkspacePolicyPathMatch -PolicyPath ([string]$grantPath) -RelativePath $RelativePath) {
            return $true
        }
    }
    return $false
}

function Get-InactiveGrantReason {
    param(
        [Parameter(Mandatory = $true)][object]$Grant,
        [Parameter(Mandatory = $true)][object]$Policy,
        [Parameter(Mandatory = $true)][DateTimeOffset]$At
    )

    if ($Grant.policy_revision -ne [long]$Policy.policy_revision) {
        return "stale_policy_revision"
    }
    if ($Grant.revoked -and $null -ne $Grant.revoked_at -and $At -ge $Grant.revoked_at) {
        return "revoked_delegation"
    }
    if ($At -ge $Grant.expires_at) {
        return "expired_delegation"
    }
    return "inactive_delegation"
}

$decision = "deny"
$reasonCode = "invalid_environment"
$normalizedTarget = $null
$normalizedDestination = $null
$ownerRole = $null
$delegationIds = @()

try {
    if (-not (Test-AuthorizationString -Value $WorkspacePath)) {
        $reasonCode = "invalid_workspace"
        throw [IO.InvalidDataException]::new("stop")
    }

    $workspaceItem = Get-Item -LiteralPath $WorkspacePath -Force -ErrorAction Stop
    if (-not $workspaceItem.PSIsContainer -or (Test-AuthorizationFilesystemLink -Item $workspaceItem)) {
        $reasonCode = "invalid_workspace"
        throw [IO.InvalidDataException]::new("stop")
    }
    $workspaceRoot = [IO.Path]::GetFullPath($workspaceItem.FullName).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)

    if (-not (Test-AuthorizationString -Value $ActorRole) -or -not (Test-AuthorizationString -Value $TaskId)) {
        $reasonCode = "invalid_input"
        throw [IO.InvalidDataException]::new("stop")
    }
    if (-not (Test-WorkspacePolicyOrdinalContains -Values $script:WorkspacePolicySupportedActions -Candidate $Action)) {
        $reasonCode = "unsupported_action"
        throw [IO.InvalidDataException]::new("stop")
    }
    if ([string]::Equals($Action, "move", [StringComparison]::Ordinal)) {
        if (-not (Test-AuthorizationString -Value $DestinationPath)) {
            $reasonCode = "missing_destination"
            throw [IO.InvalidDataException]::new("stop")
        }
    }
    elseif ($null -ne $DestinationPath -and $DestinationPath.Length -gt 0) {
        $reasonCode = "unexpected_destination"
        throw [IO.InvalidDataException]::new("stop")
    }

    try {
        $normalizedTarget = ConvertTo-WorkspaceRelativePolicyPath -Path $TargetPath
    }
    catch {
        $reasonCode = "invalid_target_path"
        throw [IO.InvalidDataException]::new("stop")
    }
    if (-not (Test-AuthorizationFilesystemPath -WorkspaceRoot $workspaceRoot -RelativePath $normalizedTarget)) {
        $normalizedTarget = $null
        $reasonCode = "reparse_point"
        throw [IO.InvalidDataException]::new("stop")
    }

    if ([string]::Equals($Action, "move", [StringComparison]::Ordinal)) {
        try {
            $normalizedDestination = ConvertTo-WorkspaceRelativePolicyPath -Path $DestinationPath
        }
        catch {
            $reasonCode = "invalid_destination_path"
            throw [IO.InvalidDataException]::new("stop")
        }
        if (-not (Test-AuthorizationFilesystemPath -WorkspaceRoot $workspaceRoot -RelativePath $normalizedDestination)) {
            $normalizedDestination = $null
            $reasonCode = "reparse_point"
            throw [IO.InvalidDataException]::new("stop")
        }
    }

    $policyPath = Join-Path $workspaceRoot "workspace-policy.json"
    $policyResult = Read-WorkspacePolicy -Path $policyPath
    if (-not $policyResult.ok) {
        $reasonCode = "policy_invalid"
        throw [IO.InvalidDataException]::new("stop")
    }
    $policy = $policyResult.policy

    $actor = Get-WorkspacePolicyRole -Policy $policy -RoleId $ActorRole
    if ($null -eq $actor) {
        $reasonCode = "unknown_role"
        throw [IO.InvalidDataException]::new("stop")
    }
    if (-not [string]::Equals([string]$actor.status, "active", [StringComparison]::Ordinal)) {
        $reasonCode = "inactive_role"
        throw [IO.InvalidDataException]::new("stop")
    }

    $ledgerPath = Join-Path $workspaceRoot "_ops_log\delegations.jsonl"
    $ledgerResult = Read-DelegationLedger -Path $ledgerPath -Policy $policy -ReferenceTime $ReferenceTime
    if (-not $ledgerResult.ok) {
        $reasonCode = "ledger_invalid"
        throw [IO.InvalidDataException]::new("stop")
    }

    $evaluateLeg = {
        param([string]$RelativePath)

        $protected = Get-ProtectedPathMatch -Policy $policy -RelativePath $RelativePath
        $owner = Get-PolicyOwnerMatch -Policy $policy -RelativePath $RelativePath
        $legOwner = if ($null -eq $owner) { $null } else { [string]$owner.owner }

        if ($null -ne $protected) {
            if (
                $null -eq $owner -or
                -not [string]::Equals([string]$protected.required_role, $ActorRole, [StringComparison]::Ordinal) -or
                -not [string]::Equals([string]$owner.owner, $ActorRole, [StringComparison]::Ordinal) -or
                -not (Test-WorkspacePolicyOrdinalContains -Values @($owner.actions) -Candidate $Action)
            ) {
                return New-AuthorizationLegResult -Decision "deny" -ReasonCode "protected_path" -OwnerRole $legOwner
            }
            return New-AuthorizationLegResult -Decision "allow" -ReasonCode "direct_owner" -OwnerRole $legOwner
        }

        if (Test-StandingPermission -Policy $policy -Role $ActorRole -Action $Action -RelativePath $RelativePath) {
            return New-AuthorizationLegResult -Decision "allow" -ReasonCode "standing_permission" -OwnerRole $legOwner
        }
        if ($null -eq $owner) {
            return New-AuthorizationLegResult -Decision "deny" -ReasonCode "unowned_path"
        }
        if (-not (Test-WorkspacePolicyOrdinalContains -Values @($owner.actions) -Candidate $Action)) {
            return New-AuthorizationLegResult -Decision "deny" -ReasonCode "action_not_owned" -OwnerRole $legOwner
        }
        if ([string]::Equals([string]$owner.owner, $ActorRole, [StringComparison]::Ordinal)) {
            return New-AuthorizationLegResult -Decision "allow" -ReasonCode "direct_owner" -OwnerRole $legOwner
        }

        $inactiveReason = $null
        foreach ($grant in @($ledgerResult.grants)) {
            if (
                [string]::Equals([string]$grant.grantee_role, $ActorRole, [StringComparison]::Ordinal) -and
                [string]::Equals([string]$grant.task_id, $TaskId, [StringComparison]::Ordinal) -and
                (Test-WorkspacePolicyOrdinalContains -Values @($grant.actions) -Candidate $Action) -and
                (Test-AuthorizationGrantPath -Grant $grant -RelativePath $RelativePath)
            ) {
                if ($grant.active) {
                    return New-AuthorizationLegResult -Decision "allow" -ReasonCode "active_delegation" -OwnerRole $legOwner -DelegationIds @([string]$grant.delegation_id)
                }
                $candidateReason = Get-InactiveGrantReason -Grant $grant -Policy $policy -At $ReferenceTime
                if ($null -eq $inactiveReason -or [string]::Equals($candidateReason, "stale_policy_revision", [StringComparison]::Ordinal)) {
                    $inactiveReason = $candidateReason
                }
            }
        }

        if ($null -eq $inactiveReason) {
            $inactiveReason = "missing_delegation"
        }
        return New-AuthorizationLegResult -Decision "needs_approval" -ReasonCode $inactiveReason -OwnerRole $legOwner
    }

    $sourceResult = & $evaluateLeg $normalizedTarget
    $results = @($sourceResult)
    if ([string]::Equals($Action, "move", [StringComparison]::Ordinal)) {
        $results += @(& $evaluateLeg $normalizedDestination)
    }

    $selected = @($results | Where-Object { $_.decision -eq "deny" } | Select-Object -First 1)
    if ($selected.Count -eq 0) {
        $selected = @($results | Where-Object { $_.decision -eq "needs_approval" } | Select-Object -First 1)
    }
    if ($selected.Count -eq 0) {
        $selected = @($results[0])
    }

    $decision = [string]$selected[0].decision
    $reasonCode = [string]$selected[0].reasonCode
    $ownerRole = $selected[0].ownerRole
    $delegationIds = @($results | ForEach-Object { @($_.delegationIds) } | Select-Object -Unique)
    if (
        $decision -eq "allow" -and
        $results.Count -gt 1 -and
        @($results | Select-Object -ExpandProperty reasonCode -Unique).Count -gt 1
    ) {
        $reasonCode = "move_allowed"
    }
}
catch {
    if ($reasonCode -eq "invalid_environment") {
        $reasonCode = "invalid_environment"
    }
    $decision = "deny"
}

$summary = [pscustomobject][ordered]@{
    decision = $decision
    reasonCode = $reasonCode
    actorRole = $ActorRole
    taskId = $TaskId
    action = $Action
    targetPath = $normalizedTarget
    destinationPath = $normalizedDestination
    ownerRole = $ownerRole
    delegationIds = @($delegationIds)
}

if ($ParseSafe) {
    $summary | ConvertTo-Json -Depth 6
}
else {
    Write-Output "Decision: $($summary.decision)"
    Write-Output "Reason: $($summary.reasonCode)"
    if ($null -ne $summary.targetPath) {
        Write-Output "Target: $($summary.targetPath)"
    }
}

if ($decision -eq "allow") {
    exit 0
}
if ($decision -eq "needs_approval") {
    exit 2
}
exit 1
