#Fill in the values below and save to your content store.

#region Node Definition: Master
$Master = New-Node -Name 'Master' -NodeId '1883264f-9536-4466-a81c-77d8fbfec315' -Type 'DscTestMasterNode'

#region Target Config: DscTest
$DscTest = New-TargetConfig -Properties @{
    ConfigName = 'DscTest'
    ContentHost = $True
    ContentStorePath = 'C:\ContentStore'
    RoleList = @(
        "Windows2016Baseline"
    )
}
$DscTestAdapterProperties = @{
    InterfaceAlias  = ''
    PhysicalAddress = '00-15-5d-36-F2-11'
    NetworkAddress  = '192.0.0.31'
    SubnetBits      = '24'
    DnsAddress      = '192.0.0.31'
    AddressFamily   = 'IPv4'
    Description     = ''
}
$DscTest.TargetAdapter = New-TargetAdapter @DscTestAdapterProperties
$DscTest.Variables += @{
    ComputerName='DscTest'
    DomainName='dscpush.local'
    JoinDomain='false'
}
$Master.Configs += $DscTest
#endregion Target Config: DscTest

#endregion Node Definition: Master


@($Master)
