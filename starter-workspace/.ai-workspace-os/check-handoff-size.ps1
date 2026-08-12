param(
    [string]$Path = "00_agent_handoff.md",
    [int]$MaxLines = 120,
    [int]$MaxBytes = 12000,
    [int]$MaxReviewWindowDays = 14,
    [object]$EnforceExpiry = $true,
    [DateTimeOffset]$ReferenceTime,
    [switch]$ParseSafe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$enforceExpiryValue = $null
if ($EnforceExpiry -is [bool]) {
    $enforceExpiryValue = [bool]$EnforceExpiry
}
else {
    $enforceExpiryText = ([string]$EnforceExpiry).Trim()
    if ($enforceExpiryText -match '^(?i:true|\$true|1)$') {
        $enforceExpiryValue = $true
    }
    elseif ($enforceExpiryText -match '^(?i:false|\$false|0)$') {
        $enforceExpiryValue = $false
    }
    else {
        throw "EnforceExpiry must be true or false."
    }
}

$requiredSections = @(
    "Current Role",
    "Workspace Boundary",
    "Required Reading Order",
    "Hard Constraints",
    "Current State",
    "Next Step",
    "Pending Decisions"
)

function New-Issue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,
        [Nullable[int]]$Line = $null,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    return [pscustomobject][ordered]@{
        code = $Code
        line = $Line
        message = $Message
    }
}

function Get-LineNumber {
    param(
        [string]$Content,
        [int]$Index
    )

    if ($Index -le 0) {
        return 1
    }

    return ([regex]::Matches($Content.Substring(0, $Index), "\r\n|\n|\r").Count + 1)
}

function Convert-HandoffTimestamp {
    param(
        [string]$Value
    )

    $result = [ordered]@{
        valid = $false
        value = $null
    }

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return [pscustomobject]$result
    }

    $candidate = $Value.Trim()
    if ($candidate -notmatch "(?:[zZ]|[+-]\d{2}:\d{2})$") {
        return [pscustomobject]$result
    }

    $parsed = [DateTimeOffset]::MinValue
    $parsedSuccessfully = [DateTimeOffset]::TryParse(
        $candidate,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None,
        [ref]$parsed
    )

    if ($parsedSuccessfully) {
        $result.valid = $true
        $result.value = $parsed
    }

    return [pscustomobject]$result
}

$summary = [ordered]@{
    path = $Path
    exists = $false
    lineCount = 0
    byteSize = 0
    maxLines = $MaxLines
    maxBytes = $MaxBytes
    nulFound = $false
    bomFound = $false
    missingSections = @()
    historyWarnings = @()
    updatedAt = $null
    reviewBy = $null
    errors = @()
    warnings = @()
    ok = $false
}

if (-not (Test-Path -LiteralPath $Path)) {
    $summary["errors"] = @(
        New-Issue -Code "missing_file" -Message "Handoff file does not exist."
    )

    if ($ParseSafe) {
        [pscustomobject]$summary | ConvertTo-Json -Depth 8
    }
    else {
        Write-Output "Missing handoff: $Path"
    }
    exit 1
}

$summary.exists = $true
$resolvedPath = Resolve-Path -LiteralPath $Path
$bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
$summary.byteSize = $bytes.Length
$summary.nulFound = $bytes -contains 0
$summary.bomFound = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

$content = Get-Content -Raw -Encoding UTF8 -LiteralPath $Path
if ($null -eq $content) {
    $content = ""
}

$lines = @()
if ($content.Length -gt 0) {
    $lines = @([regex]::Split($content, "\r\n|\n|\r"))
    if ($lines.Count -gt 1 -and $lines[-1] -eq "") {
        $lines = @($lines[0..($lines.Count - 2)])
    }
}
$summary.lineCount = $lines.Count

$missingSections = New-Object System.Collections.Generic.List[string]
foreach ($section in $requiredSections) {
    $pattern = "(?im)^##\s+$([regex]::Escape($section))\s*$"
    if ($content -notmatch $pattern) {
        $missingSections.Add($section) | Out-Null
    }
}
$summary["missingSections"] = @($missingSections.ToArray())

$historyWarnings = New-Object System.Collections.Generic.List[string]
$historyPatterns = [ordered]@{
    "history heading" = [pscustomobject]@{
        Code = "history_heading"
        Pattern = "(?im)^##\s+(Daily Log|History|Chronological History|Change Log)\s*$"
        Message = "Handoff contains a history-style heading."
    }
    "dated log heading" = [pscustomobject]@{
        Code = "dated_log_heading"
        Pattern = "(?im)^#{2,4}\s+\d{4}-\d{2}-\d{2}\b"
        Message = "Handoff contains a dated log heading."
    }
    "long timeline wording" = [pscustomobject]@{
        Code = "timeline_wording"
        Pattern = "(?i)\b(yesterday|today|tomorrow|day\s+\d+)\b.*\b(then|after that|next)\b"
        Message = "Handoff contains timeline-style wording."
    }
}

