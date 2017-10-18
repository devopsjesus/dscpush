param
(
    [Parameter()]
    [switch]
    $GeneratePartialCatalog,

    [Parameter()]
    [switch]
    $GenerateSecrets,

    [Parameter()]
    [switch]
    $GenerateNewNodeDefinitionFile,

    [Parameter()]
    [switch]
    $UpdateNodeDefinitionFile,

    [Parameter()]
    [string]
    $ContentStoreRootPath = "C:\ContentStore",
    
    [Parameter()]
    [string]
    $DSCPushSetupPath = "$ContentStoreRootPath\DSCPushSetup",
    
    [Parameter()]
    [string]
    $DSCPushModulePath = "$ContentStoreRootPath\Modules\DSCPush",
    
    [Parameter()]
    [string]
    $SettingsPath = "$DSCPushSetupPath\Settings",

    [Parameter()]
    [string]
    $PartialCatalogPath = "$SettingsPath\PartialCatalog.json",
    
    [Parameter()]
    [string]
    $PartialStorePath = "$ContentStoreRootPath\DSC\PartialConfiguration",

    [Parameter()]
    [string]
    $NodeTemplatePath = "$SettingsPath\NodeTemplate.ps1",

    [Parameter()]
    [string]
    $NodeDefinitionFilePath = "$DSCPushSetupPath\DefinitionStore\NodeDefinition.ps1",

    [Parameter()]
    [string]
    $UpdateNodeDefinitionFilePath = "$ContentStoreRootPath\DSCPushSetup\DefinitionStore\newNodeDefinition.ps1"
)

#region Modules
if (Get-Module DscPush)
{
    Remove-Module DscPush
}
Import-Module -FullyQualifiedName $DSCPushModulePath
#endregion Modules

if ($GeneratePartialCatalog)
{
    Write-Output "Generating Partial Catalog"
    $NewPartialCatalogParams = @{
        PartialStorePath = $PartialStorePath
        PartialCatalogPath = $PartialCatalogPath
    }
    New-PartialCatalog @NewPartialCatalogParams
}

if ($GenerateSecrets)
{
    Write-Output "Geneterating Secrets files"
    $newSecretsFileParams = @{
        ContentStoreRootPath = $ContentStoreRootPath
        PartialCatalogPath = $PartialCatalogPath
        SettingsPath = $SettingsPath
    }
    New-SecretsFile @newSecretsFileParams
}

if ($GenerateNewNodeDefinitionFile)
{
    Write-Output "Generating New Node Definition File from template"
    $newNodeDefinitionFileParams = @{
        ContentStoreRootPath = $ContentStoreRootPath
        PartialCatalogPath = $PartialCatalogPath
        NodeTemplatePath = $NodeTemplatePath
        NodeDefinitionFilePath = $NodeDefinitionFilePath
    }
    New-NodeDefinitionFile @newNodeDefinitionFileParams
}

if ($UpdateNodeDefinitionFile)
{
    Write-Output "Updating Existing Node Definition File with Partial Catalog updates"
    $UpdateNodeDefinitionFileParams = @{
        ContentStoreRootPath = $ContentStoreRootPath
        PartialCatalogPath = $PartialCatalogPath
        NodeDefinitionFilePath = $NodeDefinitionFilePath
        UpdateNodeDefinitionFilePath = $UpdateNodeDefinitionFilePath
    }
    Update-NodeDefinitionFile @UpdateNodeDefinitionFileParams
}
