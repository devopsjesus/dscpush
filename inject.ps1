<#
    .SYNOPSIS
        Use this script to deploy DSC configurations using the DscPush module.

    .DESCRIPTION
        This script initiates the active components required to inject DSC configurations into a VHDx. It's intended to be used
        as a wrapper script for the DscPush module, which uses a Composite Resource Module to store "role" resources - simply composite
        resources that contain the necessary resources for the role that is being deployed. This script allows for configurations,
        supporting resource modules, and any supporting content to be injected directly into VHDxs for off-network deployment.

    .PARAMETER WorkspacePath
        Path to the root directory that will contain all the necessary components required to compile and inject a configuration.

    .PARAMETER CompositeResourcePath
        Path to the PowerShell DSC Composite Resource module that contains the composite resources that define the roles to be deployed.

    .PARAMETER VhdxPath
        Path to the VHDx that is used as the target for the configuration injection.

    .PARAMETER NodeDefinitionFilePath
        Path to the Node Definition File used by DscPush module that contains the required data to deploy the configuration.

    .EXAMPLE
        $params = @{
            WorkspacePath          = "C:\Library\Deploy"
            CompositeResourcePath  = "C:\Library\Deploy\resources\RoleDeploy"
            VhdxPath               = "C:\VirtualHardDisks\DscTest.vhdx"
            NodeDefinitionFilePath = "C:\Library\Deploy\nodeDefinitions\Windows2016BaselineMS.ps1"
        }
        .\inject.ps1 @params
#>
param
(
    [parameter(mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $WorkspacePath,

    [parameter(mandatory)]
    [ValidateScript({Test-Path $_})]
    [string]
    $CompositeResourcePath,
    
    [parameter(mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]
    $VhdxPath,

    [parameter(mandatory)]
    [ValidateScript({Test-Path $_})]
    [string]
    $NodeDefinitionFilePath
)

# The targetLCMSettings hashtable contains the desired settings of the target LCM.  In the case of a Node Definition File
# with multiple target nodes, the same settings will be used across all nodes.
$targetLCMSettings = @{
    ConfigurationModeFrequencyMins = 15
    RebootNodeIfNeeded             = $True
    ConfigurationMode              = "ApplyAndAutoCorrect"
    ActionAfterReboot              = "ContinueConfiguration"
    RefreshMode                    = "Push"
    AllowModuleOverwrite           = $true
    DebugMode                      = "None"
}

# The directorySettings hashtable contains the default directory paths for each different component required to compile and
# deploy configurations.  Note, the ContentStoreDestinationPath is the desired path on the target nodes to copy the content store.
# Note, the StoredSecretsPath and SecretsKeyPath are where the secrets that contain all passwords and other required encrypted content.
# The SecretsKey should be treated with the same consideration as the MofEncryptionPKPassword.
$directorySettings = @{
    ModuleDirectory        = "$WorkspacePath\Modules"
    DscPushModulePath      = "$WorkspacePath\Modules\DSCPush"
    ConfigurationDirectory = "$WorkspacePath\configs"
    ContentStoreDirectory  = "$WorkspacePath\ContentStore"
    DscResourcesDirectory  = "$WorkspacePath\resources"
    StoredSecretsPath      = "$WorkspacePath\Settings\StoredSecrets.json"
    SecretsKeyPath         = "$WorkspacePath\Settings\SecretsKey.json"
    MofStorePath           = "$WorkspacePath\mofStore"
}

#Remove and reimport module to allow for changes made during development
Get-Module DscPush -ErrorAction SilentlyContinue | Remove-Module
Import-Module -FullyQualifiedName $directorySettings.DSCPushModulePath -ErrorAction Stop
$directorySettings.Remove("DscPushModulePath")

# Add all the hashtables up and splat to the injection cmdlet
$configInjectionParams = @{
    VhdxPath               = $VhdxPath
    CompositeResourcePath  = $CompositeResourcePath
    NodeDefinitionFilePath = $NodeDefinitionFilePath
    TargetLcmSettings      = $targetLCMSettings
} + $directorySettings
Add-ConfigurationToVHDx @configInjectionParams
    