#Requires -Version 5 –Modules Hyper-V -RunAsAdministrator

<#
    .SYNOPSIS
        Use this script to deploy infrastructure using a Node Definition file used by the DscPush module.

    .DESCRIPTION
        This script deploys infrastructure to Hyper-V using the same Node Definition file that DscPush uses to compile and
        deploy configurations to target nodes. By using the same source of data for both infrastructure and configuration,
        we can keep all the data in the same location for both infra and config.

    .PARAMETER VhdPath
        Path to a sysprepped VHDx that will be copied as the target VHDx for the VM (or used a the parent of a differencing 
        disk if the DifferencingDisk switch is present).

    .PARAMETER VSwitchName
        Name of the switch to connect the VM. If the switch does not exist, it will be created, so be careful with typos.

    .PARAMETER HostIpAddress
        IP address assigned to the specified vSwitch.
        
    .PARAMETER Credential
        Typically the local administrator account from your gold image, which you built with WimAuto, right?

    .PARAMETER VmCreationTimeoutSec
        Specifies the number of seconds to wait until the VM creation workflow times out. Default is 600.
    
    .PARAMETER AdapterCount
        Number of adapters to attach to the VM(s). Default is 1.

    .PARAMETER MemoryInGB
        Amount of memory to assign to the VM(s) - given in GB notation (e.e. "2GB" or "32GB"), but can be passed in as integer.
        Max is 12TB

    .PARAMETER TargetSubnet
        IPv4 address representation of the target adapter subnet

    .PARAMETER NodeDefinitionFilePath
        Path to the Node Definition File used by DscPush module that contains the required data to configure the VMs.

    .PARAMETER Clobber
        This switch will delete and rewrite target VM and VHDx

    .PARAMETER DifferencingDisk
        This switch will designate the VHDx specified by $VhdPath to be the parent disk for the target VM's VHDx.

    .EXAMPLE
        1. Deploy infrastructure for publishing DSC configurations:

            $deployParams = @{
                VhdPath                = "C:\VirtualHardDisks\WindowsServer2016-2-20190102.vhdx"
                VSwitchName            = "DSC-vSwitch1"
                HostIpAddress          = "192.0.0.247"
                AdapterCount           = 1
                MemoryInGB             = 2GB
                TargetSubnet           = "255.255.255.0"
                NodeDefinitionFilePath = "C:\DscPushTest\nodeDefinitions\WindowsServerStandalone.ps1"
                Clobber                = $true
                DifferencingDisk       = $true
            }
            .\deployVM-HyperV.ps1 @deployParams


        2. Deploy infrastructure from a config-injected VHDx:

            $injectParams = @{
                VhdPath                = "C:\VirtualHardDisks\DscTest.vhdx"
                VSwitchName            = "DSC-vSwitch1"
                HostIpAddress          = "192.0.0.247"
                AdapterCount           = 1
                MemoryInGB             = 3GB
                TargetSubnet           = "255.255.255.0"
                NodeDefinitionFilePath = "C:\DscPushTest\nodeDefinitions\Windows2016Baseline.ps1"
            }
            .\deployVM-HyperV.ps1 @injectParams


#>
param(
    [parameter(mandatory)]
    [ValidateScript({Test-Path $_})]
    [string]
    $VhdPath,

    [parameter(mandatory)]
    [string]
    $VSwitchName,
    
    [parameter(mandatory)]
    [ipaddress]
    $HostIpAddress,

	[parameter(mandatory)]
    [pscredential]
    $Credential,

    [parameter()]
    [int]
    $VmCreationTimeoutSec = 600,
    
    [parameter()]
    [int]
    $AdapterCount = 1,

    [parameter()]
    [ValidateScript({$_ -lt 13194139533313})]
    [int64]
    $MemoryInGB,

    [parameter(mandatory)]
    [ipaddress]
    $TargetSubnet,
    
    [parameter(mandatory)]
    [ValidateScript({Test-Path $_})]
    [string]
    $NodeDefinitionFilePath,
    
    [parameter()]
    [switch]
    $Clobber,
    
    [parameter()]
    [switch]
    $DifferencingDisk
)

Import-Module Hyper-V

if (! (Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_VirtualSystemManagementService -ErrorAction Ignore))
{
    throw "Incorrect version of Hyper-V. Please update to continue"
}

#region Build the VM configs list
$nodeDefinition = . $NodeDefinitionFilePath

