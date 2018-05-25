#Requires -Version 5.1 -RunAsAdministrator

param
(
    [Parameter()]
    [pscredential]
    $DeploymentCredential = (New-Object System.Management.Automation.PSCredential (“administrator”, (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force))),

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
    $TargetVMs = @(
        @{ IP="192.0.0.236"; PhysicalAddress="00-15-5d-36-F2-10" }
        @{ IP="192.0.0.237"; PhysicalAddress="00-15-5d-36-F2-11" }
    )
)

$ProgressPreference = "SilentlyContinue"

#region Modules
Get-Module DscPush | Remove-Module DscPush -ErrorAction Ignore
Import-Module -FullyQualifiedName $DSCPushModulePath
#endregion Modules

$null = New-Item -Path "$SetupFolder\DefinitionStore"-ItemType Directory -Force
$NodeDefinitionFilePath = "$WorkshopPath\DscPushSetup\DefinitionStore\workshop.ps1"

foreach ($vm in $TargetVMs.IP)
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
    PhysicalAddress = $TargetVMs[0].PhysicalAddress
    NetworkAddress  = $TargetVMs[0].IP
    SubnetBits      = '24'
    DnsAddress      = $TargetVMs[0].IP
    AddressFamily   = 'IPv4'
    Description     = ''
}
$DscPushAD.TargetAdapter = New-TargetAdapter @adNetConfigProperties

$nodeDefinition.Configs[0].Variables = @{
    DomainName = "DscPush.local"
    NetworkConfig = "[
    {
        `"SubnetBitMask`":  24,
        `"NetworkCategory`":  `"DomainAuthenticated`",
        `"MACAddress`":  `"$($TargetVMs[0].PhysicalAddress)`",
        `"IPAddress`"`:  `"$($TargetVMs[0].IP)`",
        `"DNSServer`":  `"$($TargetVMs[0].IP)`"
    }
]"
    JoinDomain = "false"
    ComputerName = "DC"
    ContentStore = "\\CH\C$\ContentStore"
}

$chNetConfigProperties = @{
    PhysicalAddress = $TargetVMs[1].PhysicalAddress
    NetworkAddress = $TargetVMs[1].IP
    SubnetBits     = '24'
    DnsAddress     = $TargetVMs[1].IP
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
        `"MACAddress`":  `"$($TargetVMs[1].PhysicalAddress)`",
        `"IPAddress`"`:  `"$($TargetVMs[1].IP)`",
        `"DNSServer`":  `"$($TargetVMs[0].IP)`"
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
    DeploymentCredential             = $DeploymentCredential
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
