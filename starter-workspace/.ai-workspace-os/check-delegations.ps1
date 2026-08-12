[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PolicyPath,
    [DateTimeOffset]$ReferenceTime = [DateTimeOffset]::UtcNow,
    [switch]$ParseSafe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "WorkspacePolicy.ps1")

$policyResult = Read-WorkspacePolicy -Path $PolicyPath
if (-not $policyResult.ok) {
    $ledgerResult = [pscustomobject][ordered]@{
        grants = @()
        revocations = @()
        errors = @(
            (New-WorkspacePolicyIssue -Code "policy_invalid" -Message "The workspace policy is invalid; delegation validation was not performed.")
        )
        warnings = @()
        ok = $false
    }
}
else {
    $ledgerResult = Read-DelegationLedger -Path $Path -Policy $policyResult.policy -ReferenceTime $ReferenceTime
}

$activeGrantCount = @($ledgerResult.grants | Where-Object { $_.active }).Count
$summary = [pscustomobject][ordered]@{
    path = "_ops_log/delegations.jsonl"
    grantCount = @($ledgerResult.grants).Count
    revocationCount = @($ledgerResult.revocations).Count
    activeGrantCount = $activeGrantCount
    errors = @($ledgerResult.errors)
    warnings = @($ledgerResult.warnings)
    ok = [bool]$ledgerResult.ok
}

if ($ParseSafe) {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-Output "Delegation ledger"
    Write-Output "Grants: $($summary.grantCount)"
    Write-Output "Revocations: $($summary.revocationCount)"
    Write-Output "Active grants: $($summary.activeGrantCount)"
    foreach ($issue in $summary.errors) {
        Write-Output "[error][$($issue.code)] line $($issue.line): $($issue.message)"
    }
    foreach ($issue in $summary.warnings) {
        Write-Output "[warning][$($issue.code)] line $($issue.line): $($issue.message)"
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
