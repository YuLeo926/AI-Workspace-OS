Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$testFiles = @(
    "ops-log.tests.ps1",
    "handoff.tests.ps1",
    "new-adr.tests.ps1",
    "starter-workspace.tests.ps1",
    "workspace-policy.tests.ps1",
    "delegations.tests.ps1",
    "write-authorization.tests.ps1",
    "check-workspace.tests.ps1",
    "init-workspace.tests.ps1",
    "repository-quality.tests.ps1"
)

foreach ($testFile in $testFiles) {
    $path = Join-Path $PSScriptRoot $testFile
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required test suite is missing: $testFile"
    }
}

foreach ($testFile in $testFiles) {
    $path = Join-Path $PSScriptRoot $testFile
    & $path
}

Write-Host "All script tests passed."
