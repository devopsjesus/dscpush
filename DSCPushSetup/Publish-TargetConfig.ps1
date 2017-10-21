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

Import-Module -FullyQualifiedName $DSCPushModulePath -ErrorAction Stop

Import-Module PoshRSJob #Multithreading
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
    #Multithreading using RunspacePools (PoshRSJob Module)
    Start-RSJob -Name {$config.ConfigName} -ScriptBlock {

        $config = $using:config

        #Try to reach the target first (might need to mature this into function as we add non-windows devices)
        try
        {
            $null = Test-WSMan $config.TargetIP -ErrorAction Stop
        }
        catch
        {
            Write-Warning "Could not reach target $($config.TargetIP). Skipping target..."
            continue
        }

        if ($config.ContentHost -and $using:CopyContentStore)
        {
            Write-Output "Copying Content Store to Target: $($config.TargetIP)"
            $copyContentStoreParams = @{
                Path=$using:ContentStoreRootPath
                Destination=$config.Variables.ContentStore
                Target=$config.TargetIP.IPAddressToString
                Credential=$using:DeploymentCredential
            }
            Copy-RemoteContent @copyContentStoreParams
        }

        if ($ForceResourceCopy.IsPresent)
        {
            Write-Output "Copying required DSC Resources to Target: $($config.TargetIP)"
            $copyResourceParams = @{
                TargetConfig = $config
                ContentStoreDscResourceStorePath = $using:ContentStoreDscResourceStorePath
                DeploymentCredential = $using:DeploymentCredential
                PartialCatalog = $using:partialCatalog
            }
            Copy-DscResource @copyResourceParams
        }

        #Compile and Publish the Configs
        Write-Output "Deploying Config: $($config.ConfigName) to Target: $($config.TargetIP)"
        $configParams = @{
            TargetConfig = $config
            ContentStoreRootPath = $using:ContentStoreRootPath
            DeploymentCredential = $using:DeploymentCredential
            PartialCatalog = $using:PartialCatalog
        }
        Send-Config @configParams -WarningAction SilentlyContinue

        #Set the LCM
        Write-Output "Initializing LCM on Target: $($config.TargetIP)"
        $TargetLcmParams = @{
            TargetLcmSettings = $using:TargetLcmSettings
            TargetConfig = $using:config
            CorePartial = $using:corePartial
            Credential = $using:DeploymentCredential
            MofOutputPath = $using:mofOutputPath
        }
        Initialize-TargetLcm @TargetLcmParams -WarningAction SilentlyContinue

        $null = Start-DscConfiguration -ComputerName $config.TargetIP.IPAddressToString -Credential $using:DeploymentCredential -UseExisting -ErrorAction Stop

    } -ModulesToImport $DSCPushModulePath
}

#region RsJobs
$rsJobs = Get-RSjob
$rsJobs | Receive-RSJob
$rsJobs | Wait-RSJob -Timeout 600
$rsJobs | Receive-RSJob
$rsJobs | Remove-RSJob
#endregion

#Cleanup
Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $currentTrustedHost -Force
if($currentWinRMStatus.Status -eq 'Stopped')
{
    Stop-Service WinRM -Force
}

$ProgressPreference = $progressPrefSetting
