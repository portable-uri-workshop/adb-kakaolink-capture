[CmdletBinding()]
param(
    [string]$Serial,
    [switch]$Once,
    [switch]$ShowRawUri,
    [switch]$NoClipboard,
    [switch]$BlockLaunch,
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'

$projectRoot = $PSScriptRoot
$buildScript = Join-Path $projectRoot 'build.ps1'
$localJar = Join-Path $projectRoot 'out\adb-intent-capture.jar'
$remoteJar = '/data/local/tmp/adb-intent-capture.jar'
$mainClass = 'dev.local.adbintentcapture.IntentCaptureMonitor'
$redirectPrefix = 'https://deep-link-redirector.major-kite-5089.chatgpt.site/#to='

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

function Select-AdbDevice([string]$adbPath, [string]$requestedSerial) {
    $deviceLines = & $adbPath devices
    if ($LASTEXITCODE -ne 0) { throw 'adb devices 실행에 실패했습니다.' }

    $devices = @($deviceLines | ForEach-Object {
        if ($_ -match '^([^\s]+)\s+device$') { $Matches[1] }
    })

    if ($requestedSerial) {
        if ($devices -notcontains $requestedSerial) {
            throw "연결된 ADB 기기에서 serial을 찾지 못했습니다: $requestedSerial"
        }
        return $requestedSerial
    }
    if ($devices.Count -eq 0) { throw '연결된 ADB 기기가 없습니다.' }
    if ($devices.Count -gt 1) { throw '기기가 여러 대입니다. -Serial 값을 지정하세요.' }
    return $devices[0]
}

function ConvertTo-AndroidUriEncoded([string]$value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($value)
    $builder = [Text.StringBuilder]::new($bytes.Length * 3)
    foreach ($byte in $bytes) {
        $isAlphaNumeric =
            ($byte -ge 0x41 -and $byte -le 0x5A) -or
            ($byte -ge 0x61 -and $byte -le 0x7A) -or
            ($byte -ge 0x30 -and $byte -le 0x39)
        $isAllowedPunctuation = $byte -in @(
            0x5F, # _
            0x2D, # -
            0x21, # !
            0x2E, # .
            0x7E, # ~
            0x27, # '
            0x28, # (
            0x29, # )
            0x2A  # *
        )

        if ($isAlphaNumeric -or $isAllowedPunctuation) {
            [void]$builder.Append([char]$byte)
        } else {
            [void]$builder.Append('%')
            [void]$builder.Append($byte.ToString('X2'))
        }
    }
    return $builder.ToString()
}

$adb = Find-Adb
$deviceSerial = Select-AdbDevice $adb $Serial
$adbSelector = @('-s', $deviceSerial)

if (-not $SkipBuild -or -not (Test-Path -LiteralPath $localJar)) {
    & $buildScript
    if ($LASTEXITCODE -ne 0) { throw "빌드 스크립트 실패: $LASTEXITCODE" }
}
if (-not (Test-Path -LiteralPath $localJar)) {
    throw "모니터 JAR가 없습니다: $localJar"
}

Write-Host "기기: $deviceSerial"
Write-Host '모니터 업로드 중...'
& $adb @adbSelector push $localJar $remoteJar | Out-Host
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
        $mainClass)
if ($BlockLaunch) {
    $monitorArguments += '--block-launch'
}

foreach ($argument in $monitorArguments) {
    [void]$startInfo.ArgumentList.Add($argument)
}

$process = [Diagnostics.Process]::new()
$process.StartInfo = $startInfo
$capturedCount = 0

try {
    if (-not $process.Start()) { throw 'ADB 모니터 프로세스를 시작하지 못했습니다.' }
    $stderrTask = $process.StandardError.ReadToEndAsync()

    while (($line = $process.StandardOutput.ReadLine()) -ne $null) {
        if ($line -eq 'KAKAOLINK_MONITOR_READY') {
            Write-Host '캡처 준비 완료. 앱에서 카카오톡 공유를 누르세요. 종료: Ctrl+C'
            if ($BlockLaunch) {
                Write-Warning '차단 모드: 캡처한 kakaolink://send KakaoTalk Activity는 실행하지 않습니다.'
            }
            continue
        }

        if (-not $line.StartsWith("KAKAOLINK_CAPTURE`t")) {
            if ($line) { Write-Verbose $line }
            continue
        }

        $fields = $line.Split("`t", 5)
        if ($fields.Count -lt 2) {
            Write-Warning '형식이 잘못된 캡처 출력을 무시합니다.'
            continue
        }

        $rawUri = [Text.Encoding]::UTF8.GetString(
            [Convert]::FromBase64String($fields[1]))
        $action = if ($fields.Count -ge 3) { $fields[2] } else { '' }
        $targetPackage = if ($fields.Count -ge 4) { $fields[3] } else { '' }
        $component = if ($fields.Count -ge 5) { $fields[4] } else { '' }
        $portableUrl = $redirectPrefix + (ConvertTo-AndroidUriEncoded $rawUri)

        if (-not $NoClipboard) {
            Set-Clipboard -Value $portableUrl
        }

        $capturedCount++
        Write-Host "캡처 #$capturedCount 완료: action=$action, target=$targetPackage, component=$component"
        Write-Host "원본 URI 길이: $($rawUri.Length), redirect URL 길이: $($portableUrl.Length)"
        if (-not $NoClipboard) { Write-Host 'redirect URL을 PC 클립보드에 복사했습니다.' }
        if ($BlockLaunch) { Write-Host '원래 KakaoTalk 공유 Activity 실행을 차단했습니다.' }
        if ($ShowRawUri) { Write-Host "RAW URI: $rawUri" }

        if ($Once) { break }
    }

    if (-not $process.HasExited -and $Once) {
        $process.StandardInput.WriteLine('q')
        $process.StandardInput.Flush()
    }
    if (-not $process.HasExited) {
        [void]$process.WaitForExit(2000)
    }

    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($stderr) { Write-Warning $stderr.Trim() }
    if ($process.HasExited -and $process.ExitCode -ne 0) {
        throw "ADB 모니터가 오류로 종료됐습니다: $($process.ExitCode)"
    }

} finally {
    if ($process -and -not $process.HasExited) {
        try {
            $process.StandardInput.WriteLine('q')
            $process.StandardInput.Flush()
            [void]$process.WaitForExit(1500)
        } catch {}
    }
    if ($process -and -not $process.HasExited) {
        try { $process.Kill($true) } catch {}
    }
    & $adb @adbSelector shell rm -f $remoteJar 2>$null
}
