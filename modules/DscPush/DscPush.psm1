#region tests completed
<#
    .SYNOPSIS
        Attempts to get module information from the passed in path.

    .DESCRIPTION
        This function will attempt to get the specified path's module information. If a module object cannot be returned,
        the function will throw, otherwise, it returns the module object.

    .PARAMETER Path
        Path to PowerShell Composite Resource module.

    .EXAMPLE
        Get-PSScriptPatameterMetadata -Path $Path
#>
function Assert-CompositeModule
{
    Param
    (
        [Parameter(mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]
        $Path
    )

    try
    {
        return Get-Module -FullyQualifiedName $Path -ListAvailable -ErrorAction Stop
    }
    catch
    {
        throw "Could not find the module using path: $Path"
    }
}

<#
    .SYNOPSIS
        Retrieves the AST of a DSC script and returns pertinent parameter metadata.

    .DESCRIPTION
        This function will parse a PS script's parameter block into AST and return all metadata.
        Includes mandatory flags, other validations, and the parameter type.

    .PARAMETER Path
        Path to PowerShell script.

    .EXAMPLE
        Get-PSScriptPatameterMetadata -Path $Path
#>
function Get-PSScriptParameterMetadata
{
    Param
    (
        [Parameter(mandatory)]
        [ValidatePattern(".*.ps1$|.*.psm1$")]
        [ValidateScript({Test-Path $_})]
        [string]
        $Path
    )

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)

    $parameterASTs = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.ParameterAst]}, $true)
    
    $returnObjs = $parameterASTs | Select-Object Attributes, Name, StaticType

    $paramCollection = @()

    foreach ($object in $returnObjs)
    {
        $paramObj = @{
            Name = ($object.Name.ToString()).TrimStart("$")
            StaticType = $object.StaticType.ToString()
            Attributes = @()
        }

        foreach ($attribute in $object.Attributes)
        {
            $namedArguments = $attribute.NamedArguments
            $namedArgumentList = @()
            foreach ($namedArgument in $namedArguments)
            {
                $namedArgumentList += $namedArgument.ArgumentName.ToString()
            }

            $positionalArguments = $attribute.positionalArguments
            $positionalArgumentList = @()
            foreach ($positionalArgument in $positionalArguments)
            {
                $positionalArgumentList += $positionalArgument.Extent.ToString()
            }
            
            $paramAttributes = New-Object -TypeName psobject -Property @{
                Name = $attribute.TypeName.ToString()
                NamedArguments = $namedArgumentList
                PositionalArguments = $positionalArgumentList
            }
            
            $paramObj.Attributes += $paramAttributes
        }

        $paramCollection += $paramObj
    }

    return $paramCollection
}

<#
    .SYNOPSIS
        Analyze PowerShell script for any imported DSC resources (i.e. Import-DscResource cmdlet invoked).

    .DESCRIPTION
        This function will parse a PS script AST and return all resource names and versions of imported dsc resources.

    .PARAMETER Path
        Path to PowerShell script.

    .EXAMPLE
        Get-RequiredDscResourcesList -Path $Path
#>
function Get-RequiredDscResourceList
{
    Param
    (
        [Parameter(mandatory)]
        [ValidatePattern(".*.ps1$|.*.psm1$")]
        [ValidateScript({Test-Path $_})]
        [string]
        $Path
    )
    
    #Parse powershell script to AST
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)

    #Find every Import-DscResource cmdlet
    [array]$resourceStatements = $ast.FindAll({($args[0] -is [System.Management.Automation.Language.DynamicKeywordStatementAst]) -and ($args[0].CommandElements.Value -contains 'Import-DscResource')}, $true) 
    
    #Because the syntax and use of the Import-DscResource is highly regulated, we can make some assumptions here:
    #ModuleName must be the first parameter specified, so it's value is stored in the third index of the CommandElements array
    #ModuleVersion would always be specified after the ModuleName parameter, so it would be in the fifth index of the array
    #We disallow use of the Name parameter here, because it's not supported or suggested
    if ("Name" -in $resourceStatements.CommandElements.ParameterName)
    {
        throw "$Path - Use of the 'Name' parameter when calling Import-DscResource is not supported."
    }

    $resourceList = @()

    foreach ($resource in $resourceStatements)
    { 
        if ($resource.CommandElements.Count -lt 5)
        {
            throw "$Path - Missing ModuleVersion parameter in config."
        }
        $resourceList += @{
            ModuleName = $resource.CommandElements[2].Value
            ModuleVersion = $resource.CommandElements[4].Value
        }
    }

    return $resourceList.Where({$_.ModuleName -ne "PSDesiredStateConfiguration"})
}

<#
    .SYNOPSIS
        Analyze PowerShell script for any configuration statements.
    
    .DESCRIPTION
        This function will parse a PS script AST and return all configuration statement names.

    .PARAMETER Path
        Path to Powershell script.

    .EXAMPLE
        Get-DscConfigurationName -Path $Path
#>
function Get-DscConfigurationName
{
    Param
    (
        [Parameter(mandatory)]
        [ValidatePattern(".*.ps1$")]
        [ValidateScript({Test-Path $_})]
        [string]
        $Path
    )

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$Null)

    #Find all AST of type ConfigurationDefinitionAST, this will allow us to find the name of each config
    $configurationAst = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.ConfigurationDefinitionAst]}, $true)

    #If we find more than one configuration statement, throw, because that is not supported
    if ($configurationAst.count -ne 1)
    {
        throw "$Path - Only one configuration statements is supported in each script"
    }

    return $configurationAst.InstanceName.Value
}

<#
    .SYNOPSIS
        Analyze PowerShell DSC Composite Resource file.
    
    .DESCRIPTION
        This function will parse a PS script AST and return all configuration statement names.

    .PARAMETER Path
        Path to Powershell script.

    .EXAMPLE
        Get-DscConfigurationName -Path $Path
