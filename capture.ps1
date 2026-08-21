[CmdletBinding()]
param(
    [string]$Serial,
    [switch]$Once,
    [switch]$Link,
    [switch]$ShowRawUri,
    [switch]$NoClipboard,
    [switch]$BlockLaunch,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
. (Join-Path $projectRoot 'lib\CaptureSupport.ps1')

$buildScript = Join-Path $projectRoot 'build.ps1'
$localJar = Join-Path $projectRoot 'out\adb-intent-capture.jar'
$remoteJar = '/data/local/tmp/adb-intent-capture.jar'
$mainClass = 'dev.local.adbintentcapture.IntentCaptureMonitor'
$redirectPrefix = 'https://portable-uri-workshop.github.io/#to='

function Find-Adb {
    $command = Get-Command adb.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }

    $sdkCandidates = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        (Join-Path $env:LOCALAPPDATA 'Android\Sdk')
    ) | Where-Object { $_ }

    foreach ($sdk in $sdkCandidates) {
        $candidate = Join-Path $sdk 'platform-tools\adb.exe'
        if (Test-Path -LiteralPath $candidate) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    throw 'adb.exe를 찾지 못했습니다.'
}

function Select-AdbDevice([string]$AdbPath, [string]$RequestedSerial) {
    $deviceLines = & $AdbPath devices -l
    if ($LASTEXITCODE -ne 0) { throw 'adb devices -l 실행에 실패했습니다.' }

    $devices = @($deviceLines | ForEach-Object {
        if ($_ -match '^([^\s]+)\s+device(?:\s+(.*))?$') {
            [pscustomobject]@{
                Serial = $Matches[1]
                Details = if ($Matches.Count -ge 3) { $Matches[2] } else { '' }
            }
        }
    })

    if ($RequestedSerial) {
        $selected = @($devices | Where-Object { $_.Serial -ceq $RequestedSerial })
        if ($selected.Count -ne 1) {
            throw "연결된 ADB 기기에서 serial을 찾지 못했습니다: $(Format-MaskedSerial $RequestedSerial)"
        }
        return $selected[0]
    }
    if ($devices.Count -eq 0) { throw '연결된 ADB 기기가 없습니다.' }
    if ($devices.Count -gt 1) { throw '기기가 여러 대입니다. -Serial 값을 지정하세요.' }
    return $devices[0]
}

function Test-ProcessExited([Diagnostics.Process]$Process, [bool]$Started) {
    if (-not $Started) { return $true }
    try { return $Process.HasExited } catch { return $false }
}

function Stop-MonitorProcess([Diagnostics.Process]$Process, [bool]$Started) {
    if (-not $Started -or (Test-ProcessExited $Process $Started)) { return }
    try {
        $Process.StandardInput.WriteLine('q')
        $Process.StandardInput.Flush()
    } catch {}
    try {
        if ($Process.WaitForExit(2000)) { return }
    } catch {}
    try { $Process.Kill() } catch {}
    try { [void]$Process.WaitForExit(2000) } catch {}
}

$adb = Find-Adb
$device = Select-AdbDevice $adb $Serial
$deviceSerial = $device.Serial
$adbSelector = @('-s', $deviceSerial)

if (-not $SkipBuild -or -not (Test-Path -LiteralPath $localJar)) {
    & $buildScript
    if ($LASTEXITCODE -ne 0) { throw "빌드 스크립트 실패: $LASTEXITCODE" }
}
if (-not (Test-Path -LiteralPath $localJar)) {
    throw '모니터 JAR가 없습니다: out\adb-intent-capture.jar'
}

Write-Host "기기: $(Format-MaskedSerial $deviceSerial)"
Write-Verbose "전체 serial: $deviceSerial"
Write-Verbose "기기 세부정보: $(ConvertTo-SafeConsoleText $device.Details)"
Write-Verbose "로컬 JAR: $localJar"
Write-Host '모니터 업로드 중...'
& $adb @adbSelector push $localJar $remoteJar | Out-Null
if ($LASTEXITCODE -ne 0) { throw '모니터 업로드에 실패했습니다.' }

