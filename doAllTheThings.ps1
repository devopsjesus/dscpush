$deploymentParams = @{
    VhdPath                = "C:\VirtualHardDisks\win2016-20181016.vhdx"
    VSwitchName            = "DSC-vSwitch1"
    HostIpAddress          = "192.0.0.247"
	Credential             = $DeploymentCredential
    AdapterCount           = 1
    TargetSubnet           = "255.255.255.0"
    NodeDefinitionFilePath = "C:\Library\Deploy\nodeDefinitions\Windows2016BaselineMS.ps1"
    Clobber = $true
}
.\deployVM-HyperV.ps1 @deploymentParams

$params = @{
    WorkspacePath          = "C:\Library\Deploy"
    CompositeResourcePath  = "C:\Library\Deploy\resources\RoleDeploy"
    NodeDefinitionFilePath = "C:\Library\Deploy\nodeDefinitions\Windows2016BaselineMS.ps1"
    DeploymentCredential   = (New-Object System.Management.Automation.PSCredential ("administrator", (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force)))
}
.\deploy.ps1 @params

