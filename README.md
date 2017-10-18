# dscpush

DscPush is a DSC Configuration publishing framework. It consists of a module (DscPush directory) and a folder (DscPushSetup) with supporting scripts and resources. Copy the module directory to your PowerShell Module Path (e.g. "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"), and copy the Setup folder to your workspace.

1. Run $\DscPushSetup\Initialize-DscPush.ps1 -GeneratePartialCatalog
2. Populate Node Template File ($\DscPushSetup\Settings\NodeTemplate.ps1)
   - Edit Node and Config properties to match infrastructure
     - ConfigName
     - TargetIP
     - ContentHost
     - RoleList (List of partials that apply to the Config)
3. Run $\DscPushSetup\Initialize-DscPush.ps1 -GenerateNewNodeDefinitionFile -NodeDefinitionFilePath $filePath
   - Inputs
     - Partial Catalog Path
     - ii. Node Template File Path
     - Node Definition File Path
   - Outputs
     - Node Definition File
4. Edit Node Definition File
   - Replace all instances of “ENTER_VALUE_HERE” with appropriate target config values.
5. Run $\DscPushSetup\Publish-RpsConfiguration.ps1


## Requirements

* DscPush was written on WMF5.1
* Ability to establish CimSessions to target device.

