BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'HyperVStubs.psm1') -Force
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..\..\scripts\hyperv\HomelabHyperV.psm1')).ProviderPath -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:savedLocalAppData = $env:LOCALAPPDATA
    function script:Write-Override([string]$Text) {
        $path = Join-Path $TestDrive 'override.local.psd1'
        Set-Content -LiteralPath $path -Value $Text -Encoding UTF8
        $path
    }
    function script:Import-Fixture([string]$Path, [string]$Override = (Join-Path $TestDrive 'absent.local.psd1')) {
        Import-PveConfig -Path $Path -LocalOverridePath $Override
    }
}

AfterAll {
    $env:LOCALAPPDATA = $savedLocalAppData
    Remove-Module HomelabHyperV, HyperVStubs -Force -ErrorAction SilentlyContinue
}

Describe 'Import-PveConfig happy path (psm1:20-91)' {
    It 'loads the fixture and derives the computed fields (psm1:78-89)' {
        $cfg = Import-Fixture $FixturePath
        $cfg.VmName | Should -Be 'lab-vm'
        $cfg.NatCidr | Should -Be '10.99.0.0/24'
        $cfg.MemoryBytes | Should -Be (8GB)
        $cfg.DiskBytes | Should -Be (128GB)
        $cfg.MacPlain | Should -Be '00155D990002'
        $cfg.SwitchAdapterAlias | Should -Be 'vEthernet (lab-switch)'
        $cfg.VhdxPath | Should -Be 'C:\HyperVLab\lab-vm\lab-vm.vhdx'
        $cfg.MarkerPath | Should -Be 'C:\HyperVLab\lab-vm\.homelab-managed'
        $cfg.ConfigFile | Should -Be (Resolve-Path $FixturePath).ProviderPath
        @($cfg.StaticDenyPrefix).Count | Should -Be 0
        @($cfg.EgressInterfaceAlias).Count | Should -Be 0
        @($cfg.LocalOverrideKeys).Count | Should -Be 0
    }

    It 'derives the default override path from the config name under LOCALAPPDATA (psm1:41-43)' {
        $env:LOCALAPPDATA = $TestDrive
        $cfg = Import-PveConfig -Path $FixturePath
        $cfg.LocalOverridePath | Should -Be (Join-Path $TestDrive 'homelab\lab.local.psd1')
    }

    It 'fails when LOCALAPPDATA is unset and no override path is given (psm1:41)' {
        $env:LOCALAPPDATA = $null
        { Import-PveConfig -Path $FixturePath } | Should -Throw 'LOCALAPPDATA is not set'
        $env:LOCALAPPDATA = $TestDrive
    }

    It 'merges the three allowed override keys and normalises them (psm1:46-51,70-76)' {
        $path = Write-Override "@{ StaticDenyPrefix = @('203.0.113.77/24', '198.51.100.0/24'); EgressInterfaceAlias = 'Uplink A'; AddOwnerToHyperVAdministrators = `$false }"
        $cfg = Import-Fixture $FixturePath $path
        $cfg.StaticDenyPrefix | Should -Be @('203.0.113.0/24', '198.51.100.0/24')
        $cfg.EgressInterfaceAlias | Should -Be @('Uplink A')
        $cfg.AddOwnerToHyperVAdministrators | Should -BeFalse
        $cfg.LocalOverrideKeys | Should -HaveCount 3
    }

    It 'drops empty egress alias entries (psm1:74)' {
        $path = Write-Override "@{ EgressInterfaceAlias = @('', 'Uplink A', `$null) }"
        (Import-Fixture $FixturePath $path).EgressInterfaceAlias | Should -Be @('Uplink A')
    }
}

