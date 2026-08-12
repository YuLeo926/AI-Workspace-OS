param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Title,

    [string]$Destination = "00_DECISIONS",
    [string]$TemplatePath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Resolve-TemplatePath {
    param([string]$RequestedPath)

    if (-not [string]::IsNullOrWhiteSpace($RequestedPath)) {
        if (Test-Path -LiteralPath $RequestedPath) {
            return (Resolve-Path -LiteralPath $RequestedPath).Path
        }
        throw "Template not found: $RequestedPath"
    }

    $repoTemplate = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")) "templates\ADR-template.md"
    if (Test-Path -LiteralPath $repoTemplate) {
        return (Resolve-Path -LiteralPath $repoTemplate).Path
    }

    $cwdTemplate = Join-Path (Get-Location) "templates\ADR-template.md"
    if (Test-Path -LiteralPath $cwdTemplate) {
        return (Resolve-Path -LiteralPath $cwdTemplate).Path
    }

    throw "Template not found. Pass -TemplatePath or run from the repository root."
}

function ConvertTo-Slug {
    param([string]$Value)

    $slug = $Value.ToLowerInvariant()
    $slug = $slug -replace "[^a-z0-9]+", "-"
    $slug = $slug.Trim("-")

    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "decision"
    }

    return $slug
}

function Resolve-DestinationPath {
    param([string]$RequestedPath)

    if ([System.IO.Path]::IsPathRooted($RequestedPath)) {
        return $RequestedPath
    }

    return (Join-Path (Get-Location) $RequestedPath)
}

$template = Resolve-TemplatePath -RequestedPath $TemplatePath
$destinationPath = Resolve-DestinationPath -RequestedPath $Destination
New-Item -ItemType Directory -Force -Path $destinationPath | Out-Null

$existingNumbers = @(
    Get-ChildItem -LiteralPath $destinationPath -Filter "ADR-*.md" -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.BaseName -match "^ADR-(\d{3})") {
                [int]$Matches[1]
            }
        }
)

$nextNumber = 1
if ($existingNumbers.Count -gt 0) {
    $nextNumber = ([int](($existingNumbers | Measure-Object -Maximum).Maximum)) + 1
}

$number = "{0:D3}" -f $nextNumber
$date = Get-Date -Format "yyyy-MM-dd"
$slug = ConvertTo-Slug -Value $Title
$fileName = "ADR-$number-$date-$slug.md"
$targetPath = Join-Path $destinationPath $fileName

if (Test-Path -LiteralPath $targetPath) {
    throw "ADR already exists: $targetPath"
}

$content = Get-Content -Raw -Encoding UTF8 -LiteralPath $template
$content = $content.Replace("{{NUMBER}}", $number)
$content = $content.Replace("{{TITLE}}", $Title)
$content = $content.Replace("{{DATE}}", $date)

Set-Content -LiteralPath $targetPath -Encoding UTF8 -Value $content

Write-Output "Created ADR: $targetPath"
exit 0
