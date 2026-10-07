BeforeDiscovery {
    $script:canTranslateVmGroup = $true
    try { $null = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-83-0').Translate([Security.Principal.NTAccount]) } catch { $script:canTranslateVmGroup = $false }
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'HyperVStubs.psm1') -Force
    Import-Module (Resolve-Path (Join-Path $PSScriptRoot '..\..\scripts\hyperv\HomelabHyperV.psm1')).ProviderPath -Force
    . (Join-Path $PSScriptRoot 'TestHelpers.ps1')
    $script:savedLocalAppData = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = $TestDrive
    Mock Write-Host -ModuleName HomelabHyperV -MockWith {}

    function script:New-ErrorRecord([string]$Id, [string]$Category = 'NotSpecified') {
        [Management.Automation.ErrorRecord]::new([Exception]::new("simulated $Id"), $Id, $Category, $null)
    }
}

AfterAll {
    $env:LOCALAPPDATA = $savedLocalAppData
    Remove-Module HomelabHyperV, HyperVStubs -Force -ErrorAction SilentlyContinue
}

Describe 'Get-PveFirewallRuleSpec (psm1:451-460)' {
    It 'describes one inbound Block rule on all profiles scoped to the guest network and switch adapter' {
        $c = New-TestConfig
        $s = Get-PveFirewallRuleSpec -Config $c
        $s.Name | Should -Be 'lab-block-guest-inbound'
        $s.Direction | Should -Be 'Inbound'
        $s.Action | Should -Be 'Block'
        $s.Profile | Should -Be 'Any'
        $s.RemoteAddress | Should -Be '10.99.0.0/24'
        $s.InterfaceAlias | Should -Be 'vEthernet (lab-switch)'
        $s.DisplayName | Should -BeLike '*lab-vm*'
    }
}

Describe 'Get-PveFirewallState (psm1:462-473)' {
    BeforeAll {
        $fw = @{ Rule = $null; Throw = $null }
        $script:fw = $fw
        Mock Get-NetFirewallRule -ModuleName HomelabHyperV -MockWith ({ if ($fw.Throw) { throw $fw.Throw }; $fw.Rule }.GetNewClosure())
        $script:c = New-TestConfig
    }
    BeforeEach { $fw.Rule = $null; $fw.Throw = $null }

    It 'is present for an enabled inbound Block rule' {
        $fw.Rule = [pscustomobject]@{ Enabled = 'True'; Action = 'Block'; Direction = 'Inbound' }
        Get-PveFirewallState -Config $c | Should -Be 'present'
    }

    It 'is misconfigured when <Field> is <Value> (psm1:471-472)' -TestCases @(
        @{ Field = 'Enabled'; Value = 'False' }, @{ Field = 'Action'; Value = 'Allow' }, @{ Field = 'Direction'; Value = 'Outbound' }
    ) {
        $rule = @{ Enabled = 'True'; Action = 'Block'; Direction = 'Inbound' }
        $rule[$Field] = $Value
        $fw.Rule = [pscustomobject]$rule
        Get-PveFirewallState -Config $c | Should -Be 'misconfigured'
    }

    It 'is absent when the lookup returns nothing (psm1:470)' {
        Get-PveFirewallState -Config $c | Should -Be 'absent'
    }

    It 'is absent for a not-found error identified by its error id (psm1:467)' {
        $fw.Throw = New-ErrorRecord 'CmdletizationQuery_NotFound_Name'
        Get-PveFirewallState -Config $c | Should -Be 'absent'
    }

    It 'is absent for a not-found error identified by its category (psm1:467)' {
        $fw.Throw = New-ErrorRecord 'SomethingElse' 'ObjectNotFound'
        Get-PveFirewallState -Config $c | Should -Be 'absent'
    }

    It 'is unreadable, not absent, for any other error (psm1:468)' {
        $fw.Throw = New-ErrorRecord 'AccessDenied' 'PermissionDenied'
        Get-PveFirewallState -Config $c | Should -Be 'unreadable'
    }
}

