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
    $DSCPushModulePath = "$WorkshopPath\Modules\DSCPush"
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

foreach ($vm in "192.0.0.253","192.0.0.251")
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

$partialCatalogPath = . "$SetupFolder\Initialize-DscPush.ps1" -GeneratePartialCatalog
$partialCatalog = Import-PartialCatalog $partialCatalogPath

Remove-Item -Path $NodeDefinitionFilePath -ErrorAction SilentlyContinue
. "$SetupFolder\Initialize-DscPush.ps1" -GenerateNewNodeDefinitionFile -NodeTemplatePath "$SettingsPath\NodeTemplate.ps1" -NodeDefinitionFilePath $NodeDefinitionFilePath

. "$SetupFolder\Initialize-DscPush.ps1" -GenerateSecrets

#Update the Node Definition File - this would typically be done by hand.
#This section can be performed manually
#region Update Node Definition
$nodeDefinition = . $NodeDefinitionFilePath

$adNetConfigProperties = @{
    InterfaceAlias = 'Ethernet'
    NetworkAddress = '192.0.0.253'
    SubnetBits     = '24'
    DnsAddress     = '192.0.0.253'
    AddressFamily  = 'IPv4'
    Description    = ''
}
$DscPushAD.TargetAdapter = New-TargetAdapter @adNetConfigProperties

$nodeDefinition.Configs[0].Variables = @{
    DomainName = "DscPush.local"
    NetworkConfig = '[
    {
        "SubnetBitMask":  24,
        "DefaultGateway":  "",
        "NetworkCategory":  "DomainAuthenticated",
        "Alias":  "Ethernet",
        "IPAddress":  "192.0.0.253",
        "DNSServer":  "192.0.0.253"
    }
]'
    JoinDomain = "false"
    ComputerName = "DC"
    ContentStore = "\\CH\C$\ContentStore"
}


$chNetConfigProperties = @{
    InterfaceAlias = 'Ethernet'
    NetworkAddress = '192.0.0.251'
    SubnetBits     = '24'
    DnsAddress     = '192.0.0.253'
    AddressFamily  = 'IPv4'
    Description    = ''
}
$DscPushCH.TargetAdapter = New-TargetAdapter @chNetConfigProperties
$nodeDefinition.Configs[1].Variables = @{
    DomainName = "DscPush.local"
    NetworkConfig = '[
    {
        "SubnetBitMask":  24,
        "DefaultGateway":  "",
        "NetworkCategory":  "DomainAuthenticated",
        "Alias":  "Ethernet",
        "IPAddress":  "192.0.0.251",
        "DNSServer":  "192.0.0.253"
    }
]'
    JoinDomain = "true"
    ComputerName = "CH"
    ContentStore = "C:\ContentStore"
}

$UpdateNodeDefinitionFileParams = @{
        PartialCatalog = $partialCatalog
        NodeDefinition = $nodeDefinition
        UpdateNodeDefinitionFilePath = "$WorkshopPath\DscPushSetup\DefinitionStore\NodeDefinition.ps1"
    }
DSCPush\Export-NodeDefinitionFile @UpdateNodeDefinitionFileParams
#endregion

. "$SetupFolder\Publish-TargetConfig.ps1" -CompilePartials -ForceResourceCopy -SanitizeModulePaths
