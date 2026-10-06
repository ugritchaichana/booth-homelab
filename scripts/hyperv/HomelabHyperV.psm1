function Write-HomelabLog {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '')]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet('Info', 'Step', 'Pass', 'Warn', 'Fail', 'Skip', 'Plan')][string]$Level = 'Info'
    )
    $colors = @{ Info = 'Gray'; Step = 'Cyan'; Pass = 'Green'; Warn = 'Yellow'; Fail = 'Red'; Skip = 'DarkYellow'; Plan = 'White' }
    $tags = @{ Info = '      '; Step = '==>   '; Pass = '[PASS]'; Warn = '[WARN]'; Fail = '[FAIL]'; Skip = '[SKIP]'; Plan = '[PLAN]' }
    $tag = $tags[$Level]
    $text = $Message
    foreach ($pair in @(@($env:LOCALAPPDATA, '%LOCALAPPDATA%'), @($env:USERPROFILE, '%USERPROFILE%'))) {
        if ($pair[0]) { $text = [regex]::Replace($text, [regex]::Escape($pair[0]), $pair[1], 'IgnoreCase') }
    }
    foreach ($line in ($text -split "`r?`n")) {
        Write-Host ('{0} {1}' -f $tag, $line) -ForegroundColor $colors[$Level]
        $tag = '      '
    }
}

function Import-PveConfig {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$LocalOverridePath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Config file not found: $Path" }
    $full = (Resolve-Path -LiteralPath $Path).ProviderPath
    $cfg = Import-PowerShellDataFile -Path $full

    $required = @(
        'VmName', 'RootPath', 'SwitchName', 'NatName', 'NatPrefix', 'HostAddress', 'GuestAddress', 'MacAddress',
        'ProcessorCount', 'MemoryGiB', 'DiskGiB', 'SshPort', 'WebPort', 'MinHostFreeRamAfterVmGiB',
        'MinFreeDiskAfterGrowthGiB', 'EmptyVhdxMaxMiB', 'InstallTimeoutMinutes', 'ProgressSeconds',
        'BootTimeoutMinutes', 'StopTimeoutSeconds', 'CheckpointName', 'FirewallRuleName',
        'AclWeightMin', 'AclWeightMax', 'MaxExtraDenyPrefixes', 'MinHostVmConfigVersion', 'AddOwnerToHyperVAdministrators'
    )
    $missing = @($required | Where-Object { -not $cfg.ContainsKey($_) })
    if ($missing.Count -gt 0) { throw "Config $full is missing keys: $($missing -join ', ')" }

    if (-not $LocalOverridePath) {
        if (-not $env:LOCALAPPDATA) { throw 'LOCALAPPDATA is not set' }
        $LocalOverridePath = Join-Path $env:LOCALAPPDATA ('homelab\' + [IO.Path]::GetFileNameWithoutExtension($full) + '.local.psd1')
    }
    $overrideKeys = @('StaticDenyPrefix', 'EgressInterfaceAlias', 'AddOwnerToHyperVAdministrators')
    $local = @{}
    if (Test-Path -LiteralPath $LocalOverridePath -PathType Leaf) {
        $local = Import-PowerShellDataFile -Path $LocalOverridePath
        $unknown = @($local.Keys | Where-Object { $overrideKeys -notcontains $_ })
        if ($unknown.Count -gt 0) { throw "Local override $LocalOverridePath has unsupported keys: $($unknown -join ', ')" }
        foreach ($k in $local.Keys) { $cfg[$k] = $local[$k] }
    }

    foreach ($name in 'VmName', 'SwitchName', 'NatName', 'FirewallRuleName', 'CheckpointName') {
        if ([string]$cfg[$name] -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$') { throw "Config key $name must match ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$" }
    }
    if ($cfg.MacAddress -notmatch '^(00-15-5D|00:15:5D|00155D)[-:]?[0-9A-Fa-f]{2}[-:]?[0-9A-Fa-f]{2}[-:]?[0-9A-Fa-f]{2}$') { throw 'MacAddress must be in the Hyper-V 00-15-5D range' }
    $nat = ConvertTo-IPv4Range -Cidr $cfg.NatPrefix
    foreach ($key in 'HostAddress', 'GuestAddress') {
        $n = ConvertTo-IPv4Number -Address $cfg[$key]
        if ($n -lt $nat.Start -or $n -gt $nat.End) { throw "$key $($cfg[$key]) is outside NatPrefix $($cfg.NatPrefix)" }
    }
    if ($cfg.HostAddress -eq $cfg.GuestAddress) { throw 'HostAddress and GuestAddress must differ' }
    if ($cfg.AclWeightMax - $cfg.AclWeightMin -lt 200) { throw 'AclWeightMax - AclWeightMin must be at least 200' }
    if (-not [IO.Path]::IsPathRooted($cfg.RootPath) -or $cfg.RootPath.Length -lt 6 -or [IO.Path]::GetPathRoot($cfg.RootPath) -eq $cfg.RootPath) {
        throw 'RootPath must be an absolute folder path below a drive root'
    }
    if ($cfg.AclWeightMin -lt 0 -or $cfg.AclWeightMax -gt 65535) { throw 'AclWeightMin/AclWeightMax must stay inside 0..65535 (65535 accepted, 100000 rejected by the switch)' }
    if ($cfg.AddOwnerToHyperVAdministrators -isnot [bool]) { throw 'AddOwnerToHyperVAdministrators must be $true or $false' }

    $static = @()
    if ($cfg.ContainsKey('StaticDenyPrefix')) { $static = @($cfg.StaticDenyPrefix | ForEach-Object { (ConvertTo-IPv4Range -Cidr ([string]$_)).Cidr }) }
    $egress = @()
    if ($cfg.ContainsKey('EgressInterfaceAlias')) {
        $egress = @($cfg.EgressInterfaceAlias | Where-Object { $_ } | ForEach-Object { [string]$_ })
        foreach ($a in $egress) { if ($a -notmatch '^[^\x00-\x1f]{1,128}$') { throw 'EgressInterfaceAlias holds an invalid interface name' } }
    }

    $cfg.ConfigFile = $full
    $cfg.LocalOverridePath = $LocalOverridePath
    $cfg.LocalOverrideKeys = @($local.Keys)
    $cfg.StaticDenyPrefix = $static
    $cfg.EgressInterfaceAlias = $egress
    $cfg.NatCidr = '{0}/{1}' -f (ConvertFrom-IPv4Number -Number $nat.Start), $nat.PrefixLength
    $cfg.MemoryBytes = [int64]$cfg.MemoryGiB * 1GB
    $cfg.DiskBytes = [int64]$cfg.DiskGiB * 1GB
    $cfg.MacPlain = ($cfg.MacAddress -replace '[-:]', '').ToUpperInvariant()
    $cfg.SwitchAdapterAlias = 'vEthernet ({0})' -f $cfg.SwitchName
    $cfg.VhdxPath = Join-Path $cfg.RootPath ($cfg.VmName + '.vhdx')
    $cfg.MarkerPath = Join-Path $cfg.RootPath '.homelab-managed'
    $cfg
}

function ConvertTo-IPv4Number {
    param([Parameter(Mandatory)][string]$Address)
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$ip) -or $ip.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Not an IPv4 address: $Address"
    }
    $b = $ip.GetAddressBytes()
    [long]$b[0] * 16777216 + [long]$b[1] * 65536 + [long]$b[2] * 256 + [long]$b[3]
}

