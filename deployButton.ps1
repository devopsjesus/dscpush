param
(
    [parameter()]
    [string]
    $WorkspacePath = $PSScriptRoot,
    
    [parameter()]
    [switch]
    $DeployInfrastructure = $true,
    
    [parameter()]
    [string]
    $VhdPath = "C:\VirtualHardDisks\win2016core-20180914.vhdx",
    
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
    ConfigurationModeFrequencyMins   = 15
    RebootNodeIfNeeded               = $True
    ConfigurationMode                = "ApplyAndAutoCorrect"
    ActionAfterReboot                = "ContinueConfiguration"
    RefreshMode                      = "Push"
    AllowModuleOverwrite             = $true
    DebugMode                        = "None"
}

#shared vars
$dscPushModulePath = "$WorkspacePath\Modules\DSCPush"
$partialCatalogPath = "$WorkspacePath\DSCPushSetup\Settings\PartialCatalog.json"

#default vars
$partialCatalogPath          = $partialCatalogPath
$partialStorePath            = "$WorkspacePath\partials"
$contentStoreRootPath        = "$WorkspacePath\ContentStore"
$ContentStoreDestPath        = "C:\ContentStore"
$contentStoreModulePath      = "$WorkspacePath\modules"
$DscResourcesPath            = "$WorkspacePath\resources"
$partialSecretsPath          = "$WorkspacePath\DSCPushSetup\Settings\PartialSecrets.json"
$StoredSecretsPath           = "$WorkspacePath\DSCPushSetup\Settings\StoredSecrets.json"
$SecretsKeyPath              = "$WorkspacePath\DSCPushSetup\Settings\SecretsKey.json"
$partialDependenciesFilePath = "$WorkspacePath\DSCPushSetup\Settings\PartialDependencies.json"
$partialSecretsPath          = "$WorkspacePath\DSCPushSetup\Settings\PartialSecrets.json"
$mofOutputPath               = "$WorkspacePath\DSCPushSetup\Settings\mofStore"

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

#region import module
Get-Module DscPush -ErrorAction SilentlyContinue | Remove-Module
Import-Module -FullyQualifiedName $dSCPushModulePath -ErrorAction Stop
#endregion

#region Init - first step in publishing configs is to initialize your workspace
<#These settings will:
    Generate a new partial catalog (required for first deployments and after any change to partials or partial path
    Generate secrets for all pscredential Partial Configuration parameters (POPUPS WILL APPEAR!)
    The SeedDscResources param will attempt to download the DSC Resources required by the configs from PSGallery
#>
$initDeploymentSettings = @{
    GeneratePartialCatalog = $true
    GenerateSecrets        = $true
    SeedDscResources       = $true
    DscResourcesPath       = $DscResourcesPath
    PartialCatalogPath     = $partialCatalogPath
    PartialStorePath       = $partialStorePath
    PartialSecretsPath     = $partialSecretsPath
    StoredSecretsPath      = $storedSecretsPath
    SecretsKeyPath         = $secretsKeyPath
}
Initialize-DscPush @initDeploymentSettings
#endregion
#endregion Init

#region Infrastructure deployment
<#This region will deploy VM(s) to Hyper-V if the DeployInfrastructure switch is present.
  This is put after the init section so that the password collection happens right after 
  the script starts and we don't have to wait for VMs to boot. In practice, infrastructure
  would be deployed before any configuraiton happens.
#>
if ($DeployInfrastructure)
{
    $hyperVDeployScriptPath = "$WorkspacePath\deployVM-HyperV.ps1"
    $deploymentParams = @{
        VhdPath                = $VhdPath
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
#endregion

#region Publish - second step after getting your workspace setup is to publish DSC configurations
<#These are the recommended settings for initial deployments.
  Follow up deployments can often turn off the CompSanitizeModulePaths, CopyContentStore & ForceResourceCopy switches to save time
  This sample shows Mof Encryption via the $mofEncryptionSettings var.#>
$publishTargetSettings = @{
    CompilePartials             = $true
    SanitizeModulePaths         = $true
    CopyContentStore            = $true
    ForceResourceCopy           = $true
    DeploymentCredential        = $DeploymentCredential
    ContentStoreRootPath        = $contentStoreRootPath
    ContentStoreDestPath        = $ContentStoreDestPath
    ContentStoreModulePath      = $contentStoreModulePath
    DscResourcesPath            = $DscResourcesPath
    NodeDefinitionFilePath      = $NodeDefinitionFilePath
    PartialCatalogPath          = $partialCatalogPath
    PartialDependenciesFilePath = $partialDependenciesFilePath
    PartialSecretsPath          = $partialSecretsPath
    StoredSecretsPath           = $storedSecretsPath
    SecretsKeyPath              = $secretsKeyPath
    MofOutputPath               = $mofOutputPath
    TargetLcmSettings           = $targetLCMSettings
}
$publishTargetSettings += $mofEncryptionSettings
Publish-TargetConfig @publishTargetSettings
#endregion Publish

#region Update Node Definition File
<# This section will allow for updating a Node Definition File from an existing Node Definition File, due to
an action requiring a re-examination of the variables stored in each Target Config object, any partial parameter
changes, etc. #>
<#
$UpdateNodeDefinitionFilePath = "$WorkspacePath\DSCPushSetup\DefinitionStore\NodeDefinitionUpdate.ps1"
$initDeploymentSettings = @{
    GeneratePartialCatalog       = $true
    UpdateNodeDefinitionFile     = $true
    PartialCatalogPath           = $partialCatalogPath
    PartialStorePath             = $partialStorePath
    NodeDefinitionFilePath       = $NodeDefinitionFilePath
    UpdateNodeDefinitionFilePath = $UpdateNodeDefinitionFilePath
}
Initialize-DscPush @initDeploymentSettings

$publishTargetSettings = @{
    CompilePartials             = $true
    SanitizeModulePaths         = $false
    CopyContentStore            = $true
    ForceResourceCopy           = $true
    DeploymentCredential        = $DeploymentCredential
    ContentStoreRootPath        = $contentStoreRootPath
    ContentStoreDestPath        = $ContentStoreDestPath
    ContentStoreModulePath      = $contentStoreModulePath
    DscResourcesPath            = $DscResourcesPath
    NodeDefinitionFilePath      = $UpdateNodeDefinitionFilePath #This changes
    PartialCatalogPath          = $partialCatalogPath
    PartialDependenciesFilePath = $partialDependenciesFilePath
    PartialSecretsPath          = $partialSecretsPath
    StoredSecretsPath           = $storedSecretsPath
    SecretsKeyPath              = $secretsKeyPath
    MofOutputPath               = $mofOutputPath
    TargetLcmSettings           = $targetLCMSettings
}
$publishTargetSettings += $mofEncryptionSettings
Publish-TargetConfig @publishTargetSettings
#endregion #>
