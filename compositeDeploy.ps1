param
(
    [parameter()]
    [string]
    $WorkspacePath = "C:\Library\Deploy",

    [parameter()]
    [ValidateScript({Test-Path $_})]
    [string]
    $CompositeResourcePath = "$WorkspacePath\resources\RoleDeploy",
    
    [parameter()]
    [switch]
    $DeployInfrastructure = $false,
    
    [parameter()]
    [string]
    $VhdxPath = "C:\VirtualHardDisks\win2016.vhdx",
    
    [parameter()]
    [switch]
    $InjectConfig = $false,
    
    [parameter()]
    [ipaddress]
    $HostIpAddress = "192.0.0.247",
    
    [parameter()]
    [string]
    $VSwitchName = "DSC-vSwitch1",
    
    [parameter()]
    [pscredential]
    $DeploymentCredential = (New-Object System.Management.Automation.PSCredential ("administrator", (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force))),

    [parameter()]
    [string]
    $NodeDefinitionFilePath = "$WorkspacePath\DSCPushSetup\DefinitionStore\NodeDefinition.ps1"
)

#region vars
#global vars
$targetLCMSettings = @{
    ConfigurationModeFrequencyMins = 15
    RebootNodeIfNeeded             = $True
    ConfigurationMode              = "ApplyAndAutoCorrect"
    ActionAfterReboot              = "ContinueConfiguration"
    RefreshMode                    = "Push"
    AllowModuleOverwrite           = $true
    DebugMode                      = "None"
}

#shared vars
$dscPushModulePath = "$WorkspacePath\Modules\DSCPush"

#default vars
$ConfigurationDirectoryPath  = "$WorkspacePath\configs"
$contentStoreRootPath        = "$WorkspacePath\ContentStore"
$ContentStoreDestPath        = "C:\ContentStore"
$contentStoreModulePath      = "$WorkspacePath\modules"
$DscResourcesPath            = "$WorkspacePath\resources"
$StoredSecretsPath           = "$WorkspacePath\DSCPushSetup\Settings\StoredSecrets.json"
$SecretsKeyPath              = "$WorkspacePath\DSCPushSetup\Settings\SecretsKey.json"
$MofStorePath                = "$WorkspacePath\DSCPushSetup\Settings\mofStore"

#Mof encryption vars
$mofEncryptionSettings = @{
    EnableTargetMofEncryption   = $false
    TargetCertDirName           = "Certificates"
    MofEncryptionCertThumbprint = "C3CD32F10653BB2C9F795520583A9A1EF0C7D7DC"
    MofEncryptionCertPath       = "$WorkspacePath\Certificates\RpsDscEncryption.cer"
    MofEncryptionPKPath         = "$WorkspacePath\Certificates\RpsDscEncryption.pfx"
    MofEncryptionPKPassword     = $DeploymentCredential.Password
}
#endregion

Get-Module DscPush -ErrorAction SilentlyContinue | Remove-Module
Import-Module -FullyQualifiedName $dSCPushModulePath -ErrorAction Stop

if ($injectConfig)
{
    $configInjectionParams = @{
        VhdxPath                   = $vhdxPath
        NodeDefinitionFilePath     = $NodeDefinitionFilePath
        ConfigurationDirectoryPath = $ConfigurationDirectoryPath
        ContentStoreModulePath     = $contentStoreModulePath
        StoredSecretsPath          = $storedSecretsPath
        SecretsKeyPath             = $secretsKeyPath
        MofStorePath               = $MofStorePath
        TargetLcmSettings          = $targetLCMSettings
        DscResourcesPath           = $DscResourcesPath
        CompositeResourcePath      = $CompositeResourcePath
        ContentStorePath           = $contentStoreRootPath
    }
    Add-ConfigurationToVHDx @configInjectionParams
    
    if ($DeployInfrastructure)
    {
        $hyperVDeployScriptPath = "$WorkspacePath\deployVM-HyperV.ps1"
        $deploymentParams = @{
            VhdPath                = $VhdxPath
            VSwitchName            = $VSwitchName
            HostIpAddress          = $HostIpAddress
	        Credential             = $DeploymentCredential
            AdapterCount           = 1
            TargetSubnet           = "255.255.255.0"
            NodeDefinitionFilePath = $NodeDefinitionFilePath
        }
        & $hyperVDeployScriptPath @deploymentParams
    }
}
else
{
    if ($DeployInfrastructure)
    {
        $hyperVDeployScriptPath = "$WorkspacePath\deployVM-HyperV.ps1"
        $deploymentParams = @{
            VhdPath                = $vhdxPath
            VSwitchName            = $VSwitchName
            HostIpAddress          = $HostIpAddress
	        Credential             = $DeploymentCredential
            AdapterCount           = 1
            TargetSubnet           = "255.255.255.0"
            Clobber                = $true
            DifferencingDisks      = $true
            NodeDefinitionFilePath = $NodeDefinitionFilePath
        }
        & $hyperVDeployScriptPath @deploymentParams
    }

    $publishTargetSettings = @{
        SanitizeModulePaths         = $false
        CopyContentStore            = $true
        CopyDscResources            = $true
        SeedDscResources            = $true
        DeploymentCredential        = $DeploymentCredential
        CompositeResourcePath       = $CompositeResourcePath
        ConfigurationDirectoryPath  = $ConfigurationDirectoryPath
        ContentStoreRootPath        = $contentStoreRootPath
        ContentStoreDestPath        = $ContentStoreDestPath
        ContentStoreModulePath      = $contentStoreModulePath
        DscResourcesPath            = $DscResourcesPath
        NodeDefinitionFilePath      = $NodeDefinitionFilePath
        StoredSecretsPath           = $storedSecretsPath
        SecretsKeyPath              = $secretsKeyPath
        MofStorePath                = $MofStorePath
        TargetLcmSettings           = $targetLCMSettings
    }
    $publishTargetSettings += $mofEncryptionSettings
    Publish-CompositeTargetConfig @publishTargetSettings
}
