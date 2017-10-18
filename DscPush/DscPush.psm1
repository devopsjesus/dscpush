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
        if (! (Test-Path $UpdateNodeDefinitionFilePath))
        {
            throw "Data file not found."
        }

        $configsToMerge = . $UpdateNodeDefinitionFilePath
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
            $TargetIP = $config.TargetIP
            $ContentHost = $config.ContentHost
            $roleList = ($config.RoleList) -join "`"$crlf        `""
            $roleList = "$roleList"
            
            #Generate Config properties
            $mergeConfig = $configsToMerge.Configs.where({$_.ConfigName -eq $configName})

            $dataFileContents += "#region Target Config: $configName${crlf}"
            $dataFileContents += "`$$ConfigName = New-TargetConfig -Properties @{$crlf"
            $dataFileContents += "    ConfigName = '$configName'$crlf"
            $dataFileContents += "    TargetIP = '$TargetIP'$crlf"
            $dataFileContents += "    ContentHost = `$$ContentHost$crlf"
            $dataFileContents += "    RoleList = @($crlf        `"$roleList`"$crlf    )$crlf"
            $dataFileContents += "}$crlf"

            #Get the list of unique parameters from the pool of partials
            #Looks like WMF5.1 adds a case sensitivity switch to the sort-object cmdlet, which invalidates the following 2 lines below.
            #This format is required due to case sensitivity of -Unique switch (Get-Unique behaves the same)
            #$uniqueParamList = $config.Partials.Parameters.Name.ToLower() | Sort-Object -Unique
            $uniqueParamList = $PartialCatalog.Where({$_.Name -in $config.RoleList}).Parameters.Name | Sort-Object -Unique

            $dataFileContents += "`$$ConfigName.Variables += @{$crlf"

            foreach ($parameter in $uniqueParamList)
            {
                if ($UpdateNodeDefinitionFilePath)
                {
                    $paramValue = $mergeConfig.Variables.$parameter
                }

                if (! $paramValue)
                {
                
                    $paramValue = "ENTER_VALUE_HERE"
                }

                #See note above about WMF5.1
                #$paramName = $config.Partials.Parameters.Name.where({$_ -eq $parameter})[0] #to maintain case, instead of just using $parameter
                #$dataFileContents += "    $paramName='$paramValue'$crlf"
                $dataFileContents += "    $parameter='$paramValue'$crlf"
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
        Out-File -FilePath $NodeDefinitionFilePath -InputObject $dataFileContents
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
    $storedSecrets.ForEach({$_.Password = ConvertTo-SecureString -String $_.Password -Key $secretsKey})

    foreach ($config in $TargetConfigs.Value.Configs)
    {
        #Add partial dependencies to the config
        $configDependencies = $partialDependencies.Where({$_.Partial -in $config.RoleList})
        #hashtables are returned as customObjs, so this whacky crap is necessary
        $config.Dependencies = $configDependencies.ForEach({@{Partial=$_.Partial;DependsOn=$_.DependsOn}})

        #Add partial secrets to the config
        $definedSecrets = ($secretsList.where({$_.Partial -in $config.RoleList})).Secrets
        $requiredSecrets = ($storedSecrets.where({$_.Secret -in $definedSecrets}))
        $config.Secrets = $requiredSecrets
    }

    return $corePartial
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
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [string]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]
        $Target,

        [Parameter(Mandatory = $true)]
        [PSCredential]
        $Credential
    )
    
    #Create CIM & PS Session
    $targetCimSession = New-CimSession -ComputerName $Target -Credential $Credential -ErrorAction Stop

    #Enable SMB firewall and update GP if SMB test fails
    if (! (Test-NetConnection -ComputerName $Target -CommonTCPPort SMB -InformationLevel Quiet -InformationAction SilentlyContinue))
    {
        Copy-NetFirewallRule -CimSession $targetCimSession -NewPolicyStore localhost -DisplayName 'File and Printer Sharing (SMB-In)' -ErrorAction Ignore
        Enable-NetFirewallRule -CimSession $targetCimSession -PolicyStore localhost
        
        $targetPSSession = New-PSSession -ComputerName $Target -Credential $Credential
        Invoke-Command -Session $targetPSSession -ScriptBlock {
            $null = cmd.exe /c gpupdate /force
        }
        Remove-PSSession -Session $targetPSSession
    }

    #Enable SMB encryption
    Set-SmbServerConfiguration -CimSession $targetCimSession -EncryptData $true -Confirm:$false
        
    #Connect to host from target and create PSDrive mapping destination folder
    $destinationUNC = $Destination.Replace(":","$")
    if (! (Test-Path "\\$Target\$destinationUNC"))
    {
        $null = New-Item -Type Directory -Path "\\$Target\$destinationUNC" -ErrorAction Stop
    }
    $psDrive = New-PSDrive -Name Y -PSProvider "filesystem" -Root "\\$Target\$destinationUNC" -Credential $Credential
    
    #Create root directory and copy content
    #$ContentStore = New-Item -Type Directory -Path $Destination -ErrorAction Ignore
    Copy-Item -Path "$Path\*" -Destination Y:\ -Force -Recurse
    Get-ChildItem -Path Y:\ -Recurse -Force | Unblock-File

    #Cleanup
    Remove-PSDrive -Name $psDrive -ErrorAction Ignore
    Remove-CimSession -CimSession $targetCimSession
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

    #Required modules will be copied to the logged in user's documents folder
    $moduleDestPath = $env:PSModulePath.Split(";")[0]
    
    #Copy Modules to host's module path
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

function Copy-DscResource
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

    #$session = New-PSSession -ComputerName $TargetConfig.TargetIP -Credential $DeploymentCredential
    foreach ($resource in $targetResources)
    {
        $copyResourceParams = @{
            Path="$ContentStoreDscResourceStorePath\$resource"
            Destination="$modulePath\$resource"
            Target=$TargetConfig.TargetIP
            Credential=$DeploymentCredential
        }
        Copy-RemoteContent @copyResourceParams
        
        #$null = Copy-Item -Path "$ContentStoreDscResourceStorePath\$resource" -Destination $env:PSModulePath.split(";")[1] -ToSession $session -Recurse -Force -ErrorAction Stop
    }
    #$null = Remove-PSSession -Session $session
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

        [parameter()]
        [string]
        $CorePartial,

        [parameter()]
        [string]
        $MofOutputPath
    )

    # build local config
    [DSCLocalConfigurationManager()]
    Configuration TargetConfiguration
    {
        Node $TargetConfig.TargetIP.IPAddressToString
        {            
            Settings
            {                              
                RebootNodeIfNeeded = $TargetLcmSettings.RebootNodeIfNeeded
                ConfigurationModeFrequencyMins = $TargetLcmSettings.ConfigurationModeFrequencyMins
                ConfigurationMode = $TargetLcmSettings.ConfigurationMode
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

    $null = TargetConfiguration -OutputPath $mofOutputPath -ErrorAction Stop
    
    $null = Set-DscLocalConfigurationManager -ComputerName $TargetConfig.TargetIP -Path $mofOutputPath -Credential $DeploymentCredential -Force -ErrorAction Stop
}

function Send-Config
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
        $PartialCatalog
    )

    $targetPartials = $PartialCatalog.where({$_.Name -in $TargetConfig.RoleList})
    
    foreach ($partial in $targetPartials)
    {
        Write-Output "  Compiling Partial: $($partial.Name)"

        $paramList = @{}
        $paramList.Add("TargetName", [string]$TargetConfig.TargetIP)
        $paramList.Add("OutPutPath", "C:\Windows\Temp")

        $partial.Parameters.Name.ForEach({$paramList.Add($_, $TargetConfig.Variables.$_)})
        
        try
        {
            #Compile the partial using the ParamList
            . "$($partial.Path)" @paramList
            
            $null = Publish-DscConfiguration -Path "C:\Windows\Temp" -ComputerName $TargetConfig.TargetIP -Credential $DeploymentCredential -Force -ErrorAction Stop
        }
        catch
        {
            $errormsg = $_.Exception.Message
            throw "Failed to publish: $($partial.PartialPath).`r`nActual Error: " + $errormsg
        }
    }

    $null = Start-DscConfiguration -ComputerName $TargetConfig.TargetIP -Credential $DeploymentCredential -UseExisting -ErrorAction Stop
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
    Write-Output "Partial Catalog location: $PartialCatalogPath"
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

    #Currently a static list, because none of the parameters are pscredential types - once that change is made, this function can loop through parameter types of pscredential
    $partialSecrets = $partialCatalog.Name.ForEach(
    {
        switch ($_)
        {
            Certificate  { [ordered]@{Partial=$_;Secrets=@("DomainPassword","CertPassword")} }
            DeploymentShare { [ordered]@{Partial=$_;Secrets=@()} }
            DnsRecord { [ordered]@{Partial=$_;Secrets=@()} }
            DomainController { [ordered]@{Partial=$_;Secrets=@("DomainPassword")} }
            OSCore { [ordered]@{Partial=$_;Secrets=@("DomainPassword")} }
        }
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

    <#Add Partial Objects to Configs
    foreach ($config in $nodeDefinition.Configs)
    {
        #Add Partial Metadata to the config
        $targetConfigPartialMetaData = Get-PartialMetaData -TargetConfig $config.RoleList -PartialCatalog $partialCatalog
        $config.AddPartial($targetConfigPartialMetaData)
    }
    #endregion Node Definition#>

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

    #Add Partial Objects to Node Definition Configs
    foreach ($config in $nodeDefinition.Configs)
    {
        #Add Partial Metadata to the config
        $targetConfigPartialMetaData = Get-PartialMetaData -TargetConfig $config.RoleList -PartialCatalog $partialCatalog
        $config.AddPartial($targetConfigPartialMetaData)
    }

    Export-NodeDefinitionFile -NodeDefinition $nodeDefinition -NodeDefinitionFilePath $UpdateNodeDefinitionFilePath -UpdateNodeDefinitionFilePath $NodeDefinitionFilePath
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

    [ipaddress]
    $TargetIP
    
    [array]
    $RoleList

    [boolean]
    $ContentHost

    [hashtable[]]
    $Dependencies

    [string[]]
    $Secrets
    
    [array]
    $Properties

    [array]
    $Variables

    TargetConfig ()
    {
        $this.Properties = ($this | Get-Member -MemberType Properties).Name
    }

    TargetConfig ( [string] $ConfigName, [ipaddress] $TargetIP, [array] $RoleList, [string] $CopyContentStore, [hashtable[]] $Dependencies, [string[]]$Secrets )
    {
        $this.ConfigName = $ConfigName
        $this.TargetIP = $TargetIP
        $this.RoleList = $RoleList -split ','
        $this.CopyContentStore = $CopyContentStore
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

    DscLcm ( [hashtable]$Properties)
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
    {
        
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

    <#if ($Properties)
    {
        foreach ($property in $Properties)
        {
            $newDscLcm.$property = $Properties.$property
        }
    }#>

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
        [string]
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
        $newLcmPartial.DependsOn = $($partialDependsOnProperty -join ",")
    }

   
    return $newLcmPartial
}
#endregion Class Instantiation