$vmList = $nodeDefinition.Configs.ForEach({
    @{
        TargetItemName = $_.Variables.ComputerName
        TargetIP       = $_.TargetAdapter.NetworkAddress[0]
        MacAddress     = $_.TargetAdapter.PhysicalAddress
        VmMemory       = $MemoryInGB
    }
})
#endregion

#region TrustedHosts
#Add the IP list of the target VMs to the trusted host list
$currentTrustedHost = (Get-Item WSMan:\localhost\Client\TrustedHosts).Value

if(($currentTrustedHost -ne '*') -and ([string]::IsNullOrEmpty($currentTrustedHost) -eq $false))
{
    $scriptTrustedHost = $currentTrustedHost + ", " + $($vmList.TargetIP -join ", ")

    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $scriptTrustedHost -Force
}
elseif($currentTrustedHost -ne '*')
{
    $scriptTrustedHost = $Targets.TargetIP -join ", "

    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $scriptTrustedHost -Force
}
#endregion

#region host networking 
$switch = Get-VMSwitch $VSwitchName -ErrorAction Ignore
if (!($switch))
{
    $null = New-VMSwitch $VSwitchName -SwitchType Internal
}

#Set host IP for pre-build
$localIPList = Get-NetIPAddress
$targetNIC = Get-NetAdapter -Name "vEthernet ($VSwitchName)"
if ($localIPList.IPAddress -notcontains $HostIpAddress)
{
    $null = New-NetIPAddress –IPAddress $HostIpAddress –PrefixLength 24 -InterfaceIndex $targetNIC.ifIndex -ErrorAction Ignore
    $null = Set-NetIPAddress –IPAddress $HostIpAddress –PrefixLength 24 -InterfaceIndex $targetNIC.ifIndex -ErrorAction Ignore 
}

#Set host network adapter/switch to enabled
if ($targetNIC.Status -eq 'Disabled') 
{ 
    $null = Enable-NetAdapter -InputObject $targetNIC -Confirm:$false 
}
#endregion

#region provisioning VMs
workflow ConfigureVM
{
	param(
		$VmList,

        $VHDPath,

        $HostIpAddress,

        $VSwitchName,

        $Subnet,

        $AdapterCount,

        $RemoteCred,

        [bool]$Clobber,

        [bool]$DifferencingDisk
	)

    $vhdParentPath = Split-Path -Path $VHDPath -Parent

	foreach -parallel ($vm in $VmList)
	{
        sequence
        {
		    $vmName   = $vm.TargetItemName
            $vmIp     = $vm.TargetIP
            $vmMac    = $vm.MacAddress
            $vmMemory = $vm.vmMemory

	        #First cleanup the environment by removing the existing VMs and VHDXs, if clobber is set to true
            Write-Output "Deploying infrastructure for target item $vmName"

            if (Test-Path "$vhdParentPath\$vmName.vhdx")
		    {
                if ($Clobber)
                {
                    Stop-VM $vmName -TurnOff -Force -ErrorAction Ignore -WarningAction Ignore
	    		    Remove-VM $vmName -Force -ErrorAction Ignore
			        Remove-Item "$vhdParentPath\$vmName.vhdx" -ErrorAction Ignore

		            if ($DifferencingDisk)
                    {
                        Write-Output "Creating differencing disk at $vhdParentPath\$vmName.vhdk"
                        $newVHD = New-VHD -Path "$vhdParentPath\$vmName.vhdx" -ParentPath "$VHDPath" -Differencing
                    }
                    else #do a full copy
                    {
                        Write-Output "Copying sysprepped VHDX to $vhdParentPath\$vmName.vhdk"
                        Copy-Item -Path "$VHDPath" -Destination "$vhdParentPath\$vmName.vhdx" -Force
                    }
                }
                else
                {
                    Write-Output "VHD for VM $vmName already exists, and Clobber was not specified. Skipping VM VHD creation."
                }
		    }
            else
            {
                #create new differencing disks based on the template disk
		        if ($DifferencingDisk)
                {
                    Write-Output "Creating differencing disk at $vhdParentPath\$vmName.vhdk"
                    $newVHD = New-VHD -Path "$vhdParentPath\$vmName.vhdx" -ParentPath "$VHDPath" -Differencing
                }
                else #do a full copy
                {
                    Write-Output "Copying sysprepped VHDX to $vhdParentPath\$vmName.vhdk"
                    Copy-Item -Path "$VHDPath" -Destination "$vhdParentPath\$vmName.vhdx" -Force
                }
            }
        
            if (Get-VM $vmName -ErrorAction Ignore)
		    {
                if ("$vhdParentPath\$vmName.vhdx" -notin (Get-VMHardDiskDrive -VMName $vmName).Path)
                {
                    throw "Existing VM container with different disk attached"
                }
            }
            else
            {
                #Create the new VMs based on the template VHDX
		        $null = New-VM -Name $vmName -MemoryStartupBytes $VmMemory -VHDPath "$vhdParentPath\$vmName.vhdx" -Generation 2

		        #Create and configure the vNICs, assigning the static MAC addresses to the DscPush-vSwitch1 connected NICs
                Connect-VMNetworkAdapter -VMName $vmName -Name "Network Adapter" -SwitchName $VSwitchName
		        Set-VMNetworkAdapter -VMName $vmName -Name "Network Adapter" -StaticMacAddress $vmMac
            }

            Write-Output "Starting VM $vmName"
		    Start-VM -Name $vmName -WarningAction SilentlyContinue

		    #Remove dashes from MAC address for Set-VmGuestIpAddress function requirements
		    $vmMac = $vmMac.Replace('-','')

            Write-Output "Configuring target item $vmName"
		    while (! ($ipSet))
		    {
			    Start-Sleep 1
			    Set-VmGuestIpAddress -VmName $vmName -MacAddress $vmMac -IpAddress $vmIp -Subnet $Subnet

                $vmIPList = (Get-VM -Name $vmName | Get-VMNetworkAdapter).IPAddresses

                $ipSet = $vmIP -in $vmIPList
		    }

            for ($i = 1; $AdapterCount -gt $i; $i++)
            {
                $null = Add-VMNetworkAdapter -VMName $vmName -SwitchName $VSwitchName
            }
        }
	}
}

