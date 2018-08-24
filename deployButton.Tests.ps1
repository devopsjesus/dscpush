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
#>
param(
    $Credential = (New-Object System.Management.Automation.PSCredential (“administrator”, (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force))),

    $vmNetworkAddressList = @("192.168.1.24")
)

Describe "DscPush Workshop Deployment" {
    Context "VM DSC State" {
        
        #region Prepare for test
        $cimSessions = New-CimSession -ComputerName $vmNetworkAddressList -Credential $Credential
        Stop-DscConfiguration -CimSession $cimSessions -WarningAction Ignore
        #endregion

        #populate the testCases var for Pester to run and report on each target
        $testCases = $cimSessions.ForEach({@{cimSession = $_}})

        It "Start-DscConfiguration should run successfully on <cimSession>" -TestCases $testCases {
            param ( $cimSession )
            { Start-DscConfiguration -CimSession $cimSession -Wait -UseExisting -ErrorAction Stop } | Should Not Throw
        }
        
        It "Test-DscConfiguration should return True for <cimSession>"  -TestCases $testCases {
            param ( $cimSession )
            $testDscReturn = Test-DscConfiguration -CimSession $cimSession
            $testDscReturn | Should Be @($True,$True)
        }

        It "Get-DscConfiguration should run successfully on <cimSession>"  -TestCases $testCases {
            param ( $cimSession )
            { Get-DscConfiguration -CimSession $cimSession } | Should Not Throw
        }
    }
}
