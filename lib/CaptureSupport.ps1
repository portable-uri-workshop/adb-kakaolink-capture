function ConvertTo-AndroidUriEncoded([string]$Value) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
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

function ConvertTo-WindowsCommandLineArgument([AllowEmptyString()][string]$Value) {
    if ($Value.Length -eq 0) { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }

    $builder = [Text.StringBuilder]::new($Value.Length + 2)
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
            [void]$builder.Append('"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) {
        [void]$builder.Append(('\' * ($backslashes * 2)))
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Set-ProcessArguments {
    param(
        [Parameter(Mandatory)]
        [Diagnostics.ProcessStartInfo]$StartInfo,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Arguments,

        [switch]$ForceLegacy
    )

    $argumentListProperty = $StartInfo.PSObject.Properties['ArgumentList']
    if (-not $ForceLegacy -and $null -ne $argumentListProperty) {
        foreach ($argument in $Arguments) {
            [void]$StartInfo.ArgumentList.Add($argument)
        }
        return 'ArgumentList'
    }

    $StartInfo.Arguments = ($Arguments | ForEach-Object {
        ConvertTo-WindowsCommandLineArgument $_
    }) -join ' '
    return 'Arguments'
}

function ConvertTo-SafeConsoleText([AllowNull()][string]$Value) {
    if ($null -eq $Value) { return '' }
    return [Text.RegularExpressions.Regex]::Replace(
        $Value,
        '[\u0000-\u001f\u007f-\u009f]',
        [Text.RegularExpressions.MatchEvaluator]{ param($match) '?' })
}

function Format-MaskedSerial([AllowEmptyString()][string]$Serial) {
    if ($Serial.Length -le 4) { return '*' * $Serial.Length }
    $hiddenLength = [Math]::Max(3, $Serial.Length - 4)
    return $Serial.Substring(0, 2) + ('*' * $hiddenLength) + $Serial.Substring($Serial.Length - 2)
}