$errors = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]

$updatedAtFields = New-Object System.Collections.Generic.List[object]
$reviewByFields = New-Object System.Collections.Generic.List[object]
for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
    $updatedAtMatch = [regex]::Match($lines[$lineIndex], "^Updated At:[ \t]*(.*?)[ \t]*$")
    if ($updatedAtMatch.Success) {
        $updatedAtFields.Add([pscustomobject]@{
            line = $lineIndex + 1
            value = $updatedAtMatch.Groups[1].Value
        }) | Out-Null
    }

    $reviewByMatch = [regex]::Match($lines[$lineIndex], "^Review By:[ \t]*(.*?)[ \t]*$")
    if ($reviewByMatch.Success) {
        $reviewByFields.Add([pscustomobject]@{
            line = $lineIndex + 1
            value = $reviewByMatch.Groups[1].Value
        }) | Out-Null
    }
}

if ($updatedAtFields.Count -eq 0) {
    $errors.Add((New-Issue -Code "missing_updated_at" -Message "Handoff is missing the Updated At field.")) | Out-Null
}
elseif ($updatedAtFields.Count -gt 1) {
    $errors.Add((New-Issue `
        -Code "duplicate_review_field" `
        -Line $updatedAtFields[1].line `
        -Message "Handoff contains more than one Updated At field."
    )) | Out-Null
}
else {
    $summary.updatedAt = $updatedAtFields[0].value
}

if ($reviewByFields.Count -eq 0) {
    $errors.Add((New-Issue -Code "missing_review_by" -Message "Handoff is missing the Review By field.")) | Out-Null
}
elseif ($reviewByFields.Count -gt 1) {
    $errors.Add((New-Issue `
        -Code "duplicate_review_field" `
        -Line $reviewByFields[1].line `
        -Message "Handoff contains more than one Review By field."
    )) | Out-Null
}
else {
    $summary.reviewBy = $reviewByFields[0].value
}

$titleLineIndex = -1
for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
    if ($lines[$lineIndex] -match '^#\s+\S') {
        $titleLineIndex = $lineIndex
        break
    }
}

