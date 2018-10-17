# Introduction

DscPush is a DSC Configuration management framework. It consists of a module (DscPush directory) and supporting resources (DscPushSetup directory). Copy the module directory to your PowerShell Module Path (e.g. "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"), and copy the DscPushSetup folder to your workspace.

# Requirements

* DscPush was written on WMF5.1
* Ability to establish CimSessions/PSSessions to target device.


# Concept of Operations

## Recommended Workspace Directory Structure

- C:\workspace
  - Modules (put other required modules here)
    - DSCPush
      - DscPush.psd1
      - DscPush.psm1
  - DSCPushSetup
    - DefinitionStore (put your Node Definition Files here)
      - [NodeDefinition.ps1]
    - Settings
      - NodeTemplate.ps1
      - PartialDependencies.json
  - Partials
    - [Partial Configurations here]
  - Resources
    - [Required DSC Resources here]


## Process Flow

1. Generate your Partial Configuration Catalog 
   - Run Initialize-DscPush -GeneratePartialCatalog
2. Populate Node Template File ($\DscPushSetup\Settings\NodeTemplate.ps1)
   - Edit Node and Config properties to match infrastructure
     - ConfigName
     - TargetIP
     - ContentHost
     - RoleList (List of partials that apply to the Config)
3. Generate your Node Definition File
   - Run Initialize-DscPush -GenerateNewNodeDefinitionFile -NodeDefinitionFilePath $filePath
     - Inputs
       - Partial Catalog Path (Generated in Step 1.)
       - Node Template File Path (Edited in Step 2.)
       - Node Definition File Path (Location for Generating Node Definition File. e.g. $\DscPushSetup\DefinitionStore\NodeDefinition.ps1)
     - Outputs
       - Node Definition File
4. Securely store credentials required by partials
   - Run Initialize-DscPush -GenerateSecrets
     - Inputs
       - Node Definition File Path (Generated in Step 3 and modified in Step 4)
     - Outputs
       - Securely Stored Secrets File (e.g. $\DscPushSetup\Settings\StoredSecrets.ps1)
       - Secrets Key File - 256-bit AES Key (e.g. $\DscPushSetup\Settings\SecretsKey.json)
5. Edit Node Definition File
   - Replace all instances of “ENTER_VALUE_HERE” with appropriate target config values.
6. Publish the Node Definitions (Configs with values stored in Node Definition File)
   - Run Publish-RpsConfiguration


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

[![Build Status](https://dev.azure.com/devopsjesus/DscPush/_apis/build/status/devopsjesus.dscpush)](https://dev.azure.com/devopsjesus/DscPush/_build/latest?definitionId=1)