function ConvertFrom-IPv4Number {
    param([Parameter(Mandatory)][long]$Number)
    '{0}.{1}.{2}.{3}' -f [math]::Floor($Number / 16777216), ([math]::Floor($Number / 65536) % 256), ([math]::Floor($Number / 256) % 256), ($Number % 256)
}

function ConvertTo-IPv4Range {
    param([Parameter(Mandatory)][string]$Cidr)
    $parts = $Cidr.Split('/')
    if ($parts.Count -gt 2) { throw "Not a CIDR prefix: $Cidr" }
    $length = 32
    if ($parts.Count -eq 2) {
        if ($parts[1] -notmatch '^\d{1,2}$' -or [int]$parts[1] -gt 32) { throw "Bad prefix length in: $Cidr" }
        $length = [int]$parts[1]
    }
    $size = [long][math]::Pow(2, 32 - $length)
    $start = [long][math]::Floor((ConvertTo-IPv4Number -Address $parts[0]) / $size) * $size
    [pscustomobject]@{ Start = $start; End = $start + $size - 1; PrefixLength = $length; Cidr = ('{0}/{1}' -f (ConvertFrom-IPv4Number -Number $start), $length) }
}

function Test-IPv4RangeOverlap {
    param([Parameter(Mandatory)]$A, [Parameter(Mandatory)]$B)
    $A.Start -le $B.End -and $B.Start -le $A.End
}

function Test-IPv4RangeCover {
    param([Parameter(Mandatory)]$Outer, [Parameter(Mandatory)]$Inner)
    $Outer.Start -le $Inner.Start -and $Inner.End -le $Outer.End
}

function Merge-IPv4Prefix {
    param([string[]]$Cidr = @())
    $ranges = @($Cidr | ForEach-Object { ConvertTo-IPv4Range -Cidr $_ } | Sort-Object Start, PrefixLength)
    $kept = New-Object System.Collections.Generic.List[object]
    foreach ($r in $ranges) {
        $covered = $false
        foreach ($k in $kept) { if (Test-IPv4RangeCover -Outer $k -Inner $r) { $covered = $true; break } }
        if (-not $covered) { $kept.Add($r) }
    }
    @($kept | ForEach-Object { $_.Cidr })
}

function Get-PveFixedDenyPrefix {
    @('0.0.0.0/8', '10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16', '224.0.0.0/4', '240.0.0.0/4')
}