if ($titleLineIndex -ge 0 -and $updatedAtFields.Count -eq 1 -and $reviewByFields.Count -eq 1) {
    $firstMetadataIndex = $titleLineIndex + 1
    while ($firstMetadataIndex -lt $lines.Count -and [string]::IsNullOrWhiteSpace($lines[$firstMetadataIndex])) {
        $firstMetadataIndex++
    }

    $secondMetadataIndex = $firstMetadataIndex + 1
    if (
        $updatedAtFields[0].line -ne ($firstMetadataIndex + 1) -or
        $reviewByFields[0].line -ne ($secondMetadataIndex + 1)
    ) {
        $errors.Add((New-Issue `
            -Code "invalid_review_field_location" `
            -Line $updatedAtFields[0].line `
            -Message "Updated At and Review By must appear directly below the handoff title."
        )) | Out-Null
    }
}

$parsedUpdatedAt = $null
$parsedReviewBy = $null
if ($updatedAtFields.Count -eq 1) {
    if ([string]::Equals($updatedAtFields[0].value, "{{UPDATED_AT}}", [StringComparison]::Ordinal)) {
        $warnings.Add((New-Issue `
            -Code "unresolved_review_placeholder" `
            -Line $updatedAtFields[0].line `
            -Message "A starter handoff review timestamp remains unresolved."
        )) | Out-Null
    }
    else {
        $parsedUpdatedAt = Convert-HandoffTimestamp -Value $updatedAtFields[0].value
    }
    if ($null -ne $parsedUpdatedAt -and -not $parsedUpdatedAt.valid) {
        $errors.Add((New-Issue `
            -Code "invalid_updated_at" `
            -Line $updatedAtFields[0].line `
            -Message "Updated At must be an ISO 8601 timestamp with an explicit UTC offset."
        )) | Out-Null
    }
}

if ($reviewByFields.Count -eq 1) {
    if ([string]::Equals($reviewByFields[0].value, "{{REVIEW_BY}}", [StringComparison]::Ordinal)) {
        $warnings.Add((New-Issue `
            -Code "unresolved_review_placeholder" `
            -Line $reviewByFields[0].line `
            -Message "A starter handoff review timestamp remains unresolved."
        )) | Out-Null
    }
    else {
        $parsedReviewBy = Convert-HandoffTimestamp -Value $reviewByFields[0].value
    }
    if ($null -ne $parsedReviewBy -and -not $parsedReviewBy.valid) {
        $errors.Add((New-Issue `
            -Code "invalid_review_by" `
            -Line $reviewByFields[0].line `
            -Message "Review By must be an ISO 8601 timestamp with an explicit UTC offset."
        )) | Out-Null
    }
}

if (
    $null -ne $parsedUpdatedAt -and $parsedUpdatedAt.valid -and
    $null -ne $parsedReviewBy -and $parsedReviewBy.valid
) {
    if ($parsedReviewBy.value -le $parsedUpdatedAt.value) {
        $errors.Add((New-Issue `
            -Code "invalid_review_order" `
            -Line $reviewByFields[0].line `
            -Message "Review By must be later than Updated At."
        )) | Out-Null
    }
    else {
        $reviewWindow = $parsedReviewBy.value - $parsedUpdatedAt.value
        if ($reviewWindow.TotalDays -gt $MaxReviewWindowDays) {
            $errors.Add((New-Issue `
                -Code "review_window_exceeded" `
                -Line $reviewByFields[0].line `
                -Message "Handoff review window exceeds the configured maximum."
            )) | Out-Null
        }
    }

    $effectiveReferenceTime = if ($PSBoundParameters.ContainsKey("ReferenceTime")) {
        $ReferenceTime
    }
    else {
        [DateTimeOffset]::UtcNow
    }

    if ($enforceExpiryValue -and $parsedReviewBy.value -lt $effectiveReferenceTime) {
        $warnings.Add((New-Issue `
            -Code "handoff_review_expired" `
            -Line $reviewByFields[0].line `
            -Message "Handoff review date has passed."
        )) | Out-Null
    }
}

if ($summary.nulFound) {
    $errors.Add((New-Issue -Code "nul_byte" -Message "Handoff contains a NUL byte.")) | Out-Null
}

if ($summary.lineCount -gt $summary.maxLines) {
    $errors.Add((New-Issue -Code "max_lines_exceeded" -Message "Handoff exceeds the maximum line count.")) | Out-Null
}

if ($summary.byteSize -gt $summary.maxBytes) {
    $errors.Add((New-Issue -Code "max_bytes_exceeded" -Message "Handoff exceeds the maximum byte size.")) | Out-Null
}

foreach ($section in $summary.missingSections) {
    $errors.Add((New-Issue -Code "missing_section" -Message "Missing required section: ## $section.")) | Out-Null
}

if ($summary.bomFound) {
    $warnings.Add((New-Issue -Code "utf8_bom" -Line 1 -Message "Handoff starts with a UTF-8 BOM.")) | Out-Null
}

foreach ($label in $historyPatterns.Keys) {
    $definition = $historyPatterns[$label]
    $match = [regex]::Match($content, $definition.Pattern)
    if ($match.Success) {
        $historyWarnings.Add($label) | Out-Null
        $warnings.Add((New-Issue `
            -Code $definition.Code `
            -Line (Get-LineNumber -Content $content -Index $match.Index) `
            -Message $definition.Message
        )) | Out-Null
    }
}
$summary["historyWarnings"] = @($historyWarnings.ToArray())
$summary["errors"] = @($errors.ToArray())
$summary["warnings"] = @($warnings.ToArray())

$summary["ok"] = ($summary.errors.Count -eq 0)

if ($ParseSafe) {
    [pscustomobject]$summary | ConvertTo-Json -Depth 8
}
else {
    Write-Output "Handoff: $Path"
    Write-Output "Lines: $($summary.lineCount) / $($summary.maxLines)"
    Write-Output "Bytes: $($summary.byteSize) / $($summary.maxBytes)"
    Write-Output "NUL found: $($summary.nulFound)"
    Write-Output "BOM found: $($summary.bomFound)"
    Write-Output "Updated At: $($summary.updatedAt)"
    Write-Output "Review By: $($summary.reviewBy)"

    if ($summary.missingSections.Count -gt 0) {
        Write-Output "Missing sections: $($summary.missingSections -join ', ')"
    }

    if ($summary.historyWarnings.Count -gt 0) {
        Write-Output "History warnings: $($summary.historyWarnings -join ', ')"
    }

    if ($summary.errors.Count -gt 0) {
        Write-Output "Errors: $($summary.errors.code -join ', ')"
    }

    if ($summary.warnings.Count -gt 0) {
        Write-Output "Warnings: $($summary.warnings.code -join ', ')"
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
