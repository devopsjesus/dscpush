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

    $vmNetworkAddressList = @("192.0.0.236","192.0.0.237")
)

Describe "DscPush Workshop Deployment" {
    Context "VM DSC State" {
        
        #region Prepare for test
        $cimSessions = New-CimSession -ComputerName $vmNetworkAddressList -Credential $Credential
        Stop-DscConfiguration -CimSession $cimSessions -WarningAction Ignore
        #endregion

        It "Start-DscConfiguration should run successfully on the VMs" {
            { Start-DscConfiguration -CimSession $cimSessions -Wait -UseExisting } | Should Not Throw
        }
        
        It "Test-DscConfiguration should return True for both VMs" {
            $testDscReturn = Test-DscConfiguration -CimSession $cimSessions
            $testDscReturn | Should Be @($True,$True)
        }

        It "Get-DscConfiguration should run successfully on the VMs" {
            { Get-DscConfiguration -CimSession $cimSessions } | Should Not Throw
        }
    }
}