Set-StrictMode -Version Latest

$script:WorkspacePolicySupportedActions = @("create", "modify", "append", "delete", "move")

function ConvertFrom-WorkspaceJson {
    param([Parameter(Mandatory = $true)][string]$InputObject)

    $command = Get-Command ConvertFrom-Json -ErrorAction Stop
    if ($command.Parameters.ContainsKey("DateKind")) {
        return ConvertFrom-Json -InputObject $InputObject -DateKind String -ErrorAction Stop
    }

    return ConvertFrom-Json -InputObject $InputObject -ErrorAction Stop
}

function New-WorkspacePolicyIssue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Code,
        [AllowNull()]
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

function Add-WorkspacePolicyIssue {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Collection,
        [Parameter(Mandatory = $true)]
        [string]$Code,
        [AllowNull()]
        [Nullable[int]]$Line = $null,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $Collection.Add((New-WorkspacePolicyIssue -Code $Code -Line $Line -Message $Message)) | Out-Null
}

function Test-WorkspacePolicyObject {
    param([AllowNull()][object]$InputObject)

    return (
        $null -ne $InputObject -and
        -not ($InputObject -is [System.Array]) -and
        (
            $InputObject -is [System.Management.Automation.PSCustomObject] -or
            $InputObject -is [System.Collections.IDictionary]
        )
    )
}

function Test-WorkspacePolicyProperty {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name
    )

    return (
        $null -ne $InputObject -and
        $null -ne $InputObject.PSObject.Properties[$Name]
    )
}

function Test-WorkspacePolicyInteger {
    param([AllowNull()][object]$Value)

    return (
        $Value -is [byte] -or
        $Value -is [sbyte] -or
        $Value -is [int16] -or
        $Value -is [uint16] -or
        $Value -is [int32] -or
        $Value -is [uint32] -or
        $Value -is [int64] -or
        $Value -is [uint64]
    )
}

function Test-WorkspacePolicyOrdinalEqual {
    param(
        [AllowNull()][string]$Left,
        [AllowNull()][string]$Right
    )

    return [string]::Equals($Left, $Right, [StringComparison]::Ordinal)
}

function Test-WorkspacePolicyOrdinalContains {
    param(
        [object[]]$Values,
        [AllowNull()][string]$Candidate
    )

    foreach ($value in @($Values)) {
        if (
            $value -is [string] -and
            [string]::Equals([string]$value, $Candidate, [StringComparison]::Ordinal)
        ) {
            return $true
        }
    }

    return $false
}

