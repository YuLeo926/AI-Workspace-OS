Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "TestSupport.ps1")

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$CheckOps = Join-Path $RepoRoot "scripts\check-ops-log.ps1"
$Template = Join-Path $RepoRoot "templates\ops-log-entry.jsonl"
$tempRoot = New-TestDirectory -Prefix "ai-workspace-os-ops-log-tests-"

function Write-Utf8Fixture {
    param(
        [string]$Path,
        [string[]]$Lines
    )

    Write-Utf8NoBom -Path $Path -Content (($Lines -join "`n") + "`n")
}

function Get-ParseSafeSummary {
    param($Result)

    return ($Result.Output | Out-String | ConvertFrom-Json)
}

function Assert-IssueShape {
    param(
        $Issues,
        [string]$Context
    )

    foreach ($issue in @($Issues)) {
        $names = @($issue.PSObject.Properties.Name)
        Assert-Equal $names.Count 3 "$Context issue property count"
        Assert-True ($names -contains "code") "$Context issue missing code"
        Assert-True ($names -contains "line") "$Context issue missing line"
        Assert-True ($names -contains "message") "$Context issue missing message"
    }
}

function Assert-SingleError {
    param(
        $Summary,
        [string]$Code,
        [AllowNull()]
        [object]$Line,
        [string]$Message,
        [string]$Context
    )

    $matches = @($Summary.errors | Where-Object { $_.code -eq $Code })
    Assert-Equal $matches.Count 1 "$Context error count for $Code"
    if ($null -eq $Line) {
        Assert-True ($null -eq $matches[0].line) "$Context error line should be null"
    }
    else {
        Assert-Equal $matches[0].line $Line "$Context error line"
    }
    Assert-Equal $matches[0].message $Message "$Context error message"
}

$validEntry = '{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"worker","action":"created test file","target":"tmp","approval_state":"not_required","files_changed":["tmp/file.md"],"rollback_hint":"delete tmp/file.md","note":"test"}'
$validRoleCheckEntry = '{"timestamp":"2026-01-01T00:00:00+00:00","agent_or_role":"worker","action":"updated test file","target":"tmp","approval_state":"delegated","files_changed":[],"rollback_hint":"restore previous content","note":"","role_check":{"actor_role":"worker","owner_role":"lead","write_type":"delegated_write","authorization":"approved task scope"}}'