Describe 'Import-PveConfig rejections' {
    It 'rejects a missing config file (psm1:26)' {
        { Import-Fixture (Join-Path $TestDrive 'nope.psd1') } | Should -Throw 'Config file not found*'
    }

    It 'names the missing required key (psm1:37-38)' {
        $f = New-FixtureFile -Replace @{ 'SshPort\s+=\s+22' = '' }
        { Import-Fixture $f } | Should -Throw '*missing keys: SshPort*'
    }

    It 'rejects <Case> (<Line>)' -TestCases @(
        @{ Case = 'a VmName that starts with a hyphen'; Line = 'psm1:54'; Pattern = "VmName\s+=\s+'lab-vm'"; Value = "VmName = '-bad'"; Message = '*Config key VmName must match*' }
        @{ Case = 'a SwitchName with a space'; Line = 'psm1:54'; Pattern = "SwitchName\s+=\s+'lab-switch'"; Value = "SwitchName = 'lab switch'"; Message = '*Config key SwitchName must match*' }
        @{ Case = 'a name longer than 64 characters'; Line = 'psm1:54'; Pattern = "NatName\s+=\s+'lab-nat'"; Value = "NatName = '$('a' * 65)'"; Message = '*Config key NatName must match*' }
        @{ Case = 'a MAC outside the Hyper-V range'; Line = 'psm1:56'; Pattern = "MacAddress\s+=\s+'[^']+'"; Value = "MacAddress = '00-15-5E-99-00-02'"; Message = '*Hyper-V 00-15-5D range*' }
        @{ Case = 'a host address outside the NAT prefix'; Line = 'psm1:60'; Pattern = "HostAddress\s+=\s+'10.99.0.1'"; Value = "HostAddress = '10.99.1.1'"; Message = '*HostAddress 10.99.1.1 is outside NatPrefix*' }
        @{ Case = 'a guest address outside the NAT prefix'; Line = 'psm1:60'; Pattern = "GuestAddress\s+=\s+'10.99.0.2'"; Value = "GuestAddress = '10.99.1.2'"; Message = '*GuestAddress*outside NatPrefix*' }
        @{ Case = 'host and guest on the same address'; Line = 'psm1:62'; Pattern = "GuestAddress\s+=\s+'10.99.0.2'"; Value = "GuestAddress = '10.99.0.1'"; Message = '*must differ*' }
        @{ Case = 'an IPv6 host address'; Line = 'psm1:96'; Pattern = "HostAddress\s+=\s+'10.99.0.1'"; Value = "HostAddress = '2001:db8::1'"; Message = '*Not an IPv4 address*' }
        @{ Case = 'a weight range narrower than 200'; Line = 'psm1:63'; Pattern = 'AclWeightMax\s+=\s+4999'; Value = 'AclWeightMax = 4100'; Message = '*at least 200*' }
        @{ Case = 'a weight above 65535'; Line = 'psm1:67'; Pattern = 'AclWeightMax\s+=\s+4999'; Value = 'AclWeightMax = 100000'; Message = '*inside 0..65535*' }
        @{ Case = 'a negative minimum weight'; Line = 'psm1:67'; Pattern = 'AclWeightMin\s+=\s+4000'; Value = 'AclWeightMin = -5'; Message = '*inside 0..65535*' }
        @{ Case = 'a drive-root RootPath'; Line = 'psm1:64-65'; Pattern = "RootPath\s+=\s+'[^']+'"; Value = "RootPath = 'C:\'"; Message = '*absolute folder path below a drive root*' }
        @{ Case = 'a relative RootPath'; Line = 'psm1:64-65'; Pattern = "RootPath\s+=\s+'[^']+'"; Value = "RootPath = 'relative\path'"; Message = '*absolute folder path*' }
        @{ Case = 'a RootPath shorter than 6 characters'; Line = 'psm1:64-65'; Pattern = "RootPath\s+=\s+'[^']+'"; Value = "RootPath = 'C:\ab'"; Message = '*absolute folder path*' }
        @{ Case = 'a non-boolean AddOwnerToHyperVAdministrators'; Line = 'psm1:68'; Pattern = 'AddOwnerToHyperVAdministrators\s+=\s+\$true'; Value = "AddOwnerToHyperVAdministrators = 'yes'"; Message = '*must be*' }
    ) {
        $f = New-FixtureFile -Replace @{ $Pattern = $Value }
        { Import-Fixture $f } | Should -Throw $Message
    }

    It 'rejects an override key outside the allow-list (psm1:48-49)' {
        $path = Write-Override "@{ VmName = 'other' }"
        { Import-Fixture $FixturePath $path } | Should -Throw '*unsupported keys: VmName*'
    }

    It 'rejects an invalid stored deny prefix instead of keeping it (psm1:71)' {
        $path = Write-Override "@{ StaticDenyPrefix = @('203.0.113.300/8') }"
        { Import-Fixture $FixturePath $path } | Should -Throw
    }

    It 'rejects an IPv6 stored deny prefix (psm1:71)' {
        $path = Write-Override "@{ StaticDenyPrefix = @('2001:db8::/32') }"
        { Import-Fixture $FixturePath $path } | Should -Throw '*Not an IPv4 address*'
    }

    It 'rejects an egress alias holding a control character (psm1:75)' {
        $path = Write-Override "@{ EgressInterfaceAlias = @('a$([char]9)b') }"
        { Import-Fixture $FixturePath $path } | Should -Throw '*invalid interface name*'
    }

    It 'rejects an egress alias longer than 128 characters (psm1:75)' {
        $path = Write-Override "@{ EgressInterfaceAlias = @('$('x' * 129)') }"
        { Import-Fixture $FixturePath $path } | Should -Throw '*invalid interface name*'
    }
}

