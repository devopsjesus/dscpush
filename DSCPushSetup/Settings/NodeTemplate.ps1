$masterNodeDefinition = New-Node -Name "Master" -NodeId $(New-Guid).Guid -Type "DscPushMasterNode"

$adConfig = New-TargetConfig -Properties @{
    ConfigName = "DscPushAD"
    TargetIP = "192.0.0.253"
    ContentHost = $false
    RoleList = @(
        "OsCore"
        "DomainController"
        "HardenWinServer"
    )
    
}
$masterNodeDefinition.AddConfig($adConfig)

$chConfig = New-TargetConfig -Properties @{
    ConfigName = "DscPushCH"
    TargetIP = "192.0.0.251"
    ContentHost = $true
    RoleList = @(
        "OsCore"
        "HardenWinServer"
    )
}
$masterNodeDefinition.AddConfig($chConfig)

#DO NOT MODIFY BELOW THIS LINE!
@($masterNodeDefinition)
