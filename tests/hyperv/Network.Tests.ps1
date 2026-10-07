BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'HyperVStubs.psm1') -Force
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..\..\scripts\hyperv\HomelabHyperV.psm1')).ProviderPath -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $state = @{ Routes = @() }; $script:state = $state
    Mock Get-NetRoute -ModuleName HomelabHyperV -MockWith ({ $state.Routes }.GetNewClosure())
}

AfterAll {
    Remove-Module HomelabHyperV, HyperVStubs -Force -ErrorAction SilentlyContinue
}

Describe 'IPv4 number conversion (psm1:93-106)' {
    It 'converts <Address> to <Number>' -TestCases @(
        @{ Address = '0.0.0.0'; Number = 0 }
        @{ Address = '192.0.2.1'; Number = 3221225985 }
        @{ Address = '10.99.0.1'; Number = 174260225 }
        @{ Address = '255.255.255.255'; Number = 4294967295 }
    ) {
        ConvertTo-IPv4Number -Address $Address | Should -Be $Number
    }

    It 'round-trips the boundaries through ConvertFrom-IPv4Number' {
        ConvertFrom-IPv4Number -Number 0 | Should -Be '0.0.0.0'
        ConvertFrom-IPv4Number -Number 4294967295 | Should -Be '255.255.255.255'
        ConvertFrom-IPv4Number -Number (ConvertTo-IPv4Number -Address '203.0.113.7') | Should -Be '203.0.113.7'
    }

    It 'rejects an IPv6 address (psm1:96-97)' {
        { ConvertTo-IPv4Number -Address '2001:db8::1' } | Should -Throw 'Not an IPv4 address*'
    }

    It 'rejects <Text> as not an address (psm1:96)' -TestCases @(
        @{ Text = 'not-an-ip' }, @{ Text = '203.0.113.256' }, @{ Text = '2001:db8::' }
    ) {
        { ConvertTo-IPv4Number -Address $Text } | Should -Throw
    }

    It 'rejects an empty address at parameter binding' {
        { ConvertTo-IPv4Number -Address '' } | Should -Throw
    }
}

Describe 'IPv4 CIDR range (psm1:108-120)' {
    It 'normalises <Cidr> to the network address <Expected>' -TestCases @(
        @{ Cidr = '203.0.113.77/24'; Expected = '203.0.113.0/24' }
        @{ Cidr = '203.0.113.77'; Expected = '203.0.113.77/32' }
        @{ Cidr = '203.0.113.77/32'; Expected = '203.0.113.77/32' }
        @{ Cidr = '203.0.113.129/25'; Expected = '203.0.113.128/25' }
        @{ Cidr = '198.51.100.9/0'; Expected = '0.0.0.0/0' }
    ) {
        (ConvertTo-IPv4Range -Cidr $Cidr).Cidr | Should -Be $Expected
    }

    It 'computes start, end and size of a /24' {
        $r = ConvertTo-IPv4Range -Cidr '192.0.2.0/24'
        $r.End - $r.Start | Should -Be 255
        $r.PrefixLength | Should -Be 24
    }

    It 'covers the whole space for /0' {
        $r = ConvertTo-IPv4Range -Cidr '0.0.0.0/0'
        $r.Start | Should -Be 0
        $r.End | Should -Be 4294967295
    }

    It 'rejects <Cidr> (psm1:111-114)' -TestCases @(
        @{ Cidr = '192.0.2.0/33' }, @{ Cidr = '192.0.2.0/abc' }, @{ Cidr = '192.0.2.0/' }
        @{ Cidr = '192.0.2.0/24/8' }, @{ Cidr = '192.0.2.0/-1' }, @{ Cidr = '203.0.113.300/8' }
    ) {
        { ConvertTo-IPv4Range -Cidr $Cidr } | Should -Throw
    }

    It 'rejects an IPv6 prefix such as ::/0 instead of widening it (psm1:96)' {
        { ConvertTo-IPv4Range -Cidr '::/0' } | Should -Throw
        { ConvertTo-IPv4Range -Cidr '2001:db8::/32' } | Should -Throw
    }
}

