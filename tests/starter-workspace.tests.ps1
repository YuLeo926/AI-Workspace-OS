. (Join-Path $PSScriptRoot "TestSupport.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$starter = Join-Path $RepoRoot "starter-workspace"
$requiredFiles = @(
    "00_WORKSPACE_INDEX.md",
    "00_THIS_WEEK.md",
    "00_agent_handoff.md",
    "_rules.md",
    "AGENTS.md",
    "CLAUDE.md",
    "workspace-policy.json",
    "00_DECISIONS\README.md",
    "_ops_log\agent_action_log.jsonl",
    "_ops_log\delegations.jsonl"
)

$validatorFiles = @(
    "WorkspacePolicy.ps1",
    "check-workspace-policy.ps1",
    "check-delegations.ps1",
    "check-write-authorization.ps1",
    "check-handoff-size.ps1",
    "check-ops-log.ps1",
    "check-workspace.ps1"
)

foreach ($relativePath in $requiredFiles) {
    Assert-True (Test-Path -LiteralPath (Join-Path $starter $relativePath) -PathType Leaf) "Missing starter file: $relativePath"
}

foreach ($relativeLog in @("_ops_log\agent_action_log.jsonl", "_ops_log\delegations.jsonl")) {
    $logPath = Join-Path $starter $relativeLog
    Assert-Equal ([IO.File]::ReadAllBytes($logPath).Length) 0 "Starter log must be empty: $relativeLog"
}

$localValidatorRoot = Join-Path $starter ".ai-workspace-os"
Assert-True (Test-Path -LiteralPath $localValidatorRoot -PathType Container) "Missing local validator directory"
foreach ($validator in $validatorFiles) {
    $repositoryPath = Join-Path $RepoRoot ("scripts\" + $validator)
    $starterPath = Join-Path $localValidatorRoot $validator
    Assert-True (Test-Path -LiteralPath $starterPath -PathType Leaf) "Missing local validator: $validator"
    $repositoryBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($repositoryPath))
    $starterBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($starterPath))
    Assert-Equal $starterBytes $repositoryBytes "Local validator drift: $validator"
}

Assert-Equal (Read-Utf8Strict (Join-Path $starter "CLAUDE.md")) "@AGENTS.md`n" "Starter Claude entry must only import AGENTS.md"

$markdownFiles = $requiredFiles | Where-Object { $_ -like "*.md" }
$markdown = ($markdownFiles | ForEach-Object {
    Read-Utf8Strict (Join-Path $starter $_)
}) -join "`n"

$recognizedTokens = @(
    "{{WORKSPACE_PURPOSE}}",
    "{{OWNED_PATH}}",
    "{{OWNER_ROLE}}",
    "{{WEEK_OF}}",
    "{{PRIORITY_ONE}}",
    "{{CURRENT_STATE}}",
    "{{NEXT_STEP}}",
    "{{UPDATED_AT}}",
    "{{REVIEW_BY}}"
)

foreach ($token in $recognizedTokens) {
    Assert-True ($markdown.Contains($token)) "Missing recognized starter token: $token"
}

$forbiddenText = @(
    "Example product",
    "ADR-001",
    "business/"
)

foreach ($text in $forbiddenText) {
    Assert-True (-not $markdown.Contains($text)) "Starter contains fictional state: $text"
}

$policyCheck = Join-Path $RepoRoot "scripts\check-workspace-policy.ps1"
$policyResult = Invoke-TestScript -ScriptPath $policyCheck -Arguments @(
    "-Path", (Join-Path $starter "workspace-policy.json"),
    "-ParseSafe"
)
Assert-ExitCode $policyResult 0 "Starter policy validation"
$policySummary = $policyResult.Output | Out-String | ConvertFrom-Json
Assert-True ($policySummary.ok -eq $true) "Starter policy must be valid"

$index = Read-Utf8Strict (Join-Path $starter "00_WORKSPACE_INDEX.md")
Assert-True ($index.Contains("<!-- BEGIN POLICY SUMMARY -->")) "Missing policy summary start marker"
Assert-True ($index.Contains("<!-- END POLICY SUMMARY -->")) "Missing policy summary end marker"

$agentInstructions = Read-Utf8Strict (Join-Path $starter "AGENTS.md")
foreach ($requiredText in @(
    "00_WORKSPACE_INDEX.md",
    "00_THIS_WEEK.md",
    "00_agent_handoff.md",
    "workspace-policy.json",
    "check-write-authorization.ps1",
    "needs_approval",
    "agent_action_log.jsonl",
    "Chat history",
    "check-workspace.ps1"
)) {
    Assert-True ($agentInstructions.Contains($requiredText)) "Starter AGENTS.md missing contract text: $requiredText"
}

$handoffPath = Join-Path $starter "00_agent_handoff.md"
$handoff = Read-Utf8Strict $handoffPath
$requiredHeadings = @(
    "Current Role",
    "Workspace Boundary",
    "Required Reading Order",
    "Hard Constraints",
    "Current State",
    "Next Step",
    "Pending Decisions"
)

foreach ($heading in $requiredHeadings) {
    Assert-True ($handoff -match "(?m)^## $([regex]::Escape($heading))$") "Missing exact handoff heading: $heading"
}

$levelTwoHeadings = @([regex]::Matches($handoff, "(?m)^## (.+)$") | ForEach-Object { $_.Groups[1].Value })
$previousIndex = -1
foreach ($heading in $requiredHeadings) {
    $currentIndex = -1
    for ($index = $previousIndex + 1; $index -lt $levelTwoHeadings.Count; $index++) {
        if ($levelTwoHeadings[$index] -eq $heading) {
            $currentIndex = $index
            break
        }
    }
    Assert-True ($currentIndex -ge 0) "Starter handoff protocol heading order changed at: $heading"
    $previousIndex = $currentIndex
}
