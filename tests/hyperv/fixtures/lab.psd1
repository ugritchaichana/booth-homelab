@{
    VmName         = 'lab-vm'
    RootPath       = 'C:\HyperVLab\lab-vm'
    CheckpointName = 'baseline'

    AddOwnerToHyperVAdministrators = $true

    SwitchName   = 'lab-switch'
    NatName      = 'lab-nat'
    NatPrefix    = '10.99.0.0/24'
    HostAddress  = '10.99.0.1'
    GuestAddress = '10.99.0.2'
    MacAddress   = '00-15-5D-99-00-02'
    SshPort      = 22
    WebPort      = 8006

    ProcessorCount = 4
    MemoryGiB      = 8
    DiskGiB        = 128

    MinHostFreeRamAfterVmGiB  = 4
    MinFreeDiskAfterGrowthGiB = 20
    MinHostVmConfigVersion    = '9.3'
    EmptyVhdxMaxMiB           = 16

    InstallTimeoutMinutes = 45
    BootTimeoutMinutes    = 10
    ProgressSeconds       = 30
    StopTimeoutSeconds    = 180

    FirewallRuleName     = 'lab-block-guest-inbound'
    AclWeightMin         = 4000
    AclWeightMax         = 4999
    MaxExtraDenyPrefixes = 64
}