function Get-PveDenyInput {
    param([Parameter(Mandatory)][hashtable]$Config)

    $routes = @(Get-NetRoute -AddressFamily IPv4 -ErrorAction Stop)
    $defaultPrefix = @('0.0.0.0/0', '0.0.0.0/1', '128.0.0.0/1')
    $defaults = @($routes | Where-Object { $defaultPrefix -contains $_.DestinationPrefix -and $_.InterfaceAlias -ne $Config.SwitchAdapterAlias })
    $egress = @($Config.EgressInterfaceAlias)
    $source = 'configured'
    $record = @()
    $denyAll = $false
    $reason = ''
    if ($egress.Count -eq 0) {
        $source = 'none'
        $aliases = @($defaults | ForEach-Object { $_.InterfaceAlias } | Sort-Object -Unique)
        if ($aliases.Count -eq 1) {
            $egress = $aliases
            $record = $aliases
            $source = 'auto'
        } elseif ($aliases.Count -gt 1) {
            $denyAll = $true
            $reason = 'default routes exist on several interfaces ({0}); set EgressInterfaceAlias in the local override' -f ($aliases -join ', ')
        }
    }
    if (-not $denyAll) {
        $foreign = @($defaults | Where-Object { $egress -notcontains $_.InterfaceAlias } | ForEach-Object { $_.InterfaceAlias } | Sort-Object -Unique)
        if ($foreign.Count -gt 0) {
            $denyAll = $true
            $reason = 'a default route (0/0, 0/1 or 128/1) is on interface(s) outside EgressInterfaceAlias: {0}' -f ($foreign -join ', ')
        }
    }

    $nat = ConvertTo-IPv4Range -Cidr $Config.NatPrefix
    $skip = @('127.0.0.0/8', '224.0.0.0/4', '255.255.255.255/32') | ForEach-Object { ConvertTo-IPv4Range -Cidr $_ }
    $found = New-Object System.Collections.Generic.List[string]
    foreach ($r in $routes) {
        if ($defaultPrefix -contains $r.DestinationPrefix) { continue }
        if ($egress -contains $r.InterfaceAlias -or $r.InterfaceAlias -eq $Config.SwitchAdapterAlias) { continue }
        $range = ConvertTo-IPv4Range -Cidr $r.DestinationPrefix
        if (Test-IPv4RangeCover -Outer $nat -Inner $range) { continue }
        $isSkipped = $false
        foreach ($sk in $skip) { if (Test-IPv4RangeCover -Outer $sk -Inner $range) { $isSkipped = $true; break } }
        if ($isSkipped) { continue }
        $found.Add($range.Cidr)
    }
    $stored = @($Config.StaticDenyPrefix)
    $fixedRanges = @(Get-PveFixedDenyPrefix | ForEach-Object { ConvertTo-IPv4Range -Cidr $_ })
    $extra = @(Merge-IPv4Prefix -Cidr (@($found.ToArray()) + $stored) | Where-Object {
            $range = ConvertTo-IPv4Range -Cidr $_
            -not @($fixedRanges | Where-Object { Test-IPv4RangeCover -Outer $_ -Inner $range })
        })
    [pscustomobject]@{
        EgressInterfaceAlias = $egress
        EgressSource = $source
        AliasToRecord = $record
        DenyAll = $denyAll
        DenyAllReason = $reason
        Extra = $extra
        Stored = $stored
        NewPrefix = @($extra | Where-Object { $stored -notcontains $_ })
    }
}

function Get-PveExtraFingerprint {
    param([AllowEmptyCollection()][string[]]$Prefix = @())
    $bytes = [Text.Encoding]::ASCII.GetBytes((@($Prefix | Sort-Object) -join "`n"))
    $hash = [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').ToLowerInvariant()
    '{0} prefix(es), SHA-256 {1}' -f @($Prefix).Count, $hash
}

function Write-PveDenySummary {
    param([Parameter(Mandatory)]$DenyInput, [switch]$Persisted, [switch]$ShowPrefixes)
    $in = $DenyInput
    $alias = '(none yet)'
    if (@($in.EgressInterfaceAlias).Count -gt 0) { $alias = (@($in.EgressInterfaceAlias) -join ', ') }
    Write-HomelabLog -Level Info -Message ('egress interface: {0} ({1})' -f $alias, $in.EgressSource)
    if ($in.DenyAll) { Write-HomelabLog -Level Warn -Message ('ALL GUEST EGRESS DENIED (fail closed): ' + $in.DenyAllReason) }
    $verb = 'would append'
    if ($Persisted) { $verb = 'appended' }
    Write-HomelabLog -Level Info -Message ('host-routed deny prefixes: {0}; {1} {2} new to the local override; {3}' -f @($in.Extra).Count, $verb, @($in.NewPrefix).Count, (Get-PveExtraFingerprint -Prefix $in.Extra))
    if ($ShowPrefixes) { foreach ($x in @($in.Extra)) { Write-HomelabLog -Level Info -Message ('  ' + $x) } }
}

function Save-PveLocalOverride {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [AllowEmptyCollection()][string[]]$StaticDenyPrefix = @(),
        [AllowEmptyCollection()][string[]]$EgressInterfaceAlias = @()
    )
    $path = $Config.LocalOverridePath
    $dir = Split-Path -Parent $path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('@{')
    $aliases = @($EgressInterfaceAlias | ForEach-Object { "'" + ([string]$_).Replace("'", "''") + "'" })
    $lines.Add('    EgressInterfaceAlias = @(' + ($aliases -join ', ') + ')')
    $lines.Add('    StaticDenyPrefix = @(')
    foreach ($x in @($StaticDenyPrefix | ForEach-Object { (ConvertTo-IPv4Range -Cidr $_).Cidr } | Sort-Object -Unique)) { $lines.Add("        '" + $x + "'") }
    $lines.Add('    )')
    if (@($Config.LocalOverrideKeys) -contains 'AddOwnerToHyperVAdministrators') {
        $lines.Add('    AddOwnerToHyperVAdministrators = $' + ([string]$Config.AddOwnerToHyperVAdministrators).ToLowerInvariant())
    }
    $lines.Add('}')
    $tmp = $path + '.tmp'
    [IO.File]::WriteAllLines($tmp, $lines.ToArray(), (New-Object Text.UTF8Encoding($true)))
    if (Test-Path -LiteralPath $path) { [IO.File]::Replace($tmp, $path, [NullString]::Value) } else { [IO.File]::Move($tmp, $path) }
}

