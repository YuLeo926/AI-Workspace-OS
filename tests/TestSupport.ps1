Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TestPowerShellCommand {
    switch ($PSVersionTable.PSEdition) {
        "Desktop" {
            $source = Join-Path $PSHOME "powershell.exe"
            $baseArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File")
        }
        "Core" {
            $source = Join-Path $PSHOME "pwsh.exe"
            $baseArgs = @("-NoProfile", "-File")
        }
        default {
            throw "Unsupported PowerShell edition: $($PSVersionTable.PSEdition)"
        }
    }

    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "PowerShell executable not found for $($PSVersionTable.PSEdition) edition: $source"
    }

    return [pscustomobject]@{ Source = $source; BaseArgs = $baseArgs }
}

function Invoke-TestScript {
    param([string]$ScriptPath, [string[]]$Arguments = @())
    $command = Get-TestPowerShellCommand
    $argList = @($command.BaseArgs)
    $argList += $ScriptPath
    $argList += @($Arguments)
    $previousErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $output = & $command.Source @argList 2>&1
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = @($output) }
}

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message Expected: $Expected Actual: $Actual" }
}

function Assert-ExitCode {
    param($Result, [int]$Expected, [string]$Context)
    if ($Result.ExitCode -ne $Expected) {
        $joined = ($Result.Output | Out-String).Trim()
        throw "$Context expected exit code $Expected, got $($Result.ExitCode). Output: $joined"
    }
}

function New-TestDirectory {
    param([string]$Prefix)
    $path = Join-Path ([IO.Path]::GetTempPath()) ($Prefix + [Guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $path | Out-Null
    return $path
}

function Write-Utf8NoBom {
    param([string]$Path, [AllowEmptyString()][string]$Content)
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    [IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Write-Utf8Bom {
    param([string]$Path, [AllowEmptyString()][string]$Content)
    $encoding = New-Object System.Text.UTF8Encoding($true, $true)
    [IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Read-Utf8Strict {
    param([string]$Path)
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    return [IO.File]::ReadAllText($Path, $encoding)
}