<# #>
function Set-VmGuestIpAddress
{
    param(
        $VmName,

        $MacAddress,

        $IpAddress,
		
		[parameter(mandatory)]
        $Subnet,

        $Gateway = $HostIpAddress
    )
    #WMI required throughout this function because CIM functionality is not completely transcribed at this time 04/10/2018
    $hypervManagement = Get-WmiObject -ClassName 'Msvm_VirtualSystemManagementService' -Namespace 'root\virtualization\v2' 

    $guestVM = Get-WmiObject -ClassName 'Msvm_ComputerSystem' -Namespace 'root\virtualization\v2' -Filter "ElementName='$vmName'"

    $guestVMCim = Get-CimInstance -ClassName 'Msvm_ComputerSystem' -Namespace 'root\virtualization\v2' -Filter "ElementName='$vmName'"

    $hyperVGuestSettings = Get-CimAssociatedInstance -ResultClassName Msvm_VirtualSystemSettingData -InputObject $guestVMCim

    $hyperVGuestEthernetSettings = Get-CimAssociatedInstance -ResultClassName Msvm_SyntheticEthernetPortSettingData -InputObject $hyperVGuestSettings[0]

    #Need a loop because there is no filter option and using a "Where" clause changes object type from cimInstance to List
    foreach ($nic in $hyperVGuestEthernetSettings)
    {
        if ($nic.Address -eq $MacAddress)
        {
            $targetNic = $nic
        }
    }

    $instance = ($targetnic.instanceid.Split('\'))[1]

    #Need to use WMI here instead of CIM because there's no straightforward way to convert the NIC Config into
    #text, required by the SetGuestNetworkAdapterConfiguration method.  There is not a comparable CIM method
    $targetNicConfig = Get-WmiObject -Namespace root\virtualization\v2 -Class 'Msvm_GuestNetworkAdapterConfiguration' -Filter "InstanceID like '%$($instance)'"

    $targetNicConfig.DHCPEnabled = $false
    $targetNicConfig.IPAddresses = @("$IpAddress")
    $targetNicConfig.Subnets = @("$Subnet")
    $targetNicConfig.DefaultGateways = @("$Gateway")
    
    $null = $hypervManagement.SetGuestNetworkAdapterConfiguration($guestVM, $targetNicConfig.GetText(1))
}

try
{
    $vmConfig = @{
        VmList              = $vmList
        HostIPAddress       = $HostIpAddress
        VHDPath             = $VhdPath
        VSwitchName         = $VSwitchName
        Subnet              = $TargetSubnet
        AdapterCount        = $AdapterCount
        RemoteCred          = $Credential
        Clobber             = $Clobber
        DifferencingDisk    = $DifferencingDisk
        PSElapsedTimeoutSec = $VmCreationTimeoutSec
    }
    ConfigureVM @vmConfig
}
finally
{
    #Always reset the trusted host setting
    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $currentTrustedHost -Force
}
#endregion