function Get-PveAclPlan {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [string[]]$ExtraDenyPrefix = @(),
        [switch]$DenyAllEgress
    )

    $max = [int]$Config.AclWeightMax
    $min = [int]$Config.AclWeightMin
    $denyPrefixes = @(Get-PveFixedDenyPrefix) + @($ExtraDenyPrefix)
    if (@($ExtraDenyPrefix).Count -gt [int]$Config.MaxExtraDenyPrefixes) {
        throw "Host routes yield $(@($ExtraDenyPrefix).Count) extra deny prefixes; the limit is $($Config.MaxExtraDenyPrefixes). Raise MaxExtraDenyPrefixes only after checking the list."
    }
    $firstDenyWeight = $max - 100
    if ($firstDenyWeight - $denyPrefixes.Count -le $min + 12) { throw 'AclWeight range is too small for the deny prefix list' }

    $rules = New-Object System.Collections.Generic.List[object]
    $addRule = {
        param($Weight, $Action, $Direction, $Remote, $Protocol, $LocalPort, $Stateful, $Note)
        $rules.Add([pscustomobject]@{
                Weight = [int]$Weight; Action = $Action; Direction = $Direction; Remote = $Remote
                Protocol = $Protocol; LocalPort = $LocalPort; Stateful = [bool]$Stateful; Note = $Note
            })
    }
    & $addRule $max 'Allow' 'Inbound' $Config.HostAddress 'TCP' ([string]$Config.SshPort) $true 'host to guest ssh, replies flow'
    & $addRule ($max - 1) 'Allow' 'Inbound' $Config.HostAddress 'TCP' ([string]$Config.WebPort) $true 'host to guest web UI, replies flow'
    & $addRule ($max - 10) 'Deny' 'Outbound' '::/0' $null $null $false 'no IPv6 out'
    & $addRule ($max - 11) 'Deny' 'Inbound' '::/0' $null $null $false 'no IPv6 in'
    $i = 0
    foreach ($p in $denyPrefixes) {
        $note = 'private/reserved range'
        if ($i -ge (Get-PveFixedDenyPrefix).Count) { $note = 'host-routed prefix' }
        & $addRule ($firstDenyWeight - $i) 'Deny' 'Outbound' $p $null $null $false $note
        $i++
    }
    if ($DenyAllEgress) {
        & $addRule ($min + 11) 'Deny' 'Outbound' '0.0.0.0/0' $null $null $false 'all egress denied (fail closed)'
    } else {
        & $addRule ($min + 10) 'Allow' 'Outbound' '0.0.0.0/0' 'TCP' $null $true 'internet out (TCP), replies flow'
        & $addRule ($min + 9) 'Allow' 'Outbound' '0.0.0.0/0' 'UDP' $null $true 'internet out (UDP), replies flow'
    }
    & $addRule $min 'Deny' 'Inbound' '0.0.0.0/0' $null $null $false 'default deny in'
    $planned = $rules.ToArray()
    Assert-PveAclRule -Rule $planned
    $planned
}

function Assert-PveAclRule {
    param([Parameter(Mandatory)][object[]]$Rule)
    $seen = @{}
    foreach ($r in $Rule) {
        $w = [int]$r.Weight
        if ($w -lt 0 -or $w -gt 65535) { throw "ACL rule weight $w is outside 0..65535 (measured: 65535 accepted, 100000 rejected)" }
        if ($r.Stateful -and $r.Action -ne 'Allow') { throw "Stateful ACL rules must be Allow (weight $w); the switch rejects a stateful Deny" }
        if ($r.Stateful -and @('TCP', 'UDP') -notcontains ([string]$r.Protocol).ToUpperInvariant()) { throw "Stateful ACL rules must be TCP or UDP on this host (weight $w, protocol '$($r.Protocol)'); ICMP, ANY and no protocol are rejected at switch-apply time" }
        $k = '{0}|{1}' -f $w, $r.Direction
        if ($seen.ContainsKey($k)) { throw "Two ACL rules share weight $w and direction $($r.Direction)" }
        $seen[$k] = $true
    }
}

function ConvertTo-PveAclKey {
    param([Parameter(Mandatory)]$Rule)
    $remote = [string]$Rule.RemoteIPAddress
    if ($null -eq $Rule.RemoteIPAddress) { $remote = [string]$Rule.Remote }
    $remote = $remote.Trim().ToLowerInvariant() -replace '/32$', ''
    if ($remote -in @('any', '*', '')) { $remote = '0.0.0.0/0' }
    $proto = ([string]$Rule.Protocol).Trim().ToUpperInvariant()
    if ($proto -in @('ANY', '*')) { $proto = '' }
    '{0}|{1}|{2}|{3}' -f $Rule.Weight, $Rule.Action, $remote, $proto
}

