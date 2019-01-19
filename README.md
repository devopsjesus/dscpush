# Introduction

DscPush is a class-based Desired State Configuration (DSC) management framework primarily contained in a single module. It is written entirely in PowerShell, and there are no external dependencies (SQL, IIS, DLLs, etc).  

## Requirements
- DscPush was written for WMF 5.1
- Ability to establish CimSessions/PSSessions to target Node


# Features
DsCPush provides a near-complete set of features to complie and publish DSC configurations to target Nodes.  Any missing features can be requested by submitting an Issue.  Below are some of the highlighted capabilities of the module.

## Single Configuration Data File
- Configuration data for any collection of target nodes is stored in and referenced from a single custom data file
- Called a "NodeDefinition" script
- Outputs custom-typed objects when executed
- Since the data file is also a script it allows for storing PS objects in object properties (not easily done in XML or JSON data files)
- Contains all the data values to satisfy Node configuration
- Includes target Node network configuration information
  - Same network information is used to [generate and configure Hyper-V VMs](https://github.com/devopsjesus/dscpush/blob/compositeResources/deployVM-HyperV.ps1)
  - Target adapters can be identified by either MAC/Physical Address or Alias
    - If both values are specified, MAC addresses are checked first

## Secure Sensitive information
- Passwords can be stored securely using generated AES256 key
- MOF Encryption
  - Two methods
    - Share a pre-existing certificate from the authoring Node to all target Nodes
      - Requires sharing the private key to all nodes, which means if the password were compromised, all nodes would be compromised
    - Generate the certificate on the target Node
      - The public key is copied to the authoring Node, while each Node will generate and store its own private key
      - Activated with the GenerateMofEncryptionCert switch from the [deploy script](https://github.com/devopsjesus/dscpush/blob/compositeResources/deploy.ps1)
    - Activated with the EnableTargetMofEncryption switch

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

## Target Node Management
- Remote Content Copy Batches
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
- Network connectivity to target Node is tested before attempting to establish any network communications
  - If the connection test fails, the Node is skipped and the deployment continues with the next Node
  - Validates the MAC/Physical address from the NodeDefinition file matches the Adapter on the target Node
- A single set of Cim/PsSessions for each target Node is maintained across the entire deployment process
- Configures the WSMAN TrustedHosts property on the authoring Node to allow communications with target Nodes securely
  - Target IP addresses are added before deployment and removed afterwards to reduce attack vector
  - IP addresses are used primarily for deployment in greenfield scenarios
    - Removes the requirement for DNS services
- Configure LCM settings from the authoring node
  - Currently all nodes in a NodeDefinition file will receive the same LCM settings
    - **TODO**: Move the LCM settings from the deployment script to the TargetNode class
  - Able to reset the LCM to default settings using the `Reset-TargetLCM` function

## Configuration Management
- Can compile configurations separately from publishing
  - Allows for reuse of configurations for repeatable deployments
  - Can be shipped to production for immediate publishing
- Target Node Configuration is listed in the `RoleList` property of the TargetNode object
  - `RoleList` values are checked against configuration names in scripts stored in the directory specified in the `ConfigurationDirectory` Parameter of the deploy script
  - Configurations are currently a collection of Roles from the RoleDeploy module
    - Resource property values here simply reference the $Node variable key with that property name
      - E.g. `ComputerName = $Node.ComputerName`
    - Using this method, Configurations can be stored and referenced statically
      - **TODO**: Change this behavior to alternatively reference roles from the RoleDeploy module in the RoleList property and dynamically generate the Configuration
        - This would remove the requirement to store static configurations and update them when Roles are updated
        - This would force all deployment resources to be formalized in the RoleDeploy module, which I think is preferable
- Sends `Stop-DscConfiguration` and waits for target Node LCM to return Idle or Pending before deployment
  - The `-Force` is not used by any DSC CmdLet, as it tends to cause issues
- Able to inject configurations and supporting resources and files into a specified VHDx for repeateable image deployment (DSC Bootstrapping)
- Variable scope
  - Because configuration scripts are dot-sourced by the module during compilation, certain script-scoped variables are available in the configurations during runtime
    - All parameters of the `Write-CompositeConfig` function
    - $targetIP
      - Contains the IP address of the target Node
    - $configData
      - Contains all the data values stored in the Variables property of the TargetNode object
      - Sets `PSDscAllowPlainTextPassword` and `PSDscAllowDomainUser` to `$true`


# Concept of Operations
Much of the documentation for the module itself is contained in the comment-based help of each function.  The concept of operations provides guidance on how the module should be setup and executed on the authoring Node.

## Default Workspace Directory Structure
- C:\workspace
  - certificates
    - Any certificates generated or referenced by the module should be placed here
  - configs
    - Configuration files are stored in this directory
    - Partial configurations are not supported in the most recent version of the module
  - contentStore
    - Files that are to be copied to target Nodes marked as ContentHost should be placed here
  - modules
    - Place DscPush module here as well as any other required modules
    - DscPush
      - DscPush.psd1
      - DscPush.psm1
  - mofStore
    - Generated mofs and meta mofs will be placed here
  - nodeDefinitions
    - NodeDefinition files should be placed here
  - resources
    - Place RoleDeploy resource here as well as any other required resource modules
  - settings
    - Secrets related files and (deprecated) NodeTemplates are placed here
  - deploy.ps1
    - Main deployment initialization script. Run this to deploy configurations defined in the NodeDefinitions to target Nodes
  - deploy.Tests.ps1
    - Post-deployment test script that runs various checks on target Nodes to ensure published configurations have applied successfully
  - deployVM-HyperV.ps1
    - Script to generate Hyper-V VMs from NodeDefinition files  

## General Process Flow
1. 


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