Describe 'IPv4 range relations (psm1:122-130)' {
    BeforeAll {
        $script:wide = ConvertTo-IPv4Range -Cidr '198.51.100.0/24'
        $script:half = ConvertTo-IPv4Range -Cidr '198.51.100.128/25'
        $script:other = ConvertTo-IPv4Range -Cidr '203.0.113.0/24'
    }

    It 'reports overlap for nested and identical ranges, not for disjoint ones' {
        Test-IPv4RangeOverlap -A $wide -B $half | Should -BeTrue
        Test-IPv4RangeOverlap -A $half -B $wide | Should -BeTrue
        Test-IPv4RangeOverlap -A $wide -B $wide | Should -BeTrue
        Test-IPv4RangeOverlap -A $wide -B $other | Should -BeFalse
    }

    It 'covers only when the inner range is fully inside' {
        Test-IPv4RangeCover -Outer $wide -Inner $half | Should -BeTrue
        Test-IPv4RangeCover -Outer $half -Inner $wide | Should -BeFalse
        Test-IPv4RangeCover -Outer $wide -Inner $wide | Should -BeTrue
        Test-IPv4RangeCover -Outer $wide -Inner $other | Should -BeFalse
    }
}

Describe 'Merge-IPv4Prefix (psm1:132-142)' {
    It 'returns nothing for empty input' {
        @(Merge-IPv4Prefix -Cidr @()).Count | Should -Be 0
        @(Merge-IPv4Prefix).Count | Should -Be 0
    }

    It 'drops a prefix covered by a wider one regardless of input order' {
        Merge-IPv4Prefix -Cidr @('198.51.100.128/25', '198.51.100.0/24') | Should -Be @('198.51.100.0/24')
    }

    It 'collapses duplicates and normalises host bits' {
        @(Merge-IPv4Prefix -Cidr @('192.0.2.5/24', '192.0.2.0/24')) | Should -Be @('192.0.2.0/24')
    }

    It 'keeps adjacent but non-nested prefixes separate' {
        @(Merge-IPv4Prefix -Cidr @('192.0.2.0/25', '192.0.2.128/25')).Count | Should -Be 2
    }

    It 'throws on an invalid member instead of dropping it' {
        { Merge-IPv4Prefix -Cidr @('192.0.2.0/24', 'bogus') } | Should -Throw
    }
}

Describe 'Get-PveFixedDenyPrefix (psm1:144-146)' {
    BeforeAll { $script:fixed = @(Get-PveFixedDenyPrefix) }

    It 'lists canonical IPv4 prefixes that do not overlap each other' {
        $fixed.Count | Should -BeGreaterThan 0
        foreach ($p in $fixed) { (ConvertTo-IPv4Range -Cidr $p).Cidr | Should -Be $p }
        @(Merge-IPv4Prefix -Cidr $fixed).Count | Should -Be $fixed.Count
    }

    It 'covers the guest network but never the documentation ranges' {
        $covers = { param($ip) @($fixed | Where-Object { Test-IPv4RangeCover -Outer (ConvertTo-IPv4Range -Cidr $_) -Inner (ConvertTo-IPv4Range -Cidr $ip) }).Count -gt 0 }
        & $covers '10.99.0.2' | Should -BeTrue
        & $covers '192.0.2.1' | Should -BeFalse
        & $covers '198.51.100.1' | Should -BeFalse
        & $covers '203.0.113.1' | Should -BeFalse
    }
}