function Get-PveVmAdapter {
    param([Parameter(Mandatory)][hashtable]$Config)
    $adapters = @(Get-VMNetworkAdapter -VMName $Config.VmName)
    if ($adapters.Count -ne 1) { throw "Expected exactly one network adapter on $($Config.VmName), found $($adapters.Count)" }
    $adapters[0]
}

function Get-PveOwnAcl {
    param([Parameter(Mandatory)][hashtable]$Config)
    @(Get-VMNetworkAdapterExtendedAcl -VMName $Config.VmName | Where-Object { $_.Weight -ge $Config.AclWeightMin -and $_.Weight -le $Config.AclWeightMax })
}

function Get-PveForeignAcl {
    param([Parameter(Mandatory)][hashtable]$Config)
    @(Get-VMNetworkAdapterExtendedAcl -VMName $Config.VmName | Where-Object { $_.Weight -lt $Config.AclWeightMin -or $_.Weight -gt $Config.AclWeightMax })
}

function Format-PveAclTable {
    param(
        [Parameter(Mandatory)][object[]]$Rule,
        [Parameter(Mandatory)][hashtable]$Config,
        [switch]$ShowPrefixes
    )
    $public = @(Get-PveFixedDenyPrefix) + @('0.0.0.0/0', '::/0', $Config.HostAddress, $Config.NatCidr)
    $reveal = $ShowPrefixes.IsPresent
    $mask = {
        param($Remote)
        $r = ([string]$Remote).Trim().ToLowerInvariant() -replace '/32$', ''
        if ($reveal -or $r -in @('', 'any', '*') -or $public -contains $r) { return $Remote }
        '(host-routed)'
    }
    ($Rule | Sort-Object Weight -Descending |
        Select-Object Weight, Direction, Action, Stateful, Protocol, @{ n = 'Remote'; e = { if ($null -ne $_.RemoteIPAddress) { & $mask $_.RemoteIPAddress } else { & $mask $_.Remote } } }, LocalPort, Note |
        Format-Table -AutoSize | Out-String -Width 220).TrimEnd()
}

function Sync-PveVmAcl {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$ExtraDenyPrefix,
        [switch]$DenyAllEgress
    )

    try {
        $foreign = @(Get-PveForeignAcl -Config $Config)
        if ($foreign.Count -gt 0) {
            $list = ($foreign | ForEach-Object { '{0} {1} {2}' -f $_.Weight, $_.Direction, $_.Action }) -join '; '
            throw "Extended ACLs outside the reserved weight range exist on the adapter ($list). This VM is script-owned; remove them first."
        }
        $desired = @(Get-PveAclPlan -Config $Config -ExtraDenyPrefix $ExtraDenyPrefix -DenyAllEgress:$DenyAllEgress)
        $adapter = Get-PveVmAdapter -Config $Config
        $existing = @(Get-PveOwnAcl -Config $Config)
        $have = @{}
        foreach ($e in $existing) { $have[(ConvertTo-PveAclKey -Rule $e)] = $true }
        $want = @{}
        foreach ($d in $desired) { $want[(ConvertTo-PveAclKey -Rule $d)] = $d }

        $stale = @($existing | Where-Object { -not $want.ContainsKey((ConvertTo-PveAclKey -Rule $_)) })
        $missing = @($desired | Where-Object { -not $have.ContainsKey((ConvertTo-PveAclKey -Rule $_)) })
        $occupied = @($existing | ForEach-Object { [int]$_.Weight })

        $addOne = {
            param($rule)
            $p = @{
                VMNetworkAdapter = $adapter; Action = $rule.Action; Direction = $rule.Direction; Weight = $rule.Weight
                RemoteIPAddress = $rule.Remote; LocalIPAddress = 'ANY'; Stateful = $rule.Stateful
            }
            if ($rule.Protocol) { $p.Protocol = $rule.Protocol }
            if ($rule.LocalPort) { $p.LocalPort = $rule.LocalPort }
            Add-VMNetworkAdapterExtendedAcl @p
        }

        $deferred = @()
        foreach ($m in $missing) {
            if ($occupied -contains $m.Weight) { $deferred += , $m } else { & $addOne $m }
        }
        foreach ($s in $stale) {
            try { $s | Remove-VMNetworkAdapterExtendedAcl -ErrorAction Stop } catch { $null = $_ }
        }
        foreach ($m in $deferred) { & $addOne $m }

        $after = @(Get-PveOwnAcl -Config $Config)
        $afterSlots = @{}
        foreach ($a in $after) { $afterSlots['{0}|{1}' -f $a.Weight, $a.Action] = $true }
        $wantSlots = @{}
        foreach ($d in $desired) { $wantSlots['{0}|{1}' -f $d.Weight, $d.Action] = $true }
        $absent = @($desired | Where-Object { -not $afterSlots.ContainsKey(('{0}|{1}' -f $_.Weight, $_.Action)) })
        $leftover = @($after | Where-Object { -not $wantSlots.ContainsKey(('{0}|{1}' -f $_.Weight, $_.Action)) })
        if ($absent.Count -gt 0 -or $leftover.Count -gt 0) {
            Write-HomelabLog -Level Fail -Message ("ACL read-back mismatch. Read back:`n" + (Format-PveAclTable -Rule $after -Config $Config))
            throw "Port ACL verification failed: $($absent.Count) rule(s) missing, $($leftover.Count) unexpected."
        }
        [pscustomobject]@{ Desired = $desired; Applied = $after; Added = $missing.Count; Removed = $stale.Count }
    } catch {
        $failure = $_
        try {
            Disconnect-VMNetworkAdapter -VMName $Config.VmName -ErrorAction Stop
            Write-HomelabLog -Level Warn -Message 'port ACL sync failed: the VM network adapter was disconnected. Start reconnects it after a clean sync.'
        } catch {
            Write-HomelabLog -Level Fail -Message ('port ACL sync failed AND the adapter could not be disconnected; stop the VM now. ' + $_.Exception.Message)
        }
        throw $failure
    }
}

