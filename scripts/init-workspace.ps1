[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = "Low")]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Destination
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-NormalizedFileSystemPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $provider = $null
    $drive = $null

    try {
        $resolved = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
            $Path,
            [ref]$provider,
            [ref]$drive
        )
    }
    catch {
        throw "Cannot resolve the destination path. Use a valid FileSystem path."
    }

    if ($null -eq $provider -or $provider.Name -ne "FileSystem") {
        throw "Destination must use the FileSystem provider."
    }

    $fullPath = [IO.Path]::GetFullPath($resolved)
    $root = [IO.Path]::GetPathRoot($fullPath)
    if ($fullPath.Length -gt $root.Length) {
        return $fullPath.TrimEnd([char[]]@([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    }

    return $fullPath
}

function Test-PathEqualOrUnder {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate,

        [Parameter(Mandatory = $true)]
        [string]$Parent
    )

    if ([string]::Equals($Candidate, $Parent, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $prefix = $Parent
    if (-not $prefix.EndsWith([IO.Path]::DirectorySeparatorChar.ToString())) {
        $prefix += [IO.Path]::DirectorySeparatorChar
    }

    return $Candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-ExistingPathChainIsSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $cursor = $Path
    while (-not [string]::IsNullOrEmpty($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Destination path cannot pass through a reparse point."
            }

            if (-not $item.PSIsContainer) {
                if ([string]::Equals($cursor, $Path, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Destination exists and is not a directory."
                }

                throw "An existing destination ancestor is not a directory."
            }
        }

        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) {
            break
        }

        $next = $parent.FullName
        if ([string]::Equals($next, $cursor, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }

        $cursor = $next
    }
}

function Assert-NoReparsePointsBelow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
        return
    }

    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($Root)

    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $current -Force)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Destination contains a reparse point."
            }

            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
            }
        }
    }
}

function Get-StarterCopyPlan {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot
    )

    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        throw "The starter workspace is missing."
    }

    $sourcePrefix = $SourceRoot
    if (-not $sourcePrefix.EndsWith([IO.Path]::DirectorySeparatorChar.ToString())) {
        $sourcePrefix += [IO.Path]::DirectorySeparatorChar
    }

    $entries = New-Object 'System.Collections.Generic.List[object]'
    $pending = New-Object 'System.Collections.Generic.Stack[string]'
    $pending.Push($SourceRoot)

    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $current -Force)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "The starter workspace cannot contain reparse points."
            }

            $sourcePath = [IO.Path]::GetFullPath($item.FullName)
            if (-not $sourcePath.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
                throw "A starter entry resolves outside the starter workspace."
            }

            $relativePath = $sourcePath.Substring($sourcePrefix.Length)
            $targetPath = [IO.Path]::GetFullPath((Join-Path $DestinationRoot $relativePath))
            if (-not (Test-PathEqualOrUnder -Candidate $targetPath -Parent $DestinationRoot)) {
                throw "A starter entry resolves outside the destination."
            }

            $entries.Add([pscustomobject]@{
                SourcePath = $sourcePath
                TargetPath = $targetPath
                RelativePath = $relativePath
                IsDirectory = [bool]$item.PSIsContainer
            }) | Out-Null

            if ($item.PSIsContainer) {
                $pending.Push($sourcePath)
            }
        }
    }

    return @($entries.ToArray())
}

function Get-MissingDestinationAncestors {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $missing = New-Object 'System.Collections.Generic.List[string]'
    $cursor = $Path

    while (-not (Test-Path -LiteralPath $cursor)) {
        $missing.Add($cursor) | Out-Null
        $parent = [IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) {
            break
        }
        $cursor = $parent.FullName
    }

    return @($missing | Sort-Object { $_.Length })
}

function Remove-NewInitializationItems {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$Files,

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$Directories
    )

    for ($index = $Files.Count - 1; $index -ge 0; $index--) {
        $path = $Files[$index]
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    $orderedDirectories = @($Directories | Sort-Object { $_.Length } -Descending)
    foreach ($path in $orderedDirectories) {
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            continue
        }

        if (@(Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
}

$repoRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$starterRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot "starter-workspace"))
$destinationRoot = Get-NormalizedFileSystemPath -Path $Destination