Describe 'Get-PveDenyInput egress selection and fail-closed (psm1:148-208)' {
    BeforeEach {
        $state.Routes = @()
        $script:c = New-TestConfig
    }

    It 'treats an empty routing table as no egress, no deny-all and no extras (psm1:159-161)' {
        $r = Get-PveDenyInput -Config $c
        $r.EgressSource | Should -Be 'none'
        $r.DenyAll | Should -BeFalse
        @($r.EgressInterfaceAlias).Count | Should -Be 0
        @($r.Extra).Count | Should -Be 0
        @($r.NewPrefix).Count | Should -Be 0
    }

    It 'adopts the single interface that carries a default route and records it (psm1:162-165)' {
        $state.Routes = @(New-TestRoute '0.0.0.0/0' 'Uplink A')
        $r = Get-PveDenyInput -Config $c
        $r.EgressSource | Should -Be 'auto'
        $r.EgressInterfaceAlias | Should -Be @('Uplink A')
        $r.AliasToRecord | Should -Be @('Uplink A')
        $r.DenyAll | Should -BeFalse
    }

    It 'denies all egress when default routes sit on several interfaces and none is configured (psm1:166-169)' {
        $state.Routes = @((New-TestRoute '0.0.0.0/0' 'Uplink A'), (New-TestRoute '0.0.0.0/0' 'Uplink B'))
        $r = Get-PveDenyInput -Config $c
        $r.DenyAll | Should -BeTrue
        $r.DenyAllReason | Should -BeLike '*several interfaces*Uplink A, Uplink B*'
        @($r.AliasToRecord).Count | Should -Be 0
    }

    It 'denies all egress when a default route is on an interface outside the configured alias (psm1:171-176)' {
        $c.EgressInterfaceAlias = @('Uplink A')
        $state.Routes = @((New-TestRoute '0.0.0.0/0' 'Uplink A'), (New-TestRoute '0.0.0.0/0' 'Tunnel X'))
        $r = Get-PveDenyInput -Config $c
        $r.DenyAll | Should -BeTrue
        $r.EgressSource | Should -Be 'configured'
        $r.DenyAllReason | Should -BeLike '*outside EgressInterfaceAlias*Tunnel X*'
    }

    It 'treats a half-default <Prefix> on a foreign interface as a default route (psm1:152)' -TestCases @(
        @{ Prefix = '0.0.0.0/1' }, @{ Prefix = '128.0.0.0/1' }
    ) {
        $c.EgressInterfaceAlias = @('Uplink A')
        $state.Routes = @((New-TestRoute '0.0.0.0/0' 'Uplink A'), (New-TestRoute $Prefix 'Tunnel X'))
        (Get-PveDenyInput -Config $c).DenyAll | Should -BeTrue
    }

    It 'allows egress through every listed alias when both carry a default route' {
        $c.EgressInterfaceAlias = @('Uplink A', 'Uplink B')
        $state.Routes = @((New-TestRoute '0.0.0.0/0' 'Uplink A'), (New-TestRoute '0.0.0.0/0' 'Uplink B'))
        (Get-PveDenyInput -Config $c).DenyAll | Should -BeFalse
    }

    It 'ignores a default route on the homelab switch adapter itself (psm1:153)' {
        $state.Routes = @((New-TestRoute '0.0.0.0/0' $c.SwitchAdapterAlias), (New-TestRoute '0.0.0.0/0' 'Uplink A'))
        $r = Get-PveDenyInput -Config $c
        $r.DenyAll | Should -BeFalse
        $r.EgressInterfaceAlias | Should -Be @('Uplink A')
    }

    It 'propagates a Get-NetRoute failure instead of continuing with no routes (psm1:151)' {
        Mock Get-NetRoute -ModuleName HomelabHyperV -MockWith { throw 'route table unreadable' }
        { Get-PveDenyInput -Config $c } | Should -Throw 'route table unreadable'
    }
}