function Sync-PveIsolation {
    param(
        [Parameter(Mandatory)][hashtable]$Config,
        [switch]$Persist,
        [switch]$ShowPrefixes
    )
    $in = Get-PveDenyInput -Config $Config
    $saved = $false
    if ($Persist -and (@($in.NewPrefix).Count -gt 0 -or @($in.AliasToRecord).Count -gt 0)) {
        Save-PveLocalOverride -Config $Config -StaticDenyPrefix $in.Extra -EgressInterfaceAlias $in.EgressInterfaceAlias
        $Config.StaticDenyPrefix = @($in.Extra)
        $Config.EgressInterfaceAlias = @($in.EgressInterfaceAlias)
        $saved = $true
    }
    Write-PveDenySummary -DenyInput $in -Persisted:$saved -ShowPrefixes:$ShowPrefixes
    $res = Sync-PveVmAcl -Config $Config -ExtraDenyPrefix $in.Extra -DenyAllEgress:$in.DenyAll
    [pscustomobject]@{ DenyInput = $in; Result = $res }
}

function Get-PveFirewallRuleSpec {
    param([Parameter(Mandatory)][hashtable]$Config)
    @{
        Name = $Config.FirewallRuleName
        DisplayName = 'homelab ' + $Config.VmName + ' block inbound from guest network'
        Description = 'Blocks new inbound connections from the guest network to this host. Replies to host-initiated sessions are unaffected.'
        Direction = 'Inbound'; Action = 'Block'; Profile = 'Any'; Protocol = 'Any'; Enabled = 'True'
        RemoteAddress = $Config.NatCidr; InterfaceAlias = $Config.SwitchAdapterAlias
    }
}

function Get-PveFirewallState {
    param([Parameter(Mandatory)][hashtable]$Config)
    try {
        $r = Get-NetFirewallRule -Name $Config.FirewallRuleName -ErrorAction Stop
    } catch {
        if ($_.FullyQualifiedErrorId -like '*NotFound*' -or $_.CategoryInfo.Category -eq 'ObjectNotFound') { return 'absent' }
        return 'unreadable'
    }
    if (-not $r) { return 'absent' }
    if ([string]$r.Enabled -eq 'True' -and [string]$r.Action -eq 'Block' -and [string]$r.Direction -eq 'Inbound') { return 'present' }
    'misconfigured'
}

function Sync-PveHostFirewallRule {
    param([Parameter(Mandatory)][hashtable]$Config)
    $spec = Get-PveFirewallRuleSpec -Config $Config
    $current = Get-NetFirewallRule -Name $spec.Name -ErrorAction SilentlyContinue
    if ($current) {
        $addr = $current | Get-NetFirewallAddressFilter
        $iface = $current | Get-NetFirewallInterfaceFilter
        $same = ([string]$current.Action -eq 'Block') -and ([string]$current.Direction -eq 'Inbound') -and ([string]$current.Enabled -eq 'True') -and
        ([string]$current.Profile -eq 'Any') -and (@($addr.RemoteAddress) -join ',') -like ($Config.NatCidr.Split('/')[0] + '*') -and
        (@($iface.InterfaceAlias) -join ',') -eq $Config.SwitchAdapterAlias
        if ($same) { return 'unchanged' }
        Remove-NetFirewallRule -Name $spec.Name
    }
    New-NetFirewallRule @spec | Out-Null
    'applied'
}

function Revoke-PveHostFirewallRule {
    param([Parameter(Mandatory)][hashtable]$Config)
    if (Get-NetFirewallRule -Name $Config.FirewallRuleName -ErrorAction SilentlyContinue) {
        Remove-NetFirewallRule -Name $Config.FirewallRuleName
        return $true
    }
    $false
}

