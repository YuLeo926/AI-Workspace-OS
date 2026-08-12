[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,
    [switch]$ParseSafe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "WorkspacePolicy.ps1")

$result = Read-WorkspacePolicy -Path $Path
$protocolVersion = $null
$policyRevision = $null
$roleCount = 0
$ownershipCount = 0
$standingPermissionCount = 0
$protectedPathCount = 0

if ($null -ne $result.policy) {
    if (
        (Test-WorkspacePolicyProperty -InputObject $result.policy -Name "protocol_version") -and
        $result.policy.protocol_version -is [string] -and
        [string]::Equals([string]$result.policy.protocol_version, "0.2", [StringComparison]::Ordinal)
    ) {
        $protocolVersion = "0.2"
    }
    if (
        (Test-WorkspacePolicyProperty -InputObject $result.policy -Name "policy_revision") -and
        (Test-WorkspacePolicyInteger -Value $result.policy.policy_revision) -and
        [decimal]$result.policy.policy_revision -gt 0
    ) {
        $policyRevision = [long]$result.policy.policy_revision
    }
    if ((Test-WorkspacePolicyProperty -InputObject $result.policy -Name "roles") -and $result.policy.roles -is [System.Array]) {
        $roleCount = @($result.policy.roles).Count
    }
    if ((Test-WorkspacePolicyProperty -InputObject $result.policy -Name "ownership") -and $result.policy.ownership -is [System.Array]) {
        $ownershipCount = @($result.policy.ownership).Count
    }
    if ((Test-WorkspacePolicyProperty -InputObject $result.policy -Name "standing_permissions") -and $result.policy.standing_permissions -is [System.Array]) {
        $standingPermissionCount = @($result.policy.standing_permissions).Count
    }
    if ((Test-WorkspacePolicyProperty -InputObject $result.policy -Name "protected_paths") -and $result.policy.protected_paths -is [System.Array]) {
        $protectedPathCount = @($result.policy.protected_paths).Count
    }
}

$summary = [pscustomobject][ordered]@{
    path = "workspace-policy.json"
    protocolVersion = $protocolVersion
    policyRevision = $policyRevision
    roleCount = $roleCount
    ownershipCount = $ownershipCount
    standingPermissionCount = $standingPermissionCount
    protectedPathCount = $protectedPathCount
    errors = @($result.errors)
    warnings = @($result.warnings)
    ok = [bool]$result.ok
}

if ($ParseSafe) {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-Output "Policy: workspace-policy.json"
    Write-Output "Protocol: $($summary.protocolVersion)"
    Write-Output "Revision: $($summary.policyRevision)"
    foreach ($issue in $summary.errors) {
        Write-Output "[error][$($issue.code)] $($issue.message)"
    }
    foreach ($issue in $summary.warnings) {
        Write-Output "[warning][$($issue.code)] $($issue.message)"
    }
    if ($summary.ok) {
        Write-Output "OK"
    }
    else {
        Write-Output "FAILED"
    }
}

if ($summary.ok) {
    exit 0
}

exit 1
