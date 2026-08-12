Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$NewAdr = Join-Path $RepoRoot "scripts\new-adr.ps1"
$tempRoot = New-TestDirectory -Prefix "ai-workspace-os-new-adr-tests-"

try {
    Assert-True (Test-Path -LiteralPath $NewAdr) "Missing script: $NewAdr"

    $decisionsDir = Join-Path $tempRoot "decisions"
    $firstResult = Invoke-TestScript -ScriptPath $NewAdr -Arguments @("-Title", "Choose file first memory", "-Destination", $decisionsDir)
    Assert-ExitCode $firstResult 0 "First ADR"
    $adrFiles = @(Get-ChildItem -LiteralPath $decisionsDir -Filter "ADR-*.md")
    Assert-True ($adrFiles.Count -eq 1) "new-adr should create exactly one ADR file"
    Assert-True ($adrFiles[0].Name -match "^ADR-001-\d{4}-\d{2}-\d{2}-choose-file-first-memory\.md$") "First ADR filename should use sequence 001"
    $firstText = Get-Content -Raw -LiteralPath $adrFiles[0].FullName
    Assert-True ($firstText -match "# ADR 001: Choose file first memory") "new-adr should replace title placeholder"
    Assert-True ($firstText -match "Date: \d{4}-\d{2}-\d{2}") "new-adr should replace date placeholder"

    $secondResult = Invoke-TestScript -ScriptPath $NewAdr -Arguments @("-Title", "Keep ownership explicit", "-Destination", $decisionsDir)
    Assert-ExitCode $secondResult 0 "Second ADR"
    $secondFile = @(Get-ChildItem -LiteralPath $decisionsDir -Filter "ADR-002-*.md")
    Assert-True ($secondFile.Count -eq 1) "Second ADR should use sequence 002"
    Assert-True ($secondFile[0].Name -match "^ADR-002-\d{4}-\d{2}-\d{2}-keep-ownership-explicit\.md$") "Second ADR filename should use sequence 002"

    $unicodeResult = Invoke-TestScript -ScriptPath $NewAdr -Arguments @("-Title", "文件优先记忆", "-Destination", $decisionsDir)
    Assert-ExitCode $unicodeResult 0 "Non-ASCII ADR"
    $unicodeFile = @(Get-ChildItem -LiteralPath $decisionsDir -Filter "ADR-003-*.md")
    Assert-True ($unicodeFile.Count -eq 1) "Non-ASCII ADR should use sequence 003"
    Assert-True ($unicodeFile[0].Name -match "^ADR-003-\d{4}-\d{2}-\d{2}-decision\.md$") "Non-ASCII-only title should use the decision slug"
    $unicodeText = Get-Content -Raw -LiteralPath $unicodeFile[0].FullName
    Assert-True ($unicodeText -match "# ADR 003: 文件优先记忆") "Non-ASCII title should remain intact in ADR content"

    $customTemplate = Join-Path $tempRoot "custom-adr-template.md"
    Write-Utf8NoBom -Path $customTemplate -Content "# Custom ADR {{NUMBER}}: {{TITLE}}`n`nRecorded: {{DATE}}`n"
    $customResult = Invoke-TestScript -ScriptPath $NewAdr -Arguments @(
        "-Title", "Use explicit template",
        "-Destination", $decisionsDir,
        "-TemplatePath", $customTemplate
    )
    Assert-ExitCode $customResult 0 "Custom-template ADR"
    $customFile = @(Get-ChildItem -LiteralPath $decisionsDir -Filter "ADR-004-*.md")
    Assert-True ($customFile.Count -eq 1) "Custom-template ADR should use sequence 004"
    $customText = Get-Content -Raw -LiteralPath $customFile[0].FullName
    Assert-True ($customText -match "# Custom ADR 004: Use explicit template") "Explicit TemplatePath should control ADR content"
    Assert-True ($customText -match "Recorded: \d{4}-\d{2}-\d{2}") "Explicit template date placeholder should be replaced"

    $englishReadme = Read-Utf8Strict -Path (Join-Path $RepoRoot "README.md")
    $chineseReadme = Read-Utf8Strict -Path (Join-Path $RepoRoot "README.zh-CN.md")
    Assert-True ($chineseReadme.Length -lt $englishReadme.Length) "Chinese README should remain shorter than the primary English README"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
