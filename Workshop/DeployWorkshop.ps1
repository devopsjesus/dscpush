#requires -RunAsAdministrator

param(
    $Credential = (New-Object System.Management.Automation.PSCredential (“administrator”, (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force))),

    $vmNetworkAddressList = @("192.0.0.236","192.0.0.237"),

    [switch]
    $ClobberVMs
)

#cleanup
Remove-Item C:\DscPushWorkshop,C:\Windows\Temp\dscpushworkshop -Recurse -Force -ErrorAction Ignore

if ($ClobberVMs)
{
    Stop-VM dscpushdc,dscpushch -Force -ErrorAction Ignore
    Remove-VM dscpushdc,dscpushch -Force -ErrorAction Ignore
    Remove-Item 'C:\users\Public\Documents\Hyper-V\Virtual hard disks\DscPushCH.vhdx','C:\users\Public\Documents\Hyper-V\Virtual hard disks\DscPushDC.vhdx' -ErrorAction Ignore
}

Start-BitsTransfer -Source https://github.com/devopsjesus/dscpush/archive/master.zip -Destination C:\windows\Temp\dscpushworkshop.zip
Expand-Archive C:\windows\Temp\dscpushworkshop.zip -DestinationPath C:\windows\Temp\dscpushworkshop -Force
$null = New-Item C:\DSCPushWorkshop -ItemType Directory -Force
Copy-Item C:\Windows\Temp\dscpushworkshop\dscpush-master\* -Destination C:\DSCPushWorkshop -Force -Recurse

. C:\DSCPushWorkshop\Workshop\WorkshopStep0-hyperv.ps1 -clobber -Credential $Credential

. C:\DSCPushWorkshop\Workshop\WorkshopStep1.ps1

. C:\DSCPushWorkshop\Workshop\WorkshopStep2 -DeploymentCredential $Credential