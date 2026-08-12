Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")

$repoRoot = Split-Path -Parent $PSScriptRoot
$initWorkspace = Join-Path $repoRoot "scripts\init-workspace.ps1"
$starterRoot = Join-Path $repoRoot "starter-workspace"
$tempRoot = New-TestDirectory -Prefix "ai-workspace-init-"

function Assert-PathAbsent {
    param([string]$Path, [string]$Message)
    Assert-True (-not (Test-Path -LiteralPath $Path)) $Message
}

function Assert-OnlyExpectedEntries {
    param([string]$Path, [string[]]$ExpectedNames, [string]$Message)
    $actual = @(
        Get-ChildItem -LiteralPath $Path -Force |
            ForEach-Object { $_.Name } |
            Sort-Object
    )
    $expected = @($ExpectedNames | Sort-Object)
    Assert-Equal (($actual -join "|")) (($expected -join "|")) $Message
}

try {
    Assert-True (Test-Path -LiteralPath $initWorkspace -PathType Leaf) "Initializer script is missing"

    $command = Get-Command -Name $initWorkspace
    Assert-True $command.Parameters.ContainsKey("Destination") "Destination parameter is missing"
    $destinationParameterAttribute = @(
        $command.Parameters["Destination"].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
    )[0]
    Assert-True $destinationParameterAttribute.Mandatory "Destination must be mandatory"
    Assert-True $command.Parameters.ContainsKey("WhatIf") "WhatIf parameter is missing"
    Assert-True (-not $command.Parameters.ContainsKey("Force")) "Force must not be exposed"

    $scriptText = Read-Utf8Strict -Path $initWorkspace
    $shouldProcessCalls = [regex]::Matches($scriptText, '\$PSCmdlet\.ShouldProcess\s*\(').Count
    Assert-Equal $shouldProcessCalls 1 "Initializer must call ShouldProcess exactly once"

    $newDestination = Join-Path $tempRoot "new-project"
    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $newDestination)
    Assert-ExitCode $result 0 "Initialize an absent destination"
    Assert-True (Test-Path -LiteralPath (Join-Path $newDestination "00_WORKSPACE_INDEX.md") -PathType Leaf) "Index was not copied"
    Assert-True (Test-Path -LiteralPath (Join-Path $newDestination "00_DECISIONS\README.md") -PathType Leaf) "Decision directory was not copied"
    foreach ($relativePath in @(
        "AGENTS.md",
        "CLAUDE.md",
        "workspace-policy.json",
        ".ai-workspace-os\check-workspace.ps1",
        ".ai-workspace-os\check-write-authorization.ps1"
    )) {
        Assert-True (Test-Path -LiteralPath (Join-Path $newDestination $relativePath) -PathType Leaf) "New workspace file was not copied: $relativePath"
    }
    $copiedLog = Join-Path $newDestination "_ops_log\agent_action_log.jsonl"
    Assert-True (Test-Path -LiteralPath $copiedLog -PathType Leaf) "Ops log was not copied"
    Assert-Equal (Get-Item -LiteralPath $copiedLog).Length 0 "Copied ops log must remain zero bytes"
    $copiedDelegations = Join-Path $newDestination "_ops_log\delegations.jsonl"
    Assert-True (Test-Path -LiteralPath $copiedDelegations -PathType Leaf) "Delegation log was not copied"
    Assert-Equal (Get-Item -LiteralPath $copiedDelegations).Length 0 "Copied delegation log must remain zero bytes"
    $initializationOutput = $result.Output | Out-String
    Assert-True ($initializationOutput.Contains("Authorization: .ai-workspace-os\check-write-authorization.ps1")) "Initializer must print destination-local authorization guidance"
    Assert-True ($initializationOutput.Contains("Check: .ai-workspace-os\check-workspace.ps1 -Path .")) "Initializer must print destination-local check guidance"
    Assert-True (-not $initializationOutput.Contains("templates\agent-start-prompt.md")) "Initializer must not point back to the source repository"

    $installedPolicyCheck = Join-Path $newDestination ".ai-workspace-os\check-workspace-policy.ps1"
    $installedPolicyResult = Invoke-TestScript -ScriptPath $installedPolicyCheck -Arguments @(
        "-Path", (Join-Path $newDestination "workspace-policy.json"),
        "-ParseSafe"
    )
    Assert-ExitCode $installedPolicyResult 0 "Run the installed policy validator"
    $installedPolicySummary = $installedPolicyResult.Output | Out-String | ConvertFrom-Json
    Assert-True ($installedPolicySummary.ok -eq $true) "Installed policy validator should accept the starter policy"

    $installedAggregateCheck = Join-Path $newDestination ".ai-workspace-os\check-workspace.ps1"
    $installedAggregateResult = Invoke-TestScript -ScriptPath $installedAggregateCheck -Arguments @(
        "-Path", $newDestination,
        "-ParseSafe"
    )
    Assert-ExitCode $installedAggregateResult 0 "Run the installed aggregate validator"
    $installedAggregateSummary = $installedAggregateResult.Output | Out-String | ConvertFrom-Json
    Assert-True ($installedAggregateSummary.ok -eq $true) "Installed aggregate validator should accept the starter workspace by default"

    $existingProject = Join-Path $tempRoot "existing-project"
    New-Item -ItemType Directory -Path $existingProject | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $existingProject "00_DECISIONS") | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $existingProject "_ops_log") | Out-Null
    Write-Utf8NoBom -Path (Join-Path $existingProject "keep.txt") -Content "keep me"
    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $existingProject)
    Assert-ExitCode $result 0 "Initialize an existing nonconflicting project"
    Assert-Equal (Read-Utf8Strict -Path (Join-Path $existingProject "keep.txt")) "keep me" "Pre-existing content changed"
    Assert-True (Test-Path -LiteralPath (Join-Path $existingProject "00_THIS_WEEK.md") -PathType Leaf) "Starter files were not added"
    Assert-True (Test-Path -LiteralPath (Join-Path $existingProject "00_DECISIONS") -PathType Container) "Existing decisions directory was not reused"
    Assert-True (Test-Path -LiteralPath (Join-Path $existingProject "_ops_log") -PathType Container) "Existing ops log directory was not reused"
    Assert-True (Test-Path -LiteralPath (Join-Path $existingProject "workspace-policy.json") -PathType Leaf) "Policy was not added to the existing project"
    Assert-True (Test-Path -LiteralPath (Join-Path $existingProject ".ai-workspace-os\check-workspace.ps1") -PathType Leaf) "Local validators were not added to the existing project"

    $directConflict = Join-Path $tempRoot "direct-conflict"
    New-Item -ItemType Directory -Path $directConflict | Out-Null
    Write-Utf8NoBom -Path (Join-Path $directConflict "00_WORKSPACE_INDEX.md") -Content "user content"
    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $directConflict)
    Assert-ExitCode $result 1 "Reject a direct file conflict"
    Assert-OnlyExpectedEntries -Path $directConflict -ExpectedNames @("00_WORKSPACE_INDEX.md") -Message "Direct conflict produced partial writes"
    Assert-Equal (Read-Utf8Strict -Path (Join-Path $directConflict "00_WORKSPACE_INDEX.md")) "user content" "Conflicting file changed"

    $newConflictPaths = @(
        "workspace-policy.json",
        "AGENTS.md",
        "_ops_log\delegations.jsonl"
    )
    foreach ($relativeConflict in $newConflictPaths) {
        $name = ($relativeConflict -replace '[\\/]', '-')
        $conflictRoot = Join-Path $tempRoot ("new-conflict-" + $name)
        $conflictPath = Join-Path $conflictRoot $relativeConflict
        New-Item -ItemType Directory -Path (Split-Path -Parent $conflictPath) -Force | Out-Null
        Write-Utf8NoBom -Path $conflictPath -Content "existing user content"
        $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $conflictRoot)
        Assert-ExitCode $result 1 "Reject new file conflict: $relativeConflict"
        Assert-Equal (Read-Utf8Strict -Path $conflictPath) "existing user content" "New conflicting file changed: $relativeConflict"
        Assert-Equal @(Get-ChildItem -LiteralPath $conflictRoot -Recurse -File -Force).Count 1 "New conflict produced partial files: $relativeConflict"
    }

    $validatorDirectoryConflict = Join-Path $tempRoot "validator-directory-conflict"
    New-Item -ItemType Directory -Path $validatorDirectoryConflict | Out-Null
    Write-Utf8NoBom -Path (Join-Path $validatorDirectoryConflict ".ai-workspace-os") -Content "not a directory"
    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $validatorDirectoryConflict)
    Assert-ExitCode $result 1 "Reject a file at the validator directory path"
    Assert-OnlyExpectedEntries -Path $validatorDirectoryConflict -ExpectedNames @(".ai-workspace-os") -Message "Validator directory conflict produced partial writes"

    $targetDirectoryConflict = Join-Path $tempRoot "target-directory-conflict"
    New-Item -ItemType Directory -Path (Join-Path $targetDirectoryConflict "00_THIS_WEEK.md") -Force | Out-Null
    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $targetDirectoryConflict)
    Assert-ExitCode $result 1 "Reject a directory at a target file path"
    Assert-OnlyExpectedEntries -Path $targetDirectoryConflict -ExpectedNames @("00_THIS_WEEK.md") -Message "Target directory conflict produced partial writes"

    $destinationFile = Join-Path $tempRoot "destination-is-file"
    Write-Utf8NoBom -Path $destinationFile -Content "not a directory"
    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $destinationFile)
    Assert-ExitCode $result 1 "Reject a destination that is a file"
    Assert-Equal (Read-Utf8Strict -Path $destinationFile) "not a directory" "Destination file changed"

    $parentFileConflict = Join-Path $tempRoot "parent-file-conflict"
    New-Item -ItemType Directory -Path $parentFileConflict | Out-Null
    Write-Utf8NoBom -Path (Join-Path $parentFileConflict "_ops_log") -Content "not a directory"
    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $parentFileConflict)
    Assert-ExitCode $result 1 "Reject a file at a required parent path"
    Assert-OnlyExpectedEntries -Path $parentFileConflict -ExpectedNames @("_ops_log") -Message "Parent path conflict produced partial writes"

    $whatIfDestination = Join-Path $tempRoot "what-if-project"
    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $whatIfDestination, "-WhatIf")
    Assert-ExitCode $result 0 "Preview initialization"
    Assert-PathAbsent -Path $whatIfDestination -Message "WhatIf created the destination"

    $relativeParent = Join-Path $tempRoot "relative-parent"
    New-Item -ItemType Directory -Path $relativeParent | Out-Null
    Push-Location $relativeParent
    try {
        $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", "relative-project")
    }
    finally {
        Pop-Location
    }
    Assert-ExitCode $result 0 "Initialize a relative destination"
    Assert-True (Test-Path -LiteralPath (Join-Path $relativeParent "relative-project\00_WORKSPACE_INDEX.md") -PathType Leaf) "Relative destination resolved outside the current location"

    $unicodeName = "space project " + [char]0x5DE5 + [char]0x4F5C + [char]0x533A
    $unicodeDestination = Join-Path $tempRoot $unicodeName
    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $unicodeDestination)
    Assert-ExitCode $result 0 "Initialize a path with spaces and Unicode"
    Assert-True (Test-Path -LiteralPath (Join-Path $unicodeDestination "_rules.md") -PathType Leaf) "Unicode destination was not initialized"

    $providerResult = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", "Env:\TEMP")
    Assert-ExitCode $providerResult 1 "Reject a non-file-system provider"
    Assert-True ((($providerResult.Output | Out-String) -match "FileSystem")) "Provider rejection should identify the FileSystem requirement"

    $starterChild = Join-Path $starterRoot "00_DECISIONS"
    $starterBefore = (@(
        Get-ChildItem -LiteralPath $starterRoot -Recurse -Force |
            ForEach-Object {
                $size = if ($_.PSIsContainer) { "directory" } else { [string]$_.Length }
                $_.FullName + "|" + $size + "|" + $_.Attributes
            }
    )) -join "`n"
    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $starterChild)
    Assert-ExitCode $result 1 "Reject a destination inside the starter source"
    $starterAfter = (@(
        Get-ChildItem -LiteralPath $starterRoot -Recurse -Force |
            ForEach-Object {
                $size = if ($_.PSIsContainer) { "directory" } else { [string]$_.Length }
                $_.FullName + "|" + $size + "|" + $_.Attributes
            }
    )) -join "`n"
    Assert-Equal $starterAfter $starterBefore "Starter source changed after overlap rejection"

    $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $repoRoot)
    Assert-ExitCode $result 1 "Reject a destination containing the starter source"

    $rollbackDestination = Join-Path $tempRoot "rollback-project"
    $lockedSource = Join-Path $starterRoot ".ai-workspace-os\check-workspace.ps1"
    $lock = [IO.File]::Open($lockedSource, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        $result = Invoke-TestScript -ScriptPath $initWorkspace -Arguments @("-Destination", $rollbackDestination)
    }
    finally {
        $lock.Dispose()
    }
    Assert-ExitCode $result 1 "Rollback an unexpected copy failure"
    if (Test-Path -LiteralPath $rollbackDestination) {
        Assert-Equal @(Get-ChildItem -LiteralPath $rollbackDestination -Force).Count 0 "Rollback left files or non-empty directories"
    }
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

Write-Output "init-workspace.tests.ps1 passed"
