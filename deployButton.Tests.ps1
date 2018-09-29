#requires -RunAsAdministrator
#requires -Module Pester

<#
    .Synopsis
        Run these tests after deploying the DscPush Workshop configurations to infrastructure. 
        The VMs will need to reboot a few times before the Test-DscConfiguration cmdlet comes back true.

    .Parameter Credential
        The administrator credential for your image.

    .Parameter vmNetworkAddressList
        The IP addresses of the VMs you built.  Hopefully with code...

    .EXAMPLE
        $credential = get-credential administrator
        .\deployButton.Tests.ps1 -Credential $credential -VmNetworkAddressList @("192.0.0.30")
#>
param(
    [Parameter(Mandatory)]
    [pscredential]
    $Credential,

    [Parameter(Mandatory)]
    [string[]]
    $VmNetworkAddressList
)

Describe "DscPush Workshop Deployment" {
    Context "VM DSC State" {
        
        #region Prepare for test
        $cimSessions = New-CimSession -ComputerName $VmNetworkAddressList -Credential $Credential
        Stop-DscConfiguration -CimSession $cimSessions -WarningAction Ignore
        #endregion

        #populate the testCases var for Pester to run and report on each target
        $testCases = $cimSessions.ForEach({@{cimSession = $_;ComputerName=$_.ComputerName}})

        It "<ComputerName> should run Start-DscConfiguration successfully" -TestCases $testCases {
            param ( $cimSession )
            { Start-DscConfiguration -CimSession $cimSession -Wait -UseExisting -ErrorAction Stop } | Should Not Throw
        }

        It "<ComputerName> should return 'Success' from Get-DscConfigurationStatus" -TestCases $testCases {
            param ( $cimSession )
            $testResult = Get-DscConfigurationStatus -CimSession $cimSession -ErrorAction Stop
            "$($testResult.ResourcesNotInDesiredState.ResourceID)" | Should Be ""
            $testResult.Status | Should Be 'Success'
        }
        
        It "<ComputerName> should return True from Test-DscConfiguration"  -TestCases $testCases {
            param ( $cimSession )
            $testDscReturn = Test-DscConfiguration -CimSession $cimSession -ErrorAction Stop
            $testDscReturn | Should Be 'True'
        }

        It "<ComputerName> should run Get-DscConfiguration without throwing"  -TestCases $testCases {
            param ( $cimSession )
            { Get-DscConfiguration -CimSession $cimSession -ErrorAction Stop } | Should Not Throw
        }
    }
}
