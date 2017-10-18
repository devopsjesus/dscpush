$masterNodeDefinition = New-Node -Name "Master" -NodeId $(New-Guid).Guid -Type "DscPushMasterNode"

$adConfig = New-TargetConfig -Properties @{
    ConfigName = "DscPushAD"
    TargetIP = "192.0.0.253"
    ContentHost = $false
    RoleList = @(
        "OSCore"
        "DomainController"
        "DnsRecord"
    )
    
}
$masterNodeDefinition.AddConfig($adConfig)

$chConfig = New-TargetConfig -Properties @{
    ConfigName = "DscPushCH"
    TargetIP = "192.0.0.251"
    ContentHost = $true
    RoleList = @(
        "OSCore"
        "Certificate"
        "DeploymentShare"
    )
}
$masterNodeDefinition.AddConfig($chConfig)

$childNodeDefinition = New-Node -Name "Child" -NodeId $(New-Guid).Guid -Type "DscPushChildNode"
$childNodeDefinition.AddParent($masterNodeDefinition)

$childConfig = New-TargetConfig -Properties @{
    ConfigName = "DscPushChild"
    TargetIP = "192.0.0.248"
    ContentHost = $true
    RoleList = @(
        "OSCore"
        "DeploymentShare"
    )
}
$childNodeDefinition.AddConfig($childConfig)

#DO NOT MODIFY BELOW THIS LINE!
@($masterNodeDefinition,$childNodeDefinition)
