﻿param
(
    [switch]
    $DeployInfrastructure = $true,
    
    [string]
    $VhdPath = "C:\Virtualharddisks\win2016core.vhdx",

    [pscredential]
    $DeploymentCredential = (New-Object System.Management.Automation.PSCredential ("administrator", (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force)))
)

#region vars
#global vars
$workspacePath     = "C:\dscpushtest"
$targetLCMSettings = @{
    ConfigurationModeFrequencyMins   = 15
    RebootNodeIfNeeded               = $True
    ConfigurationMode                = "ApplyAndAutoCorrect"
    ActionAfterReboot                = "ContinueConfiguration"
    RefreshMode                      = "Push"
    AllowModuleOverwrite             = $true
    DebugMode                        = "None"
}

#Path and image credential to VHDx for infrastructure setup

#Node Definition file
$nodeDefinitionFilePath = "$workspacePath\DSCPushSetup\DefinitionStore\NodeDefinition.ps1"

#shared vars
$dscPushModulePath = "$workspacePath\Modules\DSCPush"
$partialCatalogPath = "$workspacePath\DSCPushSetup\Settings\PartialCatalog.json"

#default vars
$partialCatalogPath          = $partialCatalogPath
$partialStorePath            = "$workspacePath\partials"
$contentStoreRootPath        = "$workspacePath\ContentStore"
$ContentStoreDestPath        = "C:\ContentStore"
$contentStoreModulePath      = "$workspacePath\modules"
$DscResourcesPath            = "$workspacePath\resources"
$partialSecretsPath          = "$workspacePath\DSCPushSetup\Settings\PartialSecrets.json"
$StoredSecretsPath           = "$workspacePath\DSCPushSetup\Settings\StoredSecrets.json"
$SecretsKeyPath              = "$workspacePath\DSCPushSetup\Settings\SecretsKey.json"
$partialDependenciesFilePath = "$workspacePath\DSCPushSetup\Settings\PartialDependencies.json"
$partialSecretsPath          = "$workspacePath\DSCPushSetup\Settings\PartialSecrets.json"
$mofOutputPath               = "$workspacePath\DSCPushSetup\Settings\mofStore"

#Mof encryption vars
$mofEncryptionSettings = @{
    EnableTargetMofEncryption   = $false
    TargetCertDirName           = "Certificates"
    MofEncryptionCertThumbprint = "C3CD32F10653BB2C9F795520583A9A1EF0C7D7DC"
    MofEncryptionCertPath       = "$workspacePath\Certificates\RpsDscEncryption.cer"
    MofEncryptionPKPath         = "$workspacePath\Certificates\RpsDscEncryption.pfx"
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
#this is put after the init section so that the password collection happens right after 
#the script starts and we don't have to wait for VMs to boot
if ($DeployInfrastructure)
{
    $hyperVDeployScriptPath = "$workspacePath\deployVM-HyperV.ps1"
    $deploymentParams = @{
        VhdPath                = $VhdPath
        VSwitchName            = "Internet-NIC1"
        HostIpAddress          = "192.168.1.23"
        DnsServer              = "192.168.1.254"
	    Credential             = $DeploymentCredential
        AdapterCount           = 1
        TargetSubnet           = "255.255.255.0"
        Clobber                = $true
        DifferencingDisks      = $true
        NodeDefinitionFilePath = $nodeDefinitionFilePath
    }
    & $hyperVDeployScriptPath @deploymentParams
}
#endregion

#region Publish - second step after getting your workspace setup is to publish DSC configurations
<#These are the recommended settings for initial deployments.
  Follow up deployments can often turn off the CompSanitizeModulePaths, CopyContentStore & ForceResourceCopy switches to save time
  This sample shows Mof Encryption via the $mofEncryptionSettings var
#>
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
    NodeDefinitionFilePath      = $nodeDefinitionFilePath
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

<#region Update Node Definition File
#endregion #>
