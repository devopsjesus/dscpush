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
        [string]
        $ContentStoreRootPath,
    
        [Parameter()]
        [string]
        $SettingsPath,

        [Parameter()]
        [string]
        $PartialCatalogPath,
    
        [Parameter()]
        [string]
        $PartialStorePath,

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
            PartialStorePath = $PartialStorePath
            PartialCatalogPath = $PartialCatalogPath
        }
        New-PartialCatalog @NewPartialCatalogParams
    }

    if ($GenerateSecrets)
    {
        Write-Verbose "Geneterating Secrets files"
        $newSecretsFileParams = @{
            ContentStoreRootPath = $ContentStoreRootPath
            PartialCatalogPath = $PartialCatalogPath
            SettingsPath = $SettingsPath
        }
        New-SecretsFile @newSecretsFileParams
    }

    if ($GenerateNewNodeDefinitionFile)
    {
        Write-Verbose "Generating New Node Definition File from template"
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
        Write-Verbose "Updating Existing Node Definition File with Partial Catalog updates"
        $UpdateNodeDefinitionFileParams = @{
            ContentStoreRootPath = $ContentStoreRootPath
            PartialCatalogPath = $PartialCatalogPath
            NodeDefinitionFilePath = $NodeDefinitionFilePath
            UpdateNodeDefinitionFilePath = $UpdateNodeDefinitionFilePath
        }
        Update-NodeDefinitionFile @UpdateNodeDefinitionFileParams
    }
}

