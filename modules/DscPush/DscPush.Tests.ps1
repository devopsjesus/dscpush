[version]$pesterVersion = "4.4.2"
if ($pesterVersion -notin (Get-Module -Name Pester -ListAvailable -ErrorAction Ignore).Version)
{
    Install-Module -Name Pester -RequiredVersion 4.4.2 -Force -SkipPublisherCheck -ErrorAction Stop
}

$ModuleRoot = $PSScriptRoot
$ModulePath = $MyInvocation.MyCommand.Path -replace '\.Tests\.ps1$','.psm1'
$ModuleName = Split-Path -Path $ModuleRoot -Leaf

Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module
Import-Module -FullyQualifiedName $ModulePath -ErrorAction Stop

InModuleScope $ModuleName {

        $script:resourcesPath      = Join-Path -Path $env:Temp -ChildPath "resources"
        $script:compositePath      = Join-Path -Path $resourcesPath -ChildPath "CompositeResource"
        $compositeDscResourcesPath = Join-Path -Path $compositePath -ChildPath "DSCResources"

        $null = Remove-Item -Path $resourcesPath -Recurse -Force -ErrorAction Ignore
                
        $currentPsModulePath = $env:PSModulePath
        $env:PSModulePath += ";$resourcesPath"

        $script:resourceList = @(
            @{ ModuleName = "xDnsServer"                  ; ModuleVersion = "1.11.0.0" }
            @{ ModuleName = "xNetworking"                 ; ModuleVersion = "5.7.0.0"  }
            @{ ModuleName = "xComputerManagement"         ; ModuleVersion = "4.1.0.0"  }
            @{ ModuleName = "xActiveDirectory"            ; ModuleVersion = "2.21.0.0" }
            @{ ModuleName = "CertificateDsc"              ; ModuleVersion = "4.2.0.0"  }
            @{ ModuleName = "xPSDesiredStateConfiguration"; ModuleVersion = "8.4.0.0"  }
            @{ ModuleName = "CustomModule"                ; ModuleVersion = "1.1.0.0"  }
        )

        #Create the CustomModule ahead of time, because those files would already exist
        $null = New-Item -Path (Join-Path -Path $resourcesPath -ChildPath "CustomModule\1.1.0.0") -Force -ItemType Directory
        New-ModuleManifest -Path (Join-Path -Path $resourcesPath -ChildPath "CustomModule\1.1.0.0\CustomModule.psd1") -ModuleVersion "1.1.0.0"

        try
        {
            $null = New-Item -Path $compositePath -ItemType Directory -Force
            $null = New-Item -Path $compositeDscResourcesPath -ItemType Directory -Force
                
            $resourceList.ForEach({
                $newItemParams = @{
                    Path = "$compositeDscResourcesPath\$($_.ModuleName)\$($_.ModuleName).schema.psm1"
                    ItemType = "File"
                    Force = $true
                    Value = "Configuration $($_.ModuleName) {Param([parameter(Mandatory)] [string] `$$($_.ModuleName)) Import-DscResource -ModuleName $($_.ModuleName) -ModuleVersion $($_.ModuleVersion)}"
                }
                $null = New-Item @newItemParams

                $newItemParams = @{
                    Path = "$compositeDscResourcesPath\$($_.ModuleName)\$($_.ModuleName).psd1"
                    ItemType = "File"
                    Force = $true
                    Value = "@{RootModule = '$($_.ModuleName).schema.psm1';ModuleVersion = '$($_.ModuleVersion)'}"
                }
                $null = New-Item @newItemParams
            })

            #add a resource with no DSC Resource imports
            $newItemParams = @{
                Path = "$compositeDscResourcesPath\NoImports\NoImports.schema.psm1"
                ItemType = "File"
                Force = $true
                Value = "Configuration NoImports {Param([parameter(Mandatory)] [string] `$NoImports)"
            }
            $null = New-Item @newItemParams
            $script:resourceList += @{ ModuleName = "NoImports"; ModuleVersion = "1.0.0.0"  }

            #add the module manifest with all the resources included
            $null = New-ModuleManifest -Path (Join-Path -Path $compositePath -ChildPath "CompositeResource.psd1") -DscResourcesToExport $resourceList.ModuleName
        }
        catch
        {
            $env:PSModulePath = $currentPsModulePath
            throw "Could not generate composite resource"
        }
    
    Describe "Assert-CompositeModule" {
        
        Context "Normal Operations" {

            It "Returns a Module's information" {
                
                $assertedModule = Assert-CompositeModule -Path $compositePath
                $moduleInfo = Get-Module $compositePath -ListAvailable
                $assertedModule | Should -Not -BeNullOrEmpty
                
                Compare-Object -ReferenceObject $moduleInfo -DifferenceObject $assertedModule | Should -BeNullOrEmpty
            }
        }

        Context "Bad Input" {
        
            It "Throws if a bad path is given" {
            
                { Assert-CompositeModule -Path "C:\path\to\nowere" } | Should -Throw
            }
        }
    }
    
    Describe "Get-PSScriptParameterMetadata" {
        
        Context "Normal Operations" {

            #Fake param block below for the function parses out param ASTs
            $configPath = "$TestDrive\testConfig.ps1"
            $configText = 'Param
            (
                [parameter(Mandatory)]
                [ValidateScript({[System.Uri]::CheckHostName($_) -eq "Dns"})]
                [ValidateLength(1,15)]
                [string]
                $ComputerName,

                [Parameter(mandatory)]
                [ValidateNotNullOrEmpty()]
                [ValidateScript({Test-Path $_})]
                [ValidatePattern(".*.ps1$|.*.psm1$")]
                [string]
                $Path,

                [parameter()]
                [bool]
                $JoinDomain
            )' > $configPath
            { . $configPath -ComputerName "test" -Path $configPath -JoinDomain $true } | Should Not Throw

            #store an example of good data here to test against
            $json = '[{"StaticType":"System.String","Name":"ComputerName","Attributes":[{"NamedArguments":["Mandatory"],
            "Name":"parameter","PositionalArguments":[]},{"NamedArguments":[],"Name":"ValidateScript","PositionalArguments":
            ["{[System.Uri]::CheckHostName($_) -eq \"Dns\"}"]},{"NamedArguments":[],"Name":"ValidateLength","PositionalArguments":
            ["1","15"]},{"NamedArguments":[],"Name":"string","PositionalArguments":[]}]},{"StaticType":"System.String","Name":
            "Path","Attributes":[{"NamedArguments":["mandatory"],"Name":"Parameter","PositionalArguments":[]},
            {"NamedArguments":[],"Name":"ValidateNotNullOrEmpty","PositionalArguments":[]},{"NamedArguments":[],"Name":
            "ValidateScript","PositionalArguments":["{Test-Path $_}"]},{"NamedArguments":[],"Name":"ValidatePattern",
            "PositionalArguments":["\".*.ps1$|.*.psm1$\""]},{"NamedArguments":[],"Name":"string","PositionalArguments":[]}]},
            {"StaticType":"System.Boolean","Name":"JoinDomain","Attributes":[{"NamedArguments":[],"Name":"parameter",
            "PositionalArguments":[]},{"NamedArguments":[],"Name":"bool","PositionalArguments":[]}]}]'

            $correctReturn = ConvertFrom-Json ([string]$json)
            $hashtableReturn = $correctReturn.ForEach({
                @{
                    StaticType = $_.StaticType
                    Name = $_.Name
                    Attributes = $_.Attributes
                }
            })
            
            $moduleReturn = Get-PSScriptParameterMetadata -Path $ConfigPath

            It "Ensure <Name> and its metadata match known good data" -TestCases $moduleReturn {
                param($StaticType, $Name, $Attributes)

                $param = @{
                    StaticType = $StaticType
                    Name       = $Name
                    Attributes = $Attributes
                }
                Compare-Object -ReferenceObject $param -DifferenceObject $hashtableReturn.Where({$_.Name -eq $param.Name}) | Should -BeNullOrEmpty
            }

            It "Ensure <Name> metadata is correct" -TestCases $modulereturn {
                param($StaticType, $Name, $Attributes)

                $matchingReturn = $hashtableReturn.Where({$_.Name -eq $Name})
                $Attributes.count | Should -Be $matchingReturn.Attributes.count
                $Attributes.Name | Should -Be $matchingReturn.Attributes.Name
            }

            It "Returns an array of hashtables" {
                $moduleReturn -is [array] | Should -Be $true
                $moduleReturn.Foreach({ $_ -is [hashtable] | Should -Be $true })
            }
        }

        Context "Bad Inputs" {
            
            It "Path parameter not ending in '.ps1' or '.psm1' will cause an error" {

                "foo" > "$TestDrive\pathexists.exe"
                try
                {
                   Get-PSScriptParameterMetadata -Path "$TestDrive\pathexists.exe"
                }
                catch
                {
                   $error = $_ 
                }
                $error | Should BeLike '*does not match the ".*.ps1$|.*.psm1$" pattern*'
            }

            It "Path cannot be found will cause an error" {

                try
                {
                   Get-PSScriptParameterMetadata -Path "Path\To\Knowhere.ps1"
                }
                catch
                {
                   $error = $_ 
                }
                $error | Should BeLike '*"Test-Path $_" validation script for the argument with value "Path\To\Knowhere.ps1"*'
            }
        }
    }

    Describe "Get-RequiredDscResourceList" {

        Context "Normal Operations" {

            #Fake config below to ensure the function parses out required DSC Resources correctly
            $configPath = "$TestDrive\testConfig.ps1"
            $configText = 'Configuration OSCore 
            { 
                Import-DscResource -ModuleName "PSDesiredStateConfiguration" -ModuleVersion 1.1
                Import-DscResource -ModuleName "xNetworking" -ModuleVersion 5.7.0.0
                Import-DscResource -ModuleName "xComputerManagement" -ModuleVersion 4.1.0.0
            }' >> $configPath
            { . $configPath } | Should Not Throw

            $correctReturn = @(
                @{ ModuleName = "xNetworking"        ; ModuleVersion = "5.7.0.0" }
                @{ ModuleName = "xComputerManagement"; ModuleVersion = "4.1.0.0" }
            )
            $requiredResourceList = Get-RequiredDscResourceList -Path $ConfigPath

            It "ModuleName <ModuleName> & ModuleVersion <ModuleVersion> are returned correctly" -TestCases $requiredResourceList {
                param ( $ModuleName, $ModuleVersion )

                $requiredResourceList.Where({$ModuleName -eq $_.ModuleName}).ModuleName | Should -BeIn $correctReturn.ModuleName
                $requiredResourceList.Where({$ModuleName -eq $_.ModuleName}).ModuleVersion | Should -BeIn $correctReturn.ModuleVersion
            }

            It "Returns the correct number of resources" {
                $requiredResourceList.count | Should -Be 2
            }
        }

        Context "Bad Inputs" {

            $configPath = "$TestDrive\testConfig.ps1"

            It "Name parameter used will cause an error" {

                $configText = 'Configuration OSCore { Import-DscResource -Name xComputer -ModuleName "xComputerManagement" }' > $configPath
                { . $configPath } | Should Not Throw
                $testErrorStatement = "$configPath - Use of the 'Name' parameter when calling Import-DscResource is not supported."

                try
                { 
                    Get-RequiredDscResourceList -Path $ConfigPath
                }
                catch
                {
                    $error = $_
                } 
                $error | Should BeLike "$testErrorStatement*"
            }
            
            It "ModuleVersion parameter missing will cause an error" {
            
                $configText = 'Configuration OSCore { Import-DscResource -ModuleName "xNetworking" }' > $configPath
                { . $configPath } | Should Not Throw
                $testErrorStatement = "$configPath - Missing ModuleVersion parameter in config"
            
                try
                {
                    Get-RequiredDscResourceList -Path $ConfigPath 
                }
                catch
                {
                   $error = $_ 
                }
                $error | Should BeLike "$testErrorStatement*"
            }
        }
    }

    Describe "Get-DscConfigurationName" {
        
        Context "Normal Operations" {

            $configPath = "$TestDrive\testConfig.ps1"
            $configText = 'Configuration Banana {}' > $configPath
            { . $configPath } | Should Not Throw

            $correctReturn = "Banana"

            It "Returns the Configuration statement Name" {

                $configName = Get-DscConfigurationName -Path $configPath

                $configName | Should -Be $correctReturn
            }
        }

        Context "Bad Input" {

            $configPath = "$TestDrive\testConfig.ps1"
            $testErrorStatement = "$configPath - Only one configuration statements is supported in each script"
            
            It "More than one configuration name in a script will cause an error" {

                $configText = 'Configuration Banana {} ; Configuration Pineapple {}' > $configPath
                { . $configPath } | Should Not Throw

                try
                {
                    $configName = Get-DscConfigurationName -Path $configPath
                }
                catch
                {
                    $error = $_
                }
                $error | Should BeLike "$testErrorStatement*"
            }

            It "No configuration names found in a script will cause an error" {
           
                $configText = 'function Banana {}' > $configPath
                { . $configPath } | Should Not Throw

                try
                {
                    $configName = Get-DscConfigurationName -Path $configPath
                }
                catch
                {
                    $error = $_
                }
                $error | Should BeLike "$testErrorStatement*"
            }
        }
    }

    Describe "Get-DscCompositeMetaData" {
        
        Context "Normal Operations" {
            
            It "Should return a DSCCompositeResource array with the appropriate properties" {
               
                $env:PSModulePath += ";$TestDrive"
                $script:composite = Get-DscCompositeMetaData -Path $script:compositePath

                $composite.GetType().BaseType | Should -Be "Array"
                $composite.ForEach({ $_.GetType().Name | Should -Be "DscCompositeResource" })
                $composite.Count | Should -BeExactly $script:resourceList.Count
                $composite.Resource.ForEach({ $_ | Should -BeIn $resourceList.ModuleName })
                $composite.Resources.ModuleName.ForEach({ $_ | Should -BeIn $resourceList.ModuleName })
                $composite.Resources.ModuleVersion.ForEach({ $_ | Should -BeIn $resourceList.ModuleVersion })
                $composite.Parameters.Name.ForEach({ $_ | Should -BeIn $resourceList.ModuleName })
                $composite.Parameters.StaticType.ForEach({ $_ | Should -Be "System.String" })
            }
        }

        Context "Bad Input" {
            
            It "Should throw if the module is not found in the PSModulePath" {
                { Get-DscCompositeMetaData -Path "C:\path\to\knowhere" } | Should -Throw
            }
        }
    }

    Describe "Save-CompositeDscResourceList" {
        
        Context "Normal Operations" {
            
            Mock -CommandName "Find-Module" -MockWith { throw } -ParameterFilter { $Name -eq "CustomModule" }
            Mock -CommandName "Find-Module" -MockWith { }
            
            #Cleanup output by nulling write-Warning
            Mock -CommandName "Write-Warning" -MockWith { }

            Mock -CommandName "Save-Module" -MockWith { 
                New-Item -Path "$script:resourcesPath\$Name\$RequiredVersion" -ItemType Directory
                New-ModuleManifest -Path "$script:resourcesPath\$Name\$RequiredVersion\$Name.psd1" -ModuleVersion $RequiredVersion
            }

            #$script:resourceList = $script:composite.Resources
            
            Save-CompositeDscResourceList -ResourceList $script:resourceList -DestinationPath $script:resourcesPath

            It "Saves the required DSC resources to the specified path" -TestCases $resourceList {
                
                param( $ModuleName, $ModuleVersion )

                #CustomModule won't be saved, because it's a custom module, and this module only retrieves resources from public repos
                #if ($ModuleName -eq "CustomModule")
                #{
                #    Test-Path -Path "$resourcesPath\$ModuleName\$ModuleVersion" | Should -Be $false
                #}
                #else
                #{
                    Test-Path -Path "$resourcesPath\$ModuleName\$ModuleVersion" | Should -Be $true
                #}
            }

            It "Saves the correct number of unique DSC resources" {
                
                #count is + 1, despite CoreApps not downloading, because of the compositeResource & CustomModule
                (Get-ChildItem $resourcesPath).Count | Should -BeExactly ($resourceList.count + 1)
            }

            It "Warned about CustomModule resource not found" {

                Assert-MockCalled -CommandName "Find-Module" -Times 1 -ParameterFilter {$Name -eq "CustomModule"}
                Assert-MockCalled -CommandName "Write-Warning" -Times 1
            }

            It "Found and saved all Unique public Modules" {

                Assert-MockCalled -CommandName "Find-Module" -Times ($resourceList.count) -Exactly
                Assert-MockCalled -CommandName "Save-Module" -Times ($resourceList.count - 1) -Exactly #Less 1 because CustomModule won't be found
            }

            It "Removes existing resource directories" {

                Mock -CommandName "Remove-Item" -MockWith { }
                Mock -CommandName "Save-Module" -MockWith { }
                
                Save-CompositeDscResourceList -ResourceList $resourceList -DestinationPath $resourcesPath
                
                Assert-MockCalled -CommandName "Remove-Item" -Times 7 -Exactly
            }

        }
    }
    
    Describe "ConvertFrom-Hashtable" {
        
        Context "Normal Operations" {

            It "Throws if something other than hashtable or hashtable array is passed in" {
                { ConvertFrom-Hashtable -InputObject "string" } | Should -Throw
                { ConvertFrom-Hashtable -InputObject 123 } | Should -Throw
            }
            
            $convertedHashtableList = ConvertFrom-Hashtable -InputObject $script:resourceList

            $hashtableScriptBlock = [scriptblock]::Create($convertedHashtableList)
            $hashtableArray = $hashtableScriptBlock.Invoke()

            It "Hashtable with keys <ModuleName>/<ModuleVersion> is capable of converting back from string objects" -TestCases $hashtableArray {
                param ($ModuleName, $ModuleVersion)
                
                $ModuleName | Should -BeIn $resourceList.ModuleName
                $ModuleVersion | Should -BeIn $resourceList.ModuleVersion
            }

            It "Returns nested hashtable objects" {
                
                $inputObject = @{
                    Hashtable = @{
                        NestedHashtable = $true
                    }
                }

                $stringObject =  ConvertFrom-Hashtable -InputObject $inputObject
                $hashtableScriptBlock = [scriptblock]::Create($stringObject)
                $reconsitutedHashtable = ($hashtableScriptBlock.Invoke())[0] #Invoke method returns a collection, so we grab the hashtable inside
                
                $reconsitutedHashtable -is [hashtable] | Should -BeTrue
                $reconsitutedHashtable.Hashtable -is [hashtable] | Should -BeTrue

                Compare-Object -ReferenceObject $reconsitutedHashtable -DifferenceObject $inputObject | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Hashtable -DifferenceObject $inputObject.Hashtable | Should -BeNullOrEmpty
            }

            It "Returns array values as arrays" {
                
                $inputObject = @{
                    Array = @(1,2,3)
                }

                $stringObject =  ConvertFrom-Hashtable -InputObject $inputObject
                $hashtableScriptBlock = [scriptblock]::Create($stringObject)
                $reconsitutedHashtable = ($hashtableScriptBlock.Invoke())[0] #Invoke method returns a collection, so we grab the hashtable inside
                
                $reconsitutedHashtable -is [hashtable] | Should -BeTrue
                $reconsitutedHashtable.Array -is [array] | Should -BeTrue


                Compare-Object -ReferenceObject $reconsitutedHashtable -DifferenceObject $inputObject | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Array -DifferenceObject $inputObject.Array | Should -BeNullOrEmpty
            }

            It "Returns nested array values as arrays" {
                
                $inputObject = @{
                    Hashtable = @{
                        Array = @(1,2,3)
                        NestedKey = "NestedValue"
                    }
                    Key = 1
                }

                $stringObject =  ConvertFrom-Hashtable -InputObject $inputObject
                $hashtableScriptBlock = [scriptblock]::Create($stringObject)
                $reconsitutedHashtable = ($hashtableScriptBlock.Invoke())[0] #Invoke method returns a collection, so we grab the hashtable inside
                
                $reconsitutedHashtable -is [hashtable] | Should -BeTrue
                $reconsitutedHashtable.Hashtable -is [hashtable] | Should -BeTrue
                $reconsitutedHashtable.Hashtable.Array -is [array] | Should -BeTrue
                $reconsitutedHashtable.Hashtable.NestedKey -is [string] | Should -BeTrue
                $reconsitutedHashtable.Key -is [string] | Should -BeTrue

                $reconsitutedHashtable.Hashtable.NestedKey | Should -Be $inputObject.Hashtable.NestedKey
                $reconsitutedHashtable.Key | Should -Be $inputObject.Key

                Compare-Object -ReferenceObject $reconsitutedHashtable -DifferenceObject $inputObject | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Hashtable -DifferenceObject $inputObject.Hashtable | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Hashtable.Array -DifferenceObject $inputObject.Hashtable.Array | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Hashtable.NestedKey -DifferenceObject $inputObject.Hashtable.NestedKey | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Key -DifferenceObject $inputObject.Key | Should -BeNullOrEmpty
            }

            It "Returns when a hashtable array is passed in" {
                
                $inputObject = @(
                    @{
                        Hashtable = @{
                            Array = @(1,2,3)
                            NestedKey = "NestedValue"
                        }
                        Key = 1
                    }
                    @{
                        Hashtable2 = @{
                            Array2 = @(3,2,1)
                            NestedKey2 = "PineappleBanana"
                        }
                        Key2 = 2
                    }
                )

                $stringObject =  ConvertFrom-Hashtable -InputObject $inputObject
                $hashtableScriptBlock = [scriptblock]::Create($stringObject)
                $reconsitutedHashtable = [array]($hashtableScriptBlock.Invoke())

                $reconsitutedHashtable -is [array] | Should -BeTrue
                $reconsitutedHashtable.Hashtable -is [hashtable] | Should -BeTrue
                $reconsitutedHashtable.Hashtable2  -is [hashtable] | Should -BeTrue
                $reconsitutedHashtable.Hashtable.Array -is [array] | Should -BeTrue
                $reconsitutedHashtable.Hashtable2.Array2 -is [array] | Should -BeTrue
                $reconsitutedHashtable.Hashtable.NestedKey -is [string] | Should -BeTrue
                $reconsitutedHashtable.Hashtable2.NestedKey2 -is [string] | Should -BeTrue
                $reconsitutedHashtable.Key -is [string] | Should -BeTrue
                $reconsitutedHashtable.Key2 -is [string] | Should -BeTrue
                
                $reconsitutedHashtable.Hashtable.NestedKey | Should -Be $inputObject.Hashtable.NestedKey
                $reconsitutedHashtable.Key | Should -Be $inputObject.Key
                $reconsitutedHashtable.Hashtable2.NestedKey2 | Should -Be $inputObject.Hashtable2.NestedKey2
                $reconsitutedHashtable.Key2 | Should -Be $inputObject.Key2

                Compare-Object -ReferenceObject $reconsitutedHashtable -DifferenceObject $inputObject | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Hashtable -DifferenceObject $inputObject.Hashtable | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Hashtable.Array -DifferenceObject $inputObject.Hashtable.Array | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Hashtable.NestedKey -DifferenceObject $inputObject.Hashtable.NestedKey | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Key -DifferenceObject $inputObject.Key | Should -BeNullOrEmpty

                Compare-Object -ReferenceObject $reconsitutedHashtable.Hashtable2 -DifferenceObject $inputObject.Hashtable2 | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Hashtable2.Array2 -DifferenceObject $inputObject.Hashtable2.Array2 | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Hashtable2.NestedKey2 -DifferenceObject $inputObject.Hashtable2.NestedKey2 | Should -BeNullOrEmpty
                Compare-Object -ReferenceObject $reconsitutedHashtable.Key2 -DifferenceObject $inputObject.Key2 | Should -BeNullOrEmpty
            }
        }
    }

    Describe "New-DscResourceList" {
    
        Context "Normal Operations" {

            $params = @{
                CompositeResource      = $script:composite
                DscResourcesDirectory       = $script:resourcesPath
                DestinationDriveLetter = "Q"
            }
            $resourceFileList = New-DscResourceList @params
            
            It "Contains the local and destination paths for the passed in parameters" -TestCases $resourceFileList {
                
                Param( $Path, $Destination )

                Split-Path -Path $Path -Parent | Should -Be $script:resourcesPath
                Split-Path -Path $Path -Leaf | Should -BeIn $script:resourceList.ModuleName

                Split-Path -Path $Destination -Parent | Should -Be "Q:\Program Files\WindowsPowerShell\Modules"
                Split-Path -Path $Destination -Leaf | Should -BeIn $script:resourceList.ModuleName

                #count is less than 1 becaues NoImports has no required resources to copy
                $resourceFileList.Count | Should -BeExactly ($resourceList.Count - 1) 
            }
        }

        Context "Bad Input" {
            
            It "-" {
                

            }
        }
    }

    <#
    Describe "Export-NodeDefinitionFile" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Enable-TargetMofEncryption" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Copy-RemoteContent" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Initialize-DeploymentEnvironment" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Connect-TargetAdapter" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Write-Config" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Select-DscResource" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Initialize-TargetLcm" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Reset-TargetLcm" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Send-Config" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "ConvertTo-ByteArray" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "New-SecretsFile" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "New-NodeDefinitionFile" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Update-NodeDefinitionFile" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }#>

}