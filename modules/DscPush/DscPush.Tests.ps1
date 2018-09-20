$ModuleRoot = $PSScriptRoot
$ModulePath = $MyInvocation.MyCommand.Path -replace '\.Tests\.ps1$','.psm1'
$ModuleName = Split-Path -Path $ModuleRoot -Leaf

Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module
Import-Module -FullyQualifiedName $ModulePath -ErrorAction Stop

InModuleScope $ModuleName {

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
            )' >> $configPath
            . $configPath -ComputerName "test" -Path $configPath -JoinDomain $true

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
            . $configPath

            $correctReturn = @(
                <#@{ we filter out PSDSC
                    ModuleName = "PSDesiredStateConfiguration"
                    ModuleVersion = "1.1"
                } #>
                @{
                    ModuleName = "xNetworking"
                    ModuleVersion = "5.7.0.0"
                }
                @{
                    ModuleName = "xComputerManagement"
                    ModuleVersion = "4.1.0.0"
                }
            )

            It "Returns a list of DSC Resource Names and Version Numbers" {
                $resourceList = Get-RequiredDscResourceList -Path $ConfigPath
                foreach ($resource in $correctReturn)
                {
                    $resourceList.Where({$resource.ModuleName -eq $_.ModuleName}) -match $resource | Should -Be $true
                }
            }
        }

        Context "Missing ModuleVersion" {
            #Fake config below to ensure the function parses out required DSC Resources correctly
            $configPath = "$TestDrive\testConfig.ps1"
            $configText = 'Configuration OSCore 
            { 
                Import-DscResource –ModuleName "PSDesiredStateConfiguration" -ModuleVersion 1.1
                Import-DscResource -ModuleName "xNetworking"
                Import-DscResource -ModuleName "xComputerManagement" -ModuleVersion 4.1.0.0
            }' >> $configPath
            . $configPath
            
            It "Throws on a missing ModuleVersion parameter" {
                { Get-RequiredDscResourceList -Path $ConfigPath } | Should throw
            }
        }

        Context "'Name' Parameter is passed to Import-DscResource cmdlet in config" {
            #Fake config below to ensure the function parses out required DSC Resources correctly
            $configPath = "$TestDrive\testConfig.ps1"
            $configText = 'Configuration OSCore 
            { 
                Import-DscResource –ModuleName "PSDesiredStateConfiguration" -ModuleVersion 1.1
                Import-DscResource -ModuleName "xNetworking" -ModuleVersion 5.7.0.0
                Import-DscResource -Name xComputer -ModuleName "xComputerManagement" -ModuleVersion 4.1.0.0
            }' >> $configPath
            . $configPath

            It "Throws on Name parameter in use" {
                { Get-RequiredDscResourceList -Path $ConfigPath } | Should throw
            }
        }
    }
}