Describe 'Get-PveDenyInput host-routed prefixes (psm1:179-207)' {
    BeforeEach {
        $script:c = New-TestConfig @{ EgressInterfaceAlias = @('Uplink A') }
        $state.Routes = @(New-TestRoute '0.0.0.0/0' 'Uplink A')
    }

    It 'reports a prefix routed on a non-default interface (psm1:182-191)' {
        $state.Routes += New-TestRoute '203.0.113.0/24' 'Tunnel X'
        $r = Get-PveDenyInput -Config $c
        $r.Extra | Should -Be @('203.0.113.0/24')
        $r.NewPrefix | Should -Be @('203.0.113.0/24')
    }

    It 'does not report prefixes routed on the egress interface (psm1:184)' {
        $state.Routes += New-TestRoute '203.0.113.0/24' 'Uplink A'
        @((Get-PveDenyInput -Config $c).Extra).Count | Should -Be 0
    }

    It 'does not report prefixes routed on the switch adapter (psm1:184)' {
        $state.Routes += New-TestRoute '203.0.113.0/24' $c.SwitchAdapterAlias
        @((Get-PveDenyInput -Config $c).Extra).Count | Should -Be 0
    }

    It 'skips a route inside the guest NAT prefix (psm1:186)' {
        $state.Routes += New-TestRoute '10.99.0.0/25' 'Tunnel X'
        @((Get-PveDenyInput -Config $c).Extra).Count | Should -Be 0
    }

    It 'skips a prefix already covered by the fixed private ranges (psm1:194-197)' {
        $state.Routes += New-TestRoute '10.99.5.0/24' 'Tunnel X'
        @((Get-PveDenyInput -Config $c).Extra).Count | Should -Be 0
    }

    It 'skips every fixed deny prefix when it is routed on a foreign interface (psm1:180-189)' {
        foreach ($p in Get-PveFixedDenyPrefix) { $state.Routes += New-TestRoute $p 'Tunnel X' }
        @((Get-PveDenyInput -Config $c).Extra).Count | Should -Be 0
    }

    It 'merges overlapping routes into the wider prefix (psm1:194)' {
        $state.Routes += New-TestRoute '203.0.113.128/25' 'Tunnel X'
        $state.Routes += New-TestRoute '203.0.113.0/24' 'Tunnel Y'
        (Get-PveDenyInput -Config $c).Extra | Should -Be @('203.0.113.0/24')
    }

    It 'keeps a stored prefix with no live route and does not call it new (psm1:192,206)' {
        $c.StaticDenyPrefix = @('198.51.100.0/24')
        $r = Get-PveDenyInput -Config $c
        $r.Extra | Should -Be @('198.51.100.0/24')
        @($r.NewPrefix).Count | Should -Be 0
        $r.Stored | Should -Be @('198.51.100.0/24')
    }

    It 'reports only the live prefix as new when a stored one exists (psm1:206)' {
        $c.StaticDenyPrefix = @('198.51.100.0/24')
        $state.Routes += New-TestRoute '203.0.113.0/24' 'Tunnel X'
        $r = Get-PveDenyInput -Config $c
        @($r.Extra).Count | Should -Be 2
        $r.NewPrefix | Should -Be @('203.0.113.0/24')
    }

    It 'fails on an IPv6 destination prefix instead of ignoring it (psm1:185)' {
        $state.Routes += New-TestRoute '2001:db8::/32' 'Tunnel X'
        { Get-PveDenyInput -Config $c } | Should -Throw
    }
}

