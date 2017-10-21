# Introduction

DscPush is a DSC Configuration management framework. It consists of a module (DscPush directory) and supporting resources (DscPushSetup directory). Copy the module directory to your PowerShell Module Path (e.g. "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"), and copy the DscPushSetup folder to your workspace.

# DSC Push Backlog
- [ ] Interface (Coming Soon!)
- [ ] Scheduling
- [ ] Parameter Collision Mitigation Enhancement
- [ ] Scalability (Multithreading)
- [ ] Plug-in Support


# Requirements

* DscPush was written on WMF5.1
* Ability to establish CimSessions/PSSessions to target device.


# Concept of Operations

## Workspace Directory Structure

- C:\workspace
  - DSCPush
  - DSCPushSetup
  - Partials
  - Resources


## Process Flow

1. Generate your Partial Catalog 
   - Run $\DscPushSetup\Initialize-DscPush.ps1 -GeneratePartialCatalog
2. Populate Node Template File ($\DscPushSetup\Settings\NodeTemplate.ps1)
   - Edit Node and Config properties to match infrastructure
     - ConfigName
     - TargetIP
     - ContentHost
     - RoleList (List of partials that apply to the Config)
3. Generate your Node Definition File
   - Run $\DscPushSetup\Initialize-DscPush.ps1 -GenerateNewNodeDefinitionFile -NodeDefinitionFilePath $filePath
     - Inputs
       - Partial Catalog Path (Generated in Step 1.)
       - Node Template File Path (Edited in Step 2.)
       - Node Definition File Path (Location for Generating Node Definition File. e.g. $\DscPushSetup\DefinitionStore\NodeDefinition.ps1)
     - Outputs
       - Node Definition File
4. Securely store credentials required by partials
   - Run $\DscPushSetup\Initialize-DscPush.ps1 -GenerateSecrets
     - Inputs
       - Node Definition File Path (Generated in Step 3 and modified in Step 4)
     - Outputs
       - Securely Stored Secrets File (e.g. $\DscPushSetup\Settings\StoredSecrets.ps1)
       - Secrets Key File - 256 bit AES Key (e.g. $\DscPushSetup\Settings\SecretsKey.json)
5. Edit Node Definition File
   - Replace all instances of “ENTER_VALUE_HERE” with appropriate target config values.
6. Run $\DscPushSetup\Publish-RpsConfiguration.ps1


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
