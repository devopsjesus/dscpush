#Fill in the values below and save to your content store.

#region Node Definition: Master
$Master = New-Node -Name 'Master' -NodeId '1883264f-9536-4466-a81c-77d8fbfec315' -Type 'DscTestMasterNode'

#region Target Config: DscTest
$DscTest = New-TargetConfig -Properties @{
    ConfigName       = 'DscTest'
    ContentHost      = $true
    ContentStorePath = "C:\ContentStore"
    RoleList = @(
        "OsCore"
        "DomainController"
    )
}
$DscTestAdapterProperties = @{
    PhysicalAddress = '00-15-5d-36-F3-10'
    NetworkAddress  = '192.0.0.30'
    SubnetBits      = '24'
    AddressFamily   = 'IPv4'
    Description     = ''
}
$DscTest.TargetAdapter = New-TargetAdapter @DscTestAdapterProperties
$DscTest.Variables += @{
    ComputerName='DscTest'
    ContentStore='C:\ContentStore'
    DomainCredential='|pscredential|'
    DomainName='dscpush.local'
    JoinDomain='false'
}
$Master.Configs += $DscTest
#endregion Target Config: DscTest
#endregion Node Definition: Master

@($Master)
