BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'HyperVStubs.psm1') -Force
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..\..\scripts\hyperv\HomelabHyperV.psm1')).ProviderPath -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:savedLocalAppData = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = $TestDrive

    $store = @{ Acls = New-Object System.Collections.ArrayList; Events = New-Object System.Collections.ArrayList; Adapters = @(); AddFails = $false; RemoveFails = $false; DisconnectFails = $false; Routes = @() }
    $script:store = $store

    Mock Write-Host -ModuleName HomelabHyperV -MockWith {}
    Mock Get-NetRoute -ModuleName HomelabHyperV -MockWith ({ $store.Routes }.GetNewClosure())
    Mock Get-VMNetworkAdapter -ModuleName HomelabHyperV -MockWith ({ $store.Adapters }.GetNewClosure())
    Mock Get-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -MockWith ({ $store.Acls.ToArray() }.GetNewClosure())
    Mock Add-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -MockWith ({
            param($Weight, $Action, $Direction, $RemoteIPAddress, $Protocol, $LocalPort)
            [void]$store.Events.Add("add:$Weight")
            if (-not $store.AddFails) {
                [void]$store.Acls.Add([pscustomobject]@{ Weight = $Weight; Action = $Action; Direction = $Direction; RemoteIPAddress = $RemoteIPAddress; Protocol = $Protocol; LocalPort = $LocalPort })
            }
        }.GetNewClosure())
    Mock Remove-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -MockWith ({
            param($InputObject)
            [void]$store.Events.Add("remove:$($InputObject.Weight)")
            if ($store.RemoveFails) { throw 'remove refused' }
            $store.Acls.Remove($InputObject)
        }.GetNewClosure())
    Mock Disconnect-VMNetworkAdapter -ModuleName HomelabHyperV -MockWith ({
            if ($store.DisconnectFails) { throw 'disconnect refused' }
            [void]$store.Events.Add('disconnect')
        }.GetNewClosure())

    function script:Reset-Store {
        $store.Acls.Clear()
        $store.Events.Clear()
        $store.Adapters = @([pscustomobject]@{ Name = 'adapter-0'; SwitchName = 'lab-switch' })
        $store.AddFails = $false
        $store.RemoveFails = $false
        $store.DisconnectFails = $false
        $store.Routes = @()
    }
    function script:Add-ReadBack([object[]]$Plan) {
        foreach ($p in $Plan) {
            [void]$store.Acls.Add([pscustomobject]@{ Weight = $p.Weight; Action = $p.Action; Direction = $p.Direction; RemoteIPAddress = $p.Remote; Protocol = $p.Protocol; LocalPort = $p.LocalPort })
        }
    }
}

AfterAll {
    $env:LOCALAPPDATA = $savedLocalAppData
    Remove-Module HomelabHyperV, HyperVStubs -Force -ErrorAction SilentlyContinue
}

Describe 'Get-PveVmAdapter (psm1:327-332)' {
    BeforeEach { Reset-Store; $script:c = New-TestConfig }

    It 'returns the single adapter' {
        (Get-PveVmAdapter -Config $c).Name | Should -Be 'adapter-0'
    }

    It 'refuses <Count> adapters (psm1:330)' -TestCases @(@{ Count = 0 }, @{ Count = 2 }) {
        $store.Adapters = @(for ($i = 0; $i -lt $Count; $i++) { [pscustomobject]@{ Name = "adapter-$i" } })
        { Get-PveVmAdapter -Config $c } | Should -Throw "*Expected exactly one network adapter on lab-vm, found $Count*"
    }
}

Describe 'Get-PveOwnAcl and Get-PveForeignAcl split on the weight range (psm1:334-342)' {
    BeforeEach { Reset-Store; $script:c = New-TestConfig }

    It 'treats weight <Weight> as <Side>' -TestCases @(
        @{ Weight = 3999; Side = 'foreign' }, @{ Weight = 4000; Side = 'own' }
        @{ Weight = 4999; Side = 'own' }, @{ Weight = 5000; Side = 'foreign' }, @{ Weight = 0; Side = 'foreign' }
    ) {
        [void]$store.Acls.Add((New-TestAcl -Weight $Weight))
        $own = @(Get-PveOwnAcl -Config $c)
        $foreign = @(Get-PveForeignAcl -Config $c)
        if ($Side -eq 'own') { $own.Count | Should -Be 1; $foreign.Count | Should -Be 0 } else { $own.Count | Should -Be 0; $foreign.Count | Should -Be 1 }
    }

    It 'returns empty lists when the adapter has no rules' {
        @(Get-PveOwnAcl -Config $c).Count | Should -Be 0
        @(Get-PveForeignAcl -Config $c).Count | Should -Be 0
    }
}

