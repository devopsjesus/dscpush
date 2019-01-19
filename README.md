# Introduction

DscPush is a class-based Desired State Configuration (DSC) management framework primarily contained in a single module. It is written entirely in PowerShell, and there are no external dependencies (SQL, IIS, DLLs, etc).  

# Features
## Single Configuration Data File
- Configuration data for any collection of target nodes is stored in and referenced from a single custom data file
- Called a "NodeDefinition" script
- Outputs custom-typed objects when executed
- Contains all the data values to satisfy Node configuration
- Includes target Node network configuration information
  - Same network information is used to [generate and configure Hyper-V VMs](https://github.com/devopsjesus/dscpush/blob/compositeResources/deployVM-HyperV.ps1)

## Secure Sensitive information
- Passwords can be stored securely using generated AES256 key
- MOF Encryption
  - Built-in components generate or publish information encryption certificates to secure MOF files
    - Share a PK from the authoring Node, or generate the PK on the target Node

## Deploy "Roles" to Target Nodes
- A "Deployment Composite Resource Module" (called RoleDeploy) stores deployable "Roles" as custom composite resources
- "Roles" - just like usual composite resources - contain all the resources necessary to deploy an application or collection of settings to the target Node
- Allows for the flexibility of deploying partial configurations without their limitations
- Roles should be owned by their product teams
- Formalizes and organizes required modules and resources for all the composite resources in a single module

## Module and Resource Management
- Downloads all required modules and resource modules dynamically
- Scans the RoleDeploy module for instances of `Import-DscResource`
  - `ModuleVersion` Parameter is considered a required Parameter for all instances of the `Import-DscResource` CmdLet
  - Does not support use of importing single resources using the `Name` Parameter
  - E.g. `Import-DscResource -ModuleName RoleDeploy -ModuleVersion 1.0.0.0`
- Compares the generated list to the RequiredModules array in the RoleDeploy module manifest and reports discrepencies
- Activated by using the `SeedDscResources` switch from the [deploy script](https://github.com/devopsjesus/dscpush/blob/compositeResources/deploy.ps1)
- Can optionally scan the `PsModulePath` for any instances of required modules and removes them
  - Actived by using the `SanitizeModulePaths` switch

## Remote Content Copy
- Copies all required supporting files to the target Node
- Copies DSC Resource Modules and the contents of a "ContentStore" directory to the target Node
  - These operations can be specified separately
  - This allows for speedier development by optionally turning off the ContentStore copy, which can be time consuming with large amounts of files
- ContentStore information is stored in the NodeDefinition file
  - If a Node is marked as a ContentHost, the ContentStore directory is copied to the target
    - In this case, file paths referenced in the Variables property of the TargetNode should all be local paths
  - If a Node is not marked as a ContentHost, the ContentStore directory is not copied to the target
    - In this case, the ContentStorePath property of that TargetNode should be a UNC path to a Node that is marked as a ContentHost
    - Composite Resources published to Nodes not marked as a ContentHost will typically need to check for UNC paths passed in and copy remote files locally using the File resource
    - This method removes the burden of file copy batches to target Nodes from the authoring Node
      - Speeds up development, testing, and deployment
      - Also allows for more granular management of the resources' required files
- Attempts to enable and use SMB3 - via PSDrive on the target Node
  - Opens firewall ports automatically
  - Falls back on copying files over PsSession if PSDrive cannot be established

## But wait! There's more...
- Configure LCM settings from the authoring node


# Requirements

* DscPush was written on WMF5.1
* Ability to establish CimSessions/PSSessions to target node


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
