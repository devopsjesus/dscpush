param
(
    [Parameter(Mandatory)]
    [pscredential]
    $DeploymentCredential,

    [Parameter()]
    [string]
    $ContentStoreRootPath = "C:\DscPushWorkshop",

    [Parameter()]
    [string]
    $ContentStoreModulePath = "$ContentStoreRootPath\Modules",

    [Parameter()]
    [string]
    $DSCPushModulePath = "$ContentStoreModulePath\DSCPush",

    [Parameter()]
    [string]
    $ContentStoreDscResourceStorePath = "$ContentStoreRootPath\Resources",

    [Parameter()]
    [string]
    $NodeDefinitionFilePath = "$ContentStoreRootPath\DSCPushSetup\DefinitionStore\NodeDefinition.ps1",

    [Parameter()]
    [string]
    $PartialCatalogPath = "$ContentStoreRootPath\DSCPushSetup\Settings\PartialCatalog.json",

    [Parameter()]
    [string]
    $PartialDependenciesFilePath = "$ContentStoreRootPath\DSCPushSetup\Settings\PartialDependencies.json",

    [Parameter()]
    [string]
    $PartialSecretsPath = "$ContentStoreRootPath\DSCPushSetup\Settings\PartialSecrets.json",

    [Parameter()]
    [string]
    $StoredSecretsPath = "$ContentStoreRootPath\DSCPushSetup\Settings\StoredSecrets.json",

    [Parameter()]
    [string]
    $SecretsKeyPath = "$ContentStoreRootPath\DSCPushSetup\Settings\SecretsKey.json",

    [Parameter()]
    [string]
    $mofOutputPath = "$ContentStoreRootPath\DSCPushSetup\Settings\mofStore",

    [Parameter()]
    $TargetLcmSettings = @{
        ConfigurationModeFrequencyMins = 15
        RebootNodeIfNeeded             = $True
        ConfigurationMode              = "ApplyAndAutoCorrect"
        ActionAfterReboot              = "ContinueConfiguration"
        RefreshMode                    = "Push"
        AllowModuleOverwrite           = $true
        DebugMode                      = "None"
    },

    [Parameter(ParameterSetName = 'LcmEncryption')]
    [string]
    $TargetCertDirName,

    [Parameter(ParameterSetName = 'LcmEncryption')]
    [ValidatePattern("[a-f0-9]{40}")]
    [string]
    $LcmEncryptionCertThumbprint,

    [Parameter(ParameterSetName = 'LcmEncryption')]
    [string]
    $LcmEncryptionCertPath,

    [Parameter(ParameterSetName = 'LcmEncryption')]
    [string]
    $LcmEncryptionPKPath,

    [Parameter(ParameterSetName = 'LcmEncryption')]
    [securestring]
    $LcmEncryptionPKPassword,

    [Parameter(ParameterSetName = 'LcmEncryption')]
    [switch]
    $EnableTargetLcmEncryption,

    [Parameter()]
    [switch]
    $CompilePartials,
    
    [Parameter()]
    [switch]
    $SanitizeModulePaths,

    [Parameter()]
    [switch]
    $CopyContentStore,

    [Parameter()]
    [switch]
    $ForceResourceCopy
)
#Hide Progress Bars
$progressPrefSetting = $ProgressPreference
$ProgressPreference = "SilentlyContinue"

#region Modules
if (Get-Module DscPush) #if statement is dev necessity that can be removed for production code
{
    Remove-Module DscPush
}

Import-Module -FullyQualifiedName $DSCPushModulePath -ErrorAction Stop
#endregion Modules

#Import the partial catalog
$partialCatalog = Import-PartialCatalog -PartialCatalogPath $PartialCatalogPath -ErrorAction Stop

#Import the Node Definition file
$targetConfigs = . $NodeDefinitionFilePath

#Add dependencies and secrets to the Configs
$partialProperties = @{
    PartialDependenciesFilePath = $PartialDependenciesFilePath
    PartialSecretsPath = $PartialSecretsPath
    StoredSecretsPath = $StoredSecretsPath
    SecretsKeyPath = $SecretsKeyPath
    TargetConfigs = ([ref]$targetConfigs)
}
$corePartial = Add-PartialProperties @partialProperties