Describe 'Get-PveAclPlan (psm1:255-300)' {
    BeforeAll { $script:cfg = New-TestConfig }

    It 'builds the full default plan with unique weights in the reserved range' {
        $plan = @(Get-PveAclPlan -Config $cfg)
        $plan.Count | Should -Be (4 + @(Get-PveFixedDenyPrefix).Count + 3)
        foreach ($r in $plan) { $r.Weight | Should -BeIn ($cfg.AclWeightMin..$cfg.AclWeightMax) }
        @($plan.Weight | Select-Object -Unique).Count | Should -Be $plan.Count
    }

    It 'allows only the host to reach guest ssh and web, stateful TCP (psm1:279-280)' {
        $plan = @(Get-PveAclPlan -Config $cfg)
        $in = @($plan | Where-Object { $_.Direction -eq 'Inbound' -and $_.Action -eq 'Allow' })
        $in.Count | Should -Be 2
        foreach ($r in $in) {
            $r.Remote | Should -Be $cfg.HostAddress
            $r.Protocol | Should -Be 'TCP'
            $r.Stateful | Should -BeTrue
        }
        $in.LocalPort | Should -Be @('22', '8006')
    }

    It 'denies IPv6 in both directions at the reserved slots (psm1:281-282)' {
        $plan = @(Get-PveAclPlan -Config $cfg)
        $v6 = @($plan | Where-Object { $_.Remote -eq '::/0' })
        $v6.Count | Should -Be 2
        foreach ($r in $v6) { $r.Action | Should -Be 'Deny' }
        ($v6 | Where-Object Direction -EQ 'Outbound').Weight | Should -Be ($cfg.AclWeightMax - 10)
        ($v6 | Where-Object Direction -EQ 'Inbound').Weight | Should -Be ($cfg.AclWeightMax - 11)
    }

    It 'denies each fixed prefix outbound and labels host-routed extras separately (psm1:284-289)' {
        $plan = @(Get-PveAclPlan -Config $cfg -ExtraDenyPrefix @('203.0.113.0/24'))
        foreach ($p in Get-PveFixedDenyPrefix) {
            $r = $plan | Where-Object { $_.Remote -eq $p }
            $r.Action | Should -Be 'Deny'
            $r.Direction | Should -Be 'Outbound'
            $r.Note | Should -Be 'private/reserved range'
        }
        $extra = $plan | Where-Object { $_.Remote -eq '203.0.113.0/24' }
        $extra.Note | Should -Be 'host-routed prefix'
        $extra.Action | Should -Be 'Deny'
    }

    It 'opens the internet with stateful TCP and UDP allow and no catch-all outbound deny (psm1:293-294)' {
        $plan = @(Get-PveAclPlan -Config $cfg)
        $out = @($plan | Where-Object { $_.Direction -eq 'Outbound' -and $_.Remote -eq '0.0.0.0/0' })
        $out.Count | Should -Be 2
        foreach ($r in $out) { $r.Action | Should -Be 'Allow'; $r.Stateful | Should -BeTrue }
        $out.Protocol | Should -Be @('TCP', 'UDP')
        $out.Weight | Should -Be @(($cfg.AclWeightMin + 10), ($cfg.AclWeightMin + 9))
    }

    It 'fails closed with DenyAllEgress: a catch-all outbound Deny and no outbound Allow (psm1:290-291)' {
        $plan = @(Get-PveAclPlan -Config $cfg -DenyAllEgress)
        $catchAll = @($plan | Where-Object { $_.Direction -eq 'Outbound' -and $_.Remote -eq '0.0.0.0/0' })
        $catchAll.Count | Should -Be 1
        $catchAll[0].Action | Should -Be 'Deny'
        $catchAll[0].Weight | Should -Be ($cfg.AclWeightMin + 11)
        @($plan | Where-Object { $_.Direction -eq 'Outbound' -and $_.Action -eq 'Allow' }).Count | Should -Be 0
    }

    It 'ends with a default deny inbound at the lowest weight (psm1:296)' {
        $last = @(Get-PveAclPlan -Config $cfg) | Sort-Object Weight | Select-Object -First 1
        $last.Action | Should -Be 'Deny'
        $last.Direction | Should -Be 'Inbound'
        $last.Weight | Should -Be $cfg.AclWeightMin
    }

    It 'accepts an empty extra list' {
        { Get-PveAclPlan -Config $cfg -ExtraDenyPrefix @() } | Should -Not -Throw
    }

    It 'accepts exactly MaxExtraDenyPrefixes extras and refuses one more (psm1:265-267)' {
        $max = [int]$cfg.MaxExtraDenyPrefixes
        $ok = @(1..$max | ForEach-Object { '203.0.113.{0}/32' -f $_ })
        { Get-PveAclPlan -Config $cfg -ExtraDenyPrefix $ok } | Should -Not -Throw
        $tooMany = $ok + '198.51.100.0/24'
        { Get-PveAclPlan -Config $cfg -ExtraDenyPrefix $tooMany } | Should -Throw '*the limit is*'
    }

    It 'refuses a weight range too small for the deny list (psm1:268-269)' {
        $small = New-TestConfig @{ AclWeightMax = 4100 }
        { Get-PveAclPlan -Config $small } | Should -Throw '*too small*'
    }
}

