[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Path,
    [switch]$ParseSafe,
    [switch]$Strict
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-AggregateIssue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,
        [Parameter(Mandatory = $true)]
        [string]$Code,
        [AllowNull()]
        [object]$Line,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    return [pscustomobject][ordered]@{
        source = $Source
        path = $RelativePath
        code = $Code
        line = $Line
        message = $Message
    }
}

function Add-AggregateIssue {
    param(
        [System.Collections.Generic.List[object]]$Collection,
        [string]$Source,
        [string]$RelativePath,
        [string]$Code,
        [AllowNull()]
        [object]$Line,
        [string]$Message
    )

    $Collection.Add((New-AggregateIssue `
        -Source $Source `
        -RelativePath $RelativePath `
        -Code $Code `
        -Line $Line `
        -Message $Message
    )) | Out-Null
}

function New-ChildResult {
    param(
        [string]$RelativePath,
        [bool]$Ok,
        [int]$ErrorCount,
        [int]$WarningCount
    )

    return [pscustomobject][ordered]@{
        path = $RelativePath
        ok = $Ok
        errorCount = $ErrorCount
        warningCount = $WarningCount
    }
}

function Test-HasProperty {
    param(
        [AllowNull()]
        [object]$InputObject,
        [string]$Name
    )

    return ($null -ne $InputObject -and $null -ne $InputObject.PSObject.Properties[$Name])
}

function Get-CurrentPowerShellCommand {
    switch ($PSVersionTable.PSEdition) {
        "Desktop" {
            $source = Join-Path $PSHOME "powershell.exe"
            $baseArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File")
        }
        "Core" {
            $source = (Get-Process -Id $PID -ErrorAction Stop).Path
            $baseArgs = @("-NoProfile", "-File")
        }
        default {
            throw "Unsupported PowerShell edition."
        }
    }

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "The current PowerShell executable is unavailable."
    }

    return [pscustomobject]@{
        Source = $source
        BaseArgs = $baseArgs
    }
}

function Get-RelativeWorkspacePath {
    param(
        [string]$WorkspaceRoot,
        [string]$FullPath
    )

    $root = [IO.Path]::GetFullPath($WorkspaceRoot)
    $candidate = [IO.Path]::GetFullPath($FullPath)
    $rootWithSeparator = $root.TrimEnd([char[]]@('\', '/')) + [IO.Path]::DirectorySeparatorChar

    if (-not $candidate.StartsWith($rootWithSeparator, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Discovered path is outside the workspace root."
    }

    return $candidate.Substring($rootWithSeparator.Length).Replace('\', '/')
}

function Get-WorkspaceFiles {
    param([string]$WorkspaceRoot)

    $files = New-Object System.Collections.Generic.List[object]
    $pending = New-Object System.Collections.Generic.Stack[string]
    $pending.Push($WorkspaceRoot)

    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        $children = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction Stop | Sort-Object -Property Name)

        foreach ($child in $children) {
            $isReparsePoint = (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
            if ($isReparsePoint) {
                continue
            }

            if ($child.PSIsContainer) {
                $pending.Push($child.FullName)
            }
            else {
                $files.Add($child) | Out-Null
            }
        }
    }

    return @($files.ToArray() | Sort-Object -Property FullName)
}

function Test-ChildIssueCollection {
    param([AllowNull()][object]$Issues)

    foreach ($issue in @($Issues)) {
        if (
            $null -eq $issue -or
            -not (Test-HasProperty -InputObject $issue -Name "code") -or
            -not (Test-HasProperty -InputObject $issue -Name "line") -or
            -not (Test-HasProperty -InputObject $issue -Name "message") -or
            -not ($issue.code -is [string]) -or
            $issue.code -notmatch '^[a-z0-9_]+$'
        ) {
            return $false
        }
    }

    return $true
}

function Invoke-ChildValidator {
    param(
        [string]$ValidatorPath,
        [string]$TargetPath,
        [string[]]$AdditionalArguments = @(),
        [string]$Source,
        [string]$RelativePath,
        [System.Collections.Generic.List[object]]$Errors,
        [System.Collections.Generic.List[object]]$Warnings
    )

    if (-not (Test-Path -LiteralPath $ValidatorPath -PathType Leaf)) {
        Add-AggregateIssue `
            -Collection $Errors `
            -Source $Source `
            -RelativePath $RelativePath `
            -Code "child_validator_failed" `
            -Line $null `
            -Message "The required child validator is unavailable."
        return (New-ChildResult -RelativePath $RelativePath -Ok $false -ErrorCount 1 -WarningCount 0)
    }

    try {
        $command = Get-CurrentPowerShellCommand
        $arguments = @($command.BaseArgs)
        $arguments += $ValidatorPath
        $arguments += @("-Path", $TargetPath, "-ParseSafe")
        $arguments += @($AdditionalArguments)
        $output = & $command.Source @arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    catch {
        Add-AggregateIssue `
            -Collection $Errors `
            -Source $Source `
            -RelativePath $RelativePath `
            -Code "child_validator_failed" `
            -Line $null `
            -Message "The child validator could not be executed."
        return (New-ChildResult -RelativePath $RelativePath -Ok $false -ErrorCount 1 -WarningCount 0)
    }

    $outputText = (@($output) | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
    try {
        $childSummary = ConvertFrom-Json -InputObject $outputText -ErrorAction Stop
    }
    catch {
        Add-AggregateIssue `
            -Collection $Errors `
            -Source $Source `
            -RelativePath $RelativePath `
            -Code "invalid_validator_output" `
            -Line $null `
            -Message "The child validator did not return valid parse-safe JSON."
        return (New-ChildResult -RelativePath $RelativePath -Ok $false -ErrorCount 1 -WarningCount 0)
    }

    if (
        $null -eq $childSummary -or
        $childSummary -is [System.Array] -or
        -not (Test-HasProperty -InputObject $childSummary -Name "ok") -or
        -not (Test-HasProperty -InputObject $childSummary -Name "errors") -or
        -not (Test-HasProperty -InputObject $childSummary -Name "warnings") -or
        -not ($childSummary.ok -is [bool]) -or
        -not (Test-ChildIssueCollection -Issues $childSummary.errors) -or
        -not (Test-ChildIssueCollection -Issues $childSummary.warnings)
    ) {
        Add-AggregateIssue `
            -Collection $Errors `
            -Source $Source `
            -RelativePath $RelativePath `
            -Code "invalid_validator_output" `
            -Line $null `
            -Message "The child validator returned an invalid summary structure."
        return (New-ChildResult -RelativePath $RelativePath -Ok $false -ErrorCount 1 -WarningCount 0)
    }

    $childErrors = @($childSummary.errors)
    $childWarnings = @($childSummary.warnings)
    $expectedOk = ($childErrors.Count -eq 0)
    $expectedExitCode = if ($expectedOk) { 0 } else { 1 }

    if ($childSummary.ok -ne $expectedOk -or $exitCode -ne $expectedExitCode) {
        Add-AggregateIssue `
            -Collection $Errors `
            -Source $Source `
            -RelativePath $RelativePath `
            -Code "child_validator_failed" `
            -Line $null `
            -Message "The child validator returned an inconsistent result."
        return (New-ChildResult -RelativePath $RelativePath -Ok $false -ErrorCount 1 -WarningCount 0)
    }

    foreach ($issue in $childErrors) {
        Add-AggregateIssue `
            -Collection $Errors `
            -Source $Source `
            -RelativePath $RelativePath `
            -Code ([string]$issue.code) `
            -Line $issue.line `
            -Message "A child validator reported an error."
    }

    foreach ($issue in $childWarnings) {
        Add-AggregateIssue `
            -Collection $Warnings `
            -Source $Source `
            -RelativePath $RelativePath `
            -Code ([string]$issue.code) `
            -Line $issue.line `
            -Message "A child validator reported a warning."
    }

    return (New-ChildResult `
        -RelativePath $RelativePath `
        -Ok ([bool]$childSummary.ok) `
        -ErrorCount $childErrors.Count `
        -WarningCount $childWarnings.Count
    )
}

function Test-PolicySummaryDrift {
    param(
        [object]$Policy,
        [string]$IndexPath,
        [System.Collections.Generic.List[object]]$Warnings
    )

    if (-not (Test-Path -LiteralPath $IndexPath -PathType Leaf)) {
        return
    }

    try {
        $content = [IO.File]::ReadAllText($IndexPath, (New-Object Text.UTF8Encoding($false, $true)))
    }
    catch {
        Add-AggregateIssue -Collection $Warnings -Source "policy" -RelativePath "00_WORKSPACE_INDEX.md" -Code "invalid_policy_summary" -Line $null -Message "The policy summary could not be read."
        return
    }

    $lines = @([regex]::Split($content, "\r\n|\n|\r"))
    $startLines = @()
    $endLines = @()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -ceq "<!-- BEGIN POLICY SUMMARY -->") { $startLines += $index }
        if ($lines[$index] -ceq "<!-- END POLICY SUMMARY -->") { $endLines += $index }
    }

    if ($startLines.Count -ne 1 -or $endLines.Count -ne 1 -or $startLines[0] -ge $endLines[0]) {
        Add-AggregateIssue -Collection $Warnings -Source "policy" -RelativePath "00_WORKSPACE_INDEX.md" -Code "invalid_policy_summary" -Line $null -Message "The policy summary markers are missing or malformed."
        return
    }

    $documented = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $rowPattern = '^\|\s*`([^`]+)`\s*\|\s*`([^`]+)`\s*\|$'
    $invalid = $false
    for ($index = $startLines[0] + 1; $index -lt $endLines[0]; $index++) {
        $line = $lines[$index]
        if ([string]::IsNullOrWhiteSpace($line) -or $line -ceq "| Path | Owner |" -or $line -ceq "| --- | --- |") {
            continue
        }

        $match = [regex]::Match($line, $rowPattern)
        if (-not $match.Success) {
            $invalid = $true
            break
        }

        $key = $match.Groups[1].Value + [char]0x1F + $match.Groups[2].Value
        if (-not $documented.Add($key)) {
            $invalid = $true
            break
        }
    }

    if ($invalid) {
        Add-AggregateIssue -Collection $Warnings -Source "policy" -RelativePath "00_WORKSPACE_INDEX.md" -Code "invalid_policy_summary" -Line $null -Message "The policy summary table is malformed."
        return
    }

    $expected = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($entry in @($Policy.ownership)) {
        $null = $expected.Add(([string]$entry.path + [char]0x1F + [string]$entry.owner))
    }

    if (-not $expected.SetEquals($documented)) {
        Add-AggregateIssue -Collection $Warnings -Source "policy" -RelativePath "00_WORKSPACE_INDEX.md" -Code "policy_index_drift" -Line $null -Message "The ownership summary differs from workspace-policy.json."
    }
}

function Write-SummaryAndExit {
    param(
        [System.Collections.IDictionary]$Summary,
        [switch]$AsJson
    )

    if ($AsJson) {
        [pscustomobject]$Summary | ConvertTo-Json -Depth 10
    }
    else {
        Write-Output "Workspace: ."
        Write-Output "Policy: $($Summary.policy.ok)"
        Write-Output "Delegations: $($Summary.delegations.ok)"
        Write-Output "Handoffs: $($Summary.handoffs.Count)"
        Write-Output "Ops logs: $($Summary.opsLogs.Count)"
        Write-Output "ADRs: $($Summary.adrCount)"

        foreach ($issue in $Summary.errors) {
            Write-Output "[error][$($issue.code)] $($issue.path): $($issue.message)"
        }
        foreach ($issue in $Summary.warnings) {
            Write-Output "[warning][$($issue.code)] $($issue.path): $($issue.message)"
        }

        if ($Summary.ok) {
            Write-Output "OK"
        }
        else {
            Write-Output "FAILED"
        }
    }

    if ($Summary.ok) {
        exit 0
    }

    exit 1
}

$summary = [ordered]@{
    path = "."
    exists = $false
    policy = (New-ChildResult -RelativePath "workspace-policy.json" -Ok $false -ErrorCount 0 -WarningCount 0)
    delegations = (New-ChildResult -RelativePath "_ops_log/delegations.jsonl" -Ok $false -ErrorCount 0 -WarningCount 0)
    handoffs = @()
    opsLogs = @()
    adrCount = 0
    errors = @()
    warnings = @()
    strict = [bool]$Strict
    ok = $false
}
$errors = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]

if (-not (Test-Path -LiteralPath $Path)) {
    Add-AggregateIssue `
        -Collection $errors `
        -Source "workspace" `
        -RelativePath "." `
        -Code "missing_workspace" `
        -Line $null `
        -Message "The workspace does not exist."
    $summary.errors = @($errors.ToArray())
    Write-SummaryAndExit -Summary $summary -AsJson:$ParseSafe
}

$summary.exists = $true
if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
    Add-AggregateIssue `
        -Collection $errors `
        -Source "workspace" `
        -RelativePath "." `
        -Code "workspace_not_directory" `
        -Line $null `
        -Message "The workspace path is not a directory."
    $summary.errors = @($errors.ToArray())
    Write-SummaryAndExit -Summary $summary -AsJson:$ParseSafe
}

$workspaceRoot = (Resolve-Path -LiteralPath $Path).Path
$requiredFiles = @(
    "00_WORKSPACE_INDEX.md",
    "00_THIS_WEEK.md",
    "00_agent_handoff.md",
    "_rules.md",
    "AGENTS.md",
    "CLAUDE.md",
    "workspace-policy.json",
    "_ops_log/agent_action_log.jsonl",
    "_ops_log/delegations.jsonl"
)
$requiredDirectories = @("00_DECISIONS", "_ops_log", ".ai-workspace-os")
$coreMarkdownFiles = @(
    "00_WORKSPACE_INDEX.md",
    "00_THIS_WEEK.md",
    "00_agent_handoff.md",
    "_rules.md"
)
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

foreach ($relativePath in $requiredFiles) {
    $nativeRelativePath = $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $target = Join-Path $workspaceRoot $nativeRelativePath
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        Add-AggregateIssue `
            -Collection $errors `
            -Source "workspace" `
            -RelativePath $relativePath `
            -Code "missing_core_file" `
            -Line $null `
            -Message "A required root file is missing."
    }
}

foreach ($relativePath in $requiredDirectories) {
    $target = Join-Path $workspaceRoot $relativePath
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        Add-AggregateIssue `
            -Collection $errors `
            -Source "workspace" `
            -RelativePath $relativePath `
            -Code "missing_core_directory" `
            -Line $null `
            -Message "A required root directory is missing."
    }
}

$policyPath = Join-Path $workspaceRoot "workspace-policy.json"
$policyValidator = Join-Path $PSScriptRoot "check-workspace-policy.ps1"
$summary.policy = Invoke-ChildValidator `
    -ValidatorPath $policyValidator `
    -TargetPath $policyPath `
    -Source "policy" `
    -RelativePath "workspace-policy.json" `
    -Errors $errors `
    -Warnings $warnings

$handoffMaxReviewWindowDays = 14
$handoffEnforceExpiry = $true
$policy = $null
if ($summary.policy.ok) {
    try {
        . (Join-Path $PSScriptRoot "WorkspacePolicy.ps1")
        $policyRead = Read-WorkspacePolicy -Path $policyPath
        if ($policyRead.ok) {
            $policy = $policyRead.policy
            $handoffMaxReviewWindowDays = [int]$policy.handoff.max_review_window_days
            $handoffEnforceExpiry = [bool]$policy.handoff.enforce_expiry
            Test-PolicySummaryDrift -Policy $policy -IndexPath (Join-Path $workspaceRoot "00_WORKSPACE_INDEX.md") -Warnings $warnings
        }
    }
    catch {
        Add-AggregateIssue -Collection $errors -Source "policy" -RelativePath "workspace-policy.json" -Code "child_validator_failed" -Line $null -Message "The validated policy could not be loaded."
    }
}

$delegationPath = Join-Path $workspaceRoot "_ops_log\delegations.jsonl"
$delegationValidator = Join-Path $PSScriptRoot "check-delegations.ps1"
$summary.delegations = Invoke-ChildValidator `
    -ValidatorPath $delegationValidator `
    -TargetPath $delegationPath `
    -AdditionalArguments @("-PolicyPath", $policyPath) `
    -Source "delegation" `
    -RelativePath "_ops_log/delegations.jsonl" `
    -Errors $errors `
    -Warnings $warnings

$placeholderPattern = '\{\{[A-Z0-9_]+\}\}'
foreach ($relativePath in $coreMarkdownFiles) {
    $target = Join-Path $workspaceRoot $relativePath
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        continue
    }

    try {
        $content = [IO.File]::ReadAllText($target, (New-Object Text.UTF8Encoding($false, $true)))
    }
    catch {
        Add-AggregateIssue `
            -Collection $errors `
            -Source "workspace" `
            -RelativePath $relativePath `
            -Code "child_validator_failed" `
            -Line $null `
            -Message "A core Markdown file could not be read as UTF-8."
        continue
    }

    $lines = @([regex]::Split($content, "\r\n|\n|\r"))
    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        foreach ($match in [regex]::Matches($lines[$lineIndex], $placeholderPattern)) {
            if ($recognizedTokens -contains $match.Value) {
                Add-AggregateIssue `
                    -Collection $warnings `
                    -Source "workspace" `
                    -RelativePath $relativePath `
                    -Code "unresolved_placeholder" `
                    -Line ($lineIndex + 1) `
                    -Message "A recognized starter placeholder remains unresolved."
            }
            else {
                Add-AggregateIssue `
                    -Collection $warnings `
                    -Source "workspace" `
                    -RelativePath $relativePath `
                    -Code "unknown_placeholder" `
                    -Line ($lineIndex + 1) `
                    -Message "An unknown placeholder is present in a core Markdown file."
            }
        }
    }
}

try {
    $workspaceFiles = @(Get-WorkspaceFiles -WorkspaceRoot $workspaceRoot)
}
catch {
    Add-AggregateIssue `
        -Collection $errors `
        -Source "workspace" `
        -RelativePath "." `
        -Code "child_validator_failed" `
        -Line $null `
        -Message "The workspace could not be enumerated."
    $workspaceFiles = @()
}

$handoffFiles = @($workspaceFiles | Where-Object { $_.Name -ceq "00_agent_handoff.md" })
$opsLogFiles = @($workspaceFiles | Where-Object {
    $_.Name -ceq "agent_action_log.jsonl" -and $_.Directory.Name -ceq "_ops_log"
})
$adrFiles = @($workspaceFiles | Where-Object {
    $_.Directory.Name -ceq "00_DECISIONS" -and $_.Name -clike "ADR-*.md"
})
$summary.adrCount = $adrFiles.Count

if ($summary.adrCount -eq 0) {
    Add-AggregateIssue `
        -Collection $warnings `
        -Source "workspace" `
        -RelativePath "00_DECISIONS" `
        -Code "no_adr" `
        -Line $null `
        -Message "No ADR files were found."
}

$handoffValidator = Join-Path $PSScriptRoot "check-handoff-size.ps1"
$handoffResults = New-Object System.Collections.Generic.List[object]
foreach ($file in $handoffFiles) {
    $relativePath = Get-RelativeWorkspacePath -WorkspaceRoot $workspaceRoot -FullPath $file.FullName
    $handoffResults.Add((Invoke-ChildValidator `
        -ValidatorPath $handoffValidator `
        -TargetPath $file.FullName `
        -AdditionalArguments @(
            "-MaxReviewWindowDays", [string]$handoffMaxReviewWindowDays,
            "-EnforceExpiry", ([string]$handoffEnforceExpiry).ToLowerInvariant()
        ) `
        -Source "handoff" `
        -RelativePath $relativePath `
        -Errors $errors `
        -Warnings $warnings
    )) | Out-Null
}
$summary.handoffs = @($handoffResults.ToArray())

$opsLogValidator = Join-Path $PSScriptRoot "check-ops-log.ps1"
$opsLogResults = New-Object System.Collections.Generic.List[object]
foreach ($file in $opsLogFiles) {
    $relativePath = Get-RelativeWorkspacePath -WorkspaceRoot $workspaceRoot -FullPath $file.FullName
    $opsLogResults.Add((Invoke-ChildValidator `
        -ValidatorPath $opsLogValidator `
        -TargetPath $file.FullName `
        -Source "ops_log" `
        -RelativePath $relativePath `
        -Errors $errors `
        -Warnings $warnings
    )) | Out-Null
}
$summary.opsLogs = @($opsLogResults.ToArray())

$summary.errors = @($errors.ToArray())
$summary.warnings = @($warnings.ToArray())
$hasErrors = ($summary.errors.Count -gt 0)
$hasWarnings = ($summary.warnings.Count -gt 0)
$summary.ok = (-not $hasErrors -and (-not $Strict -or -not $hasWarnings))

Write-SummaryAndExit -Summary $summary -AsJson:$ParseSafe