Describe 'Sync-PveHostFirewallRule and Revoke-PveHostFirewallRule (psm1:475-499)' {
    BeforeAll {
        $fw = @{ Rule = $null; Addr = $null; Iface = $null }
        $script:fw = $fw
        Mock Get-NetFirewallRule -ModuleName HomelabHyperV -MockWith ({ $fw.Rule }.GetNewClosure())
        Mock Get-NetFirewallAddressFilter -ModuleName HomelabHyperV -MockWith ({ $fw.Addr }.GetNewClosure())
        Mock Get-NetFirewallInterfaceFilter -ModuleName HomelabHyperV -MockWith ({ $fw.Iface }.GetNewClosure())
        Mock New-NetFirewallRule -ModuleName HomelabHyperV -MockWith {}
        Mock Remove-NetFirewallRule -ModuleName HomelabHyperV -MockWith {}
        $script:c = New-TestConfig
        function script:Set-MatchingRule {
            $fw.Rule = [pscustomobject]@{ Action = 'Block'; Direction = 'Inbound'; Enabled = 'True'; Profile = 'Any' }
            $fw.Addr = [pscustomobject]@{ RemoteAddress = '10.99.0.0/255.255.255.0' }
            $fw.Iface = [pscustomobject]@{ InterfaceAlias = 'vEthernet (lab-switch)' }
        }
    }
    BeforeEach { $fw.Rule = $null; $fw.Addr = $null; $fw.Iface = $null }

    It 'creates the rule from the spec when none exists (psm1:488-489)' {
        Sync-PveHostFirewallRule -Config $c | Should -Be 'applied'
        Should -Invoke New-NetFirewallRule -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter {
            $Name -eq 'lab-block-guest-inbound' -and $Direction -eq 'Inbound' -and $Action -eq 'Block' -and $RemoteAddress -eq '10.99.0.0/24' -and $InterfaceAlias -eq 'vEthernet (lab-switch)' -and $Profile -eq 'Any'
        }
        Should -Invoke Remove-NetFirewallRule -ModuleName HomelabHyperV -Times 0 -Exactly
    }

    It 'leaves a matching rule untouched (psm1:485)' {
        Set-MatchingRule
        Sync-PveHostFirewallRule -Config $c | Should -Be 'unchanged'
        Should -Invoke New-NetFirewallRule -ModuleName HomelabHyperV -Times 0 -Exactly
        Should -Invoke Remove-NetFirewallRule -ModuleName HomelabHyperV -Times 0 -Exactly
    }

    It 'replaces a rule whose <Field> drifted (psm1:482-486)' -TestCases @(
        @{ Field = 'Action'; Value = 'Allow'; Target = 'Rule' }
        @{ Field = 'Direction'; Value = 'Outbound'; Target = 'Rule' }
        @{ Field = 'Enabled'; Value = 'False'; Target = 'Rule' }
        @{ Field = 'Profile'; Value = 'Private'; Target = 'Rule' }
        @{ Field = 'RemoteAddress'; Value = '203.0.113.0/24'; Target = 'Addr' }
        @{ Field = 'InterfaceAlias'; Value = 'other adapter'; Target = 'Iface' }
    ) {
        Set-MatchingRule
        $fw[$Target].$Field = $Value
        Sync-PveHostFirewallRule -Config $c | Should -Be 'applied'
        Should -Invoke Remove-NetFirewallRule -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter { $Name -eq 'lab-block-guest-inbound' }
        Should -Invoke New-NetFirewallRule -ModuleName HomelabHyperV -Times 1 -Exactly
    }

    It 'removes an existing rule and reports true (psm1:494-496)' {
        $fw.Rule = [pscustomobject]@{ Name = 'x' }
        Revoke-PveHostFirewallRule -Config $c | Should -BeTrue
        Should -Invoke Remove-NetFirewallRule -ModuleName HomelabHyperV -Times 1 -Exactly
    }

    It 'reports false and removes nothing when the rule is absent (psm1:498)' {
        Revoke-PveHostFirewallRule -Config $c | Should -BeFalse
        Should -Invoke Remove-NetFirewallRule -ModuleName HomelabHyperV -Times 0 -Exactly
    }
}