Describe 'Format-PveAclTable masking (psm1:344-361)' {
    BeforeAll {
        $script:c = New-TestConfig
        $script:rules = @(
            [pscustomobject]@{ Weight = 4800; Direction = 'Outbound'; Action = 'Deny'; Stateful = $false; Protocol = $null; Remote = '203.0.113.0/24'; LocalPort = $null; Note = 'host-routed prefix' }
            [pscustomobject]@{ Weight = 4999; Direction = 'Inbound'; Action = 'Allow'; Stateful = $true; Protocol = 'TCP'; Remote = '10.99.0.1'; LocalPort = '22'; Note = 'ssh' }
            [pscustomobject]@{ Weight = 4010; Direction = 'Outbound'; Action = 'Allow'; Stateful = $true; Protocol = 'TCP'; Remote = '0.0.0.0/0'; LocalPort = $null; Note = 'internet' }
            [pscustomobject]@{ Weight = 4989; Direction = 'Outbound'; Action = 'Deny'; Stateful = $false; Protocol = $null; Remote = '::/0'; LocalPort = $null; Note = 'v6' }
        )
    }

    It 'hides a host-routed prefix by default (psm1:355-356)' {
        $text = Format-PveAclTable -Rule $rules -Config $c
        $text | Should -Match '\(host-routed\)'
        $text | Should -Not -Match '203\.0\.113'
    }

    It 'keeps the public and well-known remotes visible' {
        $text = Format-PveAclTable -Rule $rules -Config $c
        $text | Should -Match '10\.99\.0\.1'
        $text | Should -Match '0\.0\.0\.0/0'
        $text | Should -Match '::/0'
    }

    It 'reveals the prefix with -ShowPrefixes (psm1:351)' {
        Format-PveAclTable -Rule $rules -Config $c -ShowPrefixes | Should -Match '203\.0\.113\.0/24'
    }

    It 'reads RemoteIPAddress from a read-back rule and masks it the same way (psm1:359)' {
        $readBack = [pscustomobject]@{ Weight = 4800; Direction = 'Outbound'; Action = 'Deny'; Stateful = $false; Protocol = $null; RemoteIPAddress = '203.0.113.0/24'; LocalPort = $null; Note = $null }
        $text = Format-PveAclTable -Rule @($readBack) -Config $c
        $text | Should -Match '\(host-routed\)'
        $text | Should -Not -Match '203\.0\.113'
    }

    It 'lists the highest weight first' {
        $text = Format-PveAclTable -Rule $rules -Config $c
        $text.IndexOf('4999') | Should -BeLessThan $text.IndexOf('4010')
    }
}

Describe 'Sync-PveVmAcl happy path (psm1:363-419)' {
    BeforeEach { Reset-Store; $script:c = New-TestConfig }

    It 'adds every planned rule on an empty adapter and verifies the read-back (psm1:376-419)' {
        $r = Sync-PveVmAcl -Config $c -ExtraDenyPrefix @('203.0.113.0/24')
        $want = @(Get-PveAclPlan -Config $c -ExtraDenyPrefix @('203.0.113.0/24'))
        $r.Added | Should -Be $want.Count
        $r.Removed | Should -Be 0
        @($r.Applied).Count | Should -Be $want.Count
        @($r.Desired).Count | Should -Be $want.Count
        $store.Events | Should -Not -Contain 'disconnect'
    }

    It 'passes the stateful ssh rule to the switch with protocol, port and host remote (psm1:388-396)' {
        Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() | Out-Null
        Should -Invoke Add-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter {
            $Weight -eq 4999 -and $Action -eq 'Allow' -and $Direction -eq 'Inbound' -and $Protocol -eq 'TCP' -and $LocalPort -eq '22' -and $Stateful -eq $true -and $RemoteIPAddress -eq '10.99.0.1' -and $LocalIPAddress -eq 'ANY'
        }
    }

    It 'omits protocol and port for a plain deny rule (psm1:394-395)' {
        Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() | Out-Null
        Should -Invoke Add-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter {
            $Weight -eq 4000 -and $Action -eq 'Deny' -and -not $Protocol -and -not $LocalPort -and $Stateful -eq $false
        }
    }

    It 'changes nothing when the adapter already matches the plan (idempotent)' {
        Add-ReadBack (Get-PveAclPlan -Config $c -ExtraDenyPrefix @())
        $r = Sync-PveVmAcl -Config $c -ExtraDenyPrefix @()
        $r.Added | Should -Be 0
        $r.Removed | Should -Be 0
        Should -Invoke Add-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -Times 0 -Exactly
        Should -Invoke Remove-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -Times 0 -Exactly
    }

    It 'adds only the missing rule and removes a stale one inside the range (psm1:384-385,403-405)' {
        Add-ReadBack (Get-PveAclPlan -Config $c -ExtraDenyPrefix @())
        [void]$store.Acls.Add((New-TestAcl -Weight 4500 -Remote '203.0.113.0/24'))
        $r = Sync-PveVmAcl -Config $c -ExtraDenyPrefix @()
        $r.Added | Should -Be 0
        $r.Removed | Should -Be 1
        $store.Events | Should -Contain 'remove:4500'
    }

    It 'removes the stale rule that holds a slot before adding the replacement (psm1:399-406)' {
        [void]$store.Acls.Add((New-TestAcl -Weight 4010 -Action 'Deny' -Direction 'Outbound'))
        Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() | Out-Null
        $store.Events.IndexOf('remove:4010') | Should -BeLessThan $store.Events.IndexOf('add:4010')
    }

    It 'with DenyAllEgress writes the catch-all deny and no outbound allow (psm1:290-291)' {
        Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() -DenyAllEgress | Out-Null
        Should -Invoke Add-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter { $Weight -eq 4011 -and $Action -eq 'Deny' -and $RemoteIPAddress -eq '0.0.0.0/0' }
        Should -Invoke Add-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -Times 0 -Exactly -ParameterFilter { $Weight -in 4010, 4009 }
    }

    It 'accepts an empty extra list (psm1:366)' {
        { Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() } | Should -Not -Throw
    }
}