if ((Test-PathEqualOrUnder -Candidate $destinationRoot -Parent $starterRoot) -or
    (Test-PathEqualOrUnder -Candidate $starterRoot -Parent $destinationRoot)) {
    throw "Destination and starter workspace must not contain one another."
}

Assert-ExistingPathChainIsSafe -Path $destinationRoot
Assert-NoReparsePointsBelow -Root $destinationRoot

$copyPlan = @(Get-StarterCopyPlan -SourceRoot $starterRoot -DestinationRoot $destinationRoot)
foreach ($entry in $copyPlan) {
    if (Test-Path -LiteralPath $entry.TargetPath) {
        $targetItem = Get-Item -LiteralPath $entry.TargetPath -Force
        $isReparsePoint = (($targetItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
        if (-not $entry.IsDirectory -or -not $targetItem.PSIsContainer -or $isReparsePoint) {
            throw "Destination conflict at '$($entry.RelativePath)'. No files were written."
        }
    }

    $parentPath = [IO.Path]::GetDirectoryName($entry.TargetPath)
    while (-not [string]::IsNullOrEmpty($parentPath) -and
        -not [string]::Equals($parentPath, $destinationRoot, [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $parentPath) {
            $parentItem = Get-Item -LiteralPath $parentPath -Force
            if (-not $parentItem.PSIsContainer) {
                throw "A required destination parent is not a directory: '$($entry.RelativePath)'."
            }
            if (($parentItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "A required destination parent is a reparse point."
            }
        }
        $parentPath = [IO.Path]::GetDirectoryName($parentPath)
    }
}

$missingAncestors = @(Get-MissingDestinationAncestors -Path $destinationRoot)
$directoryPlan = @(
    $copyPlan |
        Where-Object { $_.IsDirectory } |
        Sort-Object @{ Expression = { ($_.RelativePath -split '[\\/]').Count } }, RelativePath
)
$filePlan = @($copyPlan | Where-Object { -not $_.IsDirectory } | Sort-Object RelativePath)

if (-not $PSCmdlet.ShouldProcess($destinationRoot, "Initialize the complete AI Workspace OS starter workspace")) {
    return
}

$createdFiles = New-Object 'System.Collections.Generic.List[string]'
$createdDirectories = New-Object 'System.Collections.Generic.List[string]'
$currentRelativePath = "destination directories"

try {
    foreach ($path in $missingAncestors) {
        [IO.Directory]::CreateDirectory($path) | Out-Null
        $createdDirectories.Add($path) | Out-Null
    }

    foreach ($entry in $directoryPlan) {
        $currentRelativePath = $entry.RelativePath
        if (-not (Test-Path -LiteralPath $entry.TargetPath -PathType Container)) {
            [IO.Directory]::CreateDirectory($entry.TargetPath) | Out-Null
            $createdDirectories.Add($entry.TargetPath) | Out-Null
        }
    }

    foreach ($entry in $filePlan) {
        $currentRelativePath = $entry.RelativePath
        $sourceStream = $null
        $targetStream = $null
        try {
            $sourceStream = [IO.File]::Open(
                $entry.SourcePath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::Read
            )
            $targetStream = [IO.File]::Open(
                $entry.TargetPath,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None
            )
            $createdFiles.Add($entry.TargetPath) | Out-Null
            $sourceStream.CopyTo($targetStream)
        }
        finally {
            if ($null -ne $targetStream) {
                $targetStream.Dispose()
            }
            if ($null -ne $sourceStream) {
                $sourceStream.Dispose()
            }
        }
    }
}
catch {
    Remove-NewInitializationItems -Files $createdFiles -Directories $createdDirectories
    throw "Initialization failed while creating '$currentRelativePath'. New items from this run were rolled back."
}

Write-Output "AI Workspace OS initialized at: $destinationRoot"
Write-Output "Fill in: 00_WORKSPACE_INDEX.md, 00_THIS_WEEK.md, and 00_agent_handoff.md"
Write-Output "Review: AGENTS.md, workspace-policy.json, and _rules.md"
Write-Output "Authorization: .ai-workspace-os\check-write-authorization.ps1"
Write-Output "Check: .ai-workspace-os\check-workspace.ps1 -Path ."