function Add-WorkspacePolicyUnknownFieldIssues {
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string[]]$AllowedNames,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Errors
    )

    foreach ($property in @($InputObject.PSObject.Properties)) {
        if (-not (Test-WorkspacePolicyOrdinalContains -Values $AllowedNames -Candidate $property.Name)) {
            Add-WorkspacePolicyIssue `
                -Collection $Errors `
                -Code "unknown_policy_field" `
                -Message "The workspace policy contains an unsupported field."
        }
    }
}

function ConvertTo-WorkspaceRelativePolicyPath {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [object]$Path
    )

    if (-not ($Path -is [string])) {
        throw [IO.InvalidDataException]::new("The policy path must be a string.")
    }

    $value = [string]$Path
    if (
        [string]::IsNullOrWhiteSpace($value) -or
        -not [string]::Equals($value, $value.Trim(), [StringComparison]::Ordinal) -or
        $value.IndexOf([char]0) -ge 0 -or
        $value.IndexOf('\') -ge 0 -or
        $value.StartsWith("/", [StringComparison]::Ordinal) -or
        $value -match '^[A-Za-z][A-Za-z0-9+.-]*:' -or
        $value.IndexOfAny([char[]]@('*', '?', '[', ']')) -ge 0
    ) {
        throw [IO.InvalidDataException]::new("The policy path is not a normalized workspace-relative path.")
    }

    $segments = @($value.Split([char]'/', [StringSplitOptions]::None))
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $segment = $segments[$index]
        $isDirectorySuffix = ($index -eq ($segments.Count - 1) -and $segment.Length -eq 0)
        if ($isDirectorySuffix) {
            continue
        }

        if (
            $segment.Length -eq 0 -or
            [string]::Equals($segment, ".", [StringComparison]::Ordinal) -or
            [string]::Equals($segment, "..", [StringComparison]::Ordinal) -or
            -not [string]::Equals($segment, $segment.Trim(), [StringComparison]::Ordinal)
        ) {
            throw [IO.InvalidDataException]::new("The policy path is not a normalized workspace-relative path.")
        }
    }

    if ($segments.Count -eq 1 -and $segments[0].Length -eq 0) {
        throw [IO.InvalidDataException]::new("The policy path is not a normalized workspace-relative path.")
    }

    return $value
}

function Test-WorkspacePolicyPathMatch {
    param(
        [Parameter(Mandatory = $true)][string]$PolicyPath,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if ($PolicyPath.EndsWith("/", [StringComparison]::Ordinal)) {
        return $RelativePath.StartsWith($PolicyPath, [StringComparison]::Ordinal)
    }

    return [string]::Equals($PolicyPath, $RelativePath, [StringComparison]::Ordinal)
}

function Test-WorkspacePolicyPathOverlap {
    param(
        [Parameter(Mandatory = $true)][string]$First,
        [Parameter(Mandatory = $true)][string]$Second
    )

    if ([string]::Equals($First, $Second, [StringComparison]::Ordinal)) {
        return $true
    }
    if ($First.EndsWith("/", [StringComparison]::Ordinal) -and $Second.StartsWith($First, [StringComparison]::Ordinal)) {
        return $true
    }
    if ($Second.EndsWith("/", [StringComparison]::Ordinal) -and $First.StartsWith($Second, [StringComparison]::Ordinal)) {
        return $true
    }

    return $false
}

function Get-WorkspacePolicyRole {
    param(
        [AllowNull()][object]$Policy,
        [Parameter(Mandatory = $true)][string]$RoleId
    )

    if ($null -eq $Policy -or -not (Test-WorkspacePolicyProperty -InputObject $Policy -Name "roles")) {
        return $null
    }

    foreach ($role in @($Policy.roles)) {
        if (
            (Test-WorkspacePolicyObject -InputObject $role) -and
            (Test-WorkspacePolicyProperty -InputObject $role -Name "id") -and
            $role.id -is [string] -and
            [string]::Equals([string]$role.id, $RoleId, [StringComparison]::Ordinal)
        ) {
            return $role
        }
    }

    return $null
}

function Test-WorkspacePolicyActionList {
    param(
        [AllowNull()][object]$Actions,
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Errors
    )

    if (-not ($Actions -is [System.Array]) -or @($Actions).Count -eq 0) {
        Add-WorkspacePolicyIssue -Collection $Errors -Code "invalid_actions" -Message "Actions must be a nonempty array."
        return $false
    }

    $valid = $true
    $seen = New-Object System.Collections.Generic.List[string]
    foreach ($action in @($Actions)) {
        if (
            -not ($action -is [string]) -or
            [string]::IsNullOrWhiteSpace([string]$action) -or
            -not (Test-WorkspacePolicyOrdinalContains -Values $script:WorkspacePolicySupportedActions -Candidate ([string]$action))
        ) {
            Add-WorkspacePolicyIssue -Collection $Errors -Code "unsupported_action" -Message "An action is not supported by this protocol version."
            $valid = $false
            continue
        }

        if (Test-WorkspacePolicyOrdinalContains -Values @($seen.ToArray()) -Candidate ([string]$action)) {
            Add-WorkspacePolicyIssue -Collection $Errors -Code "invalid_actions" -Message "Actions must not contain duplicates."
            $valid = $false
            continue
        }

        $seen.Add([string]$action) | Out-Null
    }

    return $valid
}

function Add-WorkspacePolicyRoleReferenceIssue {
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [AllowNull()][object]$RoleId,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Errors
    )

    if (-not ($RoleId -is [string]) -or [string]::IsNullOrWhiteSpace([string]$RoleId)) {
        Add-WorkspacePolicyIssue -Collection $Errors -Code "unknown_role" -Message "A policy entry references an unknown role."
        return
    }

    $role = Get-WorkspacePolicyRole -Policy $Policy -RoleId ([string]$RoleId)
    if ($null -eq $role) {
        Add-WorkspacePolicyIssue -Collection $Errors -Code "unknown_role" -Message "A policy entry references an unknown role."
        return
    }

    if (
        -not (Test-WorkspacePolicyProperty -InputObject $role -Name "status") -or
        -not ($role.status -is [string]) -or
        -not [string]::Equals([string]$role.status, "active", [StringComparison]::Ordinal)
    ) {
        Add-WorkspacePolicyIssue -Collection $Errors -Code "inactive_role" -Message "A policy entry references a role that is not active."
    }
}

function Read-WorkspacePolicy {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    $errors = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[object]
    $policy = $null

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "missing_file" -Message "The workspace policy file is missing."
        return [pscustomobject][ordered]@{
            policy = $null
            errors = @($errors.ToArray())
            warnings = @()
            ok = $false
        }
    }

    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
    }
    catch {
        Add-WorkspacePolicyIssue -Collection $errors -Code "unreadable_file" -Message "The workspace policy file could not be read."
        return [pscustomobject][ordered]@{
            policy = $null
            errors = @($errors.ToArray())
            warnings = @()
            ok = $false
        }
    }

    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "utf8_bom" -Message "The workspace policy must use UTF-8 without a BOM."
        $offset = 3
    }

    try {
        $encoding = New-Object Text.UTF8Encoding($false, $true)
        $content = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_utf8" -Message "The workspace policy is not valid UTF-8."
        return [pscustomobject][ordered]@{
            policy = $null
            errors = @($errors.ToArray())
            warnings = @()
            ok = $false
        }
    }

    if ($content.IndexOf([char]0) -ge 0) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "nul_byte" -Message "The workspace policy must not contain NUL bytes."
        return [pscustomobject][ordered]@{
            policy = $null
            errors = @($errors.ToArray())
            warnings = @()
            ok = $false
        }
    }

    try {
        $policy = ConvertFrom-WorkspaceJson -InputObject $content
    }
    catch {
        Add-WorkspacePolicyIssue -Collection $errors -Code "malformed_json" -Message "The workspace policy is not valid JSON."
        return [pscustomobject][ordered]@{
            policy = $null
            errors = @($errors.ToArray())
            warnings = @()
            ok = $false
        }
    }

    if (-not (Test-WorkspacePolicyObject -InputObject $policy)) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_root_type" -Message "The workspace policy must have an object root."
        return [pscustomobject][ordered]@{
            policy = $null
            errors = @($errors.ToArray())
            warnings = @()
            ok = $false
        }
    }

    Add-WorkspacePolicyUnknownFieldIssues `
        -InputObject $policy `
        -AllowedNames @(
            "protocol_version",
            "policy_revision",
            "default_write",
            "human_override_role",
            "roles",
            "ownership",
            "standing_permissions",
            "protected_paths",
            "handoff"
        ) `
        -Errors $errors

    if (
        -not (Test-WorkspacePolicyProperty -InputObject $policy -Name "protocol_version") -or
        -not ($policy.protocol_version -is [string]) -or
        -not [string]::Equals([string]$policy.protocol_version, "0.2", [StringComparison]::Ordinal)
    ) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "unsupported_protocol_version" -Message "The workspace policy protocol version is not supported."
    }

    if (
        -not (Test-WorkspacePolicyProperty -InputObject $policy -Name "policy_revision") -or
        -not (Test-WorkspacePolicyInteger -Value $policy.policy_revision) -or
        [decimal]$policy.policy_revision -le 0
    ) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_policy_revision" -Message "The policy revision must be a positive integer."
    }

    if (
        -not (Test-WorkspacePolicyProperty -InputObject $policy -Name "default_write") -or
        -not ($policy.default_write -is [string]) -or
        -not [string]::Equals([string]$policy.default_write, "deny", [StringComparison]::Ordinal)
    ) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_default_write" -Message "The default write decision must be deny."
    }

    $rolesValidForReferences = $false
    if (
        -not (Test-WorkspacePolicyProperty -InputObject $policy -Name "roles") -or
        -not ($policy.roles -is [System.Array]) -or
        @($policy.roles).Count -eq 0
    ) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_roles" -Message "Roles must be a nonempty array."
    }
    else {
        $rolesValidForReferences = $true
        $seenRoleIds = New-Object System.Collections.Generic.List[string]
        foreach ($role in @($policy.roles)) {
            if (-not (Test-WorkspacePolicyObject -InputObject $role)) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_role" -Message "Each role must be an object."
                $rolesValidForReferences = $false
                continue
            }

            Add-WorkspacePolicyUnknownFieldIssues `
                -InputObject $role `
                -AllowedNames @("id", "description", "status") `
                -Errors $errors

            $roleIdValid = (
                (Test-WorkspacePolicyProperty -InputObject $role -Name "id") -and
                $role.id -is [string] -and
                ([string]$role.id) -cmatch '^[a-z][a-z0-9_-]*$'
            )
            if (-not $roleIdValid) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_role" -Message "A role has an invalid identifier."
                $rolesValidForReferences = $false
            }
            elseif (Test-WorkspacePolicyOrdinalContains -Values @($seenRoleIds.ToArray()) -Candidate ([string]$role.id)) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "duplicate_role" -Message "Role identifiers must be unique."
                $rolesValidForReferences = $false
            }
            else {
                $seenRoleIds.Add([string]$role.id) | Out-Null
            }

            if (
                -not (Test-WorkspacePolicyProperty -InputObject $role -Name "description") -or
                -not ($role.description -is [string])
            ) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_role" -Message "A role has an invalid description."
            }

            if (
                -not (Test-WorkspacePolicyProperty -InputObject $role -Name "status") -or
                -not ($role.status -is [string]) -or
                -not (
                    [string]::Equals([string]$role.status, "active", [StringComparison]::Ordinal) -or
                    [string]::Equals([string]$role.status, "retired", [StringComparison]::Ordinal)
                )
            ) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_role_status" -Message "A role has an invalid status."
            }
        }
    }

    if (
        -not (Test-WorkspacePolicyProperty -InputObject $policy -Name "human_override_role") -or
        -not ($policy.human_override_role -is [string])
    ) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_human_override_role" -Message "The human override role must reference an active role."
    }
    elseif ($rolesValidForReferences) {
        $overrideRole = Get-WorkspacePolicyRole -Policy $policy -RoleId ([string]$policy.human_override_role)
        if (
            $null -eq $overrideRole -or
            -not (Test-WorkspacePolicyProperty -InputObject $overrideRole -Name "status") -or
            -not ($overrideRole.status -is [string]) -or
            -not [string]::Equals([string]$overrideRole.status, "active", [StringComparison]::Ordinal)
        ) {
            Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_human_override_role" -Message "The human override role must reference an active role."
        }
    }

    if (
        -not (Test-WorkspacePolicyProperty -InputObject $policy -Name "ownership") -or
        -not ($policy.ownership -is [System.Array])
    ) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_ownership" -Message "Ownership must be an array."
    }
    else {
        $seenOwnershipPaths = New-Object System.Collections.Generic.List[string]
        foreach ($entry in @($policy.ownership)) {
            if (-not (Test-WorkspacePolicyObject -InputObject $entry)) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_ownership" -Message "Each ownership entry must be an object."
                continue
            }

            Add-WorkspacePolicyUnknownFieldIssues `
                -InputObject $entry `
                -AllowedNames @("path", "owner", "actions") `
                -Errors $errors

            $normalizedPath = $null
            if (-not (Test-WorkspacePolicyProperty -InputObject $entry -Name "path")) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_policy_path" -Message "A policy path is invalid."
            }
            else {
                try {
                    $normalizedPath = ConvertTo-WorkspaceRelativePolicyPath -Path $entry.path
                }
                catch {
                    Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_policy_path" -Message "A policy path is invalid."
                }
            }

            if ($null -ne $normalizedPath) {
                if (Test-WorkspacePolicyOrdinalContains -Values @($seenOwnershipPaths.ToArray()) -Candidate $normalizedPath) {
                    Add-WorkspacePolicyIssue -Collection $errors -Code "duplicate_ownership" -Message "Ownership paths must be unique."
                }
                else {
                    $seenOwnershipPaths.Add($normalizedPath) | Out-Null
                }
            }

            if (Test-WorkspacePolicyProperty -InputObject $entry -Name "owner") {
                Add-WorkspacePolicyRoleReferenceIssue -Policy $policy -RoleId $entry.owner -Errors $errors
            }
            else {
                Add-WorkspacePolicyIssue -Collection $errors -Code "unknown_role" -Message "A policy entry references an unknown role."
            }

            if (Test-WorkspacePolicyProperty -InputObject $entry -Name "actions") {
                Test-WorkspacePolicyActionList -Actions $entry.actions -Errors $errors | Out-Null
            }
            else {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_actions" -Message "Actions must be a nonempty array."
            }
        }
    }

    $protectedPaths = New-Object System.Collections.Generic.List[string]
    if (
        -not (Test-WorkspacePolicyProperty -InputObject $policy -Name "protected_paths") -or
        -not ($policy.protected_paths -is [System.Array])
    ) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_protected_paths" -Message "Protected paths must be an array."
    }
    else {
        foreach ($entry in @($policy.protected_paths)) {
            if (-not (Test-WorkspacePolicyObject -InputObject $entry)) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_protected_paths" -Message "Each protected path entry must be an object."
                continue
            }

            Add-WorkspacePolicyUnknownFieldIssues `
                -InputObject $entry `
                -AllowedNames @("path", "required_role") `
                -Errors $errors

            $normalizedPath = $null
            if (Test-WorkspacePolicyProperty -InputObject $entry -Name "path") {
                try {
                    $normalizedPath = ConvertTo-WorkspaceRelativePolicyPath -Path $entry.path
                }
                catch {
                    Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_policy_path" -Message "A policy path is invalid."
                }
            }
            else {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_policy_path" -Message "A policy path is invalid."
            }

            if ($null -ne $normalizedPath) {
                if (Test-WorkspacePolicyOrdinalContains -Values @($protectedPaths.ToArray()) -Candidate $normalizedPath) {
                    Add-WorkspacePolicyIssue -Collection $errors -Code "duplicate_protected_path" -Message "Protected paths must be unique."
                }
                else {
                    $protectedPaths.Add($normalizedPath) | Out-Null
                }
            }

            if (Test-WorkspacePolicyProperty -InputObject $entry -Name "required_role") {
                Add-WorkspacePolicyRoleReferenceIssue -Policy $policy -RoleId $entry.required_role -Errors $errors
            }
            else {
                Add-WorkspacePolicyIssue -Collection $errors -Code "unknown_role" -Message "A policy entry references an unknown role."
            }
        }

        if (-not (Test-WorkspacePolicyOrdinalContains -Values @($protectedPaths.ToArray()) -Candidate "workspace-policy.json")) {
            Add-WorkspacePolicyIssue -Collection $errors -Code "missing_required_protected_path" -Message "The workspace policy file must be protected."
        }
        else {
            $policyProtection = @($policy.protected_paths | Where-Object {
                $_.path -is [string] -and
                [string]::Equals([string]$_.path, "workspace-policy.json", [StringComparison]::Ordinal)
            })[0]
            if (
                -not ($policyProtection.required_role -is [string]) -or
                -not ($policy.human_override_role -is [string]) -or
                -not [string]::Equals(
                    [string]$policyProtection.required_role,
                    [string]$policy.human_override_role,
                    [StringComparison]::Ordinal
                )
            ) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_policy_protection" -Message "The workspace policy must require the human override role."
            }
        }
    }

    if (
        -not (Test-WorkspacePolicyProperty -InputObject $policy -Name "standing_permissions") -or
        -not ($policy.standing_permissions -is [System.Array])
    ) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_standing_permissions" -Message "Standing permissions must be an array."
    }
    else {
        $seenStandingKeys = New-Object System.Collections.Generic.List[string]
        foreach ($entry in @($policy.standing_permissions)) {
            if (-not (Test-WorkspacePolicyObject -InputObject $entry)) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_standing_permissions" -Message "Each standing permission must be an object."
                continue
            }

            Add-WorkspacePolicyUnknownFieldIssues `
                -InputObject $entry `
                -AllowedNames @("path", "role", "actions") `
                -Errors $errors

            $normalizedPath = $null
            if (Test-WorkspacePolicyProperty -InputObject $entry -Name "path") {
                try {
                    $normalizedPath = ConvertTo-WorkspaceRelativePolicyPath -Path $entry.path
                }
                catch {
                    Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_policy_path" -Message "A policy path is invalid."
                }
            }
            else {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_policy_path" -Message "A policy path is invalid."
            }

            $roleId = $null
            if (Test-WorkspacePolicyProperty -InputObject $entry -Name "role") {
                $roleId = $entry.role
                Add-WorkspacePolicyRoleReferenceIssue -Policy $policy -RoleId $roleId -Errors $errors
            }
            else {
                Add-WorkspacePolicyIssue -Collection $errors -Code "unknown_role" -Message "A policy entry references an unknown role."
            }

            if (Test-WorkspacePolicyProperty -InputObject $entry -Name "actions") {
                Test-WorkspacePolicyActionList -Actions $entry.actions -Errors $errors | Out-Null
            }
            else {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_actions" -Message "Actions must be a nonempty array."
            }

            if ($null -ne $normalizedPath -and $roleId -is [string]) {
                if ($normalizedPath.EndsWith("/", [StringComparison]::Ordinal)) {
                    Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_standing_path" -Message "A standing permission must target one file."
                }

                $standingActions = @()
                if (Test-WorkspacePolicyProperty -InputObject $entry -Name "actions") {
                    $standingActions = @($entry.actions)
                }
                if (
                    $standingActions.Count -ne 1 -or
                    -not ($standingActions[0] -is [string]) -or
                    -not [string]::Equals([string]$standingActions[0], "append", [StringComparison]::Ordinal)
                ) {
                    Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_standing_actions" -Message "A standing permission may allow append only."
                }

                $key = $normalizedPath + [char]0 + [string]$roleId
                if (Test-WorkspacePolicyOrdinalContains -Values @($seenStandingKeys.ToArray()) -Candidate $key) {
                    Add-WorkspacePolicyIssue -Collection $errors -Code "duplicate_standing_permission" -Message "Standing permission path and role pairs must be unique."
                }
                else {
                    $seenStandingKeys.Add($key) | Out-Null
                }

                foreach ($protectedPath in @($protectedPaths.ToArray())) {
                    if (Test-WorkspacePolicyPathOverlap -First $normalizedPath -Second $protectedPath) {
                        Add-WorkspacePolicyIssue -Collection $errors -Code "standing_permission_protected_overlap" -Message "A standing permission overlaps a protected path."
                        break
                    }
                }
            }
        }
    }

    if (
        -not (Test-WorkspacePolicyProperty -InputObject $policy -Name "handoff") -or
        -not (Test-WorkspacePolicyObject -InputObject $policy.handoff)
    ) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_handoff_settings" -Message "Handoff settings are invalid."
    }
    else {
        Add-WorkspacePolicyUnknownFieldIssues `
            -InputObject $policy.handoff `
            -AllowedNames @("max_review_window_days", "enforce_expiry") `
            -Errors $errors

        if (
            -not (Test-WorkspacePolicyProperty -InputObject $policy.handoff -Name "max_review_window_days") -or
            -not (Test-WorkspacePolicyInteger -Value $policy.handoff.max_review_window_days) -or
            [decimal]$policy.handoff.max_review_window_days -le 0
        ) {
            Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_handoff_settings" -Message "Handoff settings are invalid."
        }
        if (
            -not (Test-WorkspacePolicyProperty -InputObject $policy.handoff -Name "enforce_expiry") -or
            -not ($policy.handoff.enforce_expiry -is [bool])
        ) {
            Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_handoff_settings" -Message "Handoff settings are invalid."
        }
    }

    return [pscustomobject][ordered]@{
        policy = $policy
        errors = @($errors.ToArray())
        warnings = @($warnings.ToArray())
        ok = ($errors.Count -eq 0)
    }
}

function Get-PolicyOwnerMatch {
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $candidate = ConvertTo-WorkspaceRelativePolicyPath -Path $RelativePath
    $bestMatch = $null
    $bestLength = -1
    foreach ($entry in @($Policy.ownership)) {
        $policyPath = [string]$entry.path
        if (
            (Test-WorkspacePolicyPathMatch -PolicyPath $policyPath -RelativePath $candidate) -and
            $policyPath.Length -gt $bestLength
        ) {
            $bestMatch = $entry
            $bestLength = $policyPath.Length
        }
    }

    return $bestMatch
}

function Test-StandingPermission {
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $candidate = ConvertTo-WorkspaceRelativePolicyPath -Path $RelativePath
    foreach ($entry in @($Policy.standing_permissions)) {
        if (
            [string]::Equals([string]$entry.role, $Role, [StringComparison]::Ordinal) -and
            (Test-WorkspacePolicyOrdinalContains -Values @($entry.actions) -Candidate $Action) -and
            (Test-WorkspacePolicyPathMatch -PolicyPath ([string]$entry.path) -RelativePath $candidate)
        ) {
            return $true
        }
    }

    return $false
}

function Get-DelegationTimestampValue {
    param([AllowNull()][object]$Value)

    if (
        -not ($Value -is [string]) -or
        [string]::IsNullOrWhiteSpace([string]$Value) -or
        [string]$Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$'
    ) {
        return $null
    }

    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
        [string]$Value,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::RoundtripKind,
        [ref]$parsed
    )) {
        return $null
    }

    return $parsed
}

function Add-DelegationUnknownFieldIssues {
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string[]]$AllowedNames,
        [Parameter(Mandatory = $true)][int]$Line,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Errors
    )

    foreach ($property in @($InputObject.PSObject.Properties)) {
        if (-not (Test-WorkspacePolicyOrdinalContains -Values $AllowedNames -Candidate $property.Name)) {
            Add-WorkspacePolicyIssue `
                -Collection $Errors `
                -Code "unknown_delegation_field" `
                -Line $Line `
                -Message "A delegation event contains an unsupported field."
        }
    }
}

function Test-DelegationRequiredString {
    param(
        [Parameter(Mandatory = $true)][object]$EventObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][int]$Line,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Errors,
        [switch]$AllowEmpty
    )

    if (-not (Test-WorkspacePolicyProperty -InputObject $EventObject -Name $Name)) {
        Add-WorkspacePolicyIssue -Collection $Errors -Code "missing_required_field" -Line $Line -Message "A required delegation field is missing."
        return $false
    }

    $value = $EventObject.PSObject.Properties[$Name].Value
    if (
        -not ($value -is [string]) -or
        ((-not $AllowEmpty) -and [string]::IsNullOrWhiteSpace([string]$value)) -or
        -not [string]::Equals([string]$value, ([string]$value).Trim(), [StringComparison]::Ordinal)
    ) {
        Add-WorkspacePolicyIssue -Collection $Errors -Code "invalid_field_type" -Line $Line -Message "A delegation field has an invalid type or value."
        return $false
    }

    return $true
}

function Get-DelegationPathList {
    param(
        [Parameter(Mandatory = $true)][object]$EventObject,
        [Parameter(Mandatory = $true)][int]$Line,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Errors
    )

    if (-not (Test-WorkspacePolicyProperty -InputObject $EventObject -Name "paths")) {
        Add-WorkspacePolicyIssue -Collection $Errors -Code "missing_required_field" -Line $Line -Message "A required delegation field is missing."
        return @()
    }
    if (-not ($EventObject.paths -is [System.Array]) -or @($EventObject.paths).Count -eq 0) {
        Add-WorkspacePolicyIssue -Collection $Errors -Code "invalid_paths" -Line $Line -Message "Delegation paths must be a nonempty array."
        return @()
    }

    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($path in @($EventObject.paths)) {
        $normalized = $null
        try {
            $normalized = ConvertTo-WorkspaceRelativePolicyPath -Path $path
        }
        catch {
            Add-WorkspacePolicyIssue -Collection $Errors -Code "invalid_delegation_path" -Line $Line -Message "A delegation path is invalid."
            continue
        }

        if (Test-WorkspacePolicyOrdinalContains -Values @($paths.ToArray()) -Candidate $normalized) {
            Add-WorkspacePolicyIssue -Collection $Errors -Code "duplicate_delegation_path" -Line $Line -Message "Delegation paths must not contain duplicates."
            continue
        }
        $paths.Add($normalized) | Out-Null
    }

    return @($paths.ToArray())
}

function Get-DelegationActionList {
    param(
        [Parameter(Mandatory = $true)][object]$EventObject,
        [Parameter(Mandatory = $true)][int]$Line,
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Errors
    )

    if (-not (Test-WorkspacePolicyProperty -InputObject $EventObject -Name "actions")) {
        Add-WorkspacePolicyIssue -Collection $Errors -Code "missing_required_field" -Line $Line -Message "A required delegation field is missing."
        return @()
    }
    if (-not ($EventObject.actions -is [System.Array]) -or @($EventObject.actions).Count -eq 0) {
        Add-WorkspacePolicyIssue -Collection $Errors -Code "invalid_actions" -Line $Line -Message "Delegation actions must be a nonempty array."
        return @()
    }

    $actions = New-Object System.Collections.Generic.List[string]
    foreach ($action in @($EventObject.actions)) {
        if (
            -not ($action -is [string]) -or
            [string]::IsNullOrWhiteSpace([string]$action) -or
            -not (Test-WorkspacePolicyOrdinalContains -Values $script:WorkspacePolicySupportedActions -Candidate ([string]$action))
        ) {
            Add-WorkspacePolicyIssue -Collection $Errors -Code "unsupported_action" -Line $Line -Message "A delegation action is not supported."
            continue
        }
        if (Test-WorkspacePolicyOrdinalContains -Values @($actions.ToArray()) -Candidate ([string]$action)) {
            Add-WorkspacePolicyIssue -Collection $Errors -Code "duplicate_delegation_action" -Line $Line -Message "Delegation actions must not contain duplicates."
            continue
        }
        $actions.Add([string]$action) | Out-Null
    }

    return @($actions.ToArray())
}

function Test-DelegationGrantorScope {
    param(
        [Parameter(Mandatory = $true)][object]$Policy,
        [Parameter(Mandatory = $true)][object]$Grant
    )

    foreach ($path in @($Grant.paths)) {
        foreach ($protected in @($Policy.protected_paths)) {
            if (Test-WorkspacePolicyPathOverlap -First ([string]$path) -Second ([string]$protected.path)) {
                return $false
            }
        }

        $ownerMatch = Get-PolicyOwnerMatch -Policy $Policy -RelativePath ([string]$path)
        if (
            $null -eq $ownerMatch -or
            -not [string]::Equals([string]$ownerMatch.owner, [string]$Grant.grantor_role, [StringComparison]::Ordinal)
        ) {
            return $false
        }

        foreach ($action in @($Grant.actions)) {
            if (-not (Test-WorkspacePolicyOrdinalContains -Values @($ownerMatch.actions) -Candidate ([string]$action))) {
                return $false
            }
        }

        if ([string]$path -like "*/") {
            foreach ($nestedEntry in @($Policy.ownership)) {
                $nestedPath = [string]$nestedEntry.path
                if (
                    $nestedPath.Length -gt ([string]$path).Length -and
                    $nestedPath.StartsWith([string]$path, [StringComparison]::Ordinal)
                ) {
                    if (-not [string]::Equals([string]$nestedEntry.owner, [string]$Grant.grantor_role, [StringComparison]::Ordinal)) {
                        return $false
                    }
                    foreach ($action in @($Grant.actions)) {
                        if (-not (Test-WorkspacePolicyOrdinalContains -Values @($nestedEntry.actions) -Candidate ([string]$action))) {
                            return $false
                        }
                    }
                }
            }
        }
    }

    return $true
}

function Read-DelegationLedger {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [object]$Policy,
        [DateTimeOffset]$ReferenceTime = [DateTimeOffset]::UtcNow
    )

    $errors = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[object]
    $grants = New-Object System.Collections.Generic.List[object]
    $revocations = New-Object System.Collections.Generic.List[object]
    $grantById = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)
    $revocationById = New-Object 'System.Collections.Generic.Dictionary[string,object]' ([StringComparer]::Ordinal)

    $newResult = {
        [pscustomobject][ordered]@{
            grants = @($grants.ToArray())
            revocations = @($revocations.ToArray())
            errors = @($errors.ToArray())
            warnings = @($warnings.ToArray())
            ok = ($errors.Count -eq 0)
        }
    }

    if (
        -not (Test-WorkspacePolicyObject -InputObject $Policy) -or
        -not (Test-WorkspacePolicyProperty -InputObject $Policy -Name "policy_revision") -or
        -not (Test-WorkspacePolicyInteger -Value $Policy.policy_revision)
    ) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "policy_invalid" -Message "The workspace policy is invalid; delegation validation was not performed."
        return & $newResult
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-WorkspacePolicyIssue -Collection $errors -Code "missing_file" -Message "The delegation ledger file is missing."
        return & $newResult
    }

    try {
        $bytes = [IO.File]::ReadAllBytes($Path)
    }
    catch {
        Add-WorkspacePolicyIssue -Collection $errors -Code "unreadable_file" -Message "The delegation ledger could not be read."
        return & $newResult
    }

    $offset = 0
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        Add-WorkspacePolicyIssue -Collection $warnings -Code "utf8_bom" -Line 1 -Message "UTF-8 BOM detected; JSONL should use UTF-8 without a BOM."
        $offset = 3
    }

    try {
        $encoding = New-Object Text.UTF8Encoding($false, $true)
        $content = $encoding.GetString($bytes, $offset, $bytes.Length - $offset)
    }
    catch {
        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_utf8" -Message "The delegation ledger is not valid UTF-8."
        return & $newResult
    }

    $lines = @()
    if ($content.Length -gt 0) {
        $lines = @([regex]::Split($content, "\r\n|\n|\r"))
        if ($lines.Count -gt 1 -and $lines[-1].Length -eq 0) {
            $lines = @($lines[0..($lines.Count - 2)])
        }
    }

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $lineNumber = $index + 1
        $line = [string]$lines[$index]
        if ([string]::IsNullOrWhiteSpace($line)) {
            Add-WorkspacePolicyIssue -Collection $errors -Code "blank_line" -Line $lineNumber -Message "Blank lines are not allowed in the delegation ledger."
            continue
        }
        if ($line.IndexOf([char]0) -ge 0) {
            Add-WorkspacePolicyIssue -Collection $errors -Code "nul_byte" -Line $lineNumber -Message "NUL bytes are not allowed in the delegation ledger."
            continue
        }

        try {
            $eventObject = ConvertFrom-WorkspaceJson -InputObject $line
        }
        catch {
            Add-WorkspacePolicyIssue -Collection $errors -Code "malformed_json" -Line $lineNumber -Message "A delegation ledger line is not valid JSON."
            continue
        }

        if (-not (Test-WorkspacePolicyObject -InputObject $eventObject)) {
            Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_root_type" -Line $lineNumber -Message "Each delegation ledger line must have an object root."
            continue
        }
        if (
            -not (Test-WorkspacePolicyProperty -InputObject $eventObject -Name "event") -or
            -not ($eventObject.event -is [string])
        ) {
            Add-WorkspacePolicyIssue -Collection $errors -Code "missing_required_field" -Line $lineNumber -Message "A delegation event type is required."
            continue
        }

        $eventType = [string]$eventObject.event
        if ([string]::Equals($eventType, "grant", [StringComparison]::Ordinal)) {
            $initialErrorCount = $errors.Count
            Add-DelegationUnknownFieldIssues `
                -InputObject $eventObject `
                -AllowedNames @("event", "delegation_id", "policy_revision", "grantor_role", "grantee_role", "task_id", "paths", "actions", "issued_at", "expires_at", "note") `
                -Line $lineNumber `
                -Errors $errors

            $idValid = Test-DelegationRequiredString -EventObject $eventObject -Name "delegation_id" -Line $lineNumber -Errors $errors
            $grantorValid = Test-DelegationRequiredString -EventObject $eventObject -Name "grantor_role" -Line $lineNumber -Errors $errors
            $granteeValid = Test-DelegationRequiredString -EventObject $eventObject -Name "grantee_role" -Line $lineNumber -Errors $errors
            $taskValid = Test-DelegationRequiredString -EventObject $eventObject -Name "task_id" -Line $lineNumber -Errors $errors
            Test-DelegationRequiredString -EventObject $eventObject -Name "note" -Line $lineNumber -Errors $errors -AllowEmpty | Out-Null

            $revisionValid = $true
            if (-not (Test-WorkspacePolicyProperty -InputObject $eventObject -Name "policy_revision")) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "missing_required_field" -Line $lineNumber -Message "A required delegation field is missing."
                $revisionValid = $false
            }
            elseif (-not (Test-WorkspacePolicyInteger -Value $eventObject.policy_revision) -or [decimal]$eventObject.policy_revision -le 0) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_policy_revision" -Line $lineNumber -Message "A delegation policy revision must be a positive integer."
                $revisionValid = $false
            }

            $paths = @(Get-DelegationPathList -EventObject $eventObject -Line $lineNumber -Errors $errors)
            $actions = @(Get-DelegationActionList -EventObject $eventObject -Line $lineNumber -Errors $errors)

            $issuedValid = Test-WorkspacePolicyProperty -InputObject $eventObject -Name "issued_at"
            $issuedAt = $null
            if ($issuedValid) { $issuedAt = Get-DelegationTimestampValue -Value $eventObject.issued_at }
            if (-not $issuedValid) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "missing_required_field" -Line $lineNumber -Message "A required delegation field is missing."
            }
            elseif ($null -eq $issuedAt) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_timestamp" -Line $lineNumber -Message "A delegation timestamp must be ISO 8601 with an offset."
            }

            $expiresValid = Test-WorkspacePolicyProperty -InputObject $eventObject -Name "expires_at"
            $expiresAt = $null
            if ($expiresValid) { $expiresAt = Get-DelegationTimestampValue -Value $eventObject.expires_at }
            if (-not $expiresValid) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "missing_required_field" -Line $lineNumber -Message "A required delegation field is missing."
            }
            elseif ($null -eq $expiresAt) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_timestamp" -Line $lineNumber -Message "A delegation timestamp must be ISO 8601 with an offset."
            }
            elseif ($null -ne $issuedAt -and $expiresAt -le $issuedAt) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_expiry_order" -Line $lineNumber -Message "A delegation expiry must be later than its issue time."
            }

            if ($idValid -and $grantById.ContainsKey([string]$eventObject.delegation_id)) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "duplicate_delegation_id" -Line $lineNumber -Message "A delegation identifier cannot be reused."
            }

            if ($errors.Count -eq $initialErrorCount -and $idValid -and $grantorValid -and $granteeValid -and $taskValid -and $revisionValid) {
                $grant = [pscustomobject][ordered]@{
                    delegation_id = [string]$eventObject.delegation_id
                    policy_revision = [long]$eventObject.policy_revision
                    grantor_role = [string]$eventObject.grantor_role
                    grantee_role = [string]$eventObject.grantee_role
                    task_id = [string]$eventObject.task_id
                    paths = @($paths)
                    actions = @($actions)
                    issued_at = [DateTimeOffset]$issuedAt
                    expires_at = [DateTimeOffset]$expiresAt
                    line = $lineNumber
                    revoked = $false
                    revoked_at = $null
                    active = $false
                }
                $grants.Add($grant) | Out-Null
                $grantById.Add($grant.delegation_id, $grant)
            }
        }
        elseif ([string]::Equals($eventType, "revoke", [StringComparison]::Ordinal)) {
            $initialErrorCount = $errors.Count
            Add-DelegationUnknownFieldIssues `
                -InputObject $eventObject `
                -AllowedNames @("event", "delegation_id", "revoked_by_role", "timestamp", "reason") `
                -Line $lineNumber `
                -Errors $errors

            $idValid = Test-DelegationRequiredString -EventObject $eventObject -Name "delegation_id" -Line $lineNumber -Errors $errors
            $revokerValid = Test-DelegationRequiredString -EventObject $eventObject -Name "revoked_by_role" -Line $lineNumber -Errors $errors
            Test-DelegationRequiredString -EventObject $eventObject -Name "reason" -Line $lineNumber -Errors $errors | Out-Null

            $timestampPresent = Test-WorkspacePolicyProperty -InputObject $eventObject -Name "timestamp"
            $timestamp = $null
            if ($timestampPresent) { $timestamp = Get-DelegationTimestampValue -Value $eventObject.timestamp }
            if (-not $timestampPresent) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "missing_required_field" -Line $lineNumber -Message "A required delegation field is missing."
            }
            elseif ($null -eq $timestamp) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_timestamp" -Line $lineNumber -Message "A delegation timestamp must be ISO 8601 with an offset."
            }

            $grant = $null
            if ($idValid) {
                if (-not $grantById.TryGetValue([string]$eventObject.delegation_id, [ref]$grant)) {
                    Add-WorkspacePolicyIssue -Collection $errors -Code "unknown_delegation_id" -Line $lineNumber -Message "A revocation must reference an earlier grant."
                }
                elseif ($revocationById.ContainsKey([string]$eventObject.delegation_id)) {
                    Add-WorkspacePolicyIssue -Collection $errors -Code "repeated_revocation" -Line $lineNumber -Message "A delegation cannot be revoked more than once."
                }
                else {
                    if ($null -ne $timestamp -and $timestamp -lt $grant.issued_at) {
                        Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_revocation_order" -Line $lineNumber -Message "A revocation cannot precede its grant."
                    }
                    if ($revokerValid) {
                        $revokerRole = Get-WorkspacePolicyRole -Policy $Policy -RoleId ([string]$eventObject.revoked_by_role)
                        if ($null -eq $revokerRole) {
                            Add-WorkspacePolicyIssue -Collection $errors -Code "unknown_role" -Line $lineNumber -Message "A revocation references an unknown role."
                        }
                        elseif (
                            -not [string]::Equals([string]$eventObject.revoked_by_role, [string]$grant.grantor_role, [StringComparison]::Ordinal) -and
                            -not [string]::Equals([string]$eventObject.revoked_by_role, [string]$Policy.human_override_role, [StringComparison]::Ordinal)
                        ) {
                            Add-WorkspacePolicyIssue -Collection $errors -Code "unauthorized_revocation" -Line $lineNumber -Message "The revoking role is not authorized for this delegation."
                        }
                    }
                }
            }

            if ($errors.Count -eq $initialErrorCount -and $null -ne $grant) {
                $revocation = [pscustomobject][ordered]@{
                    delegation_id = [string]$eventObject.delegation_id
                    revoked_by_role = [string]$eventObject.revoked_by_role
                    timestamp = [DateTimeOffset]$timestamp
                    line = $lineNumber
                }
                $revocations.Add($revocation) | Out-Null
                $revocationById.Add($revocation.delegation_id, $revocation)
                $grant.revoked = $true
                $grant.revoked_at = [DateTimeOffset]$timestamp
            }
        }
        else {
            Add-WorkspacePolicyIssue -Collection $errors -Code "unknown_event" -Line $lineNumber -Message "The delegation event type is not supported."
        }
    }

    foreach ($grant in @($grants.ToArray())) {
        $revocationIsEffective = (
            $grant.revoked -and
            $null -ne $grant.revoked_at -and
            $ReferenceTime -ge $grant.revoked_at
        )
        $grantIsWithinTime = (
            $ReferenceTime -ge $grant.issued_at -and
            $ReferenceTime -lt $grant.expires_at -and
            -not $revocationIsEffective
        )
        $grantIsCurrentRevision = ($grant.policy_revision -eq [long]$Policy.policy_revision)
        $grantIsActive = ($grantIsWithinTime -and $grantIsCurrentRevision)
        $grant.active = $grantIsActive

        $grantor = Get-WorkspacePolicyRole -Policy $Policy -RoleId ([string]$grant.grantor_role)
        $grantee = Get-WorkspacePolicyRole -Policy $Policy -RoleId ([string]$grant.grantee_role)
        if ($null -eq $grantor -or $null -eq $grantee) {
            Add-WorkspacePolicyIssue -Collection $errors -Code "unknown_role" -Line $grant.line -Message "A delegation references an unknown role."
        }
        elseif ($grantIsActive) {
            if (
                -not [string]::Equals([string]$grantor.status, "active", [StringComparison]::Ordinal) -or
                -not [string]::Equals([string]$grantee.status, "active", [StringComparison]::Ordinal)
            ) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "inactive_role" -Line $grant.line -Message "An active delegation must use active roles."
            }
        }

        if ([string]::Equals([string]$grant.grantor_role, [string]$grant.grantee_role, [StringComparison]::Ordinal)) {
            Add-WorkspacePolicyIssue -Collection $errors -Code "self_delegation" -Line $grant.line -Message "A role cannot delegate to itself."
        }

        if ($grantIsCurrentRevision) {
            if (-not (Test-DelegationGrantorScope -Policy $Policy -Grant $grant)) {
                Add-WorkspacePolicyIssue -Collection $errors -Code "invalid_grantor_scope" -Line $grant.line -Message "A grantor may delegate only directly owned paths and actions."
            }
        }
        elseif ($grantIsWithinTime) {
            Add-WorkspacePolicyIssue -Collection $warnings -Code "stale_policy_revision" -Line $grant.line -Message "A time-valid delegation uses an older policy revision and is inactive."
        }
    }

    return & $newResult
}