Describe 'Sync-PveVmAcl refuses and fails closed (psm1:370-429)' {
    BeforeEach { Reset-Store; $script:c = New-TestConfig }

    It 'refuses a foreign ACL at weight <Weight> without adding or removing anything (psm1:371-375)' -TestCases @(
        @{ Weight = 100 }, @{ Weight = 3999 }, @{ Weight = 5000 }
    ) {
        [void]$store.Acls.Add((New-TestAcl -Weight $Weight -Direction 'Inbound' -Action 'Allow'))
        { Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() } | Should -Throw "*outside the reserved weight range*($Weight Inbound Allow)*"
        Should -Invoke Add-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -Times 0 -Exactly
        Should -Invoke Remove-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -Times 0 -Exactly
        $store.Acls.Count | Should -Be 1
    }

    It 'disconnects the adapter when it refuses a foreign ACL (psm1:420-424)' {
        [void]$store.Acls.Add((New-TestAcl -Weight 100))
        { Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() } | Should -Throw
        $store.Events | Should -Contain 'disconnect'
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*adapter was disconnected*' }
    }

    It 'rethrows the original error and says so when the disconnect itself fails (psm1:425-428)' {
        [void]$store.Acls.Add((New-TestAcl -Weight 100))
        $store.DisconnectFails = $true
        { Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() } | Should -Throw '*outside the reserved weight range*'
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*could not be disconnected; stop the VM now*disconnect refused*' }
    }

    It 'fails the verification and disconnects when the switch drops one write (psm1:408-418)' {
        Add-ReadBack (Get-PveAclPlan -Config $c -ExtraDenyPrefix @() | Where-Object { $_.Weight -ne 4000 })
        $store.AddFails = $true
        { Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() } | Should -Throw '*Port ACL verification failed: 1 rule(s) missing, 0 unexpected*'
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*ACL read-back mismatch*' }
        $store.Events | Should -Contain 'disconnect'
    }

    It 'reports the verification failure and disconnects when every write is dropped (psm1:416)' {
        $store.AddFails = $true
        $want = @(Get-PveAclPlan -Config $c -ExtraDenyPrefix @()).Count
        { Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() } | Should -Throw "*Port ACL verification failed: $want rule(s) missing, 0 unexpected*"
        $store.Events | Should -Contain 'disconnect'
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*(no rules read back)*' }
    }

    It 'fails the verification when a stale rule cannot be removed (psm1:404,414-417)' {
        Add-ReadBack (Get-PveAclPlan -Config $c -ExtraDenyPrefix @())
        [void]$store.Acls.Add((New-TestAcl -Weight 4500 -Remote '203.0.113.0/24'))
        $store.RemoveFails = $true
        { Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() } | Should -Throw '*0 rule(s) missing, 1 unexpected*'
        $store.Events | Should -Contain 'disconnect'
    }

    It 'disconnects when the adapter count is wrong (psm1:330,420)' {
        $store.Adapters = @()
        { Sync-PveVmAcl -Config $c -ExtraDenyPrefix @() } | Should -Throw '*Expected exactly one network adapter*'
        $store.Events | Should -Contain 'disconnect'
        Should -Invoke Add-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -Times 0 -Exactly
    }

    It 'disconnects when the plan itself is refused for too many extras (psm1:265,420)' {
        $tooMany = @(1..65 | ForEach-Object { '203.0.113.{0}/32' -f $_ })
        { Sync-PveVmAcl -Config $c -ExtraDenyPrefix $tooMany } | Should -Throw '*the limit is*'
        $store.Events | Should -Contain 'disconnect'
        Should -Invoke Add-VMNetworkAdapterExtendedAcl -ModuleName HomelabHyperV -Times 0 -Exactly
    }
}

