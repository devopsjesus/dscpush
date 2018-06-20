#requires -RunAsAdministrator

param(
    $Credential = (New-Object System.Management.Automation.PSCredential (“administrator”, (ConvertTo-SecureString "P@ssw0rd123" -AsPlainText -Force))),

    $VmList = @(
        @{TargetItemName = "DscPushDC"; TargetIP = "192.0.0.236"; MacAddress = "00-15-5d-36-F2-10"; VmMemory = 1024MB }
        @{TargetItemName = "DscPushCH"; TargetIP = "192.0.0.237"; MacAddress = "00-15-5d-36-F2-11"; VmMemory = 1024MB }
    ),

    [switch]
    $ClobberVMs
)

#cleanup
Remove-Item C:\DscPushWorkshop,C:\Windows\Temp\dscpushworkshop -Recurse -Force -ErrorAction Ignore

if ($ClobberVMs)
{
    Stop-VM $vmList.TargetItemName -Force -ErrorAction Ignore
    Remove-VM $vmList.TargetItemName -Force -ErrorAction Ignore
    $vmList.TargetItemName.ForEach({
        Remove-Item "C:\users\Public\Documents\Hyper-V\Virtual hard disks\$_.vhdx" -ErrorAction Ignore
    })
}

Write-Verbose "Copy and unzip the repo from github"
Start-BitsTransfer -Source "https://github.com/devopsjesus/dscpush/archive/master.zip" -Destination "$env:TEMP\dscpushworkshop.zip"
Expand-Archive "$env:TEMP\dscpushworkshop.zip" -DestinationPath "$env:TEMP\dscpushworkshop" -Force

Write-Verbose "Copy the zip contents to the workshop directory"
$null = New-Item "C:\DSCPushWorkshop" -ItemType Directory -Force
Copy-Item "$env:TEMP\dscpushworkshop\dscpush-master\*" -Destination "C:\DSCPushWorkshop" -Force -Recurse

Write-Verbose "Generating Hyper-V Machines"
. C:\DSCPushWorkshop\Workshop\WorkshopStep0-hyperv.ps1 -Credential $Credential -VmList $VmList

Write-Verbose "Making appropriate changes to the system"
. C:\DSCPushWorkshop\Workshop\WorkshopStep1.ps1

Write-Verbose "Generating and Deploying the configurations with changes"
. C:\DSCPushWorkshop\Workshop\WorkshopStep2 -DeploymentCredential $Credential