#>
function Get-DscCompositeMetaData
{
    Param
    (
        [Parameter(mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]
        $Path
    )

    $moduleInfo = Assert-CompositeModule -Path $Path
    
    $resources = $moduleInfo.ExportedDscResources

    $compositeResources = @()
    foreach ($resource in $resources)
    {
        $resourcePath = Join-Path -Path $Path -ChildPath "DSCResources\$resource\$resource.schema.psm1"

        Write-Verbose "Parsing $resourcePath"
        $parameters = @(Get-PSScriptParameterMetadata -Path $resourcePath)
        $requiredResourceList = @(Get-RequiredDscResourceList -Path $resourcePath)
        
        $compositeValues = @{
            Resource = $resource
            Resources = $requiredResourceList
            Parameters = $parameters
        }
        $compositeResources += New-DscCompositeResource @compositeValues
    }

    return $compositeResources
}

<#
    .SYNOPSIS
        Converts PS hashtable objects (hashtable arrays included) to text output for later ingestion.

    .DESCRIPTION
        This function will recursively produces a string output of hashtable contents.
        Must start with a hashtable or hashtable array - TODO: add similar function for psobjects

    .PARAMETER InputObject

    .EXAMPLE
        ConvertFrom-Hashtable -InputObject @{key="value"}
#>
Function ConvertFrom-Hashtable
{
    param
    (
        [parameter(Mandatory)]
        $InputObject
    )
    $hashstr = ""

    if ($InputObject -is [array])
    {
        $hashstr = "@("
    }
    elseif ($InputObject -isnot [hashtable])
    {
        throw "Only hashtables and array objects are supported."
    }

    foreach ($object in $InputObject)
    { 
        $keys = $object.keys

        $hashstr += "@{"

        foreach ($key in $keys)
        {
            $value = $object[$key]
            
            if ($value -is [hashtable])
            {
                $hashstr = $hashstr + $key + "=" + $(ConvertFrom-Hashtable $value) + ";"
            }
            elseif ($value -is [array])
            {
                $arrayString = "@("

                foreach ($arrayValue in $value)
                {
                    if ($arrayValue -is [array])
                    {
                        $parsedValue = ConvertFrom-Hashtable $arrayValue
                    }
                    else
                    {
                        $parsedValue = "`"$arrayValue`","
                    }
                    $arrayString += $parsedValue
                }

                $arrayString = $arrayString.Trim(",")
                $arrayString += ")"

                $hashstr += $key + "=" + $arrayString + ";" 
            } #TODO: add support for psobject
            elseif ($key -match "\s") 
            {
                $hashstr += "`"$key`"" + "=" + "`"$value`"" + ";"
            }
            else {
                $hashstr += $key + "=" + "`"$value`"" + ";" 
            }
        }

        $hashstr = $hashstr.Trim(";")
        $hashstr += "};"
    }

    $hashstr = $hashstr.Trim(";")

    if ($InputObject -is [array])
    {
        $hashstr += ");"
    }

    return $hashstr
}

<#
    .SYNOPSIS
        Generates a list of required DSC Resources' local paths and destinations.

    .DESCRIPTION
        This function will 

    .PARAMETER InputObject

    .EXAMPLE
        ConvertFrom-Hashtable -InputObject @{key="value"}
#>
function New-DscResourceList
{
    param
    (
        [Parameter()]
        [string]
        $DscResourcesPath,

        [Parameter()]
        [DscCompositeResource[]]
        $CompositeResource,

        [Parameter()]
        [char]
        $DestinationDriveLetter = "C"
    )

    #Create an array of all DSC resources required
    $resourcesToCopy += $CompositeResource.Resources.ModuleName.foreach({
        @{
            Path="$DscResourcesPath\$_"
            Destination="${DestinationDriveLetter}:\Program Files\WindowsPowerShell\Modules\$_"
        }
    })
        
    return $resourcesToCopy
}
#endregion tests completed
<#
    .SYNOPSIS
        Initializes the required configuration files necessary to configure DscPush.

    .DESCRIPTION
        Performs several configuration operations necessary to operate DscPush, including, generating
        the Partial Catalog, generating secrets, & creating new or updating existing Node Definition Files.

    .PARAMETER GeneratePartialCatalog
        Instructs the function to generate the partial catalog.

    .PARAMETER GenerateSecrets
        Instructs the function to generate the files required to support secrets (stored credentials, certificate
        key passwords, and so on.

    .PARAMETER GenerateNewNodeDefinitionFile
        Instructs the function to generate a new Node Definition File.

    .PARAMETER UpdateNodeDefinitionFile
        Instructs the function to update an existing Node Definition File.

    .PARAMETER SeedDscResources
        Instructs the function to download the resources required by the partials into a specified folder.

    .PARAMETER DscResourceStorePath
        Path where Required DSC Resources will be stored.

    .PARAMETER PartialSecretsPath
        Path to the file that contains the names and referencing partials with pscredential type parameter names.

    .PARAMETER StoredSecretsPath
        Path to the file that contains the secrets required by the partial configurations.

    .PARAMETER SecretsKeyPath
        Path to the file containing the key to unencrypt the stored secrets.

    .PARAMETER PartialCatalogPath
        Path to generate and reference the Partial Catalog.
        
    .PARAMETER PartialDirectoryPath
        Path to the directory containing the Partial Configurations to be published.

    .PARAMETER NodeTemplatePath
        Path to the Node Template file that initializes the Node Definition File.
        
    .PARAMETER NodeDefinitionFilePath
        Path to the Node Definition File to be generated or updated. File will not be overwritten.

    .PARAMETER UpdateNodeDefinitionFilePath
        Path to the generate an updated Node Definition File.

    .Example
        $initDscPushGenerateParams = @{
            GeneratePartialCatalog = $true
            GenerateSecrets        = $true
            ContentStoreRootPath   = $workspacePath
            PartialCatalogPath     = $partialCatalogPath
            PartialDirectoryPath   = $PartialDirectoryPath
            PartialSecretsPath     = $partialSecretsPath
            StoredSecretsPath      = $storedSecretsPath
            SecretsKeyPath         = $secretsKeyPath
        }
        Initialize-DscPush @initDscPushGenerateParams
#>
function Initialize-DscPush
{
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
        [switch]
        $SeedDscResources,

        [Parameter()]
        [string]
        $DscResourcesPath,

        [Parameter()]
        [string]
        $PartialSecretsPath,

        [Parameter()]
        [string]
        $StoredSecretsPath,

        [Parameter()]
        [string]
        $SecretsKeyPath,

        [Parameter()]
        [string]
        $PartialCatalogPath,
    
        [Parameter()]
        [string]
        $PartialDirectoryPath,

        [Parameter()]
        [string]
        $NodeTemplatePath,

        [Parameter()]
        [string]
        $NodeDefinitionFilePath,

        [Parameter()]
        [string]
        $UpdateNodeDefinitionFilePath
    )

    if ($GeneratePartialCatalog)
    {
        Write-Verbose "Generating Partial Catalog"
        $NewPartialCatalogParams = @{
            PartialDirectoryPath = $PartialDirectoryPath
            PartialCatalogPath = $PartialCatalogPath
        }
        New-PartialCatalog @NewPartialCatalogParams
    }

    if ($GenerateSecrets)
    {
        Write-Verbose "Geneterating Secrets files"
        $newSecretsFileParams = @{
            PartialCatalogPath   = $PartialCatalogPath
            PartialSecretsPath   = $PartialSecretsPath
            StoredSecretsPath    = $StoredSecretsPath
            SecretsKeyPath       = $SecretsKeyPath
        }
        New-SecretsFile @newSecretsFileParams
    }

    if ($GenerateNewNodeDefinitionFile)
    {
        Write-Verbose "Generating New Node Definition File from template"
        $newNodeDefinitionFileParams = @{
            PartialCatalogPath = $PartialCatalogPath
            NodeTemplatePath = $NodeTemplatePath
            NodeDefinitionFilePath = $NodeDefinitionFilePath
        }
        New-NodeDefinitionFile @newNodeDefinitionFileParams
    }

    if ($UpdateNodeDefinitionFile)
    {
        Write-Verbose "Updating Existing Node Definition File with Partial Catalog updates"
        $UpdateNodeDefinitionFileParams = @{
            PartialCatalogPath = $PartialCatalogPath
            NodeDefinitionFilePath = $NodeDefinitionFilePath
            UpdateNodeDefinitionFilePath = $UpdateNodeDefinitionFilePath
        }
        Update-NodeDefinitionFile @UpdateNodeDefinitionFileParams
    }

    if ($SeedDscResources)
    {
        Write-Verbose "Saving required DSC Resources to the specified DSC Resources path"
        $saveDscResourcesParams = @{
            PartialCatalogPath = $PartialCatalogPath
            DscResourcesPath   = $DscResourcesPath
        }
        Save-DscResourceList @saveDscResourcesParams
    }
}

<#
    .SYNOPSIS
        Function to publish DSC configurations.

    .DESCRIPTION
        Performs several operations necessary to publish DSC Configurations to the targets defined in the
        Node Definition File, including compiling the configurations, sanitizing the PS module path, & copying required
        file resources to the targets.
        
    .PARAMETER DeploymentCredential
        Credential of the administrator account on the targets. Typically the local admin account of the deployed image.

    .PARAMETER RemoteAuthCertThumbprint
        Certificate thumbprint to authenticate on the targets.

    .PARAMETER ContentStoreRootPath
        Root path of the directory that will be copied to any content hosts.

    .PARAMETER ContentStoreModulePath
        Path to the directory containing modules supporting the partial configurations.

    .PARAMETER DscResourcesPath
        Path to the directory containing the DSC Resource modules required by the partial configurations.
        
    .PARAMETER NodeDefinitionFilePath
        Path to the Node Definition File to be generated or updated. File will not be overwritten.

    .PARAMETER PartialCatalogPath
        Path to a generated Partial Catalog.
        
    .PARAMETER PartialDependenciesFilePath
        Instructs the function to generate the partial catalog.

    .PARAMETER PartialSecretsPath
        Path to the file that contains the names and referencing partials with pscredential type parameter names.

    .PARAMETER StoredSecretsPath
        Path to the file that contains the secrets required by the partial configurations.

    .PARAMETER SecretsKeyPath
        Path to the file containing the key to unencrypt the stored secrets.

    .PARAMETER mofOutputPath
        Path to the directory containing the compiled mofs.
        
    .PARAMETER TargetLcmSettings
        Hashtable containing the properties to push to the target and applied to the LCM.

    .PARAMETER TargetCertDirName
        Path to the directory on the target that will contain the required certificates for mof encryption.
        
    .PARAMETER MofEncryptionCertThumbprint
        Thumbprint of the certificate used to encrypt the compiled mofs.
        
    .PARAMETER MofEncryptionCertPath
        Local path to the certificate used to encrypt the compiled mofs.

    .PARAMETER MofEncryptionPKPath
        Local path to the private key of the certificate used to encrypt the compiled mofs.

    .PARAMETER MofEncryptionPKPassword
        Password used to secure the private key for mof encryption.

    .PARAMETER EnableTargetMofEncryption
        Switch to instruct the function to perform the required operations to encypt compiled mofs.

    .PARAMETER CompilePartials
        Switch to instruct the function to compile the target partials.
        
    .PARAMETER SanitizeModulePaths
        Switch to instruct the function to remove any modules referenced in the ContentStoreModulePath from the PS Module Path.

    .PARAMETER CopyContentStore
        Switch to instruct the function to copy the ContentStore directory contents to any content hosts.
        
    .PARAMETER ContentStoreDestPath
        The Desination path for the content store on the content hosts.
        
    .PARAMETER ForceResourceCopy
        Switch to instruct the function to copy the required DSC Resource modules to the targets.
        
    .Example
        $publishTargetSettings = @{
            CompilePartials                  = $true
            SanitizeModulePaths              = $true
            CopyContentStore                 = $true
            ForceResourceCopy                = $true
            DeploymentCredential             = $DeploymentCredential
            ContentStoreRootPath             = "C:\workspace"
            ContentStoreDestPath             = "C:\ContentStore"
            ContentStoreModulePath           = "$workspace\Modules"
            DscResourcesPath = "$workspace\DscResources"
            NodeDefinitionFilePath           = "$workspace\DscPushSetup\DefinitionStore\NodeDefinition.ps1"
            PartialCatalogPath               = "$workspace\DSCPushSetup\Settings\PartialCatalog.json"
            PartialDependenciesFilePath      = "$WorkshopPath\DSCPushSetup\Settings\PartialDependencies.json"
            PartialSecretsPath               = "$WorkshopPath\DSCPushSetup\Settings\PartialSecrets.json"
            StoredSecretsPath                = "$WorkshopPath\DSCPushSetup\Settings\StoredSecrets.json"
            SecretsKeyPath                   = "$WorkshopPath\DSCPushSetup\Settings\SecretsKey.json"
            mofOutputPath                    = "$WorkshopPath\DSCPushSetup\Settings\mofStore"
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
        Publish-CompositeTargetConfig @publishTargetSettings -Verbose
#>
function Publish-CompositeTargetConfig
{
    param
    (
        [Parameter(Mandatory)]
        [pscredential]
        $DeploymentCredential,
        
        [parameter()]
        [ValidateScript({Test-Path $_})]
        [string]
        $CompositeResourcePath,
        
        [parameter()]
        [ValidateScript({Test-Path $_})]
        [string]
        $ConfigurationDirectoryPath,

        [parameter()]
        [string]
        $RemoteAuthCertThumbprint,

        [Parameter(Mandatory)]
        [string]
        $ContentStoreRootPath,

        [Parameter(Mandatory)]
        [string]
        $ContentStoreModulePath,

        [Parameter(Mandatory)]
        [string]
        $DscResourcesPath,

        [Parameter(Mandatory)]
        [string]
        $NodeDefinitionFilePath,

        [Parameter()]
        [string]
        $StoredSecretsPath,
        
        [Parameter()]
        [string]
        $SecretsKeyPath,

        [Parameter(Mandatory)]
        [string]
        $MofStorePath,

        [Parameter(Mandatory)]
        [hashtable]
        $TargetLcmSettings,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [string]
        $TargetCertDirName,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [ValidatePattern("[a-f0-9]{40}")]
        [string]
        $MofEncryptionCertThumbprint,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [string]
        $MofEncryptionCertPath,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [string]
        $MofEncryptionPKPath,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [securestring]
        $MofEncryptionPKPassword,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [switch]
        $EnableTargetMofEncryption,

        [Parameter()]
        [switch]
        $SanitizeModulePaths,

        [Parameter()]
        [switch]
        $CopyContentStore,

        [Parameter()]
        [string]
        $ContentStoreDestPath,

        [Parameter()]
        [switch]
        $CopyDscResources,

        [Parameter()]
        [switch]
        $SeedDscResources
    )
    #Hide Progress Bars
    $progressPrefSetting = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"

    Write-Verbose "Import the Node Definition file"
    $targetConfigs = . $NodeDefinitionFilePath

    $composite = Get-DscCompositeMetaData -Path $CompositeResourcePath

    Write-Verbose "Setup Deployment Environment"
    $initializeParams = @{
        ContentStoreRootPath   = $ContentStoreRootPath
        ContentStoreModulePath = $ContentStoreModulePath
        DscResourcesPath       = $DscResourcesPath
        TargetIPList           = $targetConfigs.Configs.TargetAdapter.NetworkAddress.IPAddressToString
        SanitizeModulePaths    = $SanitizeModulePaths.IsPresent
    }
    $currentTrustedHost = Initialize-DeploymentEnvironment @initializeParams

    if ($SeedDscResources)
    {
        Write-Verbose "Saving required DSC Resources to the specified DSC Resources path"
        $saveDscResourcesParams = @{
            ResourceList    = $composite.Resources
            DestinationPath = $DscResourcesPath
        }
        Save-CompositeDscResourceList @saveDscResourcesParams
    }

    $secretsImportParams = @{
        StoredSecretsPath = $StoredSecretsPath
        SecretsKeyPath    = $SecretsKeyPath
        CompositeResource = $composite
    }
    $storedSecrets = Register-Secrets @secretsImportParams

    Write-Verbose "Deploy Configs"
    foreach ($config in $targetConfigs.Configs)#.where({$_.configname -eq 'DscMember'}))
    {
        Write-Output "Preparing Config: $($config.ConfigName)"

        Write-Output "  Testing Connection to Target Adapter (Target IP: $($config.TargetAdapter.NetworkAddress))"
        $targetIp = $config.TargetAdapter.NetworkAddress.IpAddressToString
        $connectParams = @{
            TargetIpAddress       = $targetIp
            TargetAdapter         = $config.TargetAdapter
            Credential            = $DeploymentCredential
            CertificateThumbprint = $RemoteAuthCertThumbprint
        }
        $sessions = Connect-TargetAdapter @connectParams
        if ($sessions -eq $false)
        {
            continue #skip the rest of the config if we can't connect
        }

        Write-Output "  Compiling and writing Config to directory: $MofStorePath"
        $configParams = @{
            TargetConfig               = $config
            CompositeResource          = $composite
            ConfigurationDirectoryPath = $ConfigurationDirectoryPath
            StoredSecrets              = $storedSecrets
            SecretsKeyPath             = $SecretsKeyPath
            MofStorePath               = $MofStorePath
        }
        $null = Write-CompositeConfig @configParams
        
        $fileCopyList = @()
        if ($config.ContentHost -and $CopyContentStore.IsPresent)
        {
            if ([string]::IsNullOrEmpty($ContentStoreDestPath))
            {
                throw "ContentStore Destination path is required for designated Content Host: $($config.ConfigName)"
            }

            if (! (Test-Path $ContentStoreRootPath))
            {
                Write-Verbose "Creating Content Store root directory"
                $null = New-Item -Path $ContentStoreRootPath -ItemType Directory -Force -ErrorAction Stop
            }

            Write-Output "  Preparing Content Store for remote copy"
            $fileCopyList += @{
                Path        = $ContentStoreRootPath
                Destination = $ContentStoreDestPath
            }
        }

        if ($CopyDscResources.IsPresent)
        {
            Write-Output "  Preparing required DSC Resources for remote copy"
            $copyResourceParams = @{
                CompositeResource = $composite
                DscResourcesPath  = $DscResourcesPath
            }
            $fileCopyList += New-DscResourceList @copyResourceParams
        }

        if ($fileCopyList)
        {
            Write-Output "  Commencing remote copy of required file resources."
            $contentCopyParams = @{
                CopyList = $fileCopyList
                TargetCimSession = $sessions.TargetCimSession
                TargetPSSession = $sessions.TargetPsSession
                Credential = $DeploymentCredential
            }
            Copy-RemoteContent @contentCopyParams
        }

        $targetLcmParams = $null #null the LCM settings var to accomodate for the MofEncryptionCertThumbprint key
        if ($EnableTargetMofEncryption)
        {
            Write-Output "  Enabling LCM Encryption"
            $targetMofEncryptionParams = @{
                MofEncryptionCertThumbprint = $MofEncryptionCertThumbprint
                CertPassword = $MofEncryptionPKPassword
                TargetCertPath = (Join-Path -Path $ContentStoreDestPath -ChildPath $TargetCertDirName)
                MofEncryptionPKPath = $MofEncryptionPKPath
                TargetPSSession = $sessions.TargetPSSession
            }
            Enable-TargetMofEncryption @targetMofEncryptionParams

            $targetLcmParams = @{ MofEncryptionCertThumbprint = $MofEncryptionCertThumbprint }
        }

        #Set the LCM
        Write-Output "Initializing LCM Settings"
        $targetLcmParams += @{
            TargetLcmSettings = $TargetLcmSettings
            TargetConfig = $config
            MofStorePath = $MofStorePath
        }
        Initialize-NodeLcm @targetLcmParams

        Write-Output "Sending LCM Settings"
        $sendTargetLcmParams = @{
            TargetCimSession = $sessions.targetCimSession
            MofStorePath = $MofStorePath
        }
        Send-TargetLcm @sendTargetLcmParams

        <#Compile and Publish the Configs
        Write-Output "Deploying Config: $($config.ConfigName) to Target: $targetIp"
        $configParams = @{
            TargetConfig = $config
            TargetCimSession = $sessions.targetCimSession
            DeploymentCredential = $DeploymentCredential
            PartialCatalog = $PartialCatalog
            MofOutputPath = $mofOutputPath
        }
        Send-Config @configParams#>

        #This cmdlet now breaks baremetal deployment
        #Start-DscConfiguration -ComputerName $targetIp -Credential $DeploymentCredential -UseExisting
    }

    #Cleanup
    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $currentTrustedHost -Force
    if($currentWinRMStatus.Status -eq 'Stopped')
    {
        Stop-Service WinRM -Force
    }

    $ProgressPreference = $progressPrefSetting
}

<#
    .PARAMETER UpdateFileList
        Hashtable array of update/packages to install.
    
    .EXAMPLE
        $UpdateFileList = @{
            ID       = ""
            FilePath = Join-path -Path $WsusRepoDirectory -ChildPath $($_.FileUri.LocalPath.replace("/Content","/WsusContent"))
        }
#>
function Add-ConfigurationToVHDx
{
    param
    (
        [parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]
        $VhdxPath,

        [parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]
        $NodeDefinitionFilePath,
        
        [parameter()]
        [ValidateScript({Test-Path $_})]
        [string]
        $ConfigurationDirectoryPath,

        [Parameter()]
        [string]
        $StoredSecretsPath,
        
        [Parameter()]
        [string]
        $SecretsKeyPath,

        [Parameter(Mandatory)]
        [string]
        $MofStorePath,

        [Parameter(Mandatory)]
        [hashtable]
        $TargetLcmSettings,

        <#[Parameter(ParameterSetName = 'MofEncryption')]
        [string]
        $TargetCertDirName,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [ValidatePattern("[a-f0-9]{40}")]
        [string]
        $MofEncryptionCertThumbprint,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [string]
        $MofEncryptionCertPath,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [string]
        $MofEncryptionPKPath,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [securestring]
        $MofEncryptionPKPassword,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [switch]
        $EnableTargetMofEncryption, #>

        [parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]
        $ContentStoreModulePath,

        [parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]
        $DscResourcesPath,
        
        [parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]
        $CompositeResourcePath,        

        [parameter(Mandatory)]
        [string]
        $ContentStorePath,

        [Parameter()]
        [switch]
        $SeedDscResources
    )

    Write-Verbose "Import the Node Definition file"
    $targetConfigs = . $NodeDefinitionFilePath

    $composite = Get-DscCompositeMetaData -Path $CompositeResourcePath

    if ($SeedDscResources)
    {
        Write-Verbose "Saving required DSC Resources to the specified DSC Resources path"
        $resourceList += $composite.Resources
        $saveDscResourcesParams = @{
            ResourceList    = $resourceList
            DestinationPath = $DscResourcesPath
        }
        Save-CompositeDscResourceList @saveDscResourcesParams
    }

    $moduleDestPath = $env:PSModulePath.Split(";")[1]

    Write-Verbose "Copy Modules to host's module path"
    if (!(Test-Path $moduleDestPath))
    {
        New-Item -Path $moduleDestPath -ItemType Directory
    }
    Copy-Item -Path "$ContentStoreModulePath\*" -Destination $moduleDestPath -Recurse -Force -ErrorAction Stop

    Write-Verbose "Copy DSC Resources to the host's module path"
    Copy-Item -Path "$DscResourcesPath\*" -Destination $moduleDestPath -Recurse -Force

    Write-Verbose "Importing secrets"
    $secretsImportParams = @{
        StoredSecretsPath = $StoredSecretsPath
        SecretsKeyPath    = $SecretsKeyPath
        CompositeResource = $composite
    }
    $storedSecrets = Register-Secrets @secretsImportParams

    Write-Verbose "Deploy Configs"
    foreach ($config in $targetConfigs.Configs)
    {
        Write-Output "Preparing Config: $($config.ConfigName)"
        
        Write-Output "  Compiling and writing Config to directory: $MofStorePath"
        $configParams = @{
            TargetConfig               = $config
            CompositeResource          = $composite
            ConfigurationDirectoryPath = $ConfigurationDirectoryPath
            StoredSecrets              = $storedSecrets
            SecretsKeyPath             = $SecretsKeyPath
            MofStorePath               = $MofStorePath
        }
        $mofs = Write-CompositeConfig @configParams

        $targetLcmParams = $null #null the LCM settings var to accomodate for the MofEncryptionCertThumbprint key
        <#if ($EnableTargetMofEncryption)
        {
            Write-Output "  Enabling LCM Encryption"
            $targetMofEncryptionParams = @{
                MofEncryptionCertThumbprint = $MofEncryptionCertThumbprint
                CertPassword = $MofEncryptionPKPassword
                TargetCertPath = (Join-Path -Path $ContentStoreDestPath -ChildPath $TargetCertDirName)
                MofEncryptionPKPath = $MofEncryptionPKPath
                TargetPSSession = $sessions.TargetPSSession
            }
            Enable-TargetMofEncryption @targetMofEncryptionParams

            $targetLcmParams = @{ MofEncryptionCertThumbprint = $MofEncryptionCertThumbprint }
        } #>

        #Set the LCM
        Write-Output "Initializing LCM Settings"
        $targetLcmParams += @{
            TargetLcmSettings = $TargetLcmSettings
            TargetConfig = $config
            MofStorePath = $MofStorePath
        }
        Initialize-NodeLcm @targetLcmParams

        $vhdxDriveLetter = Assert-DriveMounted -Path $VhdxPath

        $mofPath = $mofs.MofPath
        $metaMofPath = $mofs.MetaMofPath

        $mofDestinationPath = "${vhdxDriveLetter}:\Windows\System32\Configuration\Pending.mof"
        $metaMofDestinationPath = "${vhdxDriveLetter}:\Windows\System32\Configuration\MetaConfig.mof"

        Write-Verbose "Injecting configuration from $mofPath to VHDX at $VhdxPath"
        try
        {
            #xcopy.exe used because Copy-Item would constantly be unable to recognize the mounted drive letter.
            $null = & xcopy.exe $mofPath "$mofDestinationPath*" /R /Y
            $null = & xcopy.exe $metaMofPath "$metaMofDestinationPath*" /R /Y
            Write-Verbose "Configuration injected successfully"
        }
        catch
        {
            throw "Configuration injection failed."
        }

        Write-Verbose "Adding DSC Resources from $DscResourcesPath"
        Add-DscResourcesToVHDx -DscResourcesPath $DscResourcesPath -CompositeResourcePath $CompositeResourcePath -vhdxDriveLetter $vhdxDriveLetter

        Write-Verbose "Adding content store from $ContentStorePath"
        Add-ContentStoreToVHDx -ContentStorePath $contentStorePath -vhdxDriveLetter $vhdxDriveLetter

        $null = Dismount-VHD -Path $VhdxPath
    }
}

function Add-DscResourcesToVHDx
{
    param
    (
        [parameter(Mandatory)]
        [char]
        $vhdxDriveLetter,

        [parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]
        $DscResourcesPath,
        
        [parameter(Mandatory)]
        [DscCompositeResource[]]
        $CompositeResource
    )

    $resourceDestinationPath = "${vhdxDriveLetter}:\Program Files\WindowsPowerShell\Modules"

    $resourcesToInject = New-DscResourceList -DscResourcesPath $DscResourcesPath -CompositeResource $CompositeResource -DestinationDriveLetter $vhdxDriveLetter

    Write-Verbose "Injecting resources from $DscResourcesPath to VHDX at $VhdxPath"
    
    foreach ($resource in $resourcesToInject)
        {
        try
        {
            $null = New-Item -Path $resource.Destination -ItemType Directory -Force -ErrorAction Stop
            $null = & xcopy.exe $resource.Path "$($resource.Destination)\*" /R /Y /E
        }
        catch
        {
            throw "Configuration resource injection failed."
        }
    }
    
    Write-Verbose "Configuration resources injected successfully"
}

function Add-ContentStoreToVHDx
{
    param
    (
        [parameter(Mandatory)]
        [char]
        $VhdxDriveLetter,

        [parameter(Mandatory)]
        [string]
        $ContentStorePath
    )

    if (! (Test-Path $ContentStorePath))
    {
        Write-Verbose "ContentStore path not found at $ContentStorePath, skipping content store copy."
    }
    else
        {
        $contentStoreDestinationPath = "${vhdxDriveLetter}:\ContentStore"

        if (! (Test-Path $contentStoreDestinationPath))
        {
            try
            {
                $null = New-Item -Path $contentStoreDestinationPath -ItemType Directory -ErrorAction Stop
            }
            catch
            {
                throw "Could not create content store directory on mounted drive."
            }
        }

        $null = & xcopy.exe "$contentStorePath" "$contentStoreDestinationPath\*" /R /Y /E
    }
}

function Assert-DriveMounted
{
    param
        (
        [parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]
        $Path
    )

    $vhdInfo = Get-VHD -Path $Path -ErrorAction Stop

    if (! $vhdInfo.DiskNumber)
    {
        Write-Verbose "Image not mounted"
        try
        {
            $null = Mount-VHD -Path $Path -ErrorAction Stop
            $vhdInfo = Get-VHD -Path $Path -ErrorAction Stop
        }
        catch
        {
            throw "Could not mount disk image. Is it in use?"
        }
    }

    try
    {
        $diskInfo = Get-Disk -Number $vhdInfo.DiskNumber -ErrorAction Stop
        $volumeInfo = Get-Partition -DiskNumber $vhdInfo.DiskNumber | Get-Volume
        $driveLetter = $volumeInfo.DriveLetter.Where({! ([string]::IsNullOrEmpty($_))})
        if ($driveLetter.count -gt 1)
        {
            throw "Disk drive letter misconfiguration - either too many partitions have drive letters, or there are none."
        }
    }
    catch
    {
        throw $_
    }

    return $driveLetter
}

<#
    .SYNOPSIS
        Function to publish DSC configurations.

    .DESCRIPTION
        Performs several operations necessary to publish DSC Configurations to the targets defined in the
        Node Definition File, including compiling the configurations, sanitizing the PS module path, & copying required
        file resources to the targets.
        
    .PARAMETER DeploymentCredential
        Credential of the administrator account on the targets. Typically the local admin account of the deployed image.

    .PARAMETER RemoteAuthCertThumbprint
        Certificate thumbprint to authenticate on the targets.

    .PARAMETER ContentStoreRootPath
        Root path of the directory that will be copied to any content hosts.

    .PARAMETER ContentStoreModulePath
        Path to the directory containing modules supporting the partial configurations.

    .PARAMETER DscResourcesPath
        Path to the directory containing the DSC Resource modules required by the partial configurations.
        
    .PARAMETER NodeDefinitionFilePath
        Path to the Node Definition File to be generated or updated. File will not be overwritten.

    .PARAMETER PartialCatalogPath
        Path to a generated Partial Catalog.
        
    .PARAMETER PartialDependenciesFilePath
        Instructs the function to generate the partial catalog.

    .PARAMETER PartialSecretsPath
        Path to the file that contains the names and referencing partials with pscredential type parameter names.

    .PARAMETER StoredSecretsPath
        Path to the file that contains the secrets required by the partial configurations.

    .PARAMETER SecretsKeyPath
        Path to the file containing the key to unencrypt the stored secrets.

    .PARAMETER mofOutputPath
        Path to the directory containing the compiled mofs.
        
    .PARAMETER TargetLcmSettings
        Hashtable containing the properties to push to the target and applied to the LCM.

    .PARAMETER TargetCertDirName
        Path to the directory on the target that will contain the required certificates for mof encryption.
        
    .PARAMETER MofEncryptionCertThumbprint
        Thumbprint of the certificate used to encrypt the compiled mofs.
        
    .PARAMETER MofEncryptionCertPath
        Local path to the certificate used to encrypt the compiled mofs.

    .PARAMETER MofEncryptionPKPath
        Local path to the private key of the certificate used to encrypt the compiled mofs.

    .PARAMETER MofEncryptionPKPassword
        Password used to secure the private key for mof encryption.

    .PARAMETER EnableTargetMofEncryption
        Switch to instruct the function to perform the required operations to encypt compiled mofs.

    .PARAMETER CompilePartials
        Switch to instruct the function to compile the target partials.
        
    .PARAMETER SanitizeModulePaths
        Switch to instruct the function to remove any modules referenced in the ContentStoreModulePath from the PS Module Path.

    .PARAMETER CopyContentStore
        Switch to instruct the function to copy the ContentStore directory contents to any content hosts.
        
    .PARAMETER ContentStoreDestPath
        The Desination path for the content store on the content hosts.
        
    .PARAMETER ForceResourceCopy
        Switch to instruct the function to copy the required DSC Resource modules to the targets.
        
    .Example
        $publishTargetSettings = @{
            CompilePartials                  = $true
            SanitizeModulePaths              = $true
            CopyContentStore                 = $true
            ForceResourceCopy                = $true
            DeploymentCredential             = $DeploymentCredential
            ContentStoreRootPath             = "C:\workspace"
            ContentStoreDestPath             = "C:\ContentStore"
            ContentStoreModulePath           = "$workspace\Modules"
            DscResourcesPath = "$workspace\DscResources"
            NodeDefinitionFilePath           = "$workspace\DscPushSetup\DefinitionStore\NodeDefinition.ps1"
            PartialCatalogPath               = "$workspace\DSCPushSetup\Settings\PartialCatalog.json"
            PartialDependenciesFilePath      = "$WorkshopPath\DSCPushSetup\Settings\PartialDependencies.json"
            PartialSecretsPath               = "$WorkshopPath\DSCPushSetup\Settings\PartialSecrets.json"
            StoredSecretsPath                = "$WorkshopPath\DSCPushSetup\Settings\StoredSecrets.json"
            SecretsKeyPath                   = "$WorkshopPath\DSCPushSetup\Settings\SecretsKey.json"
            mofOutputPath                    = "$WorkshopPath\DSCPushSetup\Settings\mofStore"
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
        Publish-TargetConfig @publishTargetSettings -Verbose
#>
function Publish-TargetConfig
{
    param
    (
        [Parameter(Mandatory)]
        [pscredential]
        $DeploymentCredential,

        [parameter()]
        [string]
        $RemoteAuthCertThumbprint,

        [Parameter(Mandatory)]
        [string]
        $ContentStoreRootPath,

        [Parameter(Mandatory)]
        [string]
        $ContentStoreModulePath,

        [Parameter(Mandatory)]
        [string]
        $DscResourcesPath,

        [Parameter(Mandatory)]
        [string]
        $NodeDefinitionFilePath,

        [Parameter(Mandatory)]
        [string]
        $PartialCatalogPath,

        [Parameter(Mandatory)]
        [string]
        $PartialDependenciesFilePath,

        [Parameter()]
        [string]
        $PartialSecretsPath,

        [Parameter()]
        [string]
        $StoredSecretsPath,

        [Parameter()]
        [string]
        $SecretsKeyPath,

        [Parameter(Mandatory)]
        [string]
        $mofOutputPath,

        [Parameter(Mandatory)]
        [hashtable]
        $TargetLcmSettings,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [string]
        $TargetCertDirName,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [ValidatePattern("[a-f0-9]{40}")]
        [string]
        $MofEncryptionCertThumbprint,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [string]
        $MofEncryptionCertPath,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [string]
        $MofEncryptionPKPath,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [securestring]
        $MofEncryptionPKPassword,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [switch]
        $EnableTargetMofEncryption,

        [Parameter()]
        [switch]
        $CompilePartials,
    
        [Parameter()]
        [switch]
        $SanitizeModulePaths,

        [Parameter()]
        [switch]
        $CopyContentStore,

        [Parameter()]
        [string]
        $ContentStoreDestPath,

        [Parameter()]
        [switch]
        $ForceResourceCopy
    )
    #Hide Progress Bars
    $progressPrefSetting = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"

    Write-Verbose "Import the partial catalog"
    $partialCatalog = [DscPartial[]](ConvertFrom-Json ([string](Get-Content $PartialCatalogPath)))

    Write-Verbose "Import the Node Definition file"
    $targetConfigs = . $NodeDefinitionFilePath

    Write-Verbose "Add dependencies and secrets to the Configs"
    $partialProperties = @{
        PartialDependenciesFilePath = $PartialDependenciesFilePath
        PartialSecretsPath          = $PartialSecretsPath
        StoredSecretsPath           = $StoredSecretsPath
        SecretsKeyPath              = $SecretsKeyPath
        TargetConfigs               = ([ref]$targetConfigs)
    }
    $corePartial = Add-PartialProperties @partialProperties

    Write-Verbose "Setup Deployment Environment"
    $initializeParams = @{
        ContentStoreRootPath   = $ContentStoreRootPath
        ContentStoreModulePath = $ContentStoreModulePath
        DscResourcesPath       = $DscResourcesPath
        TargetIPList           = $targetConfigs.Configs.TargetAdapter.NetworkAddress.IPAddressToString
        SanitizeModulePaths    = $SanitizeModulePaths.IsPresent
    }
    $currentTrustedHost = Initialize-DeploymentEnvironment @initializeParams

    Write-Verbose "Deploy Configs"
    foreach ($config in $targetConfigs.Configs)#.where({$_.configname -eq 'DscMember'}))
    {
        Write-Output "Preparing Config: $($config.ConfigName)"

        Write-Verbose "  Testing Connection to Target Adapter (Target IP: $($config.TargetAdapter.NetworkAddress))"
        $targetIp = $config.TargetAdapter.NetworkAddress.IpAddressToString
        $connectParams = @{
            TargetIpAddress       = $targetIp
            TargetAdapter         = $config.TargetAdapter
            Credential            = $DeploymentCredential
            CertificateThumbprint = $RemoteAuthCertThumbprint
        }
        $sessions = Connect-TargetAdapter @connectParams
        if ($sessions -eq $false)
        {
            continue #skip the rest of the config if we can't connect
        }

        if ($CompilePartials.IsPresent)
        {
            Write-Output "  Compiling and writing Config to directory: $mofOutputPath"
            $configParams = @{
                TargetConfig         = $config
                DeploymentCredential = $DeploymentCredential
                PartialCatalog       = $PartialCatalog
                MofOutputPath        = $mofOutputPath
            }
            Write-Config @configParams
        }

        $fileCopyList = @()
        if ($config.ContentHost -and $CopyContentStore.IsPresent)
        {
            if ([string]::IsNullOrEmpty($ContentStoreDestPath))
            {
                throw "ContentStore Destination path is required for designated Content Host: $($config.ConfigName)"
            }

            if (! (Test-Path $ContentStoreRootPath))
            {
                Write-Verbose "Creating Content Store root directory"
                $null = New-Item -Path $ContentStoreRootPath -ItemType Directory -Force -ErrorAction Stop
            }

            Write-Output "  Preparing Content Store for remote copy"
            $fileCopyList += @{
                Path        = $ContentStoreRootPath
                Destination = $ContentStoreDestPath
            }
        }

        if ($ForceResourceCopy.IsPresent)
        {
            Write-Output "  Preparing required DSC Resources for remote copy"
            $copyResourceParams = @{
                TargetConfig         = $config
                DscResourcesPath     = $DscResourcesPath
                DeploymentCredential = $DeploymentCredential
                PartialCatalog       = $partialCatalog
            }
            $fileCopyList += Select-DscResource @copyResourceParams
        }

        if ($fileCopyList)
        {
            Write-Output "  Commencing remote copy of required file resources."
            $contentCopyParams = @{
                CopyList = $fileCopyList
                TargetCimSession = $sessions.TargetCimSession
                TargetPSSession = $sessions.TargetPsSession
                Credential = $DeploymentCredential
            }
            Copy-RemoteContent @contentCopyParams
        }

        $targetLcmParams = $null #null the LCM settings var to accomodate for the MofEncryptionCertThumbprint key
        if ($EnableTargetMofEncryption)
        {
            Write-Output "  Enabling LCM Encryption"
            $targetMofEncryptionParams = @{
                MofEncryptionCertThumbprint = $MofEncryptionCertThumbprint
                CertPassword = $MofEncryptionPKPassword
                TargetCertPath = (Join-Path -Path $ContentStoreDestPath -ChildPath $TargetCertDirName)
                MofEncryptionPKPath = $MofEncryptionPKPath
                TargetPSSession = $sessions.TargetPSSession
            }
            Enable-TargetMofEncryption @targetMofEncryptionParams

            $targetLcmParams = @{ MofEncryptionCertThumbprint = $MofEncryptionCertThumbprint }
        }

        #Set the LCM
        Write-Output "Initializing LCM Settings"
        $targetLcmParams += @{
            TargetLcmSettings = $TargetLcmSettings
            TargetConfig = $config
            TargetCimSession = $sessions.targetCimSession
            CorePartial = $corePartial
            Credential = $DeploymentCredential
            MofOutputPath = $mofOutputPath
        }
        Initialize-TargetLcm @targetLcmParams

        #Compile and Publish the Configs
        Write-Output "Deploying Config: $($config.ConfigName) to Target: $targetIp"
        $configParams = @{
            TargetConfig = $config
            TargetCimSession = $sessions.targetCimSession
            DeploymentCredential = $DeploymentCredential
            PartialCatalog = $PartialCatalog
            MofOutputPath = $mofOutputPath
        }
        Send-Config @configParams

        #This cmdlet now breaks baremetal deployment
        #Start-DscConfiguration -ComputerName $targetIp -Credential $DeploymentCredential -UseExisting
    }

    #Cleanup
    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $currentTrustedHost -Force
    if($currentWinRMStatus.Status -eq 'Stopped')
    {
        Stop-Service WinRM -Force
    }

    $ProgressPreference = $progressPrefSetting
}

<#
    .SYNOPSIS
        Saves (overwrites) all the resources required for the partials in the specified directory.

    .DESCRIPTION
        This function will import the partial catalog, and return a list of unique DSC resource names and version numbers.
        With that list, the function will attempt to find the module by its name and version.  If found, it will remove the
        existing resource with the same name from the resources directory and save the module from the public repository.

    .PARAMETER PartialCatalogPath
        Path to the Partial Catalog. The catalog is used to gather the list of required resources.

    .PARAMETER DscResourcesPath
        Path to the directory containing required DSC Resources.

    .EXAMPLE
        Save-CompositeDscResourceList
#>
function Save-CompositeDscResourceList
{
    param
    (
        [Parameter()]
        [hashtable[]]
        $ResourceList,

        [Parameter()]
        [string]
        $DestinationPath
    )

    if (! (Test-Path $DestinationPath))
    {
        New-Item -Path $DestinationPath -ItemType Directory -Force -ErrorAction Stop
    }

    foreach ($resource in $ResourceList)
    {
        #Find the module first, in order to skip custom resources
        try
        {
            $null = Find-Module -Name $resource.ModuleName -RequiredVersion $resource.ModuleVersion -ErrorAction Stop
        }
        catch
        {
            Write-Warning "$($resource.ModuleName) could not be found."
            Continue
        }

        $resourceDestPath = Join-Path -Path $DestinationPath -ChildPath $resource.ModuleName
        if (Test-Path $resourceDestPath)
        {
            Remove-Item -Path $resourceDestPath -Recurse -Force -ErrorAction Stop
        }
        
        try
        {
            $currentProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'

             Write-Verbose "Saving DSC Resource: $resource to $DestinationPath"
             Save-Module -Name $resource.ModuleName -RequiredVersion $resource.ModuleVersion -Path $DestinationPath -Force -ErrorAction Stop
        }
        catch
        {
            throw "Could not save DSC Resource: $resource to $DestinationPath"
        }
        finally
        {
            $ProgressPreference = $currentProgressPreference
        }
    }
}

<#
    .SYNOPSIS
        Saves (overwrites) all the resources required for the partials in the specified directory.

    .DESCRIPTION
        This function will import the partial catalog, and return a list of unique DSC resource names and version numbers.
        With that list, the function will attempt to find the module by its name and version.  If found, it will remove the
        existing resource with the same name from the resources directory and save the module from the public repository.

    .PARAMETER PartialCatalogPath
        Path to the Partial Catalog. The catalog is used to gather the list of required resources.

    .PARAMETER DscResourcesPath
        Path to the directory containing required DSC Resources.

    .EXAMPLE
        Save-DscResourceList
#>
function Save-DscResourceList
{
    param
    (
        [Parameter()]
        [ValidateScript({Test-Path $_})]
        [string]
        $PartialCatalogPath,

        [Parameter()]
        [string]
        $DscResourcesPath
    )

    if (! (Test-Path $DscResourcesPath))
    {
        New-Item -Path $DscResourcesPath -ItemType Directory -Force -ErrorAction Stop
    }

    Write-Verbose "Import the partial catalog"
    $partialCatalog = [DscPartial[]](ConvertFrom-Json ([string](Get-Content $PartialCatalogPath)))

    $targetResources = $partialCatalog.Resources.Where({!([string]::IsNullOrEmpty($_))}) | Select-Object -Property ModuleName,ModuleVersion -Unique

    foreach ($resource in $targetResources)
    {
        #Find the module first, in order to skip custom resources
        try
        {
            $null = Find-Module -Name $resource.ModuleName -RequiredVersion $resource.ModuleVersion -ErrorAction Stop
        }
        catch
        {
            Write-Warning "$($resource.ModuleName) could not be found."
            Continue
        }

        $resourceDestPath = Join-Path -Path $DscResourcesPath -ChildPath $resource.ModuleName
        if (Test-Path $resourceDestPath)
        {
            Remove-Item -Path $resourceDestPath -Recurse -Force -ErrorAction Stop
        }
        
        try
        {
            $currentProgressPreference = $ProgressPreference
            $ProgressPreference = 'SilentlyContinue'

             Write-Verbose "Saving DSC Resource: $resource to $DscResourcesPath"
             Save-Module -Name $resource.ModuleName -RequiredVersion $resource.ModuleVersion -Path $DscResourcesPath -Force -ErrorAction Stop
        }
        catch
        {
            throw "Could not save DSC Resource: $resource to $DscResourcesPath"
        }
        finally
        {
            $ProgressPreference = $currentProgressPreference
        }
    }
}

function Export-NodeDefinitionFile
{
    param
    (
        [Parameter(Mandatory)]
        $NodeDefinition,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]
        $NodeDefinitionFilePath,

        [Parameter()]
        [string]
        $UpdateNodeDefinitionFilePath,

        [Parameter()]
        [DscPartial[]]
        $PartialCatalog
    )

    if ($UpdateNodeDefinitionFilePath)
    {
        $configsToMerge = $NodeDefinition
    }

    $crlf = "`r`n"

    $nodeList = @()

    $dataFileContents = "#Fill in the values below and save to your content store.$crlf$crlf"

    foreach ($node in $NodeDefinition)
    {
        $nodeName = $node.Name
        $nodeType = $node.Type
        $nodeId = $node.NodeId

        $dataFileContents += "#region Node Definition: $nodeName${crlf}"
        $dataFileContents += "`$$nodeName = New-Node -Name '$nodeName' -NodeId '$nodeId' -Type '$nodeType'$crlf$crlf"

        foreach ($config in $node.Configs)
        {
            $configName = $config.ConfigName
            $targetAdapter = $config.TargetAdapter
            $ContentHost = $config.ContentHost
            if ($ContentHost)
            {
                $ContentStorePath = $config.ContentStorePath
            }
            $roleList = ($config.RoleList) -join "`"$crlf        `""
            $roleList = "$roleList"
            
            #Generate Config properties
            $mergeConfig = $configsToMerge.Configs.where({$_.ConfigName -eq $configName})

            $dataFileContents += "#region Target Config: $configName${crlf}"
            $dataFileContents += "`$$ConfigName = New-TargetConfig -Properties @{$crlf"
            $dataFileContents += "    ConfigName = '$configName'$crlf"

            $dataFileContents += "    ContentHost = `$$ContentHost$crlf"
            if ($ContentHost)
            {
                $dataFileContents += "    ContentStorePath = '$ContentStorePath'$crlf"
            }
            
            $dataFileContents += "    RoleList = @($crlf        `"$roleList`"$crlf    )$crlf"
            $dataFileContents += "}$crlf"

            #Generate config targetAdapter property/class
            if ($targetAdapter)
            {
                $dataFileContents += "`$${configName}AdapterProperties = @{$crlf"
                $dataFileContents += "    InterfaceAlias  = '$($targetAdapter.InterfaceAlias)'$crlf"
                $dataFileContents += "    PhysicalAddress = '$($targetAdapter.PhysicalAddress)'$crlf"
                $dataFileContents += "    NetworkAddress  = '$($targetAdapter.NetworkAddress)'$crlf"
                $dataFileContents += "    SubnetBits      = '$($targetAdapter.SubnetBits)'$crlf"
                $dataFileContents += "    DnsAddress      = '$($targetAdapter.DnsAddress)'$crlf"
                $dataFileContents += "    AddressFamily   = '$($targetAdapter.AddressFamily)'$crlf"
                $dataFileContents += "    Description     = '$($targetAdapter.Description)'$crlf"
                $dataFileContents += "}$crlf"
                $dataFileContents += "`$$ConfigName.TargetAdapter = New-TargetAdapter @${configName}AdapterProperties$crlf"
            }
            else
            {
                $dataFileContents += "`$${configName}AdapterProperties = @{$crlf"
                $dataFileContents += "    InterfaceAlias  = 'ENTER_VALUE_HERE'$crlf"
                $dataFileContents += "    PhysicalAddress = 'ENTER_VALUE_HERE'$crlf"
                $dataFileContents += "    NetworkAddress  = 'ENTER_VALUE_HERE'$crlf"
                $dataFileContents += "    SubnetBits      = 'ENTER_VALUE_HERE'$crlf"
                $dataFileContents += "    DnsAddress      = 'ENTER_VALUE_HERE'$crlf"
                $dataFileContents += "    AddressFamily   = 'ENTER_VALUE_HERE'$crlf"
                $dataFileContents += "    Description     = 'ENTER_VALUE_HERE'$crlf"
                $dataFileContents += "}$crlf"
                $dataFileContents += "`$$ConfigName.TargetAdapter = New-TargetAdapter @${configName}AdapterProperties$crlf"
            }

            #Get the list of unique parameters from the pool of partials
            $ParamObjList = $PartialCatalog.Where({$_.Name -in $config.RoleList}).Parameters

            $uniqueParamList = $ParamObjList.Name | Sort-Object -Unique

            $dataFileContents += "`$$ConfigName.Variables += @{$crlf"

            foreach ($parameter in $uniqueParamList)
            {
                $paramValue = $null

                if ($UpdateNodeDefinitionFilePath)
                {
                    $paramValue = $mergeConfig.Variables.$parameter
                }

                if (! $paramValue)
                {
                    #Check for pscredential types and flag them for storage in a secrets file
                    if ($ParamObjList.where({$_.Name -eq $parameter}).StaticType -contains "System.Management.Automation.PSCredential")
                    {
                        $paramValue = "|pscredential|"
                    }
                    else
                    {
                        $paramValue = "ENTER_VALUE_HERE"
                    }
                }

                if ($paramValue.GetType().Name -like "*hashtable*")
                {
                    $dataFileContents += "    $parameter=$(ConvertFrom-Hashtable $paramValue)$crlf"
                }
                else
                {
                    $dataFileContents += "    $parameter='$paramValue'$crlf"
                }
            }

            $dataFileContents += "}$crlf"
        
            $dataFileContents += "`$$nodeName.Configs += `$$configName${crlf}"

            $dataFileContents += "#endregion Target Config: $configName${crlf}${crlf}"
        }

        $dataFileContents += "#endregion Node Definition: $nodeName${crlf}${crlf}${crlf}"

        $nodeList += "`$$nodeName"
    }

    $dataFileContents += "@($($NodeList -join ","))"

    try
    {
        if ($UpdateNodeDefinitionFilePath)
        {
            Out-File -FilePath $UpdateNodeDefinitionFilePath -InputObject $dataFileContents
        }
        else
        {
            Out-File -FilePath $NodeDefinitionFilePath -InputObject $dataFileContents
        }
    }
    catch
    {
        throw "Could not generate data file."
    }
}

function Add-TargetConfigProperties
{
    param
    (

        [Parameter()]
        [string]
        $SecretsListPath,

        [Parameter()]
        [string]
        $StoredSecretsPath,

        [Parameter()]
        [string]
        $SecretsKeyPath,

        [ref]
        $TargetConfigs
    )

    #Import the partial secrets, stored secrets, secrets key, and convert the hashed passwords into secureString objs
    $secretsList = ConvertFrom-Json ([string](Get-Content $SecretsListPath))
    [array]$storedSecrets = ConvertFrom-Json ([string](Get-Content $StoredSecretsPath))
    [byte[]]$secretsKey = Get-Content $SecretsKeyPath

    $securedSecrets = @(
        $storedSecrets.ForEach({
            [hashtable]@{
                Username = $_.Username
                Password = ConvertTo-SecureString -String $_.Password -Key $secretsKey
                Secret = $_.Secret
            }
        })
    )

    foreach ($config in $TargetConfigs.Value.Configs)
    {
        #Add secrets to the config
        [array]$definedSecrets = ($secretsList.where({$_.Partial -in $config.RoleList})).Secrets
        $requiredSecrets = ($securedSecrets.where({$_.Secret -in $definedSecrets}))
        $config.Secrets = $requiredSecrets
    }

    return $corePartial
}

function Add-PartialProperties
{
    param
    (
        [Parameter()]
        [string]
        $PartialDependenciesFilePath,

        [Parameter()]
        [string]
        $PartialSecretsPath,

        [Parameter()]
        [string]
        $StoredSecretsPath,

        [Parameter()]
        [string]
        $SecretsKeyPath,

        [ref]
        $TargetConfigs
    )

    #Import the partial dependencies file and store the CorePartial for use in Initialize-TargetLCM
    $partialDependencies = ConvertFrom-Json ([string](Get-Content $PartialDependenciesFilePath))
    $corePartial = $partialDependencies.CorePartial[0]

    #Import the partial secrets, stored secrets, secrets key, and convert the hashed passwords into secureString objs
    $secretsList = ConvertFrom-Json ([string](Get-Content $PartialSecretsPath))
    [array]$storedSecrets = ConvertFrom-Json ([string](Get-Content $StoredSecretsPath))
    [byte[]] $secretsKey = Get-Content $SecretsKeyPath
    $securedSecrets = @(
        $storedSecrets.ForEach({
            [hashtable]@{
                Username = $_.Username
                Password = ConvertTo-SecureString -String $_.Password -Key $secretsKey
                Secret = $_.Secret
            }
        })
    )

    foreach ($config in $TargetConfigs.Value.Configs)
    {
        #Add partial dependencies to the config
        $configDependencies = $partialDependencies.Where({$_.Partial -in $config.RoleList})
        #hashtables are returned as customObjs, so this whacky crap is necessary
        $config.Dependencies = $configDependencies.ForEach({@{Partial=$_.Partial;DependsOn=$_.DependsOn}})

        #Add partial secrets to the config
        [array]$definedSecrets = ($secretsList.where({$_.Partial -in $config.RoleList})).Secrets
        $requiredSecrets = ($securedSecrets.where({$_.Secret -in $definedSecrets}))
        $config.Secrets = $requiredSecrets
    }

    return $corePartial
}

function Enable-TargetMofEncryption
{
    Param
    (
        [Parameter(Mandatory)]
        [ValidatePattern("[a-f0-9]{40}")]
        [String]
        $MofEncryptionCertThumbprint,

        [Parameter(Mandatory)]
        [securestring]
        $CertPassword,

        [Parameter()]
        [string]
        $TargetCertPath,

        [Parameter()]
        [string]
        $MofEncryptionPKPath,

        [Parameter()]
        [System.Management.Automation.Runspaces.PSSession]
        $TargetPSSession
    )

    #region Enable passing creds to allow for importing the PK
    $null = Enable-WSManCredSSP –Role Client –DelegateComputer $TargetPSSession.ComputerName -Force -ErrorAction Stop
    try
    {
        $lcmPKName = (Get-Item -Path $MofEncryptionPKPath -ErrorAction Stop).Name
    }
    catch
    {
        Disable-WSManCredSSP -Role Client -ErrorAction Ignore
        throw "Could not access Target LCM Encryption Private Key at $MofEncryptionPKPath"
    }
    #endregion

    #region copy PK
    $remotePKPath = "$TargetCertPath\$lcmPKName"

    #attempt to copy the PK 5 times
    for ($i = 5; $i -gt 0 ; $i--)
    {
        
        $certExists = Invoke-Command { Test-Path -Path $using:remotePKPath } -Session $TargetPSSession
        if ($certExists)
        {
            break
        }
        else
        {
            try
            {
                #Create the destination folder remotely if it doesn't exist
                Invoke-Command -Session $targetPSSession -ScriptBlock {
                    $remoteDir = Get-Item -Path $using:TargetCertPath -ErrorAction Ignore
                    if (! $remoteDir) { $null = New-Item -ItemType Directory -Path $using:TargetCertPath -ErrorAction Continue }
                }
                Copy-Item -Path $MofEncryptionPKPath -Destination $remotePKPath -ToSession $TargetPSSession -Force -ErrorAction Stop
            }
            catch
            {
                Disable-WSManCredSSP -Role Server -ErrorAction Ignore
                continue
            }
        }
    }
    #endregion copy PK

    #region import PK
    $null = Invoke-Command {
        $certImported = Test-Path -Path "Cert:\LocalMachine\My\$using:MofEncryptionCertThumbprint"
        if (! $certImported)
        {
            try
            {
                Enable-WSManCredSSP –Role Server -Force
                Import-PfxCertificate -FilePath $using:remotePKPath -Password $using:CertPassword -CertStoreLocation "Cert:\LocalMachine\My"
            }
            catch
            {
                Disable-WSManCredSSP -Role Server -ErrorAction Ignore
                throw "Certificate import failed."
            }
        }

    } -Session $TargetPSSession
    #endregion import PK

    #Cleanup
    $null = Disable-WSManCredSSP -Role Client
}

<#
    .SYNOPSIS
        Copies content to a remote computer.

    .DESCRIPTION
        Copies files recursively to a remote destination using SMB2 protocol and in-transit
        encryption.

    .PARAMETER Path
        The local file path that is to be copied.

    .PARAMETER Destination
        The remote file path that is to be copied to.

    .PARAMETER Target
        The name or IP address of the remote target to copy to.

    .PARAMETER Credential
        The credential used to authenticate with on the remote computer.
#>
function Copy-RemoteContent
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [hashtable[]]
        $CopyList,
        
        [Parameter(Mandatory = $true)]
        [CimSession]
        $TargetCimSession,

        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Runspaces.PSSession]
        $TargetPSSession,

        [Parameter(Mandatory = $true)]
        [PSCredential]
        $Credential
    )

    $targetName = $($targetCimSession.ComputerName)
    
    #Enable SMB firewall and update GP if SMB test fails
    if (! (Test-NetConnection -ComputerName $targetName -CommonTCPPort SMB -InformationLevel Quiet -WarningAction SilentlyContinue))
    {
        Copy-NetFirewallRule -CimSession $targetCimSession -NewPolicyStore localhost -DisplayName 'File and Printer Sharing (SMB-In)' -ErrorAction Ignore
        Enable-NetFirewallRule -CimSession $targetCimSession -PolicyStore localhost
        
        Invoke-Command -Session $targetPSSession -ScriptBlock {
            $null = cmd.exe /c gpupdate /force
        }
    }

    #Enable SMB encryption
    Set-SmbServerConfiguration -CimSession $targetCimSession -EncryptData $true -Confirm:$false

    foreach ($copyItem in $copyList)
    {
        #Variables assemble! - this should obviously be a function call, but i'm not in the mood right now. :|
        $destinationPath = $copyItem.Destination
        $destinationUncPath = $copyItem.Destination.Replace(":","$")
        $fullDestinationUncPath = "\\$targetName\$destinationUncPath"
        $driveName = "DCSPushRC-$targetName" -replace "[;~/\.:]",""
        $driveMounted = $false

        #Attempt the drive mounting operation 5 times
        #certain actions in this loop aren't as stable as we'd like, so we just try them a few times
        for ($i = 5; $i -gt 0 ; $i--)
        {
            #Create the destination folder remotely if it doesn't exist
            Invoke-Command -Session $targetPSSession -ScriptBlock {
                $remoteDir = Get-Item -Path $using:destinationPath -ErrorAction Ignore
                if (! $remoteDir) { $null = New-Item -ItemType Directory -Path $using:destinationPath -ErrorAction Continue }
            }

            try
            {
                #Mount the PS Drive, which enables SMB3 speeds
                #would preferably like to mount shared parent paths to speed up the process, but that complexity will have to be added later 
                $psDrive = New-PSDrive -Name $driveName -PSProvider "filesystem" -Root $fullDestinationUncPath -Credential $Credential -ErrorAction Stop
            }
            catch
            {
                $driveMounted = $false
                continue
            }

            #Let the filesystem operation catch up and test 
            Start-Sleep -Seconds 1
            try
            {
                $null = Get-PSDrive -Name $driveName
                $driveMounted = $true
                break
            }
            catch
            {
                $driveMounted = $false
                Write-Warning "Failed to mount remote drive ($fullDestinationUncPath).  Attempting $i more times..."
                continue
            }
        }

        #If the drive can't be mounted, it's likely the target doesn't have file/printer sharing enabled, so we'll just copy via PS session instead (slower)
        if (! $driveMounted)
        {
            Write-Warning "Could not mount remote drive. Attempting copy using PS Session."
            try
            {
                Copy-Item -Path "$($copyItem.Path)\*" -Destination $destinationPath -ToSession $targetPSSession -Force -Recurse
            }
            catch
            {
                throw "Something went wrong with the file copy to destination $destinationPath on target $targetName"
            }
        }
        else
        {
            Write-Verbose "Copying $($copyItem.Path) to Destination $destinationUncPath"
            try
            {
                Copy-Item -Path "$($copyItem.Path)\*" -Destination "${driveName}:\" -Force -Recurse
                Get-ChildItem -Path "${driveName}:\" -Recurse -Force | Unblock-File
                continue
            }
            catch
            {
                throw "Something went wrong with the file copy to destination $destinationUncPath"
            }
            finally
            {
                Remove-PSDrive -Name $driveName
            }
        }
    }
}

function Initialize-DeploymentEnvironment
{
    param
    (
        [Parameter(Mandatory)]
        [string]
        $ContentStoreRootPath,

        [Parameter(Mandatory)]
        [string]
        $ContentStoreModulePath,

        [Parameter(Mandatory)]
        [string]
        $DscResourcesPath,

        [Parameter(Mandatory)]
        [array]
        $TargetIPList,

        [Parameter()]
        [switch]
        $SanitizeModulePaths
    )

    if ($SanitizeModulePaths.IsPresent)
    {
        #Get DSC Resource store
        $resources = Get-ChildItem $DscResourcesPath
        $modules = Get-ChildItem $ContentStoreModulePath

        #Iterate through each PS Module Path and remove all references to supporting Modules and DSC Resources
        $psModulePaths = $env:PSModulePath.Split(";")
        foreach ($psModulePath in $psModulePaths)
        {
            foreach ($resource in $resources.Name)
            {
                Remove-Item -Path "$psModulePath\$resource" -Recurse -Force -ErrorAction Ignore
            }

            foreach ($module in $modules)
            {
                Remove-Item -Path "$psModulePath\$module" -Recurse -Force -ErrorAction Ignore
            }
        }

        Write-Verbose "Sanitizing module directories complete."
    }
    
    #Required modules will be copied to the C:\Program Files\WindowsPowerShell\Modules  #logged in user's documents folder
    $moduleDestPath = $env:PSModulePath.Split(";")[1]

    #Unblock the content store
    Get-ChildItem $ContentStoreRootPath -Recurse | Unblock-File
    
    #Copy Modules to host's module path
    if (!(Test-Path $moduleDestPath))
    {
        New-Item -Path $moduleDestPath -ItemType Directory
    }

    Copy-Item -Path "$ContentStoreModulePath\*" -Destination $moduleDestPath -Recurse -Force -ErrorAction Stop

    #Copy DSC Resources to the host's module path
    Copy-Item -Path "$DscResourcesPath\*" -Destination $moduleDestPath -Recurse -Force

    # Ensure WinRM is running
    if ((Get-Service "WinRM" -ErrorAction Stop).status -eq 'Stopped') 
    {
        Start-Service "WinRM" -Confirm:$false -ErrorAction Stop
    }

    Write-Verbose "Add the IP list of the target VMs ($TargetIPList) to the trusted host list"
    $currentTrustedHost = (Get-Item "WSMan:\localhost\Client\TrustedHosts").Value
    if(($currentTrustedHost -ne '*') -and ([string]::IsNullOrEmpty($currentTrustedHost) -eq $false))
    {
        $scriptTrustedHost = @($currentTrustedHost,$($TargetIPList -join ", ")) -join ", "
        Write-Verbose "Setting Trusted Hosts List to: $scriptTrustedHost"
        Set-Item -Path "WSMan:\localhost\Client\TrustedHosts" -Value $scriptTrustedHost -Force
    }
    elseif($currentTrustedHost -ne '*')
    {
        $scriptTrustedHost = $TargetIPList -join ", "
        Write-Verbose "Setting Trusted Hosts List to: $scriptTrustedHost"
        Set-Item -Path "WSMan:\localhost\Client\TrustedHosts" -Value $scriptTrustedHost -Force
    }

    Write-Verbose "Return current Trusted Hosts list so we can reset to that after publishing."
    return $currentTrustedHost
}

function Connect-TargetAdapter
{
    param
    (
        [parameter(Mandatory)]
        [ipaddress]
        $TargetIpAddress,

        [parameter(Mandatory)]
        [TargetAdapter]
        $TargetAdapter,
        
        [parameter()]
        [pscredential]
        $Credential,

        [parameter()]
        [string]
        $CertificateThumbprint,

        [parameter()]
        [System.Management.Automation.Remoting.PSSessionOption]
        $SessionOption = (New-PSSessionOption -SkipCACheck -SkipCNCheck -SkipRevocationCheck)
    )

    #Try to reach the target first
    try
    {
        Write-Verbose "Testing Connection to Target: $TargetIpAddress"
        $null = Test-WSMan $TargetIpAddress -ErrorAction Stop
    }
    catch
    {
        Write-Warning "Could not reach target $TargetIpAddress. Skipping target..."
        return $false
    }

    try
    {
        if ($CertificateThumbprint)
        {
            Write-Verbose "Establishing sessions with Certificate $CertificateThumbprint"
            $targetCimSession = New-CimSession -CertificateThumbprint $CertificateThumbprint -SessionOption $SessionOption
            $targetPSSession = New-PSSession -CertificateThumbprint $CertificateThumbprint -SessionOption $SessionOption
        }
        elseif ($Credential)
        {
            Write-Verbose "Establishing sessions with Credential"
            $targetCimSession = New-CimSession -ComputerName $TargetIpAddress -Credential $Credential -ErrorAction Stop
            $targetPSSession = New-PSSession -ComputerName $TargetIpAddress -Credential $Credential -ErrorAction Stop
        }
    }
    catch
    {
        Write-Warning "Could not create Sessions to target: $targetIp. Skipping Target..."
        continue
    }

    try
    {
        $retrievedIpConfig = Get-NetIPConfiguration -CimSession $targetCimSession -Detailed
    }
    catch
    {
        Write-Warning "Could not retrieve actual IP configuration from target: $TargetIpAddress. Skipping target..."
        return $false
    }

    #Ensure MAC or Alias of the config's target adapter match the actual target's adapter
    if (! [string]::IsNullOrEmpty($TargetAdapter.PhysicalAddress))
    {
        if ($TargetAdapter.PhysicalAddress -notin $retrievedIpConfig.NetAdapter.LinkLayerAddress)
        {
            Write-Warning "MAC Address not found on target: $TargetIpAddress. Skipping target..."
            return $false
        }
    }
    else #Use alias if there is no MAC provided, but recommend using MAC!
    {
        if ($TargetAdapter.InterfaceAlias -notin $retrievedIpConfig.NetAdapter.InterfaceAlias)
        {
            Write-Warning "InterfaceAlias not found on target: $TargetIpAddress. Skipping target..."
            return $false
        }
    }

    return @{
        targetCimSession=$targetCimSession
        targetPSSession=$targetPSSession
    }
}

function Write-CompositeConfig
{
    param
    (
        [parameter(Mandatory)]
        $TargetConfig,

        [parameter(Mandatory)]
        [DscCompositeResource[]]
        $CompositeResource,

        [parameter(Mandatory)]
        [ValidateScript({Test-Path $_})]
        [string]
        $ConfigurationDirectoryPath,

        [parameter(Mandatory)]
        $StoredSecrets,

        [parameter()]
        [ValidateScript({Test-Path $_})]
        [string]
        $SecretsKeyPath,

        [parameter()]
        [string]
        $MofStorePath
    )

    $targetIP = $TargetConfig.TargetAdapter.NetworkAddress.IPAddressToString
    
    #Create the $MofOutputPath Directory if necessary
    if (! (Test-Path $MofStorePath))
    {
        $null = New-Item -Path $MofStorePath -Type Directory -Force -ErrorAction Stop
    }

    Write-Verbose "Generating Configuration Data"
    $ConfigData = @{
        AllNodes = @(
            @{
                NodeName                    = $targetIP
                PSDscAllowPlainTextPassword = $true
                PSDscAllowDomainUser        = $true
            }
        )
    }
    
    if ($TargetConfig.RoleList.Count -gt 1)
    {
        throw "Only a single role is supported when deploying from a comoposite resource"
    }

    $configFile = Get-ChildItem -Path $ConfigurationDirectoryPath -Filter "$($TargetConfig.RoleList).ps1"

    if (! $configFile)
    {
        throw "Configuration $($TargetConfig.RoleList) not found at $ConfigurationDirectoryPath"
    }
    
    Write-Verbose "Retrieve secrets key"
    if ($SecretsKeyPath)
    {
        [byte[]] $secretsKey = Get-Content $SecretsKeyPath -ErrorAction Stop
    }

    Write-Verbose "Retrieving resources and required data values"
    $configName = Get-DscConfigurationName -Path $configFile.FullName

    $configAst = [System.Management.Automation.Language.Parser]::ParseFile($configFile.FullName, [ref]$null, [ref]$Null)

    $keywords = $configAst.FindAll({($args[0] -is [System.Management.Automation.Language.DynamicKeywordStatementAst])}, $true).CommandElements.Value

    $resourceDeploymentList = $keywords.where({$_ -in $CompositeResource.Resource})

    $params = $resourceDeploymentList.ForEach({ $resource = $_ ; $CompositeResource.where({$_.Resource -eq $resource})}).Parameters.Name | Select-Object -Unique

    foreach ($param in $params)
    {
        if ($param -in $StoredSecrets.Secret)
        {
            $secret = $storedSecrets.where({$_.secret -eq $param})
            $securePW = ConvertTo-SecureString -String $secret.password -Key $secretsKey
            $ConfigData.AllNodes[0].Add($param, (New-Object System.Management.Automation.PSCredential ($secret.Username, $securePW)))
        }
        else
        {
            $ConfigData.AllNodes[0].Add($param, $TargetConfig.Variables.$param)
        }
    }

    Write-Verbose "Parsing Configuration"
    . "$($configFile.FullName)"

    #Add TargetConfig object to ConfigData
    $ConfigData.AllNodes[0] += @{TargetConfig = $TargetConfig}

    Write-Verbose "Compiling configuration with data"
    $null = . $configName -OutputPath $MofStorePath -ConfigurationData $ConfigData -Verbose

    return @{
        MofPath     = Join-Path -Path $MofStorePath -ChildPath "${targetIP}.mof"
        MetaMofPath = Join-Path -Path $MofStorePath -ChildPath "${targetIP}.meta.mof"
    }
}

function Write-Config
{
    param
    (
        [parameter(Mandatory)]
        $TargetConfig,

        [Parameter()]
        [pscredential]
        $DeploymentCredential,

        [Parameter()]
        [DscPartial[]]
        $PartialCatalog,

        [parameter()]
        [string]
        $MofOutputPath
    )

    $targetIP = $TargetConfig.TargetAdapter.NetworkAddress.IPAddressToString

    $targetPartials = $PartialCatalog.where({$_.Name -in $TargetConfig.RoleList})

    #Create the $MofOutputPath Directory if necessary
    if (! (Test-Path $MofOutputPath))
    {
        $null = New-Item -Path $MofOutputPath -Type Directory -Force -ErrorAction Stop
    }

    #Create the directory containing the targets partial mof output directories if necessary
    $compiledMofRootPath = Join-Path -Path $MofOutputPath -ChildPath $targetIP
    if (! (Test-Path $compiledMofRootPath))
    {
        $null = New-Item -Path $compiledMofRootPath -Type Directory -Force -ErrorAction Stop
    }
    
    foreach ($partial in $targetPartials)
    {
        Write-Output "    Compiling Partial: $($partial.Name)"

        #Create Partial mof output directory
        $compiledPartialMofPath = Join-Path -Path $compiledMofRootPath -ChildPath $partial.Name
        $null = Remove-Item -Path $compiledPartialMofPath -Recurse -Force -Confirm:$false -ErrorAction Ignore
        $null = New-Item -Path $compiledPartialMofPath -ItemType Directory -Force -ErrorAction Stop

        #Manually add TargetIP and MofOutPutPath params to ensure configs get compiled and published correctly
        $paramList = @{}
        #$paramList.Add("TargetIP", $targetIP)
        #$paramList.Add("OutPutPath", $compiledPartialMofPath)

        #Add in the secrets from the TargetConfig object if the param type is pscredential
        $partial.Parameters.Name.ForEach({
            if ($_ -in $TargetConfig.Secrets.Secret)
            {
                $paramList.Add($_, (New-Object System.Management.Automation.PSCredential ($TargetConfig.Secrets.Username, $TargetConfig.Secrets.Password)))
            }
            else
            {
                $paramList.Add($_, $TargetConfig.Variables.$_)
            }
        })

        #Compile the partial
        try
        {
            . "$($partial.Path)" @paramList
            
            $ConfigData = @{ 
                AllNodes = @(  
                    @{ 
                        NodeName = $TargetIP
                        PSDscAllowPlainTextPassword = $true
                        PSDscAllowDomainUser = $true
                        DeploymentCredential = $DeploymentCredential
                    }
                ) 
            }

            $null = . $partial.Name -ConfigurationData $ConfigData -OutputPath $compiledPartialMofPath
        }
        catch
        {
            $errormsg = $_.Exception.Message
            throw "Failed to compile: $($partial.PartialPath).`r`nActual Error: " + $errormsg
        }
    }
}

function Select-DscResource
{
    param
    (
        [parameter(Mandatory)]
        $TargetConfig,

        [Parameter()]
        [string]
        $DscResourcesPath,

        [Parameter()]
        [pscredential]
        $DeploymentCredential,

        [Parameter()]
        [DscPartial[]]
        $PartialCatalog
    )
    
    #Import PartialCatalog
    $targetPartials = $PartialCatalog.where({$_.Name -in $TargetConfig.RoleList})

    #Point to C:\Program Files\WindowsPowerShell\Modules
    $modulePath = "$env:ProgramFiles\WindowsPowerShell\Modules"

    #Retrive unique list of required DSC Resources
    $targetResources = $partialCatalog.Resources.Where({!([string]::IsNullOrEmpty($_))}) | Select-Object -Property ModuleName,ModuleVersion -Unique

    #Create an array of all DSC resources required
    $resourcesToCopy += $targetResources.ModuleName.foreach({
        return @{
            Path="$DscResourcesPath\$_"
            Destination="$modulePath\$_"
        }
    })
    
    return $resourcesToCopy
}

function Initialize-NodeLcm
{
    param
    (
        [parameter(Mandatory)]
        [hashtable]
        $TargetLcmSettings,
        
        [parameter(Mandatory)]
        [TargetConfig]
        $TargetConfig,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [ValidatePattern("[a-f0-9]{40}")]
        [string]
        $MofEncryptionCertThumbprint,

        [parameter()]
        [string]
        $MofStorePath
    )

    $targetIP = $TargetConfig.TargetAdapter.NetworkAddress.IPAddressToString

    # build local config
    [DSCLocalConfigurationManager()]
    Configuration TargetConfiguration
    {
        Node $targetIP
        {
            if ($MofEncryptionCertThumbprint)
            {
                Settings
                {
                    CertificateId                  = $MofEncryptionCertThumbprint
                    RebootNodeIfNeeded             = $TargetLcmSettings.RebootNodeIfNeeded
                    ConfigurationModeFrequencyMins = $TargetLcmSettings.ConfigurationModeFrequencyMins
                    ConfigurationMode              = $TargetLcmSettings.ConfigurationMode
                    AllowModuleOverWrite           = $TargetLcmSettings.AllowModuleOverwrite
                    ActionAfterReboot              = $TargetLcmSettings.ActionAfterReboot
                    RefreshMode                    = $TargetLcmSettings.RefreshMode
                    DebugMode                      = $TargetLcmSettings.DebugMode
                }
            }
            else
            {
                Settings
                {
                    RebootNodeIfNeeded             = $TargetLcmSettings.RebootNodeIfNeeded
                    ConfigurationModeFrequencyMins = $TargetLcmSettings.ConfigurationModeFrequencyMins
                    ConfigurationMode              = $TargetLcmSettings.ConfigurationMode
                    AllowModuleOverWrite           = $TargetLcmSettings.AllowModuleOverwrite
                    ActionAfterReboot              = $TargetLcmSettings.ActionAfterReboot
                    RefreshMode                    = $TargetLcmSettings.RefreshMode
                    DebugMode                      = $TargetLcmSettings.DebugMode
                }
            }
        }
    }

    $null = TargetConfiguration -OutputPath $MofStorePath -ErrorAction Stop
}

function Send-TargetLcm
{
    param
    (
        [parameter(Mandatory)]
        [CimSession]
        $TargetCimSession,

        [parameter()]
        [string]
        $MofStorePath
    )

    $null = Stop-DscConfiguration -CimSession $TargetCimSession -WarningAction Ignore
    while (($null = Get-DscLocalConfigurationManager -CimSession $TargetCimSession).LCMState -eq "Busy")
    {
        Start-Sleep 1
    }

    $null = Set-DscLocalConfigurationManager -CimSession $TargetCimSession -Path $MofStorePath -ErrorAction Stop

    $null = Remove-DscConfigurationDocument -Stage Pending -CimSession $TargetCimSession -ErrorAction Stop

    $null = Publish-DscConfiguration -Path $MofStorePath -CimSession $TargetCimSession -ErrorAction Stop
}

function Initialize-TargetLcm
{
    param
    (
        [parameter(Mandatory)]
        [hashtable]
        $TargetLcmSettings,
        
        [parameter(Mandatory)]
        [TargetConfig]
        $TargetConfig,

        [parameter(Mandatory)]
        [CimSession]
        $targetCimSession,

        [parameter()]
        [string]
        $CorePartial,

        [Parameter(ParameterSetName = 'MofEncryption')]
        [ValidatePattern("[a-f0-9]{40}")]
        [string]
        $MofEncryptionCertThumbprint,

        [parameter()]
        [pscredential]
        $Credential,

        [parameter()]
        [string]
        $MofOutputPath
    )

    $targetIP = $TargetConfig.TargetAdapter.NetworkAddress.IPAddressToString

    #Create the directory containing the targets partial mof output directories if necessary
    $compiledMofRootPath = Join-Path -Path $MofOutputPath -ChildPath $targetIP
    if (! (Test-Path $compiledMofRootPath))
    {
        $null = New-Item -Path $compiledMofRootPath -Type Directory -Force -ErrorAction Stop
    }

    # build local config
    [DSCLocalConfigurationManager()]
    Configuration TargetConfiguration
    {
        Node $targetIP
        {
            if ($MofEncryptionCertThumbprint)
            {
                Settings
                {
                    CertificateId                  = $MofEncryptionCertThumbprint
                    RebootNodeIfNeeded             = $TargetLcmSettings.RebootNodeIfNeeded
                    ConfigurationModeFrequencyMins = $TargetLcmSettings.ConfigurationModeFrequencyMins
                    ConfigurationMode              = $TargetLcmSettings.ConfigurationMode
                    AllowModuleOverWrite           = $TargetLcmSettings.AllowModuleOverwrite
                    ActionAfterReboot              = $TargetLcmSettings.ActionAfterReboot
                    RefreshMode                    = $TargetLcmSettings.RefreshMode
                    DebugMode                      = $TargetLcmSettings.DebugMode
                }
            }
            else
            {
                Settings
                {
                    RebootNodeIfNeeded             = $TargetLcmSettings.RebootNodeIfNeeded
                    ConfigurationModeFrequencyMins = $TargetLcmSettings.ConfigurationModeFrequencyMins
                    ConfigurationMode              = $TargetLcmSettings.ConfigurationMode
                    AllowModuleOverWrite           = $TargetLcmSettings.AllowModuleOverwrite
                    ActionAfterReboot              = $TargetLcmSettings.ActionAfterReboot
                    RefreshMode                    = $TargetLcmSettings.RefreshMode
                    DebugMode                      = $TargetLcmSettings.DebugMode
                }
            }

            foreach ($partial in $TargetConfig.RoleList)
            {

                $TargetPartial = New-LcmPartialConfiguration -PartialName $partial -TargetConfig $TargetConfig -CorePartial $CorePartial

                PartialConfiguration $partial
                {
                    RefreshMode = $TargetPartial.RefreshMode

                    DependsOn = $TargetPartial.DependsOn
                }
            }
        }
    }

    $null = TargetConfiguration -OutputPath $compiledMofRootPath -ErrorAction Stop
    
    $null = Stop-DscConfiguration -CimSession $targetCimSession -WarningAction Ignore
    while (($null = Get-DscLocalConfigurationManager -CimSession $targetCimSession).LCMState -eq "Busy")
    {
        Start-Sleep 1
    }

    $null = Set-DscLocalConfigurationManager -CimSession $targetCimSession -Path $compiledMofRootPath -ErrorAction Stop
}

<#
    .SYNOPSIS
        Resets the LCM on a specified target back to default values.

    .DESCRIPTION
        This function will create a CIM session to the remote target(s), output a generic LCM config with default values, and
        remove any DSC config documents.

    .PARAMETER TargetName
        Name or IP address of the target.

    .PARAMETER Credential
        Credential used to establish the CIM Session.

    .PARAMETER OutputPath
        Path to the directory to output the generic LCM config.

    .EXAMPLE
        Reset-TargetLcm -TargetName "192.0.0.30" -Credential (Get-Credential administrator)
#>
function Reset-TargetLcm
{
    param
    (
        [parameter(Mandatory)]
        [string[]]
        $TargetName,

        [parameter(Mandatory)]
        [pscredential]
        $Credential,

        [parameter()]
        [string]
        $OutputPath = "C:\Windows\Temp\$TargetName"
    )

    $cimSession = New-CimSession -ComputerName $TargetName -Credential $Credential -ErrorAction Stop

    [DSCLocalConfigurationManager()]
    Configuration NullConfig
    {
        Node $TargetName
        {
    
            Settings   
            {                              
                RebootNodeIfNeeded = $True
                ConfigurationModeFrequencyMins = 15
                ConfigurationMode = 'ApplyAndAutoCorrect'
            } 
        }
    }
    $null = NullConfig -OutputPath $OutputPath
    
    $null = Set-DscLocalConfigurationManager -CimSession $cimSession -Path $outputPath -Force

    $null = Remove-DscConfigurationDocument -Stage Current -CimSession $cimSession -Force
    $null = Remove-DscConfigurationDocument -Stage Pending -CimSession $cimSession -Force
    $null = Remove-DscConfigurationDocument -Stage Previous -CimSession $cimSession -Force
}

function Send-Config
{
    param
    (
        [parameter(Mandatory)]
        $TargetConfig,

        [parameter(Mandatory)]
        [CimSession]
        $TargetCimSession,

        [Parameter()]
        [pscredential]
        $DeploymentCredential,

        [Parameter()]
        [DscPartial[]]
        $PartialCatalog,

        [parameter()]
        [string]
        $MofOutputPath
    )

    $targetIP = $TargetConfig.TargetAdapter.NetworkAddress.IPAddressToString
        
    $targetPartials = $PartialCatalog.where({$_.Name -in $TargetConfig.RoleList})
    
    $compiledMofRootPath = Join-Path -Path $MofOutputPath -ChildPath $targetIP
    $compiledPartialMofs = Get-ChildItem -Path $compiledMofRootPath -Recurse -Filter "*.mof" -Exclude "*.meta.mof"
    $compiledPartialNames = Split-Path -Path $compiledPartialMofs.DirectoryName -Leaf

    $targetPartials = $compiledPartialNames.where({ $_ -in $TargetConfig.RoleList })
    
    foreach ($partial in $targetPartials)
    {
        $compiledPartialMofPath = Join-Path -Path $compiledMofRootPath -ChildPath $partial

        while ($lcmState -eq "Busy" -or $lcmState -like "*reboot")
        {
            Start-Sleep 1
            $lcmState = (Get-DscLocalConfigurationManager -CimSession $targetCimSession).LCMState
        }

        #$null = Invoke-Command -ScriptBlock { Publish-DscConfiguration -Path $using:MofOutputPath -ErrorAction Stop } -Session $targetPSSession
        $null = Publish-DscConfiguration -Path $compiledPartialMofPath -ComputerName $targetIP -Credential $DeploymentCredential -ErrorAction Stop
    }
}

function ConvertTo-ByteArray {

    param(
        [Parameter(Mandatory)]
        [System.Collections.BitArray]
        $BitArray
    )

    $numBytes = [System.Math]::Ceiling($BitArray.Count / 8)

    $bytes = New-Object byte[] $numBytes
    $byteIndex = 0 
    $bitIndex = 0

    for ($i = 0; $i -lt $BitArray.Count; $i++) {
        if ($BitArray[$i]){
            $bytes[$byteIndex] = $bytes[$byteIndex] -bor (1 -shl (7 - $bitIndex))
        }
        $bitIndex++
        if ($bitIndex -eq 8) {
            $bitIndex = 0
            $byteIndex++
        }
    }

    ,$bytes
}

<#
    New-PartialCatalog
#>
function New-PartialCatalog
{
    Param
    (
        [Parameter()]
        [string]
        $PartialDirectoryPath,

        [Parameter()]
        [string]
        $PartialCatalogPath
    )

    $partials = Get-ChildItem $PartialDirectoryPath
    
    $partialCatalog = @()
    foreach ($partial in $partials)
    {
        $partialConfigurationName = Get-DscConfigurationName -Path $partial.FullName

        #array wrapper to force array type even for single object returns to maintain data consistency
        $partialParams = @(Get-PSScriptParameterMetadata -Path $partial.FullName)

        $partialResources = Get-RequiredDscResourceList -Path $partial.FullName

        $partialValues = @{
            Name = $partialConfigurationName
            Path = $partial.FullName
            Resources = $partialResources
            Parameters = $partialParams
        }
        $partialObj = New-DscPartial @partialValues

        $partialCatalog += $partialObj
    }

    $json = ConvertTo-Json -InputObject $partialCatalog -Depth 7
    Out-File -FilePath $PartialCatalogPath -InputObject $json
}

function New-SecretsList
{
    param
    (
        [parameter(Mandatory)]
        $SecretsList,

        [parameter(Mandatory)]
        [byte[]]
        $Key
    )
    
    $uniqueSecrets = $SecretsList.secrets | Select-Object -Unique

    $storedSecrets = $uniqueSecrets.ForEach({
        $cred = Get-Credential -Message "Credential for `"$_`" secret:"
        @{Secret=$_;Username=$cred.UserName;Password=$cred.GetNetworkCredential().SecurePassword}
    })

    #if the password property is empty, the error will be caught and a random password will be generated
    foreach ($secret in $storedSecrets)
    {
        try
        {
            $secret.Password = ConvertFrom-SecureString $secret.Password -Key $Key
        }
        catch
        {
            $pw = ConvertTo-SecureString $([System.Web.Security.Membership]::GeneratePassword(78,34)) -AsPlainText -Force
            $secret.Password = ConvertFrom-SecureString $pw -Key $Key
        }
        finally
        {
            $null = $pw
        }
    }

    return $storedSecrets
}

function Register-Secrets
{
    param
    (
        [Parameter(Mandatory)]
        [string]
        $StoredSecretsPath,

        [Parameter(Mandatory)]
        [string]
        $SecretsKeyPath,

        [Parameter(Mandatory)]
        [DscCompositeResource[]]
        $CompositeResource
    )

    #Find parameter types of pscredential
    $secrets = $CompositeResource.ForEach(
    {
        @{ResourceName=$_.Resource;Secrets=$_.Parameters.Where({$_.StaticType -eq "System.Management.Automation.PSCredential"}).Name}
    })

    if (! (Test-Path $SecretsKeyPath))
    {
        Write-Verbose "Generating password key"
    
        $BitArray = New-Object System.Collections.BitArray(256)
        for ($i = 0; $i -lt 256 ;$i++)
        {
            $BitArray[$i] = [bool](Get-Random -Maximum 2)
        }
        [Byte[]] $secretsKey = ConvertTo-ByteArray -BitArray $BitArray
        $secretsKey | Out-File $SecretsKeyPath
        Write-Verbose "Key located at: $SecretsKeyPath"
    }

    try
    {
        Write-Verbose "Importing Key to test validity"
        [byte[]]$secretsKey = Get-Content $SecretsKeyPath
    }
    catch
    {
        throw "Could not import secrets key: $SecretsKeyPath"
    }
    

    if (!(Test-Path $StoredSecretsPath))
    {
        Write-Verbose "Could not find $StoredSecretsPath. Generating secrets file."
        $newSecrets = New-SecretsList -SecretsList $secrets -Key $secretsKey
        $null = ConvertTo-Json $newSecrets | Out-File $StoredSecretsPath
    }

    try
    {
        [array]$jsonSecrets = ConvertFrom-Json ([string](Get-Content $StoredSecretsPath))
        $storedSecrets = $jsonSecrets.ForEach({@{username=$_.username;password=$_.password;secret=$_.secret}})
    }
    catch
    {
        throw "Could not import stored secrets."
    }

    #Check for missing secrets by looking for any stored secrets not in the unique secrets list generated from the composite
    foreach ($secret in $storedSecrets)
    {
        if ($secret.Secret -notin ($composite.Parameters.where({$_.StaticType -eq 'System.Management.Automation.PSCredential'}).Name))
        {
            Write-Verbose "Secret $_ missing from stored secrets."
            $missingSecrets += New-SecretsList -SecretsList $secret
        }
    }

    if ($missingSecrets)
    {
        $missingSecrets.foreach({ $storedSecrets += $_ })
        $null = ConvertTo-Json $newSecrets | Out-File $StoredSecretsPath
    }

    return $storedSecrets
}

function New-SecretsFile
{
    param
    (
        [Parameter()]
        [string]
        $PartialCatalogPath,

        [Parameter()]
        [string]
        $PartialSecretsPath,

        [Parameter()]
        [string]
        $StoredSecretsPath,

        [Parameter()]
        [string]
        $SecretsKeyPath
    )

    #import the partial catalog
    $partialCatalog = [DscPartial[]](ConvertFrom-Json ([string](Get-Content $PartialCatalogPath)))

    #Find parameter types of pscredential
    #$partialSecrets = $partialCatalog.Parameters.Where({$_.Attributes.Name -eq "System.Management.Automation.PSCredential"})
    $partialSecrets = $partialCatalog.ForEach(
    {
        [ordered]@{Partial=$_.Name;Secrets=$_.Parameters.Where({$_.StaticType -eq "System.Management.Automation.PSCredential"}).Name}
    })

    #Export the file for reference
    $null = ConvertTo-Json $partialSecrets | Out-File $PartialSecretsPath

    #region Generate password key
    $BitArray = New-Object System.Collections.BitArray(256)
    for ($i = 0; $i -lt 256 ;$i++)
    {
        $BitArray[$i] = [bool](Get-Random -Maximum 2)
    }
    [Byte[]] $key = ConvertTo-ByteArray -BitArray $BitArray
    $key | Out-File $SecretsKeyPath
    #endregion

    #Retrieve list of unique secrets
    $uniqueSecrets = $partialSecrets.Secrets | Select-Object -Unique

    #Request input from user
    $storedSecrets = $uniqueSecrets.ForEach({
        $cred = Get-Credential -Message "Credential for `"$_`" secret:"
        @{Secret=$_;Username=$cred.UserName;Password=$cred.GetNetworkCredential().SecurePassword}
    })

    #if the password property is empty, the error will be caught and a random password will be generated
    foreach ($secret in $storedSecrets)
    {
        try
        {
            $secret.Password = ConvertFrom-SecureString $secret.Password -Key $key
        }
        catch
        {
            $pw = ConvertTo-SecureString $([System.Web.Security.Membership]::GeneratePassword(78,34)) -AsPlainText -Force
            $secret.Password = ConvertFrom-SecureString $pw -Key $key
        }
        finally
        {
            $null = $pw
        }
    }

    $null = ConvertTo-Json $storedSecrets | Out-File $StoredSecretsPath
}

<#
    New-NodeDefinitionFile - creates datafile with required empty parameter values from the template
#>
function New-NodeDefinitionFile
{
    param
    (
        [Parameter()]
        [string]
        $PartialCatalogPath,

        [Parameter()]
        [string]
        $NodeTemplatePath,
        
        [Parameter()]
        [string]
        $NodeDefinitionFilePath
    )

    #Don't allow DataFile overwrites.  We should not allow regression.
    if (Test-Path $NodeDefinitionFilePath)
    {
        throw "Data file exists, remove file to create new data file."
    }

    #import the partial catalog
    $partialCatalog = [DscPartial[]](ConvertFrom-Json ([string](Get-Content $PartialCatalogPath)))

    #import the template definition file
    $nodeDefinition = Invoke-Command -ScriptBlock $ExecutionContext.InvokeCommand.NewScriptBlock($NodeTemplatePath)

    Export-NodeDefinitionFile -NodeDefinition $nodeDefinition -NodeDefinitionFilePath $NodeDefinitionFilePath -PartialCatalog $partialCatalog
}

<#
    Update-NodeDefinitionFile - Merges existing datafile with partial catalog to include any partial parameter changes
#>
function Update-NodeDefinitionFile
{
    param
    (
        [Parameter()]
        [string]
        $PartialCatalogPath,

        [Parameter()]
        [string]
        $NodeDefinitionFilePath,

        [Parameter()]
        [string]
        $UpdateNodeDefinitionFilePath
    )

    #Import the partial catalog
    $partialCatalog = ConvertFrom-Json ([string](Get-Content $PartialCatalogPath))

    #Don't allow overwrites.  We should not allow regression.
    if (Test-Path $UpdateNodeDefinitionFilePath)
    {
        throw "Data file exists, remove file to create new data file."
    }

    #Import existing Node Definition File
    $nodeDefinition = . $NodeDefinitionFilePath

    Export-NodeDefinitionFile -NodeDefinition $nodeDefinition -UpdateNodeDefinitionFilePath $UpdateNodeDefinitionFilePath -PartialCatalog $partialCatalog
}

#region Class Definitions

Class DscCompositeResource
{
    [string]
    $Resource
    
    [array]
    $Resources

    [array]
    $Parameters

    DscCompositeResource ()
    {}

    DscCompositeResource ( [string]$Resource, [array]$Resources, [array]$Parameters)
    {
        $this.Resource = $Resource
        $this.Resources = $Resources
        $this.Parameters = $Parameters
    }
}

Class DscPartial
{
    [string]
    $Name

    [string]
    $Path
    
    [array]
    $Resources

    [array]
    $Parameters

    DscPartial ()
    {}

    DscPartial ( [string]$Name, [string]$Path, [array]$Resources, [array]$Parameters)
    {
        $this.Name = $Name
        $this.Path = $Path
        $this.Resources = $Resources
        $this.Parameters = $Parameters
    }
}

<##>
Class TargetConfig
{
    [string]
    $ConfigName

    [TargetAdapter]
    $TargetAdapter
    
    [array]
    $RoleList

    [boolean]
    $ContentHost

    [string]
    $ContentStorePath

    [hashtable[]]
    $Dependencies

    [hashtable[]]
    $Secrets
    
    [array]
    $Properties

    [array]
    $Variables

    TargetConfig ()
    {
        $this.Properties = ($this | Get-Member -MemberType Properties).Name
    }

    TargetConfig ( [string] $ConfigName, [ipaddress] $TargetAdapter, [array] $RoleList, [string] $ContentHost, [string] $ContentStorePath, [hashtable[]] $Dependencies, [string[]]$Secrets )
    {
        $this.ConfigName = $ConfigName
        $this.TargetAdapter = $TargetAdapter
        $this.RoleList = $RoleList -split ','
        $this.ContentHost = $ContentHost
        $this.ContentStorePath = $ContentStorePath
        $this.Dependencies = $Dependencies
        $this.Secrets = $Secrets
        $this.Properties = ($this | Get-Member -MemberType Properties).Name
    }

    [void] AddVariable ( [hashtable[]] $Variables)
    {
        $this.Variables += $Variables
    }
}

<#
    .Synopsis
    Defines Node class
#>
Class Node
{
    [guid]
    $NodeId

    [string]
    $Name

    [string]
    $Type

    [TargetConfig[]]
    $Configs

    [Node[]]
    $ParentList

    [Node[]]
    $ChildList

    # Constructors
    Node ()
    {}

    Node ( [guid] $NodeId, [string] $Name, [string] $Type )
    {
        $this.NodeId = $NodeId
        $this.Name   = $Name
        $this.Type   = $Type
    }

    # Methods
    [void] AddConfig ( [TargetConfig] $TargetConfig )
    {
        $this.Configs += $TargetConfig
    }

    [void] AddParent ( [Node] $Parent ) #to child
    {
        if (! ($this -in $Parent.ChildList))
        {
            $Parent.ChildList += $this
        }
        if (! ($Parent -in $this.ParentList))
        {
            $this.ParentList += $Parent
        }
    }

    [void] AddChild ( [Node] $Child )
    {
        if (! ($Child -in $this.ChildList))
        {
            $this.ChildList += $Child
        }
        if (! ($this -in $Child.ParentList))
        {
            $Child.ParentList += $this
        }
    }
}

class DscLcm
{
    [int]
    $ConfigurationModeFrequencyMins
    
    [bool]
    $RebootNodeIfNeeded
    
    [ConfigurationMode]
    $ConfigurationMode
    
    [ActionAfterReboot]
    $ActionAfterReboot
    
    [RefreshMode]
    $RefreshMode
    
    [string]
    $CertificateId
    
    #[guid]
    #$ConfigurationId
    
    [int]
    $RefreshFrequencyMins
    
    [bool]
    $AllowModuleOverwrite
    
    [DebugMode]
    $DebugMode
    
    [int]
    $StatusRetentionTimeInDays
    
    [array]
    $PartialConfigurations

    # Constructors
    DscLcm ()
    {
        $this.ActionAfterReboot = "ContinueConfiguration"
        $this.RebootNodeIfNeeded = $true
        $this.ConfigurationModeFrequencyMins = 15
        $this.ConfigurationMode = "ApplyAndAutoCorrect"
        $this.RefreshMode = "Push"
    }

    DscLcm ([hashtable]$Properties)
    {
        $this.ConfigurationModeFrequencyMins = $Properties.ConfigurationModeFrequencyMins
        $this.RebootNodeIfNeeded = $Properties.RebootNodeIfNeeded
        $this.ConfigurationMode  = $Properties.ConfigurationMode
        $this.ActionAfterReboot = $Properties.ActionAfterReboot
        $this.RefreshMode = $Properties.RefreshMode
        $this.CertificateId = $Properties.CertificateId
        $this.RefreshFrequencyMins = $Properties.RefreshFrequencyMins
        $this.AllowModuleOverwrite = $Properties.AllowModuleOverwrite
        $this.DebugMode = $Properties.DebugMode
        $this.StatusRetentionTimeInDays = $Properties.StatusRetentionTimeInDays
        $this.PartialConfigurations = $Properties.PartialConfigurations
    }

    DscLcm ( 
        [int] $ConfigurationModeFrequencyMins, 
        [bool] $RebootNodeIfNeeded,
        [ConfigurationMode] $ConfigurationMode, 
        [ActionAfterReboot] $ActionAfterReboot,
        [RefreshMode] $RefreshMode,
        [string] $CertificateId,
        [int] $RefreshFrequencyMins,
        [bool] $AllowModuleOverwrite,
        [DebugMode] $DebugMode,
        [int] $StatusRetentionTimeInDays,
        [array] $PartialConfigurations
    )
    {
        $this.ConfigurationModeFrequencyMins = $ConfigurationModeFrequencyMins
        $this.RebootNodeIfNeeded = $RebootNodeIfNeeded
        $this.ConfigurationMode  = $ConfigurationMode
        $this.ActionAfterReboot = $ActionAfterReboot
        $this.RefreshMode = $RefreshMode
        $this.CertificateId = $CertificateId
        $this.RefreshFrequencyMins = $RefreshFrequencyMins
        $this.AllowModuleOverwrite = $AllowModuleOverwrite
        $this.DebugMode = $DebugMode
        $this.StatusRetentionTimeInDays = $StatusRetentionTimeInDays
        $this.PartialConfigurations = $PartialConfigurations
    }
}

class LcmPartialConfiguration
{
    [string[]]
    $ConfigurationSource
    
    [System.Collections.Generic.List[string]]
    $DependsOn
    
    [string]
    $Description
    
    [string[]]
    $ExclusiveResources
    
    [RefreshMode]
    $RefreshMode
    
    [string[]]
    $ResourceModuleSource

    # Constructors
    LcmPartialConfiguration ()
    { }
}

class TargetAdapter
{
    [uint32]
    $InterfaceIndex

    [string]
    $InterfaceAlias
  
    [string]
    $PhysicalAddress
  
    [ipaddress[]]
    $NetworkAddress

    [uint16]
    $SubnetBits

    [ipaddress[]]
    $DnsAddress

    [ipaddress]
    $Gateway

    [string]
    $AddressFamily

    [string]
    $NetworkCategory

    [string]
    $Description
  
    [string]
    $Status

    [uint64]
    $Speed
  
    [uint16]
    $VlanID

  # Constructors
    TargetAdapter ( )
    { }

    TargetAdapter ([hashtable]$Properties)
    {
        $this.InterfaceIndex = $Properties.InterfaceIndex
        $this.InterfaceAlias = $Properties.InterfaceAlias
        $this.PhysicalAddress  = $Properties.PhysicalAddress
        $this.NetworkAddress = $Properties.NetworkAddress
        $this.SubnetBits = $Properties.SubnetBits
        $this.DnsAddress = $Properties.DnsAddress
        $this.Gateway = $Properties.Gateway
        $this.AddressFamily = $Properties.AddressFamily
        $this.NetworkCategory = $Properties.NetworkCategory
        $this.Description = $Properties.Description
        $this.Status = $Properties.Status
        $this.Speed = $Properties.Speed
        $this.VlanID = $Properties.VlanID
    }
    
TargetAdapter ( 
        [uint32] $InterfaceIndex, 
        [string] $InterfaceAlias,
        [string] $PhysicalAddress, 
        [ipaddress[]] $NetworkAddress,
        [uint16] $SubnetBits,
        [ipaddress[]] $DnsAddress,
        [ipaddress] $Gateway,
        [string] $AddressFamily,
        [string] $NetworkCategory,
        [string] $Description,
        [string] $Status,
        [uint64] $Speed,
        [uint16] $VlanID
    )
    {
        $this.InterfaceIndex = $InterfaceIndex
        $this.InterfaceAlias = $InterfaceAlias
        $this.PhysicalAddress  = $PhysicalAddress
        $this.NetworkAddress = $NetworkAddress
        $this.SubnetBits = $SubnetBits
        $this.DnsAddress = $DnsAddress
        $this.Gateway = $Gateway
        $this.AddressFamily = $AddressFamily
        $this.NetworkCategory = $NetworkCategory
        $this.Description = $Description
        $this.Status = $Status
        $this.Speed = $Speed
        $this.VlanID = $VlanID
    }
}

Enum ConfigurationMode
{
    ApplyAndAutoCorrect
    ApplyOnly
    ApplyAndMonitor
}

Enum ActionAfterReboot
{
    ContinueConfiguration
    StopConfiguration
}

Enum RefreshMode
{
    Push
    Disabled
    Pull
}

Enum DebugMode
{
    None
    ForceModuleImport
    All
}
#endregion Class Definitions

#region Class Instantiation
function New-DscCompositeResource
{
    param
    (
        [parameter(Mandatory)]
        [string]
        $Resource,

        [parameter()]
        [hashtable[]]
        $Resources,

        [parameter()]
        [hashtable[]]
        $Parameters
    )

    $DscCompositeResource = [DscCompositeResource]::new()

    $DscCompositeResource.Resource = $Resource
    $DscCompositeResource.Resources = $Resources
    $DscCompositeResource.Parameters = $Parameters

    return $DscCompositeResource
}

function New-DscPartial
{
    param
    (
        [parameter(Mandatory)]
        [string]
        $Name,

        [parameter(Mandatory)]
        [string]
        $Path,
    
        [parameter()]
        [hashtable[]]
        $Resources,

        [parameter()]
        [hashtable[]]
        $Parameters
    )

    $DscPartial= [DscPartial]::new()

    $DscPartial.Name = $Name
    $DscPartial.Path = $Path
    $DscPartial.Resources = $Resources
    $DscPartial.Parameters = $Parameters

    return $DscPartial
}

function New-Node
{
    param
    (
        [parameter(Mandatory)]
        [string]
        $Name,
    
        [parameter(Mandatory)]
        [guid]
        $NodeId,

        [parameter(Mandatory)]
        [string]
        $Type
    )

    $Node = [Node]::new()

    $Node.Name = $Name
    $Node.NodeId = $NodeId
    $Node.Type = $Type

    return $Node
}

function New-TargetConfig
{
    param
    (
        [parameter()]
        [TargetConfig]
        $Properties
    )

    $TargetConfig = [TargetConfig]::new()

    if ($Properties)
    {
        foreach ($property in $TargetConfig.Properties)
        {
            $TargetConfig.$property = $Properties.$property
        }
    }

    return $TargetConfig
}

function New-DscLcm
{
    param
    (
        [parameter()]
        [hashtable]
        $Properties
    )

    $newDscLcm = [DscLcm]::new($Properties)

    return $newDscLcm
}

function New-LcmPartialConfiguration
{
    param
    (
        [parameter()]
        [string]
        $PartialName,

        [parameter()]
        [string]
        $CorePartial,

        [parameter()]
        [TargetConfig]
        $TargetConfig
    )

    $newLcmPartial = [LcmPartialConfiguration]::new()

    #Add the CorePartial to each Partial dependency list unless it's itself
    $partialDependenciesList = $CorePartial.Where({$_ -ne $PartialName})

    #This next line creates an empty object that can't be seen when calling from the console. It returns
    #a null value when called ($partialDependenciesList[1] -eq $null returns $true), however the .ForEach()
    #in the following else statement was returning twice, creating an empty [PartialConfiguration] entry...
    $partialDependenciesList += $TargetConfig.Dependencies.Where({$_.Partial -eq $partial}).DependsOn
                
    if (! ($partial -eq $CorePartial))
    {
        #...so I had to add the "Where({![string]::IsNullOrEmpty($_)})." nonsense below to remove the empty object - I'm so sorry
        $partialDependsOnProperty = $partialDependenciesList.Where({![string]::IsNullOrEmpty($_)}).ForEach({"[PartialConfiguration]$_"})

        $lcmDependsOnProperty = $null
        $partialDependsOnProperty.ForEach({[System.Collections.Generic.List[string]]$lcmDependsOnProperty += "$_"})

        $newLcmPartial.DependsOn = $lcmDependsOnProperty
    }
    else
    {
        
    }
   
    return $newLcmPartial
}


<#
    .SYNOPSIS
        Creates a new TargetAdapter object.

    .DESCRIPTION
        See synopsis.

    .SAMPLE
        New-TargetAdapter -InterfaceAlias Ethernet -NetworkAddress 192.0.0.253 -SubnetBits 24 -DnsAddress 127.0.0.1 -AddressFamily IPv4 -Description test
#>
function New-TargetAdapter
{
    param
    (
        [Parameter()]
        [uint32]
        $InterfaceIndex,

        [Parameter()]
        [string]
        $InterfaceAlias,
  
        [Parameter()]
        [string]
        $PhysicalAddress,
  
        [Parameter()]
        [ipaddress]
        $NetworkAddress,

        [Parameter()]
        [int16]
        $SubnetBits,

        [Parameter()]
        [ipaddress[]]
        $DnsAddress,

        [Parameter()]
        [ipaddress]
        $Gateway,

        [Parameter()]
        [ValidateSet("IPv4","IPv6")]
        [string]
        $AddressFamily,

        [Parameter()]
        [ValidateSet("DomainAuthenticated","Private","Public")]
        [string]
        $NetworkCategory,
        
        [Parameter()]
        [string]
        $Description,

        [Parameter()]
        [string]
        $Status,
        
        [Parameter()]
        [uint64]
        $Speed,
  
        [Parameter()]
        [uint16]
        $VlanID
    )

    [hashtable]$nicProperties = $PSBoundParameters
    $nicProperties.Remove("Verbose")
    
    $targetAdapter = [TargetAdapter]::new($nicProperties)

    foreach ($property in $PSBoundParameters.GetEnumerator())
        {
            $targetAdapter.($property.key) = $property.value
        }
   
    return $targetAdapter
}
#endregion Class Instantiation
