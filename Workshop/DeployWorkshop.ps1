#requires -RunAsAdministrator

param(
    $Credential,

    $VmList = @(
        @{TargetItemName = "DscPushDC"; TargetIP = "192.0.0.236"; MacAddress = "00-15-5d-36-F2-10"; VmMemory = 1024MB }
        @{TargetItemName = "DscPushCH"; TargetIP = "192.0.0.237"; MacAddress = "00-15-5d-36-F2-11"; VmMemory = 1024MB }
    ),

    $VhdPath = "C:\Users\Public\Documents\Hyper-V\Virtual hard disks\win2016core.vhdx",

    [switch]
    $ClobberVMs
)

#cleanup
Remove-Item C:\DscPushWorkshop,C:\Windows\Temp\dscpushworkshop -Recurse -Force -ErrorAction Ignore

if ($ClobberVMs)
{
    Stop-VM $vmList.TargetItemName -Force -ErrorAction Ignore
    Remove-VM $vmList.TargetItemName -Force -ErrorAction Ignore
    
    $vhdParentPath = Split-Path -Path $VhdPath -Parent
    $vmList.TargetItemName.ForEach({
        Remove-Item "$vhdParentPath\$_.vhdx" -ErrorAction Ignore
    })
}

Write-Verbose "Copy and unzip the repo from github"
Start-BitsTransfer -Source "https://github.com/devopsjesus/dscpush/archive/master.zip" -Destination "$env:TEMP\dscpushworkshop.zip"
Expand-Archive "$env:TEMP\dscpushworkshop.zip" -DestinationPath "$env:TEMP\dscpushworkshop" -Force

Write-Verbose "Copy the zip contents to the workshop directory"
$null = New-Item "C:\DSCPushWorkshop" -ItemType Directory -Force
Copy-Item "$env:TEMP\dscpushworkshop\dscpush-master\*" -Destination "C:\DSCPushWorkshop" -Force -Recurse

Write-Verbose "Generating Hyper-V Machines"
. C:\DSCPushWorkshop\Workshop\WorkshopStep0-hyperv.ps1 -Credential $Credential -VmList $VmList -VhdPath $VhdPath

Write-Verbose "Making appropriate changes to the system"
. C:\DSCPushWorkshop\Workshop\WorkshopStep1.ps1

Write-Verbose "Generating and Deploying the configurations with changes"
. C:\DSCPushWorkshop\Workshop\WorkshopStep2 -DeploymentCredential $Credential