function Publish-TargetConfig
{
    param
    (
        [Parameter(Mandatory)]
        [pscredential]
        $DeploymentCredential,

        [Parameter(Mandatory)]
        [string]
        $ContentStoreRootPath,

        [Parameter(Mandatory)]
        [string]
        $ContentStoreModulePath,

        [Parameter(Mandatory)]
        [string]
        $ContentStoreDscResourceStorePath,

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

    #Import the partial catalog
    $partialCatalog = Import-PartialCatalog -PartialCatalogPath $PartialCatalogPath -ErrorAction Stop

    #Import the Node Definition file
    $targetConfigs = . $NodeDefinitionFilePath

    #Add dependencies and secrets to the Configs
    $partialProperties = @{
        PartialDependenciesFilePath = $PartialDependenciesFilePath
        PartialSecretsPath = $PartialSecretsPath
        StoredSecretsPath = $StoredSecretsPath
        SecretsKeyPath = $SecretsKeyPath
        TargetConfigs = ([ref]$targetConfigs)
    }
    $corePartial = Add-PartialProperties @partialProperties

    #Setup Deployment Environment
    $initializeParams = @{
        ContentStoreRootPath = $ContentStoreRootPath
        ContentStoreModulePath = $ContentStoreModulePath
        ContentStoreDscResourceStorePath = $ContentStoreDscResourceStorePath
        TargetIPList = $targetConfigs.Configs.TargetAdapter.NetworkAddress.IPAddressToString
        DeploymentCredential = $DeploymentCredential
        SanitizeModulePaths = $SanitizeModulePaths.IsPresent
    }
    $currentTrustedHost = Initialize-DeploymentEnvironment @initializeParams

    #Deploy Configs
    foreach ($config in $targetConfigs.Configs)#.where({$_.configname -eq 'dscpushch'}))
    {
        Write-Output "Preparing Config: $($config.ConfigName)"

        Write-Verbose "  Testing Connection to Target Adapter (Target IP: $($config.TargetAdapter.NetworkAddress))"
        $targetIp = $config.TargetAdapter.NetworkAddress.IpAddressToString
        $sessions = Connect-TargetAdapter -TargetIpAddress $targetIp -TargetAdapter $config.TargetAdapter -Credential $DeploymentCredential
        if ($sessions -eq $false)
        {
            continue #skip the rest of the config if we can't connect
        }

        if ($CompilePartials.IsPresent)
        {
            Write-Output "  Compiling and writing Config to directory: $mofOutputPath"
            $configParams = @{
                TargetConfig = $config
                ContentStoreRootPath = $ContentStoreRootPath
                DeploymentCredential = $DeploymentCredential
                PartialCatalog = $PartialCatalog
                MofOutputPath = $mofOutputPath
            }
            Write-Config @configParams
        }

        $fileCopyList = @()
        if ($config.ContentHost -and $CopyContentStore.IsPresent)
        {
            Write-Output "  Preparing Content Store for remote copy"
            $fileCopyList += @{
                Path=$ContentStoreRootPath
                Destination=$ContentStoreDestPath
            }
        }

        if ($ForceResourceCopy.IsPresent)
        {
            Write-Output "  Preparing required DSC Resources for remote copy"
            $copyResourceParams = @{
                TargetConfig = $config
                ContentStoreDscResourceStorePath = $ContentStoreDscResourceStorePath
                DeploymentCredential = $DeploymentCredential
                PartialCatalog = $partialCatalog
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
                TargetCertPath = "$($config.Variables.LocalSourceStore)\$TargetCertDirName"
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
            ContentStoreRootPath = $ContentStoreRootPath
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
        Returns the parameter block of a PowerShell script.

    .PARAMETER DscConfigurationPath
        Path to the PowerShell script.
#>
function Get-PSScriptParameterMetadata
{
    Param
    (
        [Parameter(mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern(".*.ps1$")]
        [string]
        $DscConfigurationPath
    )

    if($(Test-Path -Path $DscConfigurationPath) -eq $false)
    {
        Throw "Failed to access $DscConfigurationPath"
    }

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($DscConfigurationPath, [ref]$null, [ref]$null)

    $parameterASTs = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.ParameterAst]}, $true)
    
    $returnObjs = $parameterASTs.where({$_.Name.VariablePath.UserPath -notin @("TargetName","OutputPath")}) | Select-Object Attributes, Name, StaticType

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
        Analyze DSC Configuration for the imported resources.

    .PARAMETER DscConfigurationPath
        Path to DSC Configuration.
#>
function Get-ImportedDscResource
{
    Param
    (
        [Parameter(mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern(".*.ps1$")]
        [string]
        $DscConfigurationPath 
    )
    
    # add a short C# function because PowerShell doesn't handle removing the parents from a commandElementAst very well
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Language;

public class AstHelper
{
    public IEnumerable<CommandElementAst> StripParent(List<CommandElementAst> commandElementAsts)
    {
        var asts = new List<CommandElementAst>();

        foreach (var ast in commandElementAsts)
        {
            asts.Add(ast.Copy() as CommandElementAst);
        }

        return asts;
    }
}
"@ 
    
    # parse powershell to AST tree
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($DscConfigurationPath, [ref]$null, [ref]$null)

    # find every Import-DscResource cmdlet used
    $dyanmicKeywordStatementAsts = $ast.FindAll({($args[0] -is [System.Management.Automation.Language.DynamicKeywordStatementAst]) -and ($args[0].CommandElements.Value -contains 'Import-DscResource')}, $true) 
    
    $resourceList = @()

    foreach($dyanmicKeywordStatementAst in $dyanmicKeywordStatementAsts)
    {   
        # strip the parent from each commandElement of the DynamicKeywordStatementAst because creating a commandAst requires the elemets have no parents 
        $astHelper = New-Object AstHelper
    
        $noParents = $astHelper.StripParent($dyanmicKeywordStatementAst.CommandElements)
        
        # convert to commandAst so we can use the StaticParameterbinder and not have to do it ourself
        $commandAst = [System.Management.Automation.Language.CommandAst]::new($dyanmicKeywordStatementAst.Extent, $noParents, [System.Management.Automation.Language.TokenKind]::Unknown, $null)
    
        $boundParams = [System.Management.Automation.Language.StaticParameterBinder]::BindCommand($commandAst, $true)
    
        # Check each way to add a resource and add them to the list if found
        $resourceArray = @()

        if($null -ne $boundParams.BoundParameters['ModuleName'])
        {
            $resourceArray += $boundParams.BoundParameters['ModuleName'].Value.FindAll({$args[0] -is [System.Management.Automation.Language.ConstantExpressionAst]}, $true).Value
        }
    
        if($null -ne $boundParams.BoundParameters['Module'])
        {
            $resourceArray += $boundParams.BoundParameters['Module'].Value.FindAll({$args[0] -is [System.Management.Automation.Language.ConstantExpressionAst]}, $true).Value
        }
    
        if($null -ne $boundParams.BoundParameters['Name'])
        {
            $names = $boundParams.BoundParameters['Name'].Value.FindAll({$args[0] -is [System.Management.Automation.Language.ConstantExpressionAst]}, $true).Value
            Throw "Name parameter for Import-DscResource is not supported. Please use -ModuleName $names in $DscPartialPath"
        }

        $resourceList += $resourceArray.where({$_ -ne 'PSDesiredStateConfiguration'})
    }

    $resources = $resourceList -join ","

    return $resources
}

<#
    .SYNOPSIS
        Analysis DSC Configuration for the configuration names.

    .PARAMETER DscConfigurationPath
        Path to DSC Configuration.
#>
function Get-DscConfigurationName
{
    Param
    (
        [Parameter(mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidatePattern(".*.ps1$")]
        [string]
        $DscConfigurationPath
    )

    if($(Test-Path -Path $DscConfigurationPath) -eq $false)
    {
        Throw "Failed to access $DscConfigurationPath"
    }

    $ast = [System.Management.Automation.Language.Parser]::ParseFile($DscConfigurationPath, [ref]$null, [ref]$Null)

    # find all AST of type ConfigurationDefinitionAST, this will allow us to find the name of each config
    $configurationDefinitionAsts = $ast.FindAll({$args[0] -is [System.Management.Automation.Language.ConfigurationDefinitionAst]}, $true)

    # isntance name is the name of the config
    $configurationDefinitionAsts.InstanceName.Value
}

function Register-DscPartialCatalog
{
    param
    (
        [Parameter(Mandatory)]
        [string]
        $PartialStore
    )

    $partials = Get-ChildItem $PartialStore
    
    $partialCatalog = @()
    foreach ($partial in $partials)
    {
        $partialConfigurationName = Get-DscConfigurationName -DscConfigurationPath $partial.FullName

        #array wrapper to force array type even for single object returns to maintain data consistency
        $partialParams = @(Get-PSScriptParameterMetadata -DscConfigurationPath $partial.FullName)

        $partialResources = Get-ImportedDscResource -DscConfigurationPath $partial.FullName

        $partialValues = @{
            Name = $partialConfigurationName
            Path = $partial.FullName
            Resources = $partialResources
            Parameters = $partialParams
        }
        $partialObj = New-DscPartial  @partialValues

        $partialCatalog += $partialObj
    }

    return $partialCatalog
}

function Import-PartialCatalog
{
    param
    (
        [Parameter()]
        [string]
        $PartialCatalogPath
    )
    
    $partialCatalogObject = ConvertFrom-Json ([string](Get-Content $PartialCatalogPath))

    [DscPartial[]]$partialCatalog = $partialCatalogObject

    return $partialCatalog
}

function Get-PartialMetaData
{
    param
    (
        [Parameter()]
        [psobject]
        $TargetConfig,

        [Parameter()]
        [DscPartial[]]
        $PartialCatalog
    )

    $partialList = @()

    foreach ($partial in $TargetConfig)
    {
        $catalogItem = $PartialCatalog.where({$_.Name -eq $partial})

        if ($catalogItem)
        {
            $partialList += $catalogItem
        }
        else
        {
            throw "Partial $partial not found at $($partial.FullName)"
        }
    }

    return $partialList
}

<#
    .SYNOPSIS
        Recursively produces a string output of hashtable contents (currently hashtable and array objs)
        Must start with a Hashtable - TODO: add similar function, but starting with array

    .PARAMETER InputObject
#>
Function ConvertFrom-Hashtable
{
    param
    (
        [parameter(Mandatory)]
        [hashtable]
        $InputObject
    )

    $hashstr = "@{"
            
    $keys = $InputObject.keys

    foreach ($key in $keys)
    { 
        $value = $InputObject[$key]
            
        if ($value.GetType().Name -like "*hashtable*")
        {
            $hashstr += $key + "=" + $(ConvertFrom-Hashtable $value) + ";"
        }
        elseif ($value.GetType().BaseType -like "*array*")
        {
            $arrayString = "@("

            foreach ($arrayValue in $value)
            {
                if ($arrayValue.GetType().Name -like "*hashtable*")
                {
                    $parsedValue = ConvertFrom-Hashtable $arrayValue
                }
                else
                {
                    $parsedValue = "`"$arrayValue`"" + "," 
                }
                $arrayString += $parsedValue
            }

            $arrayString = $arrayString.Trim(",")
            $arrayString += ")"

            $hashstr += $key + "=" + $arrayString + ";" 
        }
        elseif ($key -match "\s") 
        {
            $hashstr += "`"$key`"" + "=" + "`"$value`"" + ";"
        }
        else {
            $hashstr += $key + "=" + "`"$value`"" + ";" 
        } 
    }
            
    $hashstr += "};"

    return $hashstr
}
#endregion

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
    $storedSecrets = ConvertFrom-Json ([string](Get-Content $StoredSecretsPath))
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

        [Parameter()]
        [string]
        $ContentStoreModulePath,

        [Parameter()]
        [string]
        $ContentStoreDscResourceStorePath,

        [Parameter(Mandatory)]
        [array]
        $TargetIPList,

        [Parameter()]
        [pscredential]
        $DeploymentCredential,

        [Parameter()]
        [switch]
        $SanitizeModulePaths
    )

    if ($SanitizeModulePaths.IsPresent)
    {
        #Get DSC Resource store
        $resources = Get-ChildItem $ContentStoreDscResourceStorePath
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

    #Unblock the content store
    Get-ChildItem $ContentStoreRootPath -Recurse | Unblock-File
    
    #Required modules will be copied to the C:\Program Files\WindowsPowerShell\Modules  #logged in user's documents folder
    $moduleDestPath = $env:PSModulePath.Split(";")[1]
    
    #Copy Modules to host's module path
    if (!(Test-Path $moduleDestPath))
    {
        New-Item -Path $moduleDestPath -ItemType Directory
    }

    Copy-Item -Path "$ContentStoreModulePath\*" -Destination $moduleDestPath -Recurse -Force -ErrorAction Stop

    #Copy DSC Resources to the host's module path
    Copy-Item -Path "$ContentStoreDscResourceStorePath\*" -Destination $moduleDestPath -Recurse -Force

    # Ensure WinRM is running
    if ((Get-Service "WinRM" -ErrorAction Stop).status -eq 'Stopped') 
    {
        Start-Service "WinRM" -Confirm:$false -ErrorAction Stop
    }

    # Add the IP list of the target VMs to the trusted host list
    $currentTrustedHost = (Get-Item "WSMan:\localhost\Client\TrustedHosts").Value
    if(($currentTrustedHost -ne '*') -and ([string]::IsNullOrEmpty($currentTrustedHost) -eq $false))
    {
        $scriptTrustedHost = @($currentTrustedHost,$($TargetIPList -join ", ")) -join ", "
        Set-Item -Path "WSMan:\localhost\Client\TrustedHosts" -Value $scriptTrustedHost -Force
    }
    elseif($currentTrustedHost -ne '*')
    {
        $scriptTrustedHost = $TargetIPList -join ", "
        Set-Item -Path "WSMan:\localhost\Client\TrustedHosts" -Value $scriptTrustedHost -Force
    }

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
        
        [parameter(Mandatory)]
        [pscredential]
        $Credential
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
        $targetCimSession = New-CimSession -ComputerName $TargetIpAddress -Credential $Credential -ErrorAction Stop
        $targetPSSession = New-PSSession -ComputerName $TargetIpAddress -Credential $Credential -ErrorAction Stop
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

function Write-Config
{
    param
    (
        [parameter(Mandatory)]
        $TargetConfig,

        [Parameter()]
        [string]
        $ContentStoreRootPath,

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

        #Manually add TargetName and OutPutPath params until we can edit partials to correct this whacky step
        $paramList = @{}
        $paramList.Add("TargetName", $targetIP)
        $paramList.Add("OutPutPath", $compiledPartialMofPath)

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
        }
        catch
        {
            $errormsg = $_.Exception.Message
            throw "Failed to publish: $($partial.PartialPath).`r`nActual Error: " + $errormsg
        }
    }
}

<# Er...don't use this for now #>
function Copy-DscPartial
{
    param
    (
        [parameter(Mandatory)]
        $TargetConfig,

        [Parameter()]
        [string]
        $ContentStoreDscPartialStorePath,

        [Parameter()]
        [pscredential]
        $DeploymentCredential,

        [Parameter()]
        [DscPartial[]]
        $PartialCatalog
    )
    
    #Import PartialCatalog
    #$targetPartials = $PartialCatalog.where({$_.Name -in $TargetConfig.RoleList})

    #Point to C:\Program Files\WindowsPowerShell\Modules
    $partialStorePath = Join-Path -Path $TargetConfig.variables.LocalSourceStore -ChildPath "DscPartials"

    
    #$session = New-PSSession -ComputerName $TargetConfig.TargetIP -Credential $DeploymentCredential
    #foreach ($partial in $targetPartials)
    #{
        $copyPartialParams = @{
            Path=$ContentStoreDscPartialStorePath
            Destination=$partialStorePath
            Target=$TargetConfig.TargetIP
            Credential=$DeploymentCredential
        }

        Copy-RemoteContent @copyPartialParams
        
        #$null = Copy-Item -Path "$ContentStoreDscResourceStorePath\$resource" -Destination $env:PSModulePath.split(";")[1] -ToSession $session -Recurse -Force -ErrorAction Stop
    #}
    #$null = Remove-PSSession -Session $session
}

function Select-DscResource
{
    param
    (
        [parameter(Mandatory)]
        $TargetConfig,

        [Parameter()]
        [string]
        $ContentStoreDscResourceStorePath,

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
    $modulePath = $($env:PSModulePath.split(";")[1])

    #Retrive unique list of required DSC Resources
    $targetResources = ($targetPartials.Resources.Where({!([string]::IsNullOrEmpty($_))}).Split(",")) | Select-Object -Unique

    #Create an array of all DSC resources required
    $resourcesToCopy += $targetResources.foreach({
        return @{
            Path="$ContentStoreDscResourceStorePath\$_"
            Destination="$modulePath\$_"
        }
    })
    
    return $resourcesToCopy
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
                    CertificateId = $MofEncryptionCertThumbprint
                    RebootNodeIfNeeded = $TargetLcmSettings.RebootNodeIfNeeded
                    ConfigurationModeFrequencyMins = $TargetLcmSettings.ConfigurationModeFrequencyMins
                    ConfigurationMode = $TargetLcmSettings.ConfigurationMode
                }
            }
            else
            {
                Settings
                {
                    RebootNodeIfNeeded = $TargetLcmSettings.RebootNodeIfNeeded
                    ConfigurationModeFrequencyMins = $TargetLcmSettings.ConfigurationModeFrequencyMins
                    ConfigurationMode = $TargetLcmSettings.ConfigurationMode
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
        [string]
        $ContentStoreRootPath,

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

        while (($null = Get-DscLocalConfigurationManager -CimSession $targetCimSession).LCMState -eq "Busy")
        {
            Start-Sleep 1
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
        $PartialStorePath,

        [Parameter()]
        [string]
        $PartialCatalogPath
    )

    $partialCatalog = Register-DscPartialCatalog -PartialStore $PartialStorePath
    $json = ConvertTo-Json -InputObject $partialCatalog -Depth 7
    Out-File -FilePath $PartialCatalogPath -InputObject $json
    return $PartialCatalogPath
}

function New-SecretsFile
{
    param
    (
        [Parameter()]
        [string]
        $ContentStoreRootPath,

        [Parameter()]
        [string]
        $PartialCatalogPath,

        [Parameter()]
        [string]
        $SettingsPath
    )

    #import the partial catalog
    $partialCatalog = Import-PartialCatalog -PartialCatalogPath $PartialCatalogPath

    #Find parameter types of pscredential
    #$partialSecrets = $partialCatalog.Parameters.Where({$_.Attributes.Name -eq "System.Management.Automation.PSCredential"})
    $partialSecrets = $partialCatalog.ForEach(
    {
        [ordered]@{Partial=$_.Name;Secrets=$_.Parameters.Where({$_.StaticType -eq "System.Management.Automation.PSCredential"}).Name}
    })

    #Export the file for reference
    $null = ConvertTo-Json $partialSecrets | Out-File "$SettingsPath\PartialSecrets.json"

    #region Generate password key
    $BitArray = New-Object System.Collections.BitArray(256)
    for ($i = 0; $i -lt 256 ;$i++)
    {
        $BitArray[$i] = [bool](Get-Random -Maximum 2)
    }
    [Byte[]] $key = ConvertTo-ByteArray -BitArray $BitArray
    $key | Out-File "$SettingsPath\SecretsKey.json"
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

    $null = ConvertTo-Json $storedSecrets | Out-File "$SettingsPath\StoredSecrets.json"
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
        $ContentStoreRootPath,

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
    $partialCatalog = Import-PartialCatalog -PartialCatalogPath $PartialCatalogPath

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
        $ContentStoreRootPath,

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

Class DscPartial
{
    [string]
    $Name

    [string]
    $Path
    
    [string]
    $Resources

    [array]
    $Parameters

    DscPartial ()
    {}

    DscPartial ( [string]$Name, [string]$Path, [string]$Resources, [string]$Parameters)
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
        [string]
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
