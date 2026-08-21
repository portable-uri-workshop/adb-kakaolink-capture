[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$policyFile = Join-Path $projectRoot 'src\dev\local\adbintentcapture\LaunchDecision.java'
$testFile = Join-Path $projectRoot 'tests\dev\local\adbintentcapture\LaunchDecisionTest.java'
$testClasses = Join-Path $projectRoot 'temp\test-classes'
$javac = (Get-Command javac.exe -ErrorAction Stop).Source
$java = (Get-Command java.exe -ErrorAction Stop).Source

if (Test-Path -LiteralPath $testClasses) {
    $resolvedTests = (Resolve-Path -LiteralPath $testClasses).Path
    $resolvedProject = (Resolve-Path -LiteralPath $projectRoot).Path
    if (-not $resolvedTests.StartsWith(
            $resolvedProject + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "안전하지 않은 테스트 임시 경로입니다: $resolvedTests"
    }
    Remove-Item -LiteralPath $resolvedTests -Recurse -Force
}

New-Item -ItemType Directory -Force $testClasses | Out-Null

& $javac `
    -encoding UTF-8 `
    -Xlint:-options `
    --release 8 `
    -d $testClasses `
    $policyFile `
    $testFile
if ($LASTEXITCODE -ne 0) { throw "테스트 javac 실패: $LASTEXITCODE" }

& $java -cp $testClasses 'dev.local.adbintentcapture.LaunchDecisionTest'
if ($LASTEXITCODE -ne 0) { throw "LaunchDecisionTest 실패: $LASTEXITCODE" }

& (Join-Path $projectRoot 'tests\powershell\CaptureSupport.Tests.ps1')
if ($LASTEXITCODE -ne 0) { throw "CaptureSupport 테스트 실패: $LASTEXITCODE" }

& (Join-Path $projectRoot 'tests\powershell\ParseScripts.ps1')
if ($LASTEXITCODE -ne 0) { throw "PowerShell parse 테스트 실패: $LASTEXITCODE" }