function Test-HomelabElevated {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-HomelabHyperVRight {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    $groupSid = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-578'
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $configured = $false
    try {
        $configured = @(Get-LocalGroupMember -SID $groupSid -ErrorAction Stop | Where-Object { $_.SID -eq $userSid }).Count -gt 0
    } catch { $null = $_ }
    $elevated = Test-HomelabElevated
    $inToken = $principal.IsInRole($groupSid)
    [pscustomobject]@{
        Elevated = $elevated
        InHyperVAdminsToken = $inToken
        HasRights = ($elevated -or $inToken)
        MemberConfigured = $configured
    }
}

function Grant-PveCurrentUserHyperVAdmin {
    $groupSid = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-578'
    $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $group = Get-LocalGroup -SID $groupSid
    $isMember = $null
    try {
        $isMember = @(Get-LocalGroupMember -SID $groupSid -ErrorAction Stop | Where-Object { $_.SID -eq $userSid }).Count -gt 0
    } catch { $isMember = $null }
    if ($isMember) { return [pscustomobject]@{ Result = 'AlreadyMember'; Group = $group.Name; UserSid = $userSid.Value } }
    try {
        Add-LocalGroupMember -SID $groupSid -Member $userSid.Value -ErrorAction Stop
        $result = 'Added'
    } catch {
        if ($_.FullyQualifiedErrorId -like 'MemberExists*') {
            $result = 'AlreadyMember'
        } else {
            try {
                $adsiGroup = [ADSI]('WinNT://./{0},group' -f $group.Name)
                $adsiGroup.Add('WinNT://' + $userSid.Value)
                $result = 'Added'
            } catch {
                if ($_.Exception.Message -match 'already a member|0x80070562|1378') { $result = 'AlreadyMember' } else { throw }
            }
        }
    }
    [pscustomobject]@{ Result = $result; Group = $group.Name; UserSid = $userSid.Value }
}

function Revoke-PveUserHyperVAdmin {
    param([Parameter(Mandatory)][string]$UserSid)
    $groupSid = New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-578'
    try {
        Remove-LocalGroupMember -SID $groupSid -Member $UserSid -ErrorAction Stop
        return $true
    } catch {
        if ($_.FullyQualifiedErrorId -like 'MemberNotFound*') { return $false }
        throw
    }
}

function Test-PveInsideRoot {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Root)
    $p = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $r = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    $p.Equals($r, [StringComparison]::OrdinalIgnoreCase) -or $p.StartsWith($r + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-PveRootOwner {
    param([Parameter(Mandatory)][string]$Path)
    $owner = (Get-Acl -LiteralPath $Path).GetOwner([Security.Principal.SecurityIdentifier])
    @('S-1-5-32-544', 'S-1-5-18') -contains $owner.Value
}

function Assert-PveSafePath {
    param([Parameter(Mandatory)][hashtable]$Config, [switch]$Lenient)
    $root = $Config.RootPath
    foreach ($p in @((Split-Path -Parent $root), $root)) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        if ((Get-Item -LiteralPath $p -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing to continue: '$p' is a reparse point (link)." }
        $ownerOk = $true
        try {
            $ownerOk = Test-PveRootOwner -Path $p
        } catch {
            if (-not $Lenient) { throw }
            Write-HomelabLog -Level Skip -Message "owner check of '$p': needs elevation/Hyper-V rights - skipped in plan"
        }
        if (-not $ownerOk) { throw "Refusing to continue: '$p' is not owned by Administrators or SYSTEM. Delete it or take ownership first." }
    }
    if (-not (Test-Path -LiteralPath $root)) { return }
    $pending = New-Object System.Collections.Generic.Queue[string]
    $pending.Enqueue($root)
    while ($pending.Count -gt 0) {
        $dir = $pending.Dequeue()
        foreach ($c in @(Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue)) {
            if ($c.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Refusing to continue: '$($c.FullName)' is a reparse point (link)." }
            if ($c.PSIsContainer) { $pending.Enqueue($c.FullName) }
        }
    }
}

function Get-PveRootAclSpec {
    @(
        @{ Sid = 'S-1-5-18'; Rights = 'FullControl'; Label = 'SYSTEM' }
        @{ Sid = 'S-1-5-32-544'; Rights = 'FullControl'; Label = 'Administrators' }
        @{ Sid = 'S-1-5-32-578'; Rights = 'Modify'; Label = 'Hyper-V Administrators' }
        @{ Sid = 'S-1-5-83-0'; Rights = 'Modify'; Label = 'Virtual Machines (VM worker group)' }
    )
}

function Test-PveRootAcl {
    param([Parameter(Mandatory)][string]$Path)
    $acl = Get-Acl -LiteralPath $Path
    if (-not $acl.AreAccessRulesProtected) { return $false }
    $expected = @{}
    foreach ($s in Get-PveRootAclSpec) { $expected[$s.Sid] = [string]$s.Rights }
    $seen = @{}
    foreach ($r in $acl.Access) {
        $sid = $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
        if (-not $expected.ContainsKey($sid) -or $r.AccessControlType -ne 'Allow') { return $false }
        $want = [int][Security.AccessControl.FileSystemRights]$expected[$sid]
        if (([int]$r.FileSystemRights -band $want) -ne $want) { return $false }
        $seen[$sid] = $true
    }
    $seen.Count -eq $expected.Count
}

function Initialize-PveRootAcl {
    param([Parameter(Mandatory)][string]$Path)
    $sec = New-Object Security.AccessControl.DirectorySecurity
    $sec.SetAccessRuleProtection($true, $false)
    foreach ($s in Get-PveRootAclSpec) {
        $sid = New-Object Security.Principal.SecurityIdentifier $s.Sid
        $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, $s.Rights, 'ContainerInherit,ObjectInherit', 'None', 'Allow')
        $sec.AddAccessRule($rule)
    }
    Set-Acl -LiteralPath $Path -AclObject $sec
}

function Get-PveVmAccountName {
    param([Parameter(Mandatory)][guid]$VmId)
    $group = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-83-0').Translate([Security.Principal.NTAccount]).Value
    '{0}\{1}' -f $group.Substring(0, $group.IndexOf('\')), $VmId.ToString().ToUpperInvariant()
}

function Confirm-PveVmFileAccess {
    param([Parameter(Mandatory)][hashtable]$Config)
    $vm = Get-VM -Name $Config.VmName
    $account = Get-PveVmAccountName -VmId $vm.Id
    $files = New-Object System.Collections.Generic.List[string]
    $files.Add($Config.VhdxPath)
    foreach ($d in @(Get-VMDvdDrive -VMName $Config.VmName)) { if ($d.Path) { $files.Add($d.Path) } }
    foreach ($f in $files) { if (-not (Test-PveInsideRoot -Path $f -Root $Config.RootPath)) { throw "Refusing to grant access to '$f': outside RootPath." } }
    $cfgDir = Join-Path $vm.Path 'Virtual Machines'
    if (Test-Path -LiteralPath $cfgDir) {
        foreach ($f in @(Get-ChildItem -LiteralPath $cfgDir -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq $vm.Id.ToString().ToUpperInvariant() })) { $files.Add($f.FullName) }
    }
    $results = foreach ($f in $files) {
        $hasAce = @((Get-Acl -LiteralPath $f).Access | Where-Object { [string]$_.IdentityReference -like ('*\' + $vm.Id.ToString()) }).Count -gt 0
        $fixed = $false
        if (-not $hasAce) {
            & icacls.exe $f /grant ('{0}:(F)' -f $account) | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "icacls failed for $f (exit $LASTEXITCODE)" }
            $fixed = $true
        }
        [pscustomobject]@{ File = $f; PerVmAcePresent = $hasAce; GrantedNow = $fixed }
    }
    @($results)
}

function Test-PveTcpPort {
    param([Parameter(Mandatory)][string]$Address, [Parameter(Mandatory)][int]$Port, [int]$TimeoutMs = 2000)
    $client = New-Object Net.Sockets.TcpClient
    try {
        $ar = $client.BeginConnect($Address, $Port, $null, $null)
        if (-not $ar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($ar)
        return $true
    } catch {
        return $false
    } finally {
        $client.Close()
    }
}

function Wait-PveTcpPort {
    param(
        [Parameter(Mandatory)][string]$Address,
        [Parameter(Mandatory)][int]$Port,
        [Parameter(Mandatory)][int]$TimeoutSeconds,
        [Parameter(Mandatory)][Diagnostics.Stopwatch]$Clock,
        [int]$ProgressSeconds = 30
    )
    $deadline = $Clock.Elapsed.TotalSeconds + $TimeoutSeconds
    $nextProgress = $Clock.Elapsed.TotalSeconds + $ProgressSeconds
    while ($Clock.Elapsed.TotalSeconds -lt $deadline) {
        if (Test-PveTcpPort -Address $Address -Port $Port -TimeoutMs 2000) { return [math]::Round($Clock.Elapsed.TotalSeconds, 1) }
        if ($Clock.Elapsed.TotalSeconds -ge $nextProgress) {
            Write-HomelabLog -Level Info -Message ('waiting for {0}:{1} ... {2} s elapsed' -f $Address, $Port, [int]$Clock.Elapsed.TotalSeconds)
            $nextProgress += $ProgressSeconds
        }
        Start-Sleep -Seconds 3
    }
    $null
}

function Get-HomelabAvailableMemory {
    $perf = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
    if ($perf -and $perf.AvailableBytes) { return [int64]$perf.AvailableBytes }
    [int64](Get-CimInstance -ClassName Win32_OperatingSystem).FreePhysicalMemory * 1KB
}

function Format-HomelabGiB {
    param([Parameter(Mandatory)][double]$Bytes)
    '{0:N1} GiB' -f ($Bytes / 1GB)
}

Export-ModuleMember -Function Write-HomelabLog, Import-PveConfig, ConvertTo-IPv4Number, ConvertFrom-IPv4Number, ConvertTo-IPv4Range,
Test-IPv4RangeOverlap, Test-IPv4RangeCover, Merge-IPv4Prefix, Get-PveFixedDenyPrefix, Get-PveDenyInput, Get-PveExtraFingerprint,
Write-PveDenySummary, Save-PveLocalOverride, Get-PveAclPlan, Assert-PveAclRule, ConvertTo-PveAclKey, Get-PveVmAdapter, Get-PveOwnAcl, Get-PveForeignAcl,
Format-PveAclTable, Sync-PveVmAcl, Sync-PveIsolation, Get-PveFirewallRuleSpec, Get-PveFirewallState, Sync-PveHostFirewallRule,
Revoke-PveHostFirewallRule, Test-HomelabElevated, Get-HomelabHyperVRight, Grant-PveCurrentUserHyperVAdmin, Revoke-PveUserHyperVAdmin,
Test-PveInsideRoot, Test-PveRootOwner, Assert-PveSafePath, Get-PveRootAclSpec, Test-PveRootAcl, Initialize-PveRootAcl,
Get-PveVmAccountName, Confirm-PveVmFileAccess, Test-PveTcpPort, Wait-PveTcpPort, Get-HomelabAvailableMemory, Format-HomelabGiB
