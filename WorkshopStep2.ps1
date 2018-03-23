#Requires -Version 5.1 -RunAsAdministrator

param
(
    [Parameter()]
    [string]
    $WorkshopPath = "C:\DscPushWorkshop",

    [Parameter()]
    [string]
    $SetupFolder = "$WorkshopPath\DscPushSetup",

    [Parameter()]
    [string]
    $SettingsPath = "$WorkshopPath\DscPushSetup\Settings",

    [Parameter()]
    [string]
    $DSCPushModulePath = "$WorkshopPath\Modules\DSCPush",

    [Parameter()]
    [array]
    $TargetIPs = @("192.0.0.245","192.0.0.246"),

    [Parameter()]
    [string]
)

$ProgressPreference = "SilentlyContinue"

#region Modules
if (Get-Module DscPush)
{
    Remove-Module DscPush
}
Import-Module -FullyQualifiedName $DSCPushModulePath
#endregion Modules

$null = New-Item -Path "$SetupFolder\DefinitionStore"-ItemType Directory -Force
$NodeDefinitionFilePath = "$WorkshopPath\DscPushSetup\DefinitionStore\workshop.ps1"

$currentDir = (Get-Item .).FullName

foreach ($vm in $TargetIps)
{
    try
    {
        $null = Test-wsman $vm -ErrorAction Stop
    }
    catch
    {
        throw "Cannot estable WinRM session to $vm."
    }
}

#Update the Node Definition File - this would typically be done by hand.
#This section can be performed manually
#default vars
$partialCatalogPath               = "$WorkshopPath\DSCPushSetup\Settings\PartialCatalog.json"
$partialStorePath                 = "$WorkshopPath\Partials"
$deploymentCredential             = (New-Object System.Management.Automation.PSCredential (“administrator”, (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force)))
$ContentStoreDestPath             = $WorkshopPath
$contentStoreModulePath           = "$WorkshopPath\Modules"
$contentStoreDscResourceStorePath = "$WorkshopPath\Resources"
$nodeDefinitionFilePath           = "$WorkshopPath\DSCPushSetup\DefinitionStore\NodeDefinition.ps1"
$partialDependenciesFilePath      = "$WorkshopPath\DSCPushSetup\Settings\PartialDependencies.json"
$partialSecretsPath               = "$WorkshopPath\DSCPushSetup\Settings\PartialSecrets.json"
$storedSecretsPath                = "$WorkshopPath\DSCPushSetup\Settings\StoredSecrets.json"
$secretsKeyPath                   = "$WorkshopPath\DSCPushSetup\Settings\SecretsKey.json"
$mofOutputPath                    = "$WorkshopPath\DSCPushSetup\Settings\mofStore"

Initialize-DscPush -GeneratePartialCatalog -PartialCatalogPath $partialCatalogPath -PartialStorePath $partialStorePath
$partialCatalog = Import-PartialCatalog "$SettingsPath\PartialCatalog.json"

Remove-Item -Path $NodeDefinitionFilePath -ErrorAction SilentlyContinue
Initialize-DscPush -GenerateNewNodeDefinitionFile -SettingsPath $SettingsPath -NodeTemplatePath "$SettingsPath\NodeTemplate.ps1" -NodeDefinitionFilePath $NodeDefinitionFilePath -GenerateSecrets -PartialCatalogPath "$SettingsPath\PartialCatalog.json" -PartialStorePath "$WorkshopPath\Partials"

#region Update Node Definition
$nodeDefinition = . $NodeDefinitionFilePath

$adNetConfigProperties = @{
    InterfaceAlias = $AdapterAlias
    NetworkAddress = $TargetIPs[0]
    SubnetBits     = '24'
    DnsAddress     = $TargetIPs[0]
    AddressFamily  = 'IPv4'
    Description    = ''
}
$DscPushAD.TargetAdapter = New-TargetAdapter @adNetConfigProperties

$nodeDefinition.Configs[0].Variables = @{
    DomainName = "DscPush.local"
    NetworkConfig = "[
    {
        `"SubnetBitMask`":  24,
        `"NetworkCategory`":  `"DomainAuthenticated`",
        `"Alias`":  `"$AdapterAlias`",
        `"IPAddress`"`:  `"$($TargetIPs[0])`",
        `"DNSServer`":  `"$($TargetIPs[0])`"
    }
]"
    JoinDomain = "false"
    ComputerName = "DC"
    ContentStore = "\\CH\C$\ContentStore"
}

$chNetConfigProperties = @{
    InterfaceAlias = $AdapterAlias
    NetworkAddress = $TargetIPs[1]
    SubnetBits     = '24'
    DnsAddress     = $TargetIPs[0]
    AddressFamily  = 'IPv4'
    Description    = ''
}
$DscPushCH.TargetAdapter = New-TargetAdapter @chNetConfigProperties
$nodeDefinition.Configs[1].Variables = @{
    DomainName = "DscPush.local"
    NetworkConfig = "[
    {
        `"SubnetBitMask`":  24,
        `"NetworkCategory`":  `"DomainAuthenticated`",
        `"Alias`":  `"$AdapterAlias`",
        `"IPAddress`"`:  `"$($TargetIPs[1])`",
        `"DNSServer`":  `"$($TargetIPs[0])`"
    }
]"
    JoinDomain = "true"
    ComputerName = "CH"
    ContentStore = "C:\ContentStore"
}

$UpdateNodeDefinitionFileParams = @{
        PartialCatalog = $partialCatalog
        NodeDefinition = $nodeDefinition
        UpdateNodeDefinitionFilePath = "$WorkshopPath\DscPushSetup\DefinitionStore\NodeDefinition.ps1"
    }
Export-NodeDefinitionFile @UpdateNodeDefinitionFileParams
#endregion

$publishTargetSettings = @{
    CompilePartials                  = $true
    SanitizeModulePaths              = $true
    CopyContentStore                 = $true
    ForceResourceCopy                = $true
    DeploymentCredential             = $deploymentCredential
    ContentStoreRootPath             = $WorkshopPath
    ContentStoreDestPath             = $ContentStoreDestPath
    ContentStoreModulePath           = $contentStoreModulePath
    ContentStoreDscResourceStorePath = $contentStoreDscResourceStorePath
    NodeDefinitionFilePath           = $nodeDefinitionFilePath
    PartialCatalogPath               = $partialCatalogPath
    PartialDependenciesFilePath      = $partialDependenciesFilePath
    PartialSecretsPath               = $partialSecretsPath
    StoredSecretsPath                = $storedSecretsPath
    SecretsKeyPath                   = $secretsKeyPath
    mofOutputPath                    = $mofOutputPath
    TargetLcmSettings                = @{
        ConfigurationModeFrequencyMins   = 15
        RebootNodeIfNeeded               = $True
        ConfigurationMode                = "ApplyAndAutoCorrect"
        ActionAfterReboot                = "ContinueConfiguration"
        RefreshMode                      = "Push"
        AllowModuleOverwrite             = $true
        DebugMode                        = "None"
    }
}
Publish-TargetConfig @publishTargetSettings