$startInfo = [Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $adb
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.CreateNoWindow = $true

$monitorArguments = @(
    '-s',
    $deviceSerial,
    'shell',
    "CLASSPATH=$remoteJar",
    'app_process',
    '/system/bin',
    $mainClass
)
if ($BlockLaunch) { $monitorArguments += '--block-launch' }
$argumentMode = Set-ProcessArguments -StartInfo $startInfo -Arguments $monitorArguments
Write-Verbose "process argument API: $argumentMode"

$process = [Diagnostics.Process]::new()
$process.StartInfo = $startInfo
$processStarted = $false
$stderrTask = $null
$capturedCount = 0
$monitorFailure = $null

try {
    if (-not $process.Start()) { throw 'ADB 모니터 프로세스를 시작하지 못했습니다.' }
    $processStarted = $true
    $stderrTask = $process.StandardError.ReadToEndAsync()

    while (($line = $process.StandardOutput.ReadLine()) -ne $null) {
        if ($line -eq 'KAKAOLINK_MONITOR_READY') {
            Write-Host '캡처 준비 완료. 앱에서 카카오톡 공유를 누르세요. 종료: Ctrl+C'
            Write-Host $(if ($Link) { '복사 모드: GitHub Pages Link' } else { '복사 모드: 원본 data URI' })
            if ($BlockLaunch) {
                Write-Warning '차단 모드: 정상 등록된 캡처만 kakaolink://send KakaoTalk Activity 실행을 취소합니다.'
            }
            continue
        }

        if (-not $line.StartsWith("KAKAOLINK_CAPTURE`t")) {
            if ($line) { Write-Verbose (ConvertTo-SafeConsoleText $line) }
            continue
        }

        $fields = $line.Split("`t", 5)
        if ($fields.Count -lt 2) {
            Write-Warning '형식이 잘못된 캡처 출력을 무시합니다.'
            continue
        }

        try {
            $strictUtf8 = [Text.UTF8Encoding]::new($false, $true)
            $rawUri = $strictUtf8.GetString([Convert]::FromBase64String($fields[1]))
        } catch {
            Write-Warning 'UTF-8/Base64 형식이 잘못된 캡처 출력을 무시합니다.'
            continue
        }
        $action = ConvertTo-SafeConsoleText $(if ($fields.Count -ge 3) { $fields[2] } else { '' })
        $targetPackage = ConvertTo-SafeConsoleText $(if ($fields.Count -ge 4) { $fields[3] } else { '' })
        $component = ConvertTo-SafeConsoleText $(if ($fields.Count -ge 5) { $fields[4] } else { '' })
        $outputValue = if ($Link) {
            $redirectPrefix + (ConvertTo-AndroidUriEncoded $rawUri)
        } else {
            $rawUri
        }

        if (-not $NoClipboard) { Set-Clipboard -Value $outputValue }

        $capturedCount++
        Write-Host "캡처 #$capturedCount 완료: action=$action, target=$targetPackage, component=$component"
        if ($Link) {
            Write-Host "원본 URI 길이: $($rawUri.Length), Pages URL 길이: $($outputValue.Length)"
        } else {
            Write-Host "원본 URI 길이: $($rawUri.Length)"
        }
        if (-not $NoClipboard) {
            Write-Host $(if ($Link) { 'GitHub Pages Link를 PC 클립보드에 복사했습니다.' } else { '원본 data URI를 PC 클립보드에 복사했습니다.' })
        }
        if ($BlockLaunch) { Write-Host '원래 KakaoTalk 공유 Activity 실행을 차단했습니다.' }
        if ($ShowRawUri) { Write-Host "RAW URI: $(ConvertTo-SafeConsoleText $rawUri)" }

        if ($Once) { break }
    }
} catch {
    $monitorFailure = $_
} finally {
    Stop-MonitorProcess $process $processStarted

    if ($stderrTask -and (Test-ProcessExited $process $processStarted)) {
        try {
            $stderr = $stderrTask.GetAwaiter().GetResult()
            if ($stderr) { Write-Warning (ConvertTo-SafeConsoleText $stderr.Trim()) }
        } catch {
            if (-not $monitorFailure) { $monitorFailure = $_ }
        }
    }

    try {
        & $adb @adbSelector shell rm -f $remoteJar 2>$null | Out-Null
    } catch {
        Write-Warning '원격 임시 JAR 삭제에 실패했습니다.'
    }
}

if ($monitorFailure) { throw $monitorFailure }
if ($processStarted -and (Test-ProcessExited $process $processStarted) -and $process.ExitCode -ne 0) {
    throw "ADB 모니터가 오류로 종료됐습니다: $($process.ExitCode)"
}
