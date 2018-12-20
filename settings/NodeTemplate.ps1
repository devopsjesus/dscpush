$masterNodeDefinition = New-Node -Name "Master" -NodeId $(New-Guid).Guid -Type "DscPushMasterNode"

$adConfig = New-TargetConfig -Properties @{
    ConfigName = "DscPushAD"
    ContentHost = $false
    RoleList = @(
        "OsCore"
        "DomainController"
        "HardenWinServer"
    )
    
}
$masterNodeDefinition.AddConfig($adConfig)

$adNetConfigProperties = @{
    InterfaceAlias = 'Ethernet'
    NetworkAddress = '192.0.0.253'
    SubnetBits     = '24'
    DnsAddress     = '192.0.0.253'
    AddressFamily  = 'IPv4'
    Description    = ''
}
$adConfig.TargetAdapter = New-TargetAdapter @adNetConfigProperties

$chConfig = New-TargetConfig -Properties @{
    ConfigName = "DscPushCH"
    ContentHost = $true
    RoleList = @(
        "OsCore"
        "HardenWinServer"
    )
}
$masterNodeDefinition.AddConfig($chConfig)

$chNetConfigProperties = @{
    InterfaceAlias = 'Ethernet'
    NetworkAddress = '192.0.0.251'
    SubnetBits     = '24'
    DnsAddress     = '192.0.0.251'
    AddressFamily  = 'IPv4'
    Description    = ''
}
$chConfig.TargetAdapter = New-TargetAdapter @chNetConfigProperties

#DO NOT MODIFY BELOW THIS LINE!
@($masterNodeDefinition)