Describe 'Assert-PveAclRule (psm1:302-314)' {
    BeforeAll {
        function script:New-Rule($Weight = 4500, $Action = 'Deny', $Direction = 'Outbound', $Stateful = $false, $Protocol = $null) {
            [pscustomobject]@{ Weight = $Weight; Action = $Action; Direction = $Direction; Stateful = $Stateful; Protocol = $Protocol }
        }
    }

    It 'accepts the weight boundary <Weight>' -TestCases @(@{ Weight = 0 }, @{ Weight = 65535 }) {
        { Assert-PveAclRule -Rule @(New-Rule -Weight $Weight) } | Should -Not -Throw
    }

    It 'rejects weight <Weight> outside 0..65535 (psm1:307)' -TestCases @(@{ Weight = 65536 }, @{ Weight = 100000 }, @{ Weight = -1 }) {
        { Assert-PveAclRule -Rule @(New-Rule -Weight $Weight) } | Should -Throw '*outside 0..65535*'
    }

    It 'rejects a stateful Deny (psm1:308)' {
        { Assert-PveAclRule -Rule @(New-Rule -Stateful $true -Protocol 'TCP') } | Should -Throw '*stateful Deny*'
    }

    It 'rejects a stateful Allow with protocol <Protocol> (psm1:309)' -TestCases @(
        @{ Protocol = 'ICMP' }, @{ Protocol = 'ANY' }, @{ Protocol = $null }, @{ Protocol = '1' }
    ) {
        { Assert-PveAclRule -Rule @(New-Rule -Action 'Allow' -Stateful $true -Protocol $Protocol) } | Should -Throw '*must be TCP or UDP*'
    }

    It 'accepts a stateful Allow with protocol <Protocol> in any case' -TestCases @(
        @{ Protocol = 'TCP' }, @{ Protocol = 'udp' }
    ) {
        { Assert-PveAclRule -Rule @(New-Rule -Action 'Allow' -Stateful $true -Protocol $Protocol) } | Should -Not -Throw
    }

    It 'rejects two rules with the same weight and direction (psm1:310-311)' {
        { Assert-PveAclRule -Rule @((New-Rule -Weight 4500), (New-Rule -Weight 4500)) } | Should -Throw '*share weight 4500*'
    }

    It 'allows the same weight in opposite directions' {
        { Assert-PveAclRule -Rule @((New-Rule -Weight 4500), (New-Rule -Weight 4500 -Direction 'Inbound')) } | Should -Not -Throw
    }
}