Describe 'Sync-PveIsolation (psm1:432-449)' {
    BeforeEach {
        Reset-Store
        $script:override = Join-Path $TestDrive 'iso\lab.local.psd1'
        $script:c = New-TestConfig @{ LocalOverridePath = $override }
        $store.Routes = @((New-TestRoute '0.0.0.0/0' 'Uplink A'), (New-TestRoute '203.0.113.0/24' 'Tunnel X'))
        $c.EgressInterfaceAlias = @('Uplink A')
    }
    AfterEach { Remove-Item -LiteralPath (Split-Path $override) -Recurse -Force -ErrorAction SilentlyContinue }

    It 'applies the plan including a host-routed prefix without persisting when -Persist is absent (psm1:440)' {
        $r = Sync-PveIsolation -Config $c
        $r.DenyInput.Extra | Should -Be @('203.0.113.0/24')
        $r.Result.Added | Should -BeGreaterThan 0
        Test-Path -LiteralPath $override | Should -BeFalse
    }

    It 'persists a newly seen prefix and updates the in-memory config (psm1:440-445)' {
        Sync-PveIsolation -Config $c -Persist | Out-Null
        $saved = Import-PveConfig -Path $FixturePath -LocalOverridePath $override
        $saved.StaticDenyPrefix | Should -Be @('203.0.113.0/24')
        $saved.EgressInterfaceAlias | Should -Be @('Uplink A')
        $c.StaticDenyPrefix | Should -Be @('203.0.113.0/24')
    }

    It 'does not rewrite the file when nothing is new (psm1:440)' {
        $c.StaticDenyPrefix = @('203.0.113.0/24')
        Sync-PveIsolation -Config $c -Persist | Out-Null
        Test-Path -LiteralPath $override | Should -BeFalse
    }

    It 'records an auto-detected egress alias even with no new prefix (psm1:440,162-165)' {
        $c.EgressInterfaceAlias = @()
        $c.StaticDenyPrefix = @('203.0.113.0/24')
        Sync-PveIsolation -Config $c -Persist | Out-Null
        (Import-PveConfig -Path $FixturePath -LocalOverridePath $override).EgressInterfaceAlias | Should -Be @('Uplink A')
    }

    It 'fails closed end to end when default routes sit on two interfaces (psm1:166-169,447)' {
        $c.EgressInterfaceAlias = @()
        $store.Routes = @((New-TestRoute '0.0.0.0/0' 'Uplink A'), (New-TestRoute '0.0.0.0/0' 'Uplink B'))
        $r = Sync-PveIsolation -Config $c
        $r.DenyInput.DenyAll | Should -BeTrue
        @($store.Acls | Where-Object { $_.Direction -eq 'Outbound' -and $_.Action -eq 'Allow' }).Count | Should -Be 0
        @($store.Acls | Where-Object { $_.Weight -eq 4011 -and $_.Action -eq 'Deny' }).Count | Should -Be 1
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*ALL GUEST EGRESS DENIED*' }
    }

    It 'keeps a prefix it already persisted even when the ACL sync then refuses (psm1:441,447)' {
        [void]$store.Acls.Add((New-TestAcl -Weight 100))
        { Sync-PveIsolation -Config $c -Persist } | Should -Throw '*outside the reserved weight range*'
        (Import-PveConfig -Path $FixturePath -LocalOverridePath $override).StaticDenyPrefix | Should -Be @('203.0.113.0/24')
    }

    It 'prints the prefixes only with -ShowPrefixes (psm1:446)' {
        Sync-PveIsolation -Config $c | Out-Null
        Should -Invoke Write-Host -ModuleName HomelabHyperV -Times 0 -ParameterFilter { $Object -like '*203.0.113.0/24' }
        Reset-Store
        $store.Routes = @((New-TestRoute '0.0.0.0/0' 'Uplink A'), (New-TestRoute '203.0.113.0/24' 'Tunnel X'))
        Sync-PveIsolation -Config $c -ShowPrefixes | Out-Null
        Should -Invoke Write-Host -ModuleName HomelabHyperV -Times 1 -ParameterFilter { $Object -like '*203.0.113.0/24' }
    }
}
