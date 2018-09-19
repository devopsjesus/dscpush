$ModuleRoot = $PSScriptRoot
$ModulePath = $MyInvocation.MyCommand.Path -replace '\.Tests\.ps1$','.psm1'
$ModuleName = Split-Path -Path $ModuleRoot -Leaf

Get-Module $ModuleName -ErrorAction SilentlyContinue | Remove-Module
Import-Module -FullyQualifiedName $ModulePath -ErrorAction Stop

InModuleScope $ModuleName {

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
                $resourceList = Get-RequiredDscResourceList -DscConfigurationPath $ConfigPath
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
                { Get-RequiredDscResourceList -DscConfigurationPath $ConfigPath } | Should throw
            }
        }

        Context "'Name' Parameter is passed to Import-DscResource cmdlet in config" {
            #Fake config below to ensure the function parses out required DSC Resources correctly
            $configPath = "$TestDrive\testConfig.ps1"
            $configText = 'Configuration OSCore 
            { 
                Import-DscResource –ModuleName "PSDesiredStateConfiguration" -ModuleVersion 1.1
                Import-DscResource -ModuleName "xNetworking"
                Import-DscResource -Name xComputer -ModuleName "xComputerManagement" -ModuleVersion 4.1.0.0
            }' >> $configPath
            . $configPath

            It "Throws on Name parameter in use" {
                { Get-RequiredDscResourceList -DscConfigurationPath $ConfigPath } | Should throw
            }
        }
    }
}
