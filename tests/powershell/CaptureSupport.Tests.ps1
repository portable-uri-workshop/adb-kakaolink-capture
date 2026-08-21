[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
. (Join-Path $projectRoot 'lib\CaptureSupport.ps1')

function Assert-Equal([string]$Label, $Expected, $Actual) {
    if ($Expected.Count -ne $Actual.Count) {
        throw "$Label count mismatch: expected $($Expected.Count), actual $($Actual.Count), type=$($Actual.GetType().FullName), value=$Actual"
    }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($Expected[$index] -cne $Actual[$index]) {
            throw "$Label mismatch at $index`: expected <$($Expected[$index])>, actual <$($Actual[$index])>"
        }
    }
}

function Invoke-ArgumentProbe([string[]]$Values, [switch]$ForceLegacy) {
    $hostExecutable = if ($PSVersionTable.PSEdition -eq 'Core') {
        Join-Path $PSHOME 'pwsh.exe'
    } else {
        Join-Path $PSHOME 'powershell.exe'
    }
    $probeScript = Join-Path $projectRoot 'tests\powershell\argv-echo.ps1'
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $hostExecutable
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    if ($null -ne $startInfo.PSObject.Properties['StandardOutputEncoding']) {
        $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    }
    $arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $probeScript) + $Values
    $mode = Set-ProcessArguments -StartInfo $startInfo -Arguments $arguments -ForceLegacy:$ForceLegacy

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw 'argument probe did not start' }
    $output = $process.StandardOutput.ReadToEnd()
    $errorOutput = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "argument probe failed ($mode): $errorOutput" }
    $decoded = [object[]](ConvertFrom-Json -InputObject $output)
    Assert-Equal "argument probe ($mode)" $Values $decoded
}

$cases = @(
    'plain',
    'space value',
    '',
    'embedded"quote',
    'trailing slash\',
    'space and trailing slash \',
    ('unicode-' + [char]0xD55C + [char]0xAE00),
    ([char]36 + '(Get-Process)'),
    ('semi' + [char]59 + 'colon' + [char]38 + 'pipe' + [char]124 + 'literal')
)

Invoke-ArgumentProbe -Values $cases -ForceLegacy
if ($null -ne ([Diagnostics.ProcessStartInfo]::new()).PSObject.Properties['ArgumentList']) {
    Invoke-ArgumentProbe -Values $cases
}

if ((ConvertTo-AndroidUriEncoded 'kakao://a b%') -cne 'kakao%3A%2F%2Fa%20b%25') {
    throw 'Android URI encoding regression'
}
$unsafeConsoleText = 'safe' + [char]27 + '[31m' + [char]10 + 'next'
$safeConsoleText = ConvertTo-SafeConsoleText $unsafeConsoleText
if ($safeConsoleText.Contains([char]27) -or $safeConsoleText.Contains([char]10)) {
    throw 'console control sanitization regression'
}
if ((Format-MaskedSerial 'R3CY60LMRYR') -ceq 'R3CY60LMRYR') {
    throw 'serial masking regression'
}

Write-Host "CaptureSupport tests passed on PowerShell $($PSVersionTable.PSVersion)"
