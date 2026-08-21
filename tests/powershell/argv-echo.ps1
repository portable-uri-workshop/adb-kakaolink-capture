param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [AllowEmptyString()]
    [string[]]$Values
)

[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$Values | ConvertTo-Json -Compress
