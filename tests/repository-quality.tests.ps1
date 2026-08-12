Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
$repoPrefix = $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$violations = New-Object System.Collections.Generic.List[object]

function Get-RepositoryRelativePath {
    param([string]$FullName)

    return $FullName.Substring($repoPrefix.Length).Replace("\", "/")
}

function Add-QualityViolation {
    param([string]$Rule, [string]$Path)

    $violations.Add([pscustomobject]@{ Rule = $Rule; Path = $Path }) | Out-Null
}

function Test-IsExcludedPath {
    param([string]$RelativePath)

    $normalized = "/" + $RelativePath.Replace("\", "/")
    $excludedPrefixes = @(
        "/.git/",
        "/.private/",
        "/docs/superpowers/",
        "/node_modules/",
        "/dist/",
        "/build/",
        "/coverage/",
        "/.cache/",
        "/.pytest_cache/",
        "/artifacts/",
        "/temp/",
        "/tmp/"
    )

    foreach ($prefix in $excludedPrefixes) {
        if ($normalized.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    $name = [IO.Path]::GetFileName($RelativePath)
    if ($name -in @(".DS_Store", "Thumbs.db") -or
        $name.EndsWith("~", [StringComparison]::Ordinal) -or
        $name -match "(?i)\.(tmp|temp|bak|swp|swo)$") {
        return $true
    }

    return $false
}

function Test-IsTextFile {
    param([string]$RelativePath)

    $name = [IO.Path]::GetFileName($RelativePath)
    if ($name -in @(".editorconfig", ".gitattributes", ".gitignore", "LICENSE")) {
        return $true
    }

    return ([IO.Path]::GetExtension($RelativePath).ToLowerInvariant() -in @(
        ".md", ".ps1", ".sh", ".py", ".js", ".jsx", ".ts", ".tsx",
        ".json", ".jsonl", ".yml", ".yaml", ".toml", ".ini", ".cfg",
        ".conf", ".txt", ".csv", ".xml", ".html", ".css", ".scss"
    ))
}

function Test-FileBytesEqual {
    param(
        [string]$FirstPath,
        [string]$SecondPath
    )

    $firstBytes = [IO.File]::ReadAllBytes($FirstPath)
    $secondBytes = [IO.File]::ReadAllBytes($SecondPath)
    if ($firstBytes.Length -ne $secondBytes.Length) {
        return $false
    }

    for ($index = 0; $index -lt $firstBytes.Length; $index++) {
        if ($firstBytes[$index] -ne $secondBytes[$index]) {
            return $false
        }
    }

    return $true
}

$requiredPublicFiles = @(
    "docs/authorization.md",
    "templates/delegation-entry.jsonl",
    "AGENTS.md",
    "CLAUDE.md",
    "starter-workspace/AGENTS.md",
    "starter-workspace/CLAUDE.md",
    "examples/solo-business-workspace/AGENTS.md",
    "examples/solo-business-workspace/CLAUDE.md"
)

foreach ($relativePath in $requiredPublicFiles) {
    $fullPath = Join-Path $repoRoot $relativePath.Replace("/", [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.File]::Exists($fullPath)) {
        Add-QualityViolation -Rule "missing_required_public_file" -Path $relativePath
    }
}

$claudeImportPaths = @(
    "CLAUDE.md",
    "starter-workspace/CLAUDE.md",
    "examples/solo-business-workspace/CLAUDE.md"
)
$expectedClaudeImport = "@AGENTS.md`n"

foreach ($relativePath in $claudeImportPaths) {
    $fullPath = Join-Path $repoRoot $relativePath.Replace("/", [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.File]::Exists($fullPath)) {
        continue
    }

    try {
        $content = [IO.File]::ReadAllText($fullPath, $utf8)
        if (-not [string]::Equals($content, $expectedClaudeImport, [StringComparison]::Ordinal)) {
            Add-QualityViolation -Rule "invalid_claude_import" -Path $relativePath
        }
    }
    catch {
        Add-QualityViolation -Rule "invalid_utf8" -Path $relativePath
    }
}

$shippedValidatorNames = @(
    "WorkspacePolicy.ps1",
    "check-workspace-policy.ps1",
    "check-delegations.ps1",
    "check-write-authorization.ps1",
    "check-handoff-size.ps1",
    "check-ops-log.ps1",
    "check-workspace.ps1"
)
$shippedValidatorRoots = @(
    "starter-workspace/.ai-workspace-os",
    "examples/solo-business-workspace/.ai-workspace-os"
)

foreach ($validatorName in $shippedValidatorNames) {
    $sourceRelativePath = "scripts/$validatorName"
    $sourcePath = Join-Path $repoRoot $sourceRelativePath.Replace("/", [IO.Path]::DirectorySeparatorChar)
    if (-not [IO.File]::Exists($sourcePath)) {
        Add-QualityViolation -Rule "missing_validator_source" -Path $sourceRelativePath
        continue
    }

    foreach ($copyRoot in $shippedValidatorRoots) {
        $copyRelativePath = "$copyRoot/$validatorName"
        $copyPath = Join-Path $repoRoot $copyRelativePath.Replace("/", [IO.Path]::DirectorySeparatorChar)
        if (-not [IO.File]::Exists($copyPath)) {
            Add-QualityViolation -Rule "missing_shipped_validator" -Path $copyRelativePath
            continue
        }

        if (-not (Test-FileBytesEqual -FirstPath $sourcePath -SecondPath $copyPath)) {
            Add-QualityViolation -Rule "shipped_validator_drift" -Path $copyRelativePath
        }
    }
}

$files = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File | Where-Object {
    $relativePath = Get-RepositoryRelativePath -FullName $_.FullName
    -not (Test-IsExcludedPath -RelativePath $relativePath)
})

$sensitiveRules = @(
    [pscustomobject]@{
        Name = "windows_user_path"
        Pattern = "(?i)\b[A-Z]:" + "[\\/]+Users[\\/]+" + "[^\\/\s]+"
    },
    [pscustomobject]@{
        Name = "private_drive_path"
        Pattern = "(?i)\b" + "E:" + "[\\/]+"
    },
    [pscustomobject]@{
        Name = "internal_thread_marker"
        Pattern = "(?i)\b" + "source_" + "thread_id\b"
    },
    [pscustomobject]@{
        Name = "openai_api_key"
        Pattern = "\bsk-" + "[A-Za-z0-9_-]{20,}\b"
    },
    [pscustomobject]@{
        Name = "github_token"
        Pattern = "\bgh" + "[pousr]_[A-Za-z0-9]{20,}\b"
    },
    [pscustomobject]@{
        Name = "aws_access_key"
        Pattern = "\bAK" + "IA[0-9A-Z]{16}\b"
    },
    [pscustomobject]@{
        Name = "google_api_key"
        Pattern = "\bAI" + "za[0-9A-Za-z_-]{35}\b"
    },
    [pscustomobject]@{
        Name = "slack_token"
        Pattern = "\bxox" + "[abprs]-[A-Za-z0-9-]{20,}\b"
    },
    [pscustomobject]@{
        Name = "jwt_token"
        Pattern = "\bey" + "J[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"
    },
    [pscustomobject]@{
        Name = "private_key_block"
        Pattern = "-----BEGIN " + "(?:RSA |EC |OPENSSH )?PRIVATE KEY-----"
    }
)

foreach ($file in $files) {
    $relativePath = Get-RepositoryRelativePath -FullName $file.FullName
    if (-not (Test-IsTextFile -RelativePath $relativePath)) {
        continue
    }

    try {
        $rawBytes = [IO.File]::ReadAllBytes($file.FullName)
        if (
            $rawBytes.Length -ge 3 -and
            $rawBytes[0] -eq 0xEF -and
            $rawBytes[1] -eq 0xBB -and
            $rawBytes[2] -eq 0xBF
        ) {
            Add-QualityViolation -Rule "utf8_bom" -Path $relativePath
        }
        $content = [IO.File]::ReadAllText($file.FullName, $utf8)
    }
    catch {
        Add-QualityViolation -Rule "invalid_utf8" -Path $relativePath
        continue
    }

    foreach ($rule in $sensitiveRules) {
        if ([regex]::IsMatch($content, $rule.Pattern)) {
            Add-QualityViolation -Rule $rule.Name -Path $relativePath
        }
    }

    if ([IO.Path]::GetExtension($relativePath).ToLowerInvariant() -ne ".md") {
        continue
    }

    $linkPattern = "!?\[[^\]]*\]\((?<target>[^)\r\n]+)\)"
    foreach ($match in [regex]::Matches($content, $linkPattern)) {
        $target = $match.Groups["target"].Value.Trim()
        if ($target.StartsWith("<", [StringComparison]::Ordinal)) {
            $closing = $target.IndexOf(">", [StringComparison]::Ordinal)
            if ($closing -gt 0) {
                $target = $target.Substring(1, $closing - 1)
            }
        }
        else {
            $target = ($target -split "\s+", 2)[0]
        }

        if ([string]::IsNullOrWhiteSpace($target) -or
            $target.StartsWith("#", [StringComparison]::Ordinal) -or
            $target.StartsWith("//", [StringComparison]::Ordinal) -or
            $target -match "^[A-Za-z][A-Za-z0-9+.-]*:") {
            continue
        }

        $pathOnly = ($target -split "[#?]", 2)[0]
        if ([string]::IsNullOrWhiteSpace($pathOnly)) {
            continue
        }

        try {
            $decodedPath = [Uri]::UnescapeDataString($pathOnly).Replace("/", [IO.Path]::DirectorySeparatorChar)
            $candidate = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $decodedPath))
            $insideRepository = $candidate.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or
                $candidate.Equals($repoRoot, [StringComparison]::OrdinalIgnoreCase)
            if (-not $insideRepository -or -not (Test-Path -LiteralPath $candidate)) {
                Add-QualityViolation -Rule "invalid_local_markdown_link" -Path $relativePath
            }
        }
        catch {
            Add-QualityViolation -Rule "invalid_local_markdown_link" -Path $relativePath
        }
    }
}

if ($violations.Count -gt 0) {
    $safeLines = @($violations | Sort-Object Rule, Path -Unique | ForEach-Object { "$($_.Rule) $($_.Path)" })
    foreach ($safeLine in $safeLines) {
        Write-Host $safeLine
    }
    exit 1
}

Write-Host "repository-quality.tests.ps1 passed"