Describe 'ConvertTo-PveAclKey (psm1:316-325)' {
    It 'reads Remote from a planned rule and RemoteIPAddress from a read-back rule alike' {
        $planned = [pscustomobject]@{ Weight = 4010; Action = 'Allow'; Remote = '0.0.0.0/0'; Protocol = 'TCP' }
        $readBack = [pscustomobject]@{ Weight = 4010; Action = 'Allow'; RemoteIPAddress = '0.0.0.0/0'; Protocol = 'TCP' }
        ConvertTo-PveAclKey -Rule $planned | Should -Be (ConvertTo-PveAclKey -Rule $readBack)
    }

    It 'strips /32 and lowers case so a host rule matches its read-back form' {
        $a = [pscustomobject]@{ Weight = 4999; Action = 'Allow'; Remote = '10.99.0.1'; Protocol = 'tcp' }
        $b = [pscustomobject]@{ Weight = 4999; Action = 'Allow'; RemoteIPAddress = '10.99.0.1/32'; Protocol = 'TCP' }
        ConvertTo-PveAclKey -Rule $a | Should -Be (ConvertTo-PveAclKey -Rule $b)
    }

    It 'maps remote <Remote> to the open prefix' -TestCases @(@{ Remote = 'Any' }, @{ Remote = '*' }, @{ Remote = '' }, @{ Remote = $null }) {
        $r = [pscustomobject]@{ Weight = 4000; Action = 'Deny'; Remote = $Remote; Protocol = $null }
        ConvertTo-PveAclKey -Rule $r | Should -Be '4000|Deny|0.0.0.0/0|'
    }

    It 'maps protocol <Protocol> to no protocol' -TestCases @(@{ Protocol = 'Any' }, @{ Protocol = '*' }, @{ Protocol = $null }) {
        $r = [pscustomobject]@{ Weight = 4000; Action = 'Deny'; Remote = '0.0.0.0/0'; Protocol = $Protocol }
        ConvertTo-PveAclKey -Rule $r | Should -Be '4000|Deny|0.0.0.0/0|'
    }

    It 'keeps an IPv6 any-prefix distinct from the IPv4 one' {
        $v6 = [pscustomobject]@{ Weight = 4989; Action = 'Deny'; Remote = '::/0'; Protocol = $null }
        $v4 = [pscustomobject]@{ Weight = 4989; Action = 'Deny'; Remote = '0.0.0.0/0'; Protocol = $null }
        ConvertTo-PveAclKey -Rule $v6 | Should -Be '4989|Deny|::/0|'
        ConvertTo-PveAclKey -Rule $v6 | Should -Not -Be (ConvertTo-PveAclKey -Rule $v4)
    }

    It 'distinguishes a different action at the same weight' {
        $a = [pscustomobject]@{ Weight = 4010; Action = 'Allow'; Remote = '0.0.0.0/0'; Protocol = 'TCP' }
        $b = [pscustomobject]@{ Weight = 4010; Action = 'Deny'; Remote = '0.0.0.0/0'; Protocol = 'TCP' }
        ConvertTo-PveAclKey -Rule $a | Should -Not -Be (ConvertTo-PveAclKey -Rule $b)
    }
}

