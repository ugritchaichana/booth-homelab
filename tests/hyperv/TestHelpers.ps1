$script:FixturePath = Join-Path $PSScriptRoot 'fixtures\lab.psd1'

function New-FixtureFile {
    param([hashtable]$Replace = @{}, [string]$Append = '', [string]$Name = 'variant.psd1')
    $text = Get-Content -LiteralPath $script:FixturePath -Raw
    foreach ($pattern in $Replace.Keys) { $text = [regex]::Replace($text, $pattern, [string]$Replace[$pattern]) }
    $text = $text.TrimEnd().TrimEnd('}') + $Append + "`n}`n"
    $path = Join-Path $TestDrive $Name
    Set-Content -LiteralPath $path -Value $text -Encoding UTF8
    $path
}

function New-TestConfig {
    param([hashtable]$Set = @{}, [string]$Path = $script:FixturePath)
    $cfg = Import-PveConfig -Path $Path -LocalOverridePath (Join-Path $TestDrive 'absent.local.psd1')
    foreach ($k in $Set.Keys) { $cfg[$k] = $Set[$k] }
    $cfg
}

function New-TestRoute {
    param([string]$Prefix, [string]$Alias)
    [pscustomobject]@{ DestinationPrefix = $Prefix; InterfaceAlias = $Alias }
}

function New-TestAcl {
    param([int]$Weight, [string]$Action = 'Deny', [string]$Direction = 'Outbound', [string]$Remote = '0.0.0.0/0', [string]$Protocol = '')
    [pscustomobject]@{ Weight = $Weight; Action = $Action; Direction = $Direction; RemoteIPAddress = $Remote; Protocol = $Protocol }
}
