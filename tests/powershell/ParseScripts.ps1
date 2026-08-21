[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$targets = @(
    'capture.ps1',
    'build.ps1',
    'test.ps1',
    'lib\CaptureSupport.ps1'
)

foreach ($target in $targets) {
    $tokens = $null
    $errors = $null
    $path = Join-Path $projectRoot $target
    [Management.Automation.Language.Parser]::ParseFile(
        $path,
        [ref]$tokens,
        [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) {
        $message = ($errors | ForEach-Object { $_.Message }) -join '; '
        throw "$target parse error: $message"
    }
}

Write-Host "PowerShell scripts parsed on $($PSVersionTable.PSVersion)"
