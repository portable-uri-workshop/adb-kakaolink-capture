[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$sourceFile = Join-Path $projectRoot 'src\dev\local\adbintentcapture\IntentCaptureMonitor.java'
$policyFile = Join-Path $projectRoot 'src\dev\local\adbintentcapture\LaunchDecision.java'
$stubFile = Join-Path $projectRoot 'compile-stubs\android\app\IActivityController.java'
$tempRoot = Join-Path $projectRoot 'temp\build'
$classesDir = Join-Path $tempRoot 'classes'
$dexDir = Join-Path $tempRoot 'dex'
$stubJar = Join-Path $tempRoot 'hidden-stubs.jar'
$monitorClassesJar = Join-Path $tempRoot 'monitor-classes.jar'
$outputDir = Join-Path $projectRoot 'out'
$outputJar = Join-Path $outputDir 'adb-intent-capture.jar'

function Find-AndroidSdk {
    $candidates = @(@(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) })

    if (-not $candidates) {
        throw 'Android SDK를 찾지 못했습니다. ANDROID_SDK_ROOT 또는 ANDROID_HOME을 설정하세요.'
    }
    return (Resolve-Path -LiteralPath $candidates[0]).Path
}

function Get-JavaTool([string]$name) {
    if ($env:JAVA_HOME) {
        $candidate = Join-Path $env:JAVA_HOME "bin\$name.exe"
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return (Get-Command "$name.exe" -ErrorAction Stop).Source
}

$androidSdk = Find-AndroidSdk
$platform = Join-Path $androidSdk 'platforms\android-36'
$buildTools = Join-Path $androidSdk 'build-tools\36.1.0'
$androidJar = Join-Path $platform 'android.jar'
$d8 = Join-Path $buildTools 'd8.bat'
$javac = Get-JavaTool 'javac'
$jar = Get-JavaTool 'jar'

if (-not (Test-Path -LiteralPath $androidJar)) {
    throw "android.jar가 없습니다: $androidJar"
}
if (-not (Test-Path -LiteralPath $d8)) {
    throw "d8.bat가 없습니다: $d8"
}

if (Test-Path -LiteralPath $tempRoot) {
    $resolvedTemp = (Resolve-Path -LiteralPath $tempRoot).Path
    $resolvedProject = (Resolve-Path -LiteralPath $projectRoot).Path
    if (-not $resolvedTemp.StartsWith(
            $resolvedProject + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "안전하지 않은 임시 경로입니다: $resolvedTemp"
    }
    Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
}

New-Item -ItemType Directory -Force $classesDir, $dexDir, $outputDir | Out-Null

Write-Host '[1/4] Java 소스 컴파일'
Write-Verbose "javac: $javac"
Write-Verbose "Android SDK: $androidSdk"
& $javac `
    -encoding UTF-8 `
    -Xlint:-options `
    --release 8 `
    -classpath $androidJar `
    -d $classesDir `
    $stubFile `
    $policyFile `
    $sourceFile
if ($LASTEXITCODE -ne 0) { throw "javac 실패: $LASTEXITCODE" }

Write-Host '[2/4] compile-only hidden API stub JAR 생성'
& $jar --create --file $stubJar -C $classesDir 'android/app'
if ($LASTEXITCODE -ne 0) { throw "stub JAR 생성 실패: $LASTEXITCODE" }

Write-Host '[3/4] monitor class JAR 생성 및 DEX 변환'
& $jar --create --file $monitorClassesJar -C $classesDir 'dev/local/adbintentcapture'
if ($LASTEXITCODE -ne 0) { throw "monitor class JAR 생성 실패: $LASTEXITCODE" }

& $d8 `
    --release `
    --min-api 26 `
    --lib $androidJar `
    --classpath $stubJar `
    --output $dexDir `
    $monitorClassesJar
if ($LASTEXITCODE -ne 0) { throw "D8 실패: $LASTEXITCODE" }

Write-Host '[4/4] app_process용 DEX JAR 생성'
if (Test-Path -LiteralPath $outputJar) {
    Remove-Item -LiteralPath $outputJar -Force
}
& $jar --create --file $outputJar -C $dexDir 'classes.dex'
if ($LASTEXITCODE -ne 0) { throw "최종 JAR 생성 실패: $LASTEXITCODE" }

$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $outputJar
Write-Host '완료: out\adb-intent-capture.jar'
Write-Verbose "절대 경로: $outputJar"
Write-Host "SHA-256: $($hash.Hash)"
