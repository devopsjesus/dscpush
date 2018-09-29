$ModuleRoot = $PSScriptRoot
$ModulePath = $MyInvocation.MyCommand.Path -replace '\.Tests\.ps1$','.psm1'
$ModuleName = Split-Path -Path $ModuleRoot -Leaf

Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module
Import-Module -FullyQualifiedName $ModulePath -ErrorAction Stop

InModuleScope $ModuleName {

    Describe "Initialize-DscPush" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }
    
    Describe "Publish-TargetConfig" {
        
        Context "Normal Operations" {

            It "-" {
                
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
                [ValidatePattern(".*.ps1$")]
                [string]
                $Path,

                [parameter()]
                [bool]
                $JoinDomain
            )' > $configPath
            { . $configPath -ComputerName "test" -Path $configPath -JoinDomain $true } | Should -Not -Throw

            #store an example of good data here to test against
            $json = '[{"StaticType":"System.String","Name":"ComputerName","Attributes":[{"NamedArguments":["Mandatory"],
            "Name":"parameter","PositionalArguments":[]},{"NamedArguments":[],"Name":"ValidateScript","PositionalArguments":
            ["{[System.Uri]::CheckHostName($_) -eq \"Dns\"}"]},{"NamedArguments":[],"Name":"ValidateLength","PositionalArguments":
            ["1","15"]},{"NamedArguments":[],"Name":"string","PositionalArguments":[]}]},{"StaticType":"System.String","Name":
            "Path","Attributes":[{"NamedArguments":["mandatory"],"Name":"Parameter","PositionalArguments":[]},
            {"NamedArguments":[],"Name":"ValidateNotNullOrEmpty","PositionalArguments":[]},{"NamedArguments":[],"Name":
            "ValidateScript","PositionalArguments":["{Test-Path $_}"]},{"NamedArguments":[],"Name":"ValidatePattern",
            "PositionalArguments":["\".*.ps1$\""]},{"NamedArguments":[],"Name":"string","PositionalArguments":[]}]},
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
                $param -match $hashtableReturn.Where({$_.Name -eq $param.Name}) | Should -Be $true
            }

            It "Ensure <Name> metadata is correct" -TestCases $modulereturn {
                param($StaticType, $Name, $Attributes)

                $matchingReturn = $hashtableReturn.Where({$_.Name -eq $Name})
                $Attributes.count | Should -Be $matchingReturn.Attributes.count
                $Attributes.Name | Should -Be $matchingReturn.Attributes.Name
            }

            It "Returns an array of hashtables" {
                $moduleReturn.GetType().BaseType.Name | Should -Be "Array"
                $moduleReturn.Foreach({ $_.GetType().Name | Should -Be "Hashtable"})
            }
        }

        Context "Bad Inputs" {
            
            It "Path parameter not ending in '.ps1' will cause an error" {

                "foo" > "$TestDrive\pathexists.exe"
                try
                {
                   Get-PSScriptParameterMetadata -Path "$TestDrive\pathexists.exe"
                }
                catch
                {
                   $error = $_ 
                }
                $error | Should -BeLike '*does not match the ".*.ps1$" pattern*'
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
                $error | Should -BeLike '*"Test-Path $_" validation script for the argument with value "Path\To\Knowhere.ps1"*'
            }
        }
    }

    Describe "Get-RequiredDscResourceList" {

        Context "Normal Operations" {

            #Fake config below to ensure the function parses out required DSC Resources correctly
            $configPath = "$TestDrive\testConfig.ps1"
            $configText = 'Configuration OSCore 
            { 
                Import-DscResource –ModuleName "PSDesiredStateConfiguration" -ModuleVersion 1.1
                Import-DscResource -ModuleName "xNetworking" -ModuleVersion 5.7.0.0
                Import-DscResource -ModuleName "xComputerManagement" -ModuleVersion 4.1.0.0
            }' >> $configPath
            { . $configPath } | Should -Not -Throw

            $correctReturn = @(
                @{ ModuleName = "xNetworking"        ; ModuleVersion = "5.7.0.0" }
                @{ ModuleName = "xComputerManagement"; ModuleVersion = "4.1.0.0" }
            )
            $resourceList = Get-RequiredDscResourceList -Path $ConfigPath

            It "ModuleName <ModuleName> & ModuleVersion <ModuleVersion> are returned correctly" -TestCases $resourceList {
                param ( $ModuleName, $ModuleVersion )

                $resourceList.Where({$ModuleName -eq $_.ModuleName}) -match $resource | Should -Be $true
                $resourceList.count | Should -Be 2
            }
        }

        Context "Bad Inputs" {

            $configPath = "$TestDrive\testConfig.ps1"

            It "Name parameter used will cause an error" {

                $configText = 'Configuration OSCore { Import-DscResource -Name xComputer -ModuleName "xComputerManagement" }' > $configPath
                { . $configPath } | Should -Not -Throw
                $testErrorStatement = "$configPath - Use of the 'Name' parameter when calling Import-DscResource is not supported."

                try
                { 
                    Get-RequiredDscResourceList -Path $ConfigPath 
                }
                catch
                {
                    $error = $_
                } 
                $error | Should -BeLike "$testErrorStatement*"
            }
            
            It "ModuleVersion parameter missing will cause an error" {
            
                $configText = 'Configuration OSCore { Import-DscResource -ModuleName "xNetworking" }' > $configPath
                { . $configPath } | Should -Not -Throw
                $testErrorStatement = "$configPath - Missing ModuleVersion parameter in config"
            
                try
                {
                    Get-RequiredDscResourceList -Path $ConfigPath 
                }
                catch
                {
                   $error = $_ 
                }
                $error | Should -BeLike "$testErrorStatement*"
            }
        }
    }

    Describe "Get-DscConfigurationName" {
        
        Context "Normal Operations" {

            $configPath = "$TestDrive\testConfig.ps1"
            $configText = 'Configuration Banana {}' > $configPath
            { . $configPath } | Should -Not -Throw

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
                { . $configPath } | Should -Not -Throw

                try
                {
                    $configName = Get-DscConfigurationName -Path $configPath
                }
                catch
                {
                    $error = $_
                }
                $error | Should -BeLike "$testErrorStatement*"
            }

            It "No configuration names found in a script will cause an error" {
           
                $configText = 'function Banana {}' > $configPath
                { . $configPath } | Should -Not -Throw

                try
                {
                    $configName = Get-DscConfigurationName -Path $configPath
                }
                catch
                {
                    $error = $_
                }
                $error | Should -BeLike "$testErrorStatement*"
            }
        }
    }
    
    Describe "Save-DscResourceList" {
        
        Context "Normal Operations" {

            $partialCatalogPath = "$ModuleRoot\testPartialCatalog.json"
            $dscResourcesPath = "$TestDrive\resources"
            $testPartialCatalog = (ConvertFrom-Json ([string](Get-Content $partialCatalogPath)))

            Mock -CommandName "Find-Module" -MockWith { throw } -ParameterFilter { $Name -eq "CoreApps" }
            Mock -CommandName "Find-Module" -MockWith { }

            #Cleanup output by nulling write-Warning
            Mock -CommandName "Write-Warning" -MockWith { }

            Mock -CommandName "Save-Module" -MockWith { New-Item -Path "$dscResourcesPath\$Name\$RequiredVersion" -ItemType Directory }

            $correctModuleList = @(
                @{ ModuleName = "xDnsServer"                  ; ModuleVersion = "1.11.0.0" }
                @{ ModuleName = "xNetworking"                 ; ModuleVersion = "5.7.0.0"  }
                @{ ModuleName = "xComputerManagement"         ; ModuleVersion = "4.1.0.0"  }
                @{ ModuleName = "xActiveDirectory"            ; ModuleVersion = "2.21.0.0" }
                @{ ModuleName = "CertificateDsc"              ; ModuleVersion = "4.2.0.0"  }
                @{ ModuleName = "xPSDesiredStateConfiguration"; ModuleVersion = "8.4.0.0"  }
            )

            Save-DscResourceList -PartialCatalogPath $partialCatalogPath -DscResourcesPath $dscResourcesPath

            It "Saves the required DSC resources to the specified path" -TestCases $correctModuleList {
                
                param( $ModuleName, $ModuleVersion )

                Test-Path -Path "$TestDrive\resources\$ModuleName\$ModuleVersion" | Should -Be $true
            }

            It "Saves the correct number of unique DSC resources" {
                
                (Get-ChildItem "$TestDrive\resources").Count | Should -Be $correctModuleList.count
            }

            It "Warned about CoreApps resource not found" {

                Assert-MockCalled -CommandName "Find-Module" -Times 1 -ParameterFilter {$Name -eq "CoreApps"}
            }

            It "Found and saved all Unique public Modules" {

                Assert-MockCalled -CommandName "Find-Module" -Times ($correctModuleList.count - 1)
                Assert-MockCalled -CommandName "Save-Module" -Times ($correctModuleList.count - 1)
            }

            It "Removes existing resource directories" {

                #Mocking Save-Module allows us to check to ensure the module directories were successfully removed
                Mock -CommandName "Save-Module" -MockWith { }
                
                Save-DscResourceList -PartialCatalogPath $partialCatalogPath -DscResourcesPath $dscResourcesPath
                
                (Get-ChildItem "$TestDrive\resources").Count | Should -Be 0
            }
        }
    }
    <#
    Describe "ConvertFrom-Hashtable" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Export-NodeDefinitionFile" {
        
        Context "Normal Operations" {

            It "-" {
                
            }
        }
    }

    Describe "Add-PartialProperties" {
        
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

    Describe "New-PartialCatalog" {
        
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