Describe 'Save-PveLocalOverride (psm1:230-253)' {
    BeforeEach {
        $script:target = Join-Path $TestDrive 'nested\dir\saved.local.psd1'
        $script:c = New-TestConfig @{ LocalOverridePath = $target; LocalOverrideKeys = @() }
    }

    It 'creates a missing folder and writes a file the loader accepts (psm1:238,251-252)' {
        Save-PveLocalOverride -Config $c -StaticDenyPrefix @('203.0.113.0/24') -EgressInterfaceAlias @('Uplink A')
        $back = Import-Fixture $FixturePath $target
        $back.StaticDenyPrefix | Should -Be @('203.0.113.0/24')
        $back.EgressInterfaceAlias | Should -Be @('Uplink A')
        Test-Path -LiteralPath ($target + '.tmp') | Should -BeFalse
    }

    It 'normalises, sorts and de-duplicates prefixes (psm1:244)' {
        Save-PveLocalOverride -Config $c -StaticDenyPrefix @('203.0.113.9/24', '198.51.100.0/24', '203.0.113.0/24')
        (Import-Fixture $FixturePath $target).StaticDenyPrefix | Should -Be @('198.51.100.0/24', '203.0.113.0/24')
    }

    It 'writes valid files for empty lists' {
        Save-PveLocalOverride -Config $c
        $back = Import-Fixture $FixturePath $target
        @($back.StaticDenyPrefix).Count | Should -Be 0
        @($back.EgressInterfaceAlias).Count | Should -Be 0
    }

    It 'escapes a single quote in an alias (psm1:241)' {
        Save-PveLocalOverride -Config $c -EgressInterfaceAlias @("Guest's Uplink")
        (Import-Fixture $FixturePath $target).EgressInterfaceAlias | Should -Be @("Guest's Uplink")
    }

    It 'replaces an existing file in place (psm1:252)' {
        Save-PveLocalOverride -Config $c -StaticDenyPrefix @('203.0.113.0/24')
        Save-PveLocalOverride -Config $c -StaticDenyPrefix @('198.51.100.0/24')
        (Import-Fixture $FixturePath $target).StaticDenyPrefix | Should -Be @('198.51.100.0/24')
    }

    It 'persists AddOwnerToHyperVAdministrators only when it came from the override (psm1:246-248)' {
        Save-PveLocalOverride -Config $c
        (Get-Content -LiteralPath $target -Raw) | Should -Not -Match 'AddOwnerToHyperVAdministrators'
        $c.LocalOverrideKeys = @('AddOwnerToHyperVAdministrators')
        $c.AddOwnerToHyperVAdministrators = $false
        Save-PveLocalOverride -Config $c
        (Import-Fixture $FixturePath $target).AddOwnerToHyperVAdministrators | Should -BeFalse
    }

    It 'rejects an invalid prefix before replacing the file' {
        Save-PveLocalOverride -Config $c -StaticDenyPrefix @('203.0.113.0/24')
        { Save-PveLocalOverride -Config $c -StaticDenyPrefix @('not-a-prefix') } | Should -Throw
        (Import-Fixture $FixturePath $target).StaticDenyPrefix | Should -Be @('203.0.113.0/24')
    }
}
