#Fill in the values below and save to your content store.

#region Node Definition: Master
$Master = New-Node -Name 'Master' -NodeId '1883264f-9536-4466-a81c-77d8fbfec315' -Type 'DscTestMasterNode'

#region Target Config: DscDC
$DscDC = New-TargetConfig -Properties @{
    ConfigName = 'DscDC'
    ContentHost = $False
    ContentStorePath = "\\DscMember\C$\ContentStore"
    RoleList = @(
        "Windows2016BaselineDC"
    )
}
$DscDCAdapterProperties = @{
    InterfaceAlias  = ''
    PhysicalAddress = '00-15-5d-36-F3-11'
    NetworkAddress  = '192.0.0.25'
    SubnetBits      = '24'
    DnsAddress      = '192.0.0.25'
    AddressFamily   = 'IPv4'
    Description     = ''
}
$DscDC.TargetAdapter = New-TargetAdapter @DscDCAdapterProperties
$DscDC.Variables += @{
    ComputerName    = 'DscDC'
    JoinDomain      = 'false'
    DomainName      = 'DscTest.local'
    WsusServerIP    = "192.0.0.247"
    WsusTargetGroup = "DscPushTest"
}
$Master.Configs += $DscDC
#endregion Target Config: DscDC

#region Target Config: DscMember
$DscMember = New-TargetConfig -Properties @{
    ConfigName = 'DscMember'
    ContentHost = $True
    ContentStorePath = 'C:\ContentStore'
    RoleList = @(
        "Windows2016BaselineMS"
    )
}
$DscMemberAdapterProperties = @{
    InterfaceAlias  = ''
    PhysicalAddress = '00-15-5d-36-F3-12'
    NetworkAddress  = '192.0.0.26'
    SubnetBits      = '24'
    DnsAddress      = '192.0.0.25'
    AddressFamily   = 'IPv4'
    Description     = ''
}
$DscMember.TargetAdapter = New-TargetAdapter @DscMemberAdapterProperties
$DscMember.Variables += @{
    ComputerName    = 'DscMember'
    JoinDomain      = 'true'
    DomainName      = 'DscTest'
    WsusServerIP    = "192.0.0.247"
    WsusTargetGroup = "DscPushTest"
}
$Master.Configs += $DscMember
#endregion Target Config: DscMember
#endregion Node Definition: Master

@($Master)
