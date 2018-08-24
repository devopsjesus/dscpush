#Requires -Version 5 –Modules Hyper-V -RunAsAdministrator

param(
    $VhdPath = "C:\Virtualharddisks\win2016core.vhdx",

    $VSwitchName = "Internet-NIC1",
    
    $HostIpAddress = "192.168.1.23",
    
    $DnsServer = "192.168.1.254",

	[parameter(mandatory)]
    [pscredential]
    $Credential,

    $AdapterCount = 1,

    $TargetSubnet = "255.255.255.0",

    [switch]$Clobber = $true,

    [switch]$DifferencingDisks,
    
    $NodeDefinitionFilePath = "C:\Library\deploy\DSCPushSetup\DefinitionStore\NodeDefinition.ps1"
)

if (!(Get-CimInstance -Namespace root\virtualization\v2 -Class Msvm_VirtualSystemManagementService -ErrorAction Ignore))
{
    throw "Incorrect version of Hyper-V. Please update to continue"
}

#Region Ensure paths are valid
if (! (Test-Path $VhdPath))
{
    throw "Could not find Parent VHDX."
}

if (! (Test-Path $NodeDefinitionFilePath))
{
    throw "Could not find Node Definition File."
}
#endregion

#region Build the VM configs list
$nodeDefinition = . $NodeDefinitionFilePath

$vmList = $nodeDefinition.Configs.ForEach({
    @{
        TargetItemName = $_.Variables.ComputerName
        TargetIP       = $_.TargetAdapter.NetworkAddress.IPAddressToString
        MacAddress     = $_.TargetAdapter.PhysicalAddress
        VmMemory       = 1024MB
    }
})
#endregion

function Set-VmGuestIpAddress
{
    param(
        $VmName,

        $MacAddress,

        $IpAddress,
		
		[parameter(mandatory)]
        $Subnet,

        $Gateway = $HostIpAddress,

        $Dns = $dnsServer
    )
    #WMI required throughout this function because CIM functionality is not completely transcribed at this time 12/5/2016
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
    $targetNicConfig.DNSServers = @("$Dns")
    
    $null = $hypervManagement.SetGuestNetworkAdapterConfiguration($guestVM, $targetNicConfig.GetText(1))
}

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

        $VSwitchName,

        $Subnet,

        $AdapterCount,

        $RemoteCred,

        [bool]$Clobber,

        [bool]$DifferencingDisks
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
                    Stop-VM $vmName -TurnOff -Force -ErrorAction Ignore
	    		    Remove-VM $vmName -Force -ErrorAction Ignore
			        Remove-Item "$vhdParentPath\$vmName.vhdx" -ErrorAction Ignore

                    #create new differencing disks based on the template disk
		            if ($DifferencingDisks)
                    {
                        $newVHD = New-VHD -Path "$vhdParentPath\$vmName.vhdx" -ParentPath "$VHDPath" -Differencing
                    }
                    else #do a full copy
                    {
                        Copy-Item -Path "$VHDPath" -Destination "$vhdParentPath\$vmName.vhdx" -Force
                    }
                }
                else
                {
                    Write-Output "VHD for VM $vmName already exists, and Clobber was not specified.  Skipping VM VHD creation."
                }
		    }
            else
            {
                #create new differencing disks based on the template disk
		        if ($DifferencingDisks)
                {
                    $newVHD = New-VHD -Path "$vhdParentPath\$vmName.vhdx" -ParentPath "$VHDPath" -Differencing
                }
                else #do a full copy
                {
                    Copy-Item -Path "$VHDPath" -Destination "$vhdParentPath\$vmName.vhdx" -Force
                }
            }
        
            if (!(Get-VM $vmName -ErrorAction Ignore))
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
		    while (!($remoteConnectTest))
		    {
			    sleep 1
			    Set-VmGuestIpAddress -VmName $vmName -MacAddress $vmMac -IpAddress $vmIp -Subnet $Subnet -ErrorAction Ignore
                $remoteConnectTest = Test-WSMan $vmIp -ErrorAction Ignore
		    }

            $i = 1
		    while ($AdapterCount -lt $i)
            {
                $null = Add-VMNetworkAdapter -VMName $vmName -SwitchName $VSwitchName
                $i++
            }
        }
	}
}

try
{
    $vmConfig = @{
        VmList            = $vmList
        VHDPath           = $VhdPath
        VSwitchName       = $VSwitchName
        Subnet            = $TargetSubnet
        AdapterCount      = $AdapterCount
        RemoteCred        = $Credential
        Clobber           = $Clobber
        DifferencingDisks = $DifferencingDisks
    }

    ConfigureVM @vmConfig
}
finally
{
    #Always reset the trusted host setting
    Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $currentTrustedHost -Force
}
#endregion
