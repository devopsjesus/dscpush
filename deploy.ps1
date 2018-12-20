<#
    .SYNOPSIS
        Use this script to deploy DSC configurations using the DscPush module.

    .DESCRIPTION
        This script initiates the active components required to publish DSC configurations to target nodes. It's intended
        to be used as a wrapper script for the DscPush module, which uses a Composite Resource Module to store "role" resources - 
        simply composite resources that contain the necessary resources for the role that is being deployed. This script allows
        for the publication of configurations to live hosts. There are other wrapper scripts for injecting configurations,
        directly into VHDs and also deploying infrastructure to Hyper-V using the same Node Definition file.

    .PARAMETER WorkspacePath
        Path to the root directory that will contain all the necessary components required to compile and publish a configuration.

    .PARAMETER CompositeResourcePath
        Path to the PowerShell DSC Composite Resource module that contains the composite resources that define the roles to be deployed.

    .PARAMETER DeploymentCredential
        Credential to connect to target node.

    .PARAMETER NodeDefinitionFilePath
        Path to the Node Definition File used by DscPush module that contains the required data to deploy the configuration.

    .EXAMPLE
        $params = @{
            WorkspacePath          = "C:\Library\Deploy"
            CompositeResourcePath  = "C:\Library\Deploy\resources\RoleDeploy"
            NodeDefinitionFilePath = "C:\Library\Deploy\nodeDefinitions\Windows2016BaselineMS.ps1"
            DeploymentCredential   = (New-Object System.Management.Automation.PSCredential ("administrator", (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force)))
            EnableTargetMofEncryption = $true
            GenerateMofEncryptionCert = $true
        }
        .\deploy.ps1 @params
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
    [ValidateScript({Test-Path $_})]
    [string]
    $NodeDefinitionFilePath,

    [parameter(mandatory)]
    [pscredential]
    $DeploymentCredential,

    [parameter()]
    [switch]
    $EnableTargetMofEncryption,

    [parameter()]
    [switch]
    $GenerateMofEncryptionCert
)

# The publishSettings hashtable contains the desired actions to take when publishing the configurations.  
# SeedDscResources key denotes whether the DscResources required by each module should be saved to the appropriate folder from 
#   the PSGallery.  This is useful when initially setting up the deployment environment.
# SanitizeModulePaths key will analyze the Modules and Resources directories and remove any of those modules from the PSModulePath.
# CopyContentStore key denotes whether the ContentStore will be copied to each ContentStoreHost (this property is defined in the
#   Node Definition file).
# CopyDscResources key denotes whether the DscResources should be copied to the target node(s)
# CompileConfig key denotes whether the configurations should be compiled, or if the stored configurations will be used.
# PublishConfig key denotes whether to send the configurations to the target node(s).
$publishSettings = @{
    SeedDscResources    = $false
    SanitizeModulePaths = $false
    CopyContentStore    = $true
    CopyDscResources    = $true
    CompileConfig       = $true
    PublishConfig       = $true
}

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

# The mofEncryptionSettings hashtable contains the desired settings if mof encryption is enabled.  This method uses a single
# certificate that is copied with the configuration to the target node. Note, the PK password is using the
# DeploymentCredential variable's password.
$mofEncryptionSettings = @{
    EnableTargetMofEncryption   = $EnableTargetMofEncryption
    GenerateMofEncryptionCert   = $GenerateMofEncryptionCert
    #TargetCertDirName           = "Certificates"
    #MofEncryptionCertThumbprint = "C3CD32F10653BB2C9F736520583A9A1EF0C7D7DC"
    MofEncryptionCertDirectory  = "$WorkspacePath\certificates"
    #MofEncryptionCertPath       = "$WorkspacePath\Certificates\DscEncryption.cer"
    #MofEncryptionPKPath         = "$WorkspacePath\Certificates\DscEncryption.pfx"
    #MofEncryptionPKPassword     = $DeploymentCredential.Password
}

# The directorySettings hashtable contains the default directory paths for each different component required to compile and
# deploy configurations.  Note, the ContentStoreDestinationPath is the desired path on the target nodes to copy the content store.
# Note, the StoredSecretsPath and SecretsKeyPath are where the secrets that contain all passwords and other required encrypted content.
# The SecretsKey should be treated with the same consideration as the MofEncryptionPKPassword.
$directorySettings = @{
    ModuleDirectory             = "$WorkspacePath\Modules"
    DscPushModulePath           = "$WorkspacePath\Modules\DSCPush"
    ConfigurationDirectory      = "$WorkspacePath\configs"
    ContentStoreDirectory       = "$WorkspacePath\ContentStore"
    DscResourcesDirectory       = "$WorkspacePath\resources"
    StoredSecretsPath           = "$WorkspacePath\Settings\StoredSecrets.json"
    SecretsKeyPath              = "$WorkspacePath\Settings\SecretsKey.json"
    MofStorePath                = "$WorkspacePath\mofStore"
}

#Remove and reimport module to allow for changes made during development
Get-Module DscPush -ErrorAction SilentlyContinue | Remove-Module
Import-Module -FullyQualifiedName $directorySettings.DSCPushModulePath -ErrorAction Stop
$directorySettings.Remove("DscPushModulePath")

# Add all the hashtables up and splat to the Publish cmdlet
$params = @{
    DeploymentCredential       = $DeploymentCredential
    CompositeResourcePath      = $CompositeResourcePath
    NodeDefinitionFilePath     = $NodeDefinitionFilePath
    TargetLCMSettings          = $targetLCMSettings
} + $publishSettings + $mofEncryptionSettings + $directorySettings
Publish-CompositeTargetConfig @params