try {
    Assert-True (Test-Path -LiteralPath $CheckOps) "Missing script: $CheckOps"

    $missingLog = Join-Path $tempRoot "missing.jsonl"
    $missingResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $missingLog, "-ParseSafe")
    Assert-ExitCode $missingResult 1 "Missing ops log"
    $missingSummary = Get-ParseSafeSummary $missingResult
    Assert-SingleError -Summary $missingSummary -Code "missing_file" -Line $null -Message "Ops log file does not exist." -Context "Missing ops log"

    $emptyLog = Join-Path $tempRoot "empty.jsonl"
    [IO.File]::WriteAllBytes($emptyLog, [byte[]]@())
    $emptyResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $emptyLog, "-ParseSafe")
    Assert-ExitCode $emptyResult 0 "Empty ops log"
    $emptySummary = Get-ParseSafeSummary $emptyResult
    Assert-True ($emptySummary.ok -eq $true) "Empty ops log should report ok=true"
    Assert-Equal $emptySummary.lineCount 0 "Empty ops log line count"
    Assert-Equal @($emptySummary.errors).Count 0 "Empty ops log error count"
    Assert-Equal @($emptySummary.warnings).Count 0 "Empty ops log warning count"

    $validLog = Join-Path $tempRoot "valid-log.jsonl"
    Write-Utf8Fixture -Path $validLog -Lines @($validEntry, $validRoleCheckEntry)
    $validResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $validLog, "-ParseSafe")
    Assert-ExitCode $validResult 0 "Valid ops log"
    $validSummary = Get-ParseSafeSummary $validResult
    Assert-True ($validSummary.ok -eq $true) "Valid ops log should report ok=true"
    Assert-Equal $validSummary.validJsonLines 2 "Valid ops log JSON line count"
    Assert-Equal @($validSummary.errors).Count 0 "Valid ops log error count"
    Assert-Equal @($validSummary.warnings).Count 0 "Valid ops log warning count"
    Assert-True ($validSummary.latestNonblankLineValid -eq $true) "Valid role_check entry should be the valid latest line"

    $compatibilityFields = @(
        "path", "exists", "lineCount", "blankLines", "nulFound", "bomFound",
        "validJsonLines", "invalidJsonLines", "latestNonblankLine",
        "latestNonblankLineValid", "errors", "warnings", "ok"
    )
    foreach ($field in $compatibilityFields) {
        Assert-True (@($validSummary.PSObject.Properties.Name) -contains $field) "Parse-safe output missing field: $field"
    }

    $requiredTopLevelFields = @(
        "timestamp", "agent_or_role", "action", "target", "approval_state",
        "files_changed", "rollback_hint", "note"
    )
    $missingFieldSummaries = @{}
    foreach ($field in $requiredTopLevelFields) {
        $entry = $validEntry | ConvertFrom-Json
        $entry.PSObject.Properties.Remove($field)
        if ($field -eq "action") {
            $entry.target = "PRIVATE_TARGET_DO_NOT_EMIT"
        }

        $path = Join-Path $tempRoot ("missing-top-level-" + $field + ".jsonl")
        $json = $entry | ConvertTo-Json -Compress -Depth 6
        Write-Utf8Fixture -Path $path -Lines @($json)
        $result = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $path, "-ParseSafe")
        Assert-ExitCode $result 1 "Missing top-level field $field"
        $summary = Get-ParseSafeSummary $result
        Assert-SingleError -Summary $summary -Code "missing_required_field" -Line 1 -Message "Required field '$field' is missing." -Context "Missing top-level field $field"
        Assert-Equal $summary.validJsonLines 1 "Missing top-level field $field parsed JSON count"
        Assert-True ($summary.latestNonblankLineValid -eq $false) "Missing top-level field $field should make latest line invalid"
        $missingFieldSummaries[$field] = $summary

        if ($field -eq "action") {
            Assert-True (($result.Output | Out-String) -notmatch "PRIVATE_TARGET_DO_NOT_EMIT") "Parse-safe output leaked a parsed value"
            $humanResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $path)
            Assert-ExitCode $humanResult 1 "Missing action human output"
            Assert-True (($humanResult.Output | Out-String) -notmatch "PRIVATE_TARGET_DO_NOT_EMIT") "Human output leaked a parsed value"
        }
    }
    $missingActionSummary = $missingFieldSummaries["action"]

    $invalidApproval = Join-Path $tempRoot "invalid-approval.jsonl"
    Write-Utf8Fixture -Path $invalidApproval -Lines @('{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"worker","action":"test action","target":"tmp","approval_state":"PRIVATE_ENUM_DO_NOT_EMIT","files_changed":[],"rollback_hint":"remove output","note":""}')
    $invalidApprovalResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $invalidApproval, "-ParseSafe")
    Assert-ExitCode $invalidApprovalResult 1 "Invalid approval state"
    $invalidApprovalSummary = Get-ParseSafeSummary $invalidApprovalResult
    Assert-True (@($invalidApprovalSummary.errors.code) -contains "invalid_approval_state") "Invalid approval state not reported"
    Assert-True (($invalidApprovalResult.Output | Out-String) -notmatch "PRIVATE_ENUM_DO_NOT_EMIT") "Parse-safe output leaked an invalid enum value"

    $invalidWriteType = Join-Path $tempRoot "invalid-write-type.jsonl"
    Write-Utf8Fixture -Path $invalidWriteType -Lines @('{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"worker","action":"test action","target":"tmp","approval_state":"explicit","files_changed":[],"rollback_hint":"remove output","note":"","role_check":{"actor_role":"worker","owner_role":"lead","write_type":"PRIVATE_WRITE_TYPE_DO_NOT_EMIT","authorization":"approved task scope"}}')
    $invalidWriteTypeResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $invalidWriteType, "-ParseSafe")
    Assert-ExitCode $invalidWriteTypeResult 1 "Invalid role_check write_type"
    $invalidWriteTypeSummary = Get-ParseSafeSummary $invalidWriteTypeResult
    Assert-True (@($invalidWriteTypeSummary.errors.code) -contains "invalid_write_type") "Invalid write_type not reported"
    Assert-True (($invalidWriteTypeResult.Output | Out-String) -notmatch "PRIVATE_WRITE_TYPE_DO_NOT_EMIT") "Parse-safe output leaked role_check content"

    $schemaCases = @(
        [pscustomobject]@{ Name = "invalid-timestamp"; Json = '{"timestamp":"not-a-timestamp","agent_or_role":"worker","action":"test","target":"tmp","approval_state":"suggested","files_changed":[],"rollback_hint":"none","note":""}'; Code = "invalid_timestamp"; Message = "Field 'timestamp' must be a parseable ISO 8601 timestamp." },
        [pscustomobject]@{ Name = "empty-required-string"; Json = '{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"","action":"test","target":"tmp","approval_state":"suggested","files_changed":[],"rollback_hint":"none","note":""}'; Code = "invalid_field_type"; Message = "Field 'agent_or_role' must be a nonempty string." },
        [pscustomobject]@{ Name = "files-changed-single-string"; Json = '{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"worker","action":"test","target":"tmp","approval_state":"suggested","files_changed":"tmp/file.md","rollback_hint":"none","note":""}'; Code = "invalid_field_type"; Message = "Field 'files_changed' must be an array of strings." },
        [pscustomobject]@{ Name = "files-changed-non-string-member"; Json = '{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"worker","action":"test","target":"tmp","approval_state":"suggested","files_changed":[42],"rollback_hint":"none","note":""}'; Code = "invalid_field_type"; Message = "Field 'files_changed' must contain only strings." },
        [pscustomobject]@{ Name = "note-not-string"; Json = '{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"worker","action":"test","target":"tmp","approval_state":"suggested","files_changed":[],"rollback_hint":"none","note":null}'; Code = "invalid_field_type"; Message = "Field 'note' must be a string." },
        [pscustomobject]@{ Name = "role-check-null"; Json = '{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"worker","action":"test","target":"tmp","approval_state":"suggested","files_changed":[],"rollback_hint":"none","note":"","role_check":null}'; Code = "invalid_role_check"; Message = "Field 'role_check' must be an object when present." },
        [pscustomobject]@{ Name = "role-check-non-object"; Json = '{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"worker","action":"test","target":"tmp","approval_state":"suggested","files_changed":[],"rollback_hint":"none","note":"","role_check":"owner"}'; Code = "invalid_role_check"; Message = "Field 'role_check' must be an object when present." }
    )
    foreach ($case in $schemaCases) {
        $path = Join-Path $tempRoot ($case.Name + ".jsonl")
        Write-Utf8Fixture -Path $path -Lines @($case.Json)
        $result = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $path, "-ParseSafe")
        Assert-ExitCode $result 1 $case.Name
        $summary = Get-ParseSafeSummary $result
        Assert-SingleError -Summary $summary -Code $case.Code -Line 1 -Message $case.Message -Context $case.Name
        Assert-Equal $summary.validJsonLines 1 "$($case.Name) parsed JSON count"
        Assert-True ($summary.latestNonblankLineValid -eq $false) "$($case.Name) should make latest line invalid"
    }

    foreach ($field in @("actor_role", "owner_role", "write_type", "authorization")) {
        $entry = $validRoleCheckEntry | ConvertFrom-Json
        $entry.role_check.PSObject.Properties.Remove($field)
        $path = Join-Path $tempRoot ("role-check-missing-" + $field + ".jsonl")
        $json = $entry | ConvertTo-Json -Compress -Depth 6
        Write-Utf8Fixture -Path $path -Lines @($json)
        $result = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $path, "-ParseSafe")
        Assert-ExitCode $result 1 "Missing role_check field $field"
        $summary = Get-ParseSafeSummary $result
        Assert-SingleError -Summary $summary -Code "missing_required_field" -Line 1 -Message "Required role_check field '$field' is missing." -Context "Missing role_check field $field"
        Assert-True ($summary.latestNonblankLineValid -eq $false) "Missing role_check field $field should make latest line invalid"
    }

    $rootCases = @(
        [pscustomobject]@{ Name = "root-array"; Json = '[]' },
        [pscustomobject]@{ Name = "root-scalar"; Json = '42' }
    )
    foreach ($case in $rootCases) {
        $path = Join-Path $tempRoot ($case.Name + ".jsonl")
        Write-Utf8Fixture -Path $path -Lines @($case.Json)
        $result = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $path, "-ParseSafe")
        Assert-ExitCode $result 1 $case.Name
        $summary = Get-ParseSafeSummary $result
        Assert-SingleError -Summary $summary -Code "invalid_root_type" -Line 1 -Message "Each JSONL entry must have an object root." -Context $case.Name
        Assert-Equal $summary.validJsonLines 1 "$($case.Name) parsed JSON count"
        Assert-True ($summary.latestNonblankLineValid -eq $false) "$($case.Name) should make latest line invalid"
    }

    $schemaInvalidLatest = Join-Path $tempRoot "schema-invalid-latest.jsonl"
    Write-Utf8Fixture -Path $schemaInvalidLatest -Lines @($validEntry, '{"timestamp":"2026-01-01T00:00:00Z","agent_or_role":"worker","action":"test","target":"tmp","approval_state":"suggested","files_changed":"tmp/file.md","rollback_hint":"none","note":""}')
    $schemaInvalidLatestResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $schemaInvalidLatest, "-ParseSafe")
    Assert-ExitCode $schemaInvalidLatestResult 1 "Schema-invalid latest line"
    $schemaInvalidLatestSummary = Get-ParseSafeSummary $schemaInvalidLatestResult
    Assert-Equal $schemaInvalidLatestSummary.validJsonLines 2 "Schema-invalid latest parsed JSON count"
    Assert-Equal $schemaInvalidLatestSummary.latestNonblankLine 2 "Schema-invalid latest line number"
    Assert-True ($schemaInvalidLatestSummary.latestNonblankLineValid -eq $false) "Schema-invalid latest nonblank line should be invalid"

    $blankLog = Join-Path $tempRoot "blank-line.jsonl"
    Write-Utf8Fixture -Path $blankLog -Lines @($validEntry, "", $validEntry)
    $blankResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $blankLog, "-ParseSafe")
    Assert-ExitCode $blankResult 1 "Blank line"
    $blankSummary = Get-ParseSafeSummary $blankResult
    Assert-True (@($blankSummary.errors.code) -contains "blank_line") "Blank line not reported"

    $malformedLog = Join-Path $tempRoot "malformed.jsonl"
    Write-Utf8Fixture -Path $malformedLog -Lines @('{"PRIVATE_SOURCE_DO_NOT_EMIT":')
    $malformedResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $malformedLog, "-ParseSafe")
    Assert-ExitCode $malformedResult 1 "Malformed JSON"
    $malformedSummary = Get-ParseSafeSummary $malformedResult
    Assert-True (@($malformedSummary.errors.code) -contains "malformed_json") "Malformed JSON not reported"
    Assert-True (($malformedResult.Output | Out-String) -notmatch "PRIVATE_SOURCE_DO_NOT_EMIT") "Parse-safe output leaked malformed source JSON"

    $nulLog = Join-Path $tempRoot "contains-nul-byte.jsonl"
    Write-Utf8NoBom -Path $nulLog -Content ($validEntry + [char]0 + "`n")
    $nulResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $nulLog, "-ParseSafe")
    Assert-ExitCode $nulResult 1 "NUL byte"
    $nulSummary = Get-ParseSafeSummary $nulResult
    Assert-True (@($nulSummary.errors.code) -contains "nul_byte") "NUL byte not reported"

    $bomLog = Join-Path $tempRoot "bom.jsonl"
    Write-Utf8Bom -Path $bomLog -Content ($validEntry + "`n")
    $bomResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $bomLog, "-ParseSafe")
    Assert-ExitCode $bomResult 0 "UTF-8 BOM warning"
    $bomSummary = Get-ParseSafeSummary $bomResult
    Assert-True ($bomSummary.ok -eq $true) "BOM warning should not make ok false"
    Assert-True (@($bomSummary.warnings.code) -contains "utf8_bom") "UTF-8 BOM warning not reported"
    Assert-Equal @($bomSummary.errors).Count 0 "BOM warning error count"

    Assert-IssueShape -Issues $missingActionSummary.errors -Context "Error"
    Assert-IssueShape -Issues $bomSummary.warnings -Context "Warning"

    Assert-True (Test-Path -LiteralPath $Template) "Missing compact ops log template"
    $templateBytes = [IO.File]::ReadAllBytes($Template)
    Assert-True ($templateBytes.Length -gt 0) "Ops log template must not be empty"
    Assert-True ($templateBytes[-1] -eq 0x0A) "Ops log template must end with a newline"
    Assert-True (-not ($templateBytes -contains 0x0D)) "Ops log template must use one LF-terminated logical line"
    $templateText = [Text.Encoding]::UTF8.GetString($templateBytes)
    $templateLines = @([regex]::Split($templateText, "\n"))
    Assert-Equal $templateLines.Count 2 "Ops log template logical line count"
    Assert-Equal $templateLines[1] "" "Ops log template final line"

    $templateResult = Invoke-TestScript -ScriptPath $CheckOps -Arguments @("-Path", $Template, "-ParseSafe")
    Assert-ExitCode $templateResult 0 "Ops log template"
    $templateSummary = Get-ParseSafeSummary $templateResult
    Assert-True ($templateSummary.ok -eq $true) "Ops log template should satisfy the contract"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
