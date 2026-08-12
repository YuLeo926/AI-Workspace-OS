param(
    [string]$Path = "_ops_log/agent_action_log.jsonl",
    [switch]$ParseSafe
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-Issue {
    param(
        [string]$Code,
        [AllowNull()]
        [object]$Line,
        [string]$Message
    )

    [pscustomobject][ordered]@{
        code = $Code
        line = $Line
        message = $Message
    }
}

function Add-Issue {
    param(
        [System.Collections.Generic.List[object]]$Collection,
        [string]$Code,
        [AllowNull()]
        [object]$Line,
        [string]$Message
    )

    $Collection.Add((New-Issue -Code $Code -Line $Line -Message $Message)) | Out-Null
}

function Test-HasProperty {
    param(
        [object]$InputObject,
        [string]$Name
    )

    return ($null -ne $InputObject -and $null -ne $InputObject.PSObject.Properties[$Name])
}

function Test-IsJsonObject {
    param([object]$InputObject)

    return ($null -ne $InputObject -and $InputObject -is [pscustomobject])
}

function Test-IsIsoTimestamp {
    param([string]$Value)

    if ($Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$') {
        return $false
    }

    $parsed = [DateTimeOffset]::MinValue
    return [DateTimeOffset]::TryParse(
        $Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )
}

function Test-EntryContract {
    param(
        [pscustomobject]$Entry,
        [int]$LineNumber,
        [System.Collections.Generic.List[object]]$Errors
    )

    $initialErrorCount = $Errors.Count
    $approvalStates = @("explicit", "delegated", "suggested", "not_required")
    $writeTypes = @("direct_owner_write", "delegated_write", "suggestion")
    $requiredStrings = @("timestamp", "agent_or_role", "action", "target", "rollback_hint")

    foreach ($name in $requiredStrings) {
        if (-not (Test-HasProperty -InputObject $Entry -Name $name)) {
            Add-Issue -Collection $Errors -Code "missing_required_field" -Line $LineNumber -Message "Required field '$name' is missing."
            continue
        }

        $value = $Entry.PSObject.Properties[$name].Value
        if (-not ($value -is [string]) -or [string]::IsNullOrWhiteSpace([string]$value)) {
            Add-Issue -Collection $Errors -Code "invalid_field_type" -Line $LineNumber -Message "Field '$name' must be a nonempty string."
        }
    }

    if (
        (Test-HasProperty -InputObject $Entry -Name "timestamp") -and
        $Entry.timestamp -is [string] -and
        -not [string]::IsNullOrWhiteSpace([string]$Entry.timestamp) -and
        -not (Test-IsIsoTimestamp -Value ([string]$Entry.timestamp))
    ) {
        Add-Issue -Collection $Errors -Code "invalid_timestamp" -Line $LineNumber -Message "Field 'timestamp' must be a parseable ISO 8601 timestamp."
    }

    if (-not (Test-HasProperty -InputObject $Entry -Name "approval_state")) {
        Add-Issue -Collection $Errors -Code "missing_required_field" -Line $LineNumber -Message "Required field 'approval_state' is missing."
    }
    elseif (-not ($Entry.approval_state -is [string])) {
        Add-Issue -Collection $Errors -Code "invalid_field_type" -Line $LineNumber -Message "Field 'approval_state' must be a string."
    }
    elseif ($approvalStates -notcontains [string]$Entry.approval_state) {
        Add-Issue -Collection $Errors -Code "invalid_approval_state" -Line $LineNumber -Message "Field 'approval_state' is not an allowed value."
    }

    if (-not (Test-HasProperty -InputObject $Entry -Name "files_changed")) {
        Add-Issue -Collection $Errors -Code "missing_required_field" -Line $LineNumber -Message "Required field 'files_changed' is missing."
    }
    elseif (-not ($Entry.files_changed -is [System.Array])) {
        Add-Issue -Collection $Errors -Code "invalid_field_type" -Line $LineNumber -Message "Field 'files_changed' must be an array of strings."
    }
    else {
        foreach ($file in @($Entry.files_changed)) {
            if (-not ($file -is [string])) {
                Add-Issue -Collection $Errors -Code "invalid_field_type" -Line $LineNumber -Message "Field 'files_changed' must contain only strings."
                break
            }
        }
    }

    if (-not (Test-HasProperty -InputObject $Entry -Name "note")) {
        Add-Issue -Collection $Errors -Code "missing_required_field" -Line $LineNumber -Message "Required field 'note' is missing."
    }
    elseif (-not ($Entry.note -is [string])) {
        Add-Issue -Collection $Errors -Code "invalid_field_type" -Line $LineNumber -Message "Field 'note' must be a string."
    }

    if (-not (Test-HasProperty -InputObject $Entry -Name "role_check")) {
        return ($Errors.Count -eq $initialErrorCount)
    }

    $roleCheck = $Entry.role_check
    if (-not (Test-IsJsonObject -InputObject $roleCheck)) {
        Add-Issue -Collection $Errors -Code "invalid_role_check" -Line $LineNumber -Message "Field 'role_check' must be an object when present."
        return ($Errors.Count -eq $initialErrorCount)
    }

    foreach ($name in @("actor_role", "owner_role", "authorization")) {
        if (-not (Test-HasProperty -InputObject $roleCheck -Name $name)) {
            Add-Issue -Collection $Errors -Code "missing_required_field" -Line $LineNumber -Message "Required role_check field '$name' is missing."
            continue
        }

        $value = $roleCheck.PSObject.Properties[$name].Value
        if (-not ($value -is [string]) -or [string]::IsNullOrWhiteSpace([string]$value)) {
            Add-Issue -Collection $Errors -Code "invalid_field_type" -Line $LineNumber -Message "Field 'role_check.$name' must be a nonempty string."
        }
    }

    if (-not (Test-HasProperty -InputObject $roleCheck -Name "write_type")) {
        Add-Issue -Collection $Errors -Code "missing_required_field" -Line $LineNumber -Message "Required role_check field 'write_type' is missing."
    }
    elseif (-not ($roleCheck.write_type -is [string])) {
        Add-Issue -Collection $Errors -Code "invalid_field_type" -Line $LineNumber -Message "Field 'role_check.write_type' must be a string."
    }
    elseif ($writeTypes -notcontains [string]$roleCheck.write_type) {
        Add-Issue -Collection $Errors -Code "invalid_write_type" -Line $LineNumber -Message "Field 'role_check.write_type' is not an allowed value."
    }

    return ($Errors.Count -eq $initialErrorCount)
}

function New-Summary {
    param([string]$LogPath)

    [ordered]@{
        path = $LogPath
        exists = $false
        lineCount = 0
        blankLines = 0
        nulFound = $false
        bomFound = $false
        validJsonLines = 0
        invalidJsonLines = @()
        latestNonblankLine = $null
        latestNonblankLineValid = $false
        errors = @()
        warnings = @()
        ok = $false
    }
}

$summary = New-Summary -LogPath $Path
$errors = New-Object System.Collections.Generic.List[object]
$warnings = New-Object System.Collections.Generic.List[object]
$invalidLines = New-Object System.Collections.Generic.List[object]

if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Add-Issue -Collection $errors -Code "missing_file" -Line $null -Message "Ops log file does not exist."
    $summary.errors = @($errors.ToArray())

    if ($ParseSafe) {
        [pscustomobject]$summary | ConvertTo-Json -Depth 8
    }
    else {
        Write-Output "Missing ops log: $Path"
        Write-Output "[missing_file] Ops log file does not exist."
        Write-Output "FAILED"
    }
    exit 1
}