Describe 'Get-PveExtraFingerprint (psm1:210-215)' {
    It 'hashes an empty list to the SHA-256 of empty input' {
        Get-PveExtraFingerprint -Prefix @() | Should -Be '0 prefix(es), SHA-256 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    }

    It 'accepts no argument at all' {
        Get-PveExtraFingerprint | Should -BeLike '0 prefix(es)*'
    }

    It 'is independent of input order and sensitive to content' {
        $a = Get-PveExtraFingerprint -Prefix @('203.0.113.0/24', '198.51.100.0/24')
        $b = Get-PveExtraFingerprint -Prefix @('198.51.100.0/24', '203.0.113.0/24')
        $c = Get-PveExtraFingerprint -Prefix @('198.51.100.0/24', '192.0.2.0/24')
        $a | Should -Be $b
        $a | Should -Not -Be $c
        $a | Should -BeLike '2 prefix(es), SHA-256 *'
    }

    It 'never contains a prefix itself' {
        Get-PveExtraFingerprint -Prefix @('203.0.113.0/24') | Should -Not -BeLike '*203.0.113*'
    }
}

Describe 'Write-HomelabLog (psm1:1-18)' {
    BeforeAll {
        Mock Write-Host -ModuleName HomelabHyperV -MockWith {}
        $script:savedLocal = $env:LOCALAPPDATA
        $script:savedProfile = $env:USERPROFILE
    }
    AfterAll {
        $env:LOCALAPPDATA = $savedLocal
        $env:USERPROFILE = $savedProfile
    }

    It 'prefixes the level tag <Tag> for <Level>' -TestCases @(
        @{ Level = 'Pass'; Tag = '[PASS]' }, @{ Level = 'Warn'; Tag = '[WARN]' }, @{ Level = 'Fail'; Tag = '[FAIL]' }
        @{ Level = 'Skip'; Tag = '[SKIP]' }, @{ Level = 'Plan'; Tag = '[PLAN]' }, @{ Level = 'Step'; Tag = '==>   ' }
    ) {
        Write-HomelabLog -Level $Level -Message 'hello'
        Should -Invoke Write-Host -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter { $Object -eq ('{0} hello' -f $Tag) }
    }

    It 'rejects an unknown level' {
        { Write-HomelabLog -Level 'Debug' -Message 'x' } | Should -Throw
    }

    It 'prints a tag only on the first line of a multi-line message' {
        Write-HomelabLog -Level Fail -Message "first`r`nsecond"
        Should -Invoke Write-Host -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter { $Object -eq '[FAIL] first' }
        Should -Invoke Write-Host -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter { $Object -eq '       second' }
    }

    It 'accepts an empty message' {
        { Write-HomelabLog -Message '' } | Should -Not -Throw
    }

    It 'masks the local-app-data and profile paths in the output (psm1:11-13)' {
        $env:LOCALAPPDATA = 'D:\fixture\AppData\Local'
        $env:USERPROFILE = 'D:\fixture'
        Write-HomelabLog -Message 'log at d:\FIXTURE\appdata\local\x.log and D:\fixture\notes'
        Should -Invoke Write-Host -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter { $Object -eq '       log at %LOCALAPPDATA%\x.log and %USERPROFILE%\notes' }
    }

    It 'leaves the message alone when the path variables are empty (psm1:12)' {
        $env:LOCALAPPDATA = ''
        $env:USERPROFILE = ''
        Write-HomelabLog -Message 'plain'
        Should -Invoke Write-Host -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter { $Object -eq '       plain' }
    }
}

Describe 'Write-PveDenySummary (psm1:217-228)' {
    BeforeAll {
        Mock Write-Host -ModuleName HomelabHyperV -MockWith {}
        function script:New-DenyInput($Alias = @('Uplink A'), $Source = 'configured', $DenyAll = $false, $Extra = @(), $NewPrefix = @()) {
            [pscustomobject]@{ EgressInterfaceAlias = $Alias; EgressSource = $Source; DenyAll = $DenyAll; DenyAllReason = 'because'; Extra = $Extra; NewPrefix = $NewPrefix }
        }
    }

    It 'names the egress interface and its source' {
        Write-PveDenySummary -DenyInput (New-DenyInput)
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*egress interface: Uplink A (configured)' }
    }

    It 'shows a placeholder when no egress interface is known yet (psm1:220-221)' {
        Write-PveDenySummary -DenyInput (New-DenyInput -Alias @() -Source 'none')
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*egress interface: (none yet) (none)' }
    }

    It 'warns loudly when all egress is denied (psm1:223)' {
        Write-PveDenySummary -DenyInput (New-DenyInput -DenyAll $true)
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '`[WARN`] ALL GUEST EGRESS DENIED (fail closed): because' }
    }

    It 'says would append for a plan and appended for a persisted run (psm1:224-226)' {
        $in = New-DenyInput -Extra @('203.0.113.0/24') -NewPrefix @('203.0.113.0/24')
        Write-PveDenySummary -DenyInput $in
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*would append 1 new*' }
        Write-PveDenySummary -DenyInput $in -Persisted
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*; appended 1 new*' }
    }

    It 'prints a count and a hash, never the prefixes, unless asked (psm1:226-227)' {
        $in = New-DenyInput -Extra @('203.0.113.0/24') -NewPrefix @()
        Write-PveDenySummary -DenyInput $in
        Should -Invoke Write-Host -ModuleName HomelabHyperV -Times 0 -ParameterFilter { $Object -like '*203.0.113.0*' }
        Write-PveDenySummary -DenyInput $in -ShowPrefixes
        Should -Invoke Write-Host -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter { $Object -like '*203.0.113.0/24' }
    }
}
