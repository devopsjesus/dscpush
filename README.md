# Introduction

DscPush is a DSC Configuration publishing framework. It consists of a module (DscPush directory) and supporting resources (DscPushSetup directory). Copy the module directory to your PowerShell Module Path (e.g. "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"), and copy the DscPushSetup folder to your workspace.


# Requirements

* DscPush was written on WMF5.1
* Ability to establish CimSessions to target device.


# Concept of Operations

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


# Lexicon

| **Term** | **Definition** |
| --- | --- |
| **Config** | Definition of a target device, including property values (e.g. Config Name, Target IP, Param values) required to publish the config. |
| **Target** | Endpoint (e.g. Windows Server) targeted by a Config. |
| **Node** | Logical collection of Configs. |
| **Node Definition** | Collection of Nodes, Configs, and required data. |
| **Role List** | List of Partial Configurations that make up the Target &quot;Role.&quot; |
| **Partial** | DSC Partial Configurations |
| **Resource** | DSC Resources used to build Partials |
| **Dependency** | Partial Dependencies (LCM Property) |
| **Secret** | Any protected property of a Config (e.g. Credential, Cert Password) |
| **Content Store** | The publishing directory that supports the Configs being published. |


# Architecture

![DscPush Architecture](https://github.com/devopsjesus/dscpush/blob/master/architecture.png)