$summary.exists = $true
$resolvedPath = (Resolve-Path -LiteralPath $Path).Path
$bytes = [System.IO.File]::ReadAllBytes($resolvedPath)
$summary.nulFound = $bytes -contains 0
$summary.bomFound = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

if ($summary.bomFound) {
    Add-Issue -Collection $warnings -Code "utf8_bom" -Line 1 -Message "UTF-8 BOM detected; JSONL should use UTF-8 without BOM."
}

$content = Get-Content -Raw -Encoding UTF8 -LiteralPath $resolvedPath
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

for ($index = 0; $index -lt $lines.Count; $index++) {
    $lineNumber = $index + 1
    $line = $lines[$index]

    if ([string]::IsNullOrWhiteSpace($line)) {
        $summary.blankLines++
        Add-Issue -Collection $errors -Code "blank_line" -Line $lineNumber -Message "Blank lines are not allowed in JSONL logs."
        continue
    }

    $summary.latestNonblankLine = $lineNumber

    if ($line.IndexOf([char]0) -ge 0) {
        Add-Issue -Collection $errors -Code "nul_byte" -Line $lineNumber -Message "NUL bytes are not allowed in JSONL logs."
        $summary.latestNonblankLineValid = $false
        $invalidLines.Add([pscustomobject][ordered]@{
            line = $lineNumber
            error = "Line contains a NUL byte."
        }) | Out-Null
        continue
    }

    try {
        $entry = ConvertFrom-Json -InputObject $line -ErrorAction Stop
        $summary.validJsonLines++
    }
    catch {
        $summary.latestNonblankLineValid = $false
        $invalidLines.Add([pscustomobject][ordered]@{
            line = $lineNumber
            error = "Malformed JSON."
        }) | Out-Null
        Add-Issue -Collection $errors -Code "malformed_json" -Line $lineNumber -Message "Line is not valid JSON."
        continue
    }

    if (-not $line.TrimStart().StartsWith("{") -or -not (Test-IsJsonObject -InputObject $entry)) {
        Add-Issue -Collection $errors -Code "invalid_root_type" -Line $lineNumber -Message "Each JSONL entry must have an object root."
        $summary.latestNonblankLineValid = $false
        continue
    }

    $summary.latestNonblankLineValid = Test-EntryContract -Entry $entry -LineNumber $lineNumber -Errors $errors
}

$summary.invalidJsonLines = @($invalidLines.ToArray())
$summary.errors = @($errors.ToArray())
$summary.warnings = @($warnings.ToArray())
$summary.ok = ($summary.errors.Count -eq 0)

if ($ParseSafe) {
    [pscustomobject]$summary | ConvertTo-Json -Depth 8
}
else {
    Write-Output "Ops log: $Path"
    Write-Output "Lines: $($summary.lineCount)"
    Write-Output "Valid JSON lines: $($summary.validJsonLines)"
    Write-Output "Blank lines: $($summary.blankLines)"
    Write-Output "NUL found: $($summary.nulFound)"
    Write-Output "BOM found: $($summary.bomFound)"
    Write-Output "Latest nonblank line valid: $($summary.latestNonblankLineValid)"

    foreach ($issue in $summary.errors) {
        Write-Output "[$($issue.code)] line $($issue.line): $($issue.message)"
    }
    foreach ($issue in $summary.warnings) {
        Write-Output "[$($issue.code)] line $($issue.line): $($issue.message)"
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