#Setup Deployment Environment
$initializeParams = @{
    ContentStoreRootPath = $ContentStoreRootPath
    ContentStoreModulePath = $ContentStoreModulePath
    ContentStoreDscResourceStorePath = $ContentStoreDscResourceStorePath
    TargetIPList = $targetConfigs.Configs.TargetAdapter.NetworkAddress.IPAddressToString
    DeploymentCredential = $DeploymentCredential
    SanitizeModulePaths = $SanitizeModulePaths.IsPresent
}
$currentTrustedHost = Initialize-DeploymentEnvironment @initializeParams

#Deploy Configs
foreach ($config in $targetConfigs.Configs)
{
    Write-Output "Preparing Config: $($config.ConfigName)"

    Write-Verbose "  Testing Connection to Target Adapter (Target IP: $($config.TargetAdapter.NetworkAddress))"
    $targetIp = $config.TargetAdapter.NetworkAddress.IpAddressToString
    $sessions = Connect-TargetAdapter -TargetIpAddress $targetIp -TargetAdapter $config.TargetAdapter -Credential $DeploymentCredential
    if ($sessions -eq $false)
    {
        continue #skip the rest of the config if we can't connect
    }

    if ($CompilePartials.IsPresent)
    {
        Write-Output "  Compiling and writing Config to directory: $mofOutputPath"
        $configParams = @{
            TargetConfig = $config
            ContentStoreRootPath = $ContentStoreRootPath
            DeploymentCredential = $DeploymentCredential
            PartialCatalog = $PartialCatalog
            MofOutputPath = $mofOutputPath
        }
        Write-Config @configParams
    }

    $fileCopyList = @()
    if ($config.ContentHost -and $CopyContentStore.IsPresent)
    {
        Write-Output "  Preparing Content Store for remote copy"
        $fileCopyList += @{
            Path=$ContentStoreRootPath
            Destination=$config.Variables.LocalSourceStore
        }
    }

    if ($ForceResourceCopy.IsPresent)
    {
        Write-Output "  Preparing required DSC Resources for remote copy"
        $copyResourceParams = @{
            TargetConfig = $config
            ContentStoreDscResourceStorePath = $ContentStoreDscResourceStorePath
            DeploymentCredential = $DeploymentCredential
            PartialCatalog = $partialCatalog
        }
        $fileCopyList += Select-DscResource @copyResourceParams
    }

    if ($fileCopyList)
    {
        Write-Output "  Commencing remote copy of required file resources."
        $contentCopyParams = @{
            CopyList = $fileCopyList
            TargetCimSession = $sessions.TargetCimSession
            TargetPsSession = $sessions.TargetPsSession
            Credential = $DeploymentCredential
        }
        Copy-RemoteContent @contentCopyParams
    }

    if ($EnableTargetLcmEncryption)
    {
        Write-Output "  Enabling LCM Encryption"
        $targetLcmEncryptionParams = @{
            LcmEncryptionCertThumbprint = $LcmEncryptionCertThumbprint
            CertPassword = $LcmEncryptionPKPassword
            TargetCertPath = "$($config.Variables.LocalSourceStore)\$TargetCertDirName"
            LcmEncryptionPKPath = $LcmEncryptionPKPath
            TargetPSSession = $sessions.TargetPSSession
        }
        Enable-TargetLcmEncryption @targetLcmEncryptionParams

        $TargetLcmParams = @{ LcmEncryptionCertThumbprint = $LcmEncryptionCertThumbprint }
    }

    #Set the LCM
    Write-Output "Initializing LCM Settings"
    $TargetLcmParams += @{
        TargetLcmSettings = $TargetLcmSettings
        TargetConfig = $config
        TargetCimSession = $sessions.targetCimSession
        CorePartial = $corePartial
        Credential = $DeploymentCredential
        MofOutputPath = $mofOutputPath
    }
    Initialize-TargetLcm @TargetLcmParams

    #Compile and Publish the Configs
    Write-Output "Deploying Config: $($config.ConfigName) to Target: $targetIp"
    $configParams = @{
        TargetConfig = $config
        TargetCimSession = $sessions.targetCimSession
        ContentStoreRootPath = $ContentStoreRootPath
        DeploymentCredential = $DeploymentCredential
        PartialCatalog = $PartialCatalog
        MofOutputPath = $mofOutputPath
    }
    Send-Config @configParams

    #This cmdlet now breaks baremetal deployment
    #Start-DscConfiguration -ComputerName $targetIp -Credential $DeploymentCredential -UseExisting
}

#Cleanup
Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $currentTrustedHost -Force
if($currentWinRMStatus.Status -eq 'Stopped')
{
    Stop-Service WinRM -Force
}

$ProgressPreference = $progressPrefSetting
