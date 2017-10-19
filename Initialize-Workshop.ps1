$WorkshopPath = "C:\workshop"

$SetupFolder = "$WorkshopPath\DscPushSetup"

$SettingsPath = "$WorkshopPath\DscPushSetup\Settings"

$DSCPushModulePath = "$WorkshopPath\Modules\DSCPush"

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
cd $SetupFolder

$partialCatalogPath = .\Initialize-DscPush.ps1 -GeneratePartialCatalog
$partialCatalog = Import-PartialCatalog $partialCatalogPath[1]

Remove-Item -Path $NodeDefinitionFilePath -ErrorAction SilentlyContinue
.\Initialize-DscPush.ps1 -GenerateNewNodeDefinitionFile -NodeTemplatePath "$SettingsPath\NodeTemplate.ps1" -NodeDefinitionFilePath $NodeDefinitionFilePath

.\Initialize-DscPush.ps1 -GenerateSecrets


#update the Node Definition file with automation
#This section can be performed manually
#region Update Node Definition
$nodeDefinition = . $NodeDefinitionFilePath

$nodeDefinition.Configs[0].TargetIP = "192.0.0.253"
$nodeDefinition.Configs[0].Variables = @{
    DomainName = "DscPush.local"
    NetworkConfig = '[
    {
        "SubnetBitMask":  16,
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

$nodeDefinition.Configs[1].TargetIP = "192.0.0.251"
$nodeDefinition.Configs[1].Variables = @{
    DomainName = "DscPush.local"
    NetworkConfig = '[
    {
        "SubnetBitMask":  16,
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
        ContentStoreRootPath = $ContentStoreRootPath
        PartialCatalogPath = $PartialCatalogPath
        NodeDefinition = $nodeDefinition
        UpdateNodeDefinitionFilePath = $UpdateNodeDefinitionFilePath
    }
DSCPush\Export-NodeDefinitionFile -NodeDefinition $nodeDefinition -UpdateNodeDefinitionFilePath "$WorkshopPath\DscPushSetup\DefinitionStore\NodeDefinition.ps1" -PartialCatalog $partialCatalog
#endregion

.\Publish-TargetConfig.ps1 -ForceResourceCopy -SanitizeModulePaths

cd $currentDir