param
(
    [Parameter(Mandatory)]
    [pscredential]
    $DeploymentCredential,

    [Parameter()]
    [string]
    $ContentStoreRootPath = "C:\contentstore",

    [Parameter()]
    [string]
    $ContentStoreModulePath = "$ContentStoreRootPath\Modules",

    [Parameter()]
    [string]
    $DSCPushModulePath = "$ContentStoreModulePath\DSCPush",

    [Parameter()]
    [string]
    $ContentStoreDscResourceStorePath = "$ContentStoreRootPath\DSC\Resource",

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
    $mofOutputPath = "C:\Windows\Temp",

    [Parameter()]
    $TargetLcmSettings = @{
        ConfigurationModeFrequencyMins = "15"
        RebootNodeIfNeeded             = $True
        ConfigurationMode              = "ApplyAndAutoCorrect"
        ActionAfterReboot              = "ContinueConfiguration"
        RefreshMode                    = "Push"
        AllowModuleOverwrite           = $False
        DebugMode                      = "None"
    },
    
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

Import-Module -FullyQualifiedName $DSCPushModulePath
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
    TargetIPList = $targetConfigs.Configs.TargetIP.IPAddressToString
    DeploymentCredential = $DeploymentCredential
    SanitizeModulePaths = $SanitizeModulePaths.IsPresent

}
$currentTrustedHost = Initialize-DeploymentEnvironment @initializeParams

#Deploy Configs
foreach ($config in $targetConfigs.Configs)
{

    #Try to reach the target first. might need to mature this into function as we add non-windows devices
    try
    {
        $null = Test-WSMan $config.TargetIP -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Could not reach target $($config.TargetIP). Skipping target..."
        continue
    }

    if ($config.ContentHost -and $CopyContentStore.IsPresent)
    {
        Write-Output "Copying Content Store to Target: $($config.TargetIP)"
        $copyContentStoreParams = @{
            Path=$ContentStoreRootPath
            Destination=$config.Variables.LocalSourceStore
            Target=$config.TargetIP.IPAddressToString
            Credential=$DeploymentCredential
        }
        Copy-RemoteContent @copyContentStoreParams
    }

    if ($ForceResourceCopy.IsPresent)
    {
        Write-Output "Copying required DSC Resources to Target: $($config.TargetIP)"
        $copyResourceParams = @{
            TargetConfig = $config
            ContentStoreDscResourceStorePath = $ContentStoreDscResourceStorePath
            DeploymentCredential = $DeploymentCredential
            PartialCatalog = $partialCatalog
        }
        Copy-DscResource @copyResourceParams
    }

    #Set the LCM
    Write-Output "Initializing LCM on Target: $($config.TargetIP)"
    $TargetLcmParams = @{
        TargetLcmSettings = $TargetLcmSettings
        TargetConfig = $config
        CorePartial = $corePartial
        Credential = $DeploymentCredential
        MofOutputPath = $mofOutputPath
    }
    Initialize-TargetLcm @TargetLcmParams

    #Compile and Publish the Configs
    Write-Output "Deploying Config: $($config.ConfigName) to Target: $($config.TargetIP)"
    $configParams = @{
        TargetConfig = $config
        ContentStoreRootPath = $ContentStoreRootPath
        DeploymentCredential = $DeploymentCredential
        PartialCatalog = $PartialCatalog
    }
    Send-Config @configParams
}

#Cleanup
Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $currentTrustedHost -Force
if($currentWinRMStatus.Status -eq 'Stopped')
{
    Stop-Service WinRM -Force
}

$ProgressPreference = $progressPrefSetting