Describe 'Hyper-V rights (psm1:501-521)' {
    BeforeAll {
        $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $members = @{ List = @(); Throw = $false }
        $script:members = $members
        $script:userSid = $userSid
        Mock Get-LocalGroupMember -ModuleName HomelabHyperV -MockWith ({ if ($members.Throw) { throw 'group unreadable' }; $members.List }.GetNewClosure())
    }
    BeforeEach { $members.List = @(); $members.Throw = $false }

    It 'returns a boolean for the real elevation check' {
        Test-HomelabElevated | Should -BeOfType [bool]
    }

    It 'grants rights when elevated: <Elevated>, regardless of the group token (psm1:518)' -TestCases @(@{ Elevated = $true }, @{ Elevated = $false }) {
        Mock Test-HomelabElevated -ModuleName HomelabHyperV -MockWith ({ $Elevated }.GetNewClosure())
        $r = Get-HomelabHyperVRight
        $r.Elevated | Should -Be $Elevated
        $r.HasRights | Should -Be ($Elevated -or $r.InHyperVAdminsToken)
    }

    It 'reports membership configured when the current user is in the group (psm1:511)' {
        $members.List = @([pscustomobject]@{ SID = $userSid })
        (Get-HomelabHyperVRight).MemberConfigured | Should -BeTrue
    }

    It 'reports membership not configured for other members and for an empty group (psm1:511)' {
        $members.List = @([pscustomobject]@{ SID = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-18') })
        (Get-HomelabHyperVRight).MemberConfigured | Should -BeFalse
        $members.List = @()
        (Get-HomelabHyperVRight).MemberConfigured | Should -BeFalse
    }

    It 'treats an unreadable group as not configured instead of failing (psm1:512)' {
        $members.Throw = $true
        (Get-HomelabHyperVRight).MemberConfigured | Should -BeFalse
    }
}

Describe 'Grant-PveCurrentUserHyperVAdmin and Revoke-PveUserHyperVAdmin (psm1:523-561)' {
    BeforeAll {
        $userSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $g = @{ Members = @(); ListThrows = $false; AddThrows = $null }
        $script:g = $g
        $script:userSid = $userSid
        Mock Get-LocalGroup -ModuleName HomelabHyperV -MockWith { [pscustomobject]@{ Name = 'Fixture Admin Group' } }
        Mock Get-LocalGroupMember -ModuleName HomelabHyperV -MockWith ({ if ($g.ListThrows) { throw 'unreadable' }; $g.Members }.GetNewClosure())
        Mock Add-LocalGroupMember -ModuleName HomelabHyperV -MockWith ({ if ($g.AddThrows) { throw $g.AddThrows } }.GetNewClosure())
        Mock Remove-LocalGroupMember -ModuleName HomelabHyperV -MockWith ({ if ($g.AddThrows) { throw $g.AddThrows } }.GetNewClosure())
    }
    BeforeEach { $g.Members = @(); $g.ListThrows = $false; $g.AddThrows = $null }

    It 'adds the current user when absent (psm1:532-535)' {
        $r = Grant-PveCurrentUserHyperVAdmin
        $r.Result | Should -Be 'Added'
        $r.Group | Should -Be 'Fixture Admin Group'
        $r.UserSid | Should -Be $userSid.Value
        Should -Invoke Add-LocalGroupMember -ModuleName HomelabHyperV -Times 1 -Exactly -ParameterFilter { $Member -eq $userSid.Value }
    }

    It 'does nothing when the user is already a member (psm1:531)' {
        $g.Members = @([pscustomobject]@{ SID = $userSid })
        (Grant-PveCurrentUserHyperVAdmin).Result | Should -Be 'AlreadyMember'
        Should -Invoke Add-LocalGroupMember -ModuleName HomelabHyperV -Times 0 -Exactly
    }

    It 'still tries the add when the member list is unreadable (psm1:530)' {
        $g.ListThrows = $true
        (Grant-PveCurrentUserHyperVAdmin).Result | Should -Be 'Added'
        Should -Invoke Add-LocalGroupMember -ModuleName HomelabHyperV -Times 1 -Exactly
    }

    It 'maps a MemberExists add failure to AlreadyMember (psm1:536-537)' {
        $g.AddThrows = New-ErrorRecord 'MemberExists,Microsoft.PowerShell.Commands.AddLocalGroupMemberCommand'
        (Grant-PveCurrentUserHyperVAdmin).Result | Should -Be 'AlreadyMember'
    }

    It 'reports true when the member was removed (psm1:555-556)' {
        Revoke-PveUserHyperVAdmin -UserSid $userSid.Value | Should -BeTrue
    }

    It 'reports false when the member was not in the group (psm1:558)' {
        $g.AddThrows = New-ErrorRecord 'MemberNotFound,Microsoft.PowerShell.Commands.RemoveLocalGroupMemberCommand'
        Revoke-PveUserHyperVAdmin -UserSid $userSid.Value | Should -BeFalse
    }

    It 'rethrows any other removal failure (psm1:559)' {
        $g.AddThrows = New-ErrorRecord 'AccessDenied'
        { Revoke-PveUserHyperVAdmin -UserSid $userSid.Value } | Should -Throw '*simulated AccessDenied*'
    }
}

Describe 'Test-PveInsideRoot (psm1:563-568)' {
    It 'treats <Path> under <Root> as <Expected>' -TestCases @(
        @{ Path = 'C:\Lab\vm\disk.vhdx'; Root = 'C:\Lab\vm'; Expected = $true }
        @{ Path = 'C:\Lab\vm'; Root = 'C:\Lab\vm'; Expected = $true }
        @{ Path = 'C:\Lab\vm\'; Root = 'C:\Lab\vm'; Expected = $true }
        @{ Path = 'c:\lab\VM\Disk.vhdx'; Root = 'C:\Lab\vm'; Expected = $true }
        @{ Path = 'C:\Lab\vm2\disk.vhdx'; Root = 'C:\Lab\vm'; Expected = $false }
        @{ Path = 'C:\Lab\vm\..\other\disk.vhdx'; Root = 'C:\Lab\vm'; Expected = $false }
        @{ Path = 'C:\Lab'; Root = 'C:\Lab\vm'; Expected = $false }
        @{ Path = 'E:\Lab\vm\disk.vhdx'; Root = 'C:\Lab\vm'; Expected = $false }
    ) {
        Test-PveInsideRoot -Path $Path -Root $Root | Should -Be $Expected
    }
}

Describe 'Root ownership and ACL (psm1:570-639)' {
    BeforeAll {
        function script:New-AclObject($Owner = 'S-1-5-32-544') {
            $o = [pscustomobject]@{}
            $o | Add-Member -MemberType ScriptMethod -Name GetOwner -Value ({ param($type) [pscustomobject]@{ Value = $Owner } }.GetNewClosure())
            $o
        }
        function script:New-AceObject($Sid, $Rights, $Type = 'Allow') {
            $id = [pscustomobject]@{}
            $id | Add-Member -MemberType ScriptMethod -Name Translate -Value ({ param($t) [pscustomobject]@{ Value = $Sid } }.GetNewClosure())
            [pscustomobject]@{ IdentityReference = $id; FileSystemRights = [Security.AccessControl.FileSystemRights]$Rights; AccessControlType = $Type }
        }
        function script:New-GoodAcl {
            [pscustomobject]@{
                AreAccessRulesProtected = $true
                Access = @(
                    (New-AceObject 'S-1-5-18' 'FullControl'), (New-AceObject 'S-1-5-32-544' 'FullControl')
                    (New-AceObject 'S-1-5-32-578' 'Modify'), (New-AceObject 'S-1-5-83-0' 'Modify')
                )
            }
        }
        $acl = @{ Value = $null }
        $script:acl = $acl
        Mock Get-Acl -ModuleName HomelabHyperV -MockWith ({ $acl.Value }.GetNewClosure())
    }

    It 'accepts <Sid> as an owner and rejects a normal user (psm1:573)' -TestCases @(
        @{ Sid = 'S-1-5-32-544'; Expected = $true }, @{ Sid = 'S-1-5-18'; Expected = $true }, @{ Sid = 'S-1-5-21-1-2-3-1001'; Expected = $false }
    ) {
        $acl.Value = New-AclObject $Sid
        Test-PveRootOwner -Path 'C:\x' | Should -Be $Expected
    }

    It 'lists SYSTEM, Administrators, Hyper-V Administrators and the VM worker group (psm1:603-610)' {
        $spec = @(Get-PveRootAclSpec)
        $spec.Sid | Should -Be @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-32-578', 'S-1-5-83-0')
        ($spec | Where-Object Sid -EQ 'S-1-5-32-544').Rights | Should -Be 'FullControl'
    }

    It 'accepts the exact protected ACL (psm1:626)' {
        $acl.Value = New-GoodAcl
        Test-PveRootAcl -Path 'C:\x' | Should -BeTrue
    }

    It 'accepts an ACE with more rights than required (psm1:623)' {
        $a = New-GoodAcl
        $a.Access[2] = New-AceObject 'S-1-5-32-578' 'FullControl'
        $acl.Value = $a
        Test-PveRootAcl -Path 'C:\x' | Should -BeTrue
    }

    It 'rejects an inheriting ACL (psm1:615)' {
        $a = New-GoodAcl
        $a.AreAccessRulesProtected = $false
        $acl.Value = $a
        Test-PveRootAcl -Path 'C:\x' | Should -BeFalse
    }

    It 'rejects an extra principal (psm1:621)' {
        $a = New-GoodAcl
        $a.Access += New-AceObject 'S-1-1-0' 'ReadAndExecute'
        $acl.Value = $a
        Test-PveRootAcl -Path 'C:\x' | Should -BeFalse
    }

    It 'rejects a Deny entry (psm1:621)' {
        $a = New-GoodAcl
        $a.Access[0] = New-AceObject 'S-1-5-18' 'FullControl' 'Deny'
        $acl.Value = $a
        Test-PveRootAcl -Path 'C:\x' | Should -BeFalse
    }

    It 'rejects insufficient rights (psm1:623)' {
        $a = New-GoodAcl
        $a.Access[3] = New-AceObject 'S-1-5-83-0' 'ReadAndExecute'
        $acl.Value = $a
        Test-PveRootAcl -Path 'C:\x' | Should -BeFalse
    }

    It 'rejects a missing principal (psm1:626)' {
        $a = New-GoodAcl
        $a.Access = @($a.Access[0], $a.Access[1], $a.Access[2])
        $acl.Value = $a
        Test-PveRootAcl -Path 'C:\x' | Should -BeFalse
    }

    It 'builds a protected ACL with the four allow entries and applies it to the given path (psm1:629-638)' {
        $captured = @{}
        Mock Set-Acl -ModuleName HomelabHyperV -MockWith ({ param($LiteralPath, $AclObject) $captured.Path = $LiteralPath; $captured.Acl = $AclObject }.GetNewClosure())
        Initialize-PveRootAcl -Path 'C:\fixture\root'
        $captured.Path | Should -Be 'C:\fixture\root'
        $captured.Acl.AreAccessRulesProtected | Should -BeTrue
        $rules = @($captured.Acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier]))
        $rules.Count | Should -Be 4
        ($rules.IdentityReference.Value | Sort-Object) | Should -Be @('S-1-5-18', 'S-1-5-32-544', 'S-1-5-32-578', 'S-1-5-83-0' | Sort-Object)
        foreach ($r in $rules) { [string]$r.AccessControlType | Should -Be 'Allow' }
        (($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-32-578' }).FileSystemRights -band [Security.AccessControl.FileSystemRights]::Modify) | Should -Be ([int][Security.AccessControl.FileSystemRights]::Modify)
        ($rules | Select-Object -First 1).InheritanceFlags.ToString() | Should -Be 'ContainerInherit, ObjectInherit'
    }
}

Describe 'Assert-PveSafePath (psm1:576-601)' {
    BeforeAll {
        $owner = @{ Ok = $true; Throws = $false }
        $script:owner = $owner
        Mock Test-PveRootOwner -ModuleName HomelabHyperV -MockWith ({ if ($owner.Throws) { throw 'owner unreadable' }; $owner.Ok }.GetNewClosure())
    }
    BeforeEach {
        $owner.Ok = $true
        $owner.Throws = $false
        $script:parent = Join-Path $TestDrive 'parent'
        $script:root = Join-Path $parent 'root'
        Remove-Item -LiteralPath $parent -Recurse -Force -ErrorAction SilentlyContinue
        $script:c = New-TestConfig @{ RootPath = $root }
    }

    It 'returns quietly when neither folder exists yet (psm1:580,591)' {
        { Assert-PveSafePath -Config $c } | Should -Not -Throw
        Should -Invoke Test-PveRootOwner -ModuleName HomelabHyperV -Times 0 -Exactly
    }

    It 'accepts an owned tree with nested folders (psm1:592-600)' {
        New-Item -ItemType Directory -Path (Join-Path $root 'a\b') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'a\b\f.txt') -Value 'x'
        { Assert-PveSafePath -Config $c } | Should -Not -Throw
        Should -Invoke Test-PveRootOwner -ModuleName HomelabHyperV -Times 2 -Exactly
    }

    It 'refuses a root not owned by Administrators or SYSTEM (psm1:589)' {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $owner.Ok = $false
        { Assert-PveSafePath -Config $c } | Should -Throw '*not owned by Administrators or SYSTEM*'
    }

    It 'propagates an owner-check failure unless lenient (psm1:586)' {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $owner.Throws = $true
        { Assert-PveSafePath -Config $c } | Should -Throw '*owner unreadable*'
    }

    It 'skips an unreadable owner in lenient mode and says so (psm1:586-587)' {
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $owner.Throws = $true
        { Assert-PveSafePath -Config $c -Lenient } | Should -Not -Throw
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*[[]SKIP]*owner check*skipped in plan*' }
    }

    It 'refuses a root that is a reparse point (psm1:581)' {
        $target = Join-Path $TestDrive 'link-target'
        New-Item -ItemType Directory -Path $target, $parent -Force | Out-Null
        New-Item -ItemType Junction -Path $root -Target $target | Out-Null
        try { { Assert-PveSafePath -Config $c } | Should -Throw '*reparse point*' }
        finally { [IO.Directory]::Delete($root) }
    }

    It 'refuses a reparse point nested inside the root (psm1:597)' {
        $target = Join-Path $TestDrive 'link-target-nested'
        New-Item -ItemType Directory -Path $target, (Join-Path $root 'a') -Force | Out-Null
        $link = Join-Path $root 'a\link'
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        try { { Assert-PveSafePath -Config $c } | Should -Throw '*reparse point*' }
        finally { [IO.Directory]::Delete($link) }
    }
}

Describe 'Get-PveVmAccountName (psm1:641-645)' {
    It 'joins the VM worker group domain with the upper-case VM id (invariant culture: psm1:644 IndexOf is culture-sensitive)' -Skip:(-not $script:canTranslateVmGroup) {
        $saved = [Threading.Thread]::CurrentThread.CurrentCulture
        [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]::InvariantCulture
        try { $name = Get-PveVmAccountName -VmId ([guid]'0a1b2c3d-4e5f-6789-abcd-ef0123456789') }
        finally { [Threading.Thread]::CurrentThread.CurrentCulture = $saved }
        $name | Should -Match '^[^\\]+\\0A1B2C3D-4E5F-6789-ABCD-EF0123456789$'
    }
}

Describe 'Confirm-PveVmFileAccess (psm1:647-670)' {
    BeforeAll {
        $s = @{ VmId = [guid]'0a1b2c3d-4e5f-6789-abcd-ef0123456789'; Dvd = @(); HasAce = @(); IcaclsExit = 0; Granted = New-Object System.Collections.ArrayList }
        $script:s = $s
        Mock Get-VM -ModuleName HomelabHyperV -MockWith ({ [pscustomobject]@{ Id = $s.VmId; Path = $s.VmPath } }.GetNewClosure())
        Mock Get-VMDvdDrive -ModuleName HomelabHyperV -MockWith ({ $s.Dvd }.GetNewClosure())
        Mock Get-Acl -ModuleName HomelabHyperV -MockWith ({
                param($LiteralPath)
                $ace = @()
                if ($s.HasAce -contains $LiteralPath) { $ace = @([pscustomobject]@{ IdentityReference = ('NT VIRTUAL MACHINE\' + $s.VmId.ToString()) }) }
                [pscustomobject]@{ Access = $ace }
            }.GetNewClosure())
        Mock icacls.exe -ModuleName HomelabHyperV -MockWith ({ [void]$s.Granted.Add($args -join ' '); $global:LASTEXITCODE = $s.IcaclsExit }.GetNewClosure())
        Mock Get-PveVmAccountName -ModuleName HomelabHyperV -MockWith { 'FIXTURE\ACCOUNT' }
    }
    BeforeEach {
        $script:root = Join-Path $TestDrive 'vmroot'
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path (Join-Path $root 'Virtual Machines') -Force | Out-Null
        $s.VmPath = $root
        $s.Dvd = @()
        $s.HasAce = @()
        $s.IcaclsExit = 0
        $s.Granted.Clear()
        $script:c = New-TestConfig @{ RootPath = $root; VhdxPath = (Join-Path $root 'lab-vm.vhdx') }
    }

    It 'grants the per-VM account on the disk when its ACE is missing (psm1:659-667)' {
        $r = @(Confirm-PveVmFileAccess -Config $c)
        $r.Count | Should -Be 1
        $r[0].PerVmAcePresent | Should -BeFalse
        $r[0].GrantedNow | Should -BeTrue
        $s.Granted | Should -HaveCount 1
        $s.Granted[0] | Should -BeLike '*lab-vm.vhdx /grant FIXTURE\ACCOUNT:(F)'
    }

    It 'does not call icacls when the ACE is already there (psm1:662)' {
        $s.HasAce = @($c.VhdxPath)
        $r = @(Confirm-PveVmFileAccess -Config $c)
        $r[0].PerVmAcePresent | Should -BeTrue
        $r[0].GrantedNow | Should -BeFalse
        $s.Granted | Should -HaveCount 0
    }

    It 'includes a mounted ISO under the root and skips an empty drive (psm1:653)' {
        $iso = Join-Path $root 'install.iso'
        $s.Dvd = @([pscustomobject]@{ Path = $iso }, [pscustomobject]@{ Path = '' })
        @(Confirm-PveVmFileAccess -Config $c).File | Should -Be @($c.VhdxPath, $iso)
    }

    It 'includes only the VM config file named after the VM id (psm1:655-658)' {
        $dir = Join-Path $root 'Virtual Machines'
        Set-Content -LiteralPath (Join-Path $dir '0A1B2C3D-4E5F-6789-ABCD-EF0123456789.vmcx') -Value 'x'
        Set-Content -LiteralPath (Join-Path $dir 'unrelated.vmcx') -Value 'x'
        $files = @(Confirm-PveVmFileAccess -Config $c).File
        $files | Should -HaveCount 2
        $files[1] | Should -BeLike '*0A1B2C3D-4E5F-6789-ABCD-EF0123456789.vmcx'
    }

    It 'refuses to grant on an ISO outside the root (psm1:654)' {
        $s.Dvd = @([pscustomobject]@{ Path = (Join-Path $TestDrive 'elsewhere\x.iso') })
        { Confirm-PveVmFileAccess -Config $c } | Should -Throw '*outside RootPath*'
        $s.Granted | Should -HaveCount 0
    }

    It 'refuses a VHDX outside the root (psm1:654)' {
        $c.VhdxPath = Join-Path $TestDrive 'elsewhere\disk.vhdx'
        { Confirm-PveVmFileAccess -Config $c } | Should -Throw '*outside RootPath*'
    }

    It 'fails when icacls exits non-zero (psm1:664)' {
        $s.IcaclsExit = 5
        { Confirm-PveVmFileAccess -Config $c } | Should -Throw '*icacls failed*exit 5*'
    }
}

Describe 'Test-PveTcpPort (psm1:672-685)' {
    It 'is true for a listening local port' {
        $listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0
        $listener.Start()
        try { Test-PveTcpPort -Address 'localhost' -Port $listener.LocalEndpoint.Port -TimeoutMs 3000 | Should -BeTrue }
        finally { $listener.Stop() }
    }

    It 'is false for a port nobody listens on (psm1:680-681)' {
        $listener = New-Object Net.Sockets.TcpListener ([Net.IPAddress]::Loopback), 0
        $listener.Start()
        $port = $listener.LocalEndpoint.Port
        $listener.Stop()
        Test-PveTcpPort -Address 'localhost' -Port $port -TimeoutMs 1000 | Should -BeFalse
    }

    It 'is false for an unreachable documentation address within the timeout (psm1:677,681)' {
        Test-PveTcpPort -Address '192.0.2.1' -Port 9 -TimeoutMs 200 | Should -BeFalse
    }

    It 'is false for an unresolvable name (psm1:681)' {
        Test-PveTcpPort -Address 'host.invalid' -Port 22 -TimeoutMs 500 | Should -BeFalse
    }
}

Describe 'Wait-PveTcpPort (psm1:687-706)' {
    BeforeAll {
        $probe = @{ Calls = 0; SucceedOn = 1 }
        $script:probe = $probe
        Mock Test-PveTcpPort -ModuleName HomelabHyperV -MockWith ({ $probe.Calls++; $probe.Calls -ge $probe.SucceedOn }.GetNewClosure())
        Mock Start-Sleep -ModuleName HomelabHyperV -MockWith { Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds 300 }
    }
    BeforeEach { $probe.Calls = 0; $probe.SucceedOn = 1 }

    It 'returns the elapsed seconds as soon as the port answers (psm1:698)' {
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $secs = Wait-PveTcpPort -Address 'fixture-host' -Port 22 -TimeoutSeconds 30 -Clock $clock
        $secs | Should -BeOfType [double]
        $secs | Should -BeLessThan 5
        $probe.Calls | Should -Be 1
    }

    It 'keeps polling until the port answers (psm1:697-703)' {
        $probe.SucceedOn = 3
        $clock = [Diagnostics.Stopwatch]::StartNew()
        Wait-PveTcpPort -Address 'fixture-host' -Port 22 -TimeoutSeconds 30 -Clock $clock | Should -Not -BeNullOrEmpty
        $probe.Calls | Should -Be 3
    }

    It 'returns null after the timeout and prints progress (psm1:699-705)' {
        $probe.SucceedOn = 1000
        $clock = [Diagnostics.Stopwatch]::StartNew()
        Wait-PveTcpPort -Address 'fixture-host' -Port 22 -TimeoutSeconds 1 -Clock $clock -ProgressSeconds 0 | Should -BeNullOrEmpty
        $probe.Calls | Should -BeGreaterThan 0
        Should -Invoke Write-Host -ModuleName HomelabHyperV -ParameterFilter { $Object -like '*waiting for fixture-host:22*' }
    }
}

Describe 'Host memory and size formatting (psm1:708-717)' {
    BeforeAll {
        $cim = @{ Perf = $null; Os = $null }
        $script:cim = $cim
        Mock Get-CimInstance -ModuleName HomelabHyperV -MockWith ({ param($ClassName) if ($ClassName -like '*PerfOS_Memory') { $cim.Perf } else { $cim.Os } }.GetNewClosure())
    }

    It 'prefers the performance counter value (psm1:710)' {
        $cim.Perf = [pscustomobject]@{ AvailableBytes = 6GB }
        $cim.Os = [pscustomobject]@{ FreePhysicalMemory = 1 }
        Get-HomelabAvailableMemory | Should -Be 6GB
    }

    It 'falls back to the OS free memory in KiB when the counter is missing (psm1:711)' {
        $cim.Perf = $null
        $cim.Os = [pscustomobject]@{ FreePhysicalMemory = 2048 }
        Get-HomelabAvailableMemory | Should -Be (2048 * 1KB)
    }

    It 'falls back when the counter reports zero (psm1:710)' {
        $cim.Perf = [pscustomobject]@{ AvailableBytes = 0 }
        $cim.Os = [pscustomobject]@{ FreePhysicalMemory = 4096 }
        Get-HomelabAvailableMemory | Should -Be (4096 * 1KB)
    }

    It 'formats <Bytes> bytes as <Pattern>' -TestCases @(
        @{ Bytes = 0; Pattern = '^0[.,]0 GiB$' }
        @{ Bytes = 1GB; Pattern = '^1[.,]0 GiB$' }
        @{ Bytes = 1.5GB; Pattern = '^1[.,]5 GiB$' }
    ) {
        Format-HomelabGiB -Bytes $Bytes | Should -Match $Pattern
    }
}
