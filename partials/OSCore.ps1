<#
    .SYNOPSIS
        Core OS Settings
#>
Param
(
    [parameter(Mandatory)]
    [ValidateScript({[System.Uri]::CheckHostName($_) -eq 'Dns'})]
    [ValidateLength(1,15)]
    [string]
    $ComputerName,

    [parameter(Mandatory)]
    [ValidateScript({[System.Uri]::CheckHostName($_) -eq 'Dns'})]
    [ValidateLength(1,64)]
    [string]
    $DomainName,

    [parameter(Mandatory)]
    [pscredential]
    $DomainCredential,

    [parameter()]
    [string]
    $JoinDomain
)

Configuration OSCore 
{ 
    Import-DscResource –ModuleName "PSDesiredStateConfiguration" -ModuleVersion 1.1
    Import-DscResource -ModuleName "xNetworking"
    Import-DscResource -ModuleName "xComputerManagement"
 
    Node $TargetIP
    {
        #Collate Domain Join Partial object Dependencies
        $domainJoinDependsOn = @()

        #Transfer values from in-scope DscPush type TargetConfig object $config
        $adapterMAC     = $config.TargetAdapter.PhysicalAddress
        $interfaceAlias = $config.TargetAdapter.InterfaceAlias
        $ipAddress      = $config.TargetAdapter.NetworkAddress[0]
        $defaultGateway = $config.TargetAdapter.Gateway
        $netmask        = $config.TargetAdapter.SubnetBits
        $dnsAddress     = $config.TargetAdapter.DNSAddress
        $networkProfile = $config.TargetAdapter.NetworkCategory
        $addressFamily  = $config.TargetAdapter.AddressFamily
        
        if ($adapterMAC)
        {
            $targetAdapter = Invoke-Command -ComputerName $TargetIP -ScriptBlock { Get-NetAdapter | Where-Object {$_.MacAddress -eq $using:adapterMAC}} -Credential $DomainCredential -ErrorAction Stop
            $interfaceAlias = $targetAdapter.InterfaceAlias
        }
        <#uncomment if you want to confirm the interface alias is correct, but otherwise, this call is unnecessary
        else
        {
            $targetAdapter = Invoke-Command -ComputerName $TargetIP -ScriptBlock { Get-NetIPInterface -InterfaceAlias $using:adapterAlias -AddressFamily $using:addressFamily } -Credential $DomainCredential -ErrorAction Stop
        }#>

        xIPAddress "$interfaceAlias-$ipAddress"
        {
            IPAddress = "$ipAddress/$netmask"
            InterfaceAlias = $interfaceAlias
            AddressFamily = $addressFamily
        }
            
        if ($defaultGateway)
        {
            xDefaultGatewayAddress "$interfaceAlias-$defaultGateway"
            {
                Address = $defaultGateway
                InterfaceAlias = $interfaceAlias
                AddressFamily = $addressFamily
            }
        }

        if ($dnsAddress)
        {
            xDNSServerAddress "$interfaceAlias-$dnsAddress"
            {
                Address = $dnsAddress
                InterfaceAlias = $interfaceAlias
                AddressFamily = $addressFamily
            }
        }

        if ($DomainName)
        {
            xDnsConnectionSuffix "$interfaceAlias-DnsConnectionSuffix"
            {
                InterfaceAlias = $interfaceAlias
                ConnectionSpecificSuffix = $DomainName
            }
        }

        Registry NlaDelayedStart
        {
            Key = "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc"
            ValueName = "DelayedAutoStart"
            ValueData = "1"
            ValueType = "DWORD"
        }

        if ($DomainName)
        {
            Registry DnsSearchSuffix
            {
                Key = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
                ValueName = "SearchList"
                ValueData = $DomainName
                ValueType = "String"
            }
        }

        if($JoinDomain -eq 'true')
        {
            xComputer JoinDomain
            {
                Name = $ComputerName
                DomainName = $DomainName
                Credential = $(New-Object System.Management.Automation.PSCredential("$DomainName\$($DomainCredential.UserName)", $DomainCredential.Password))
                DependsOn = $domainJoinDependsOn
            }
        }
        else
        {
            xComputer NewComputerName 
            { 
                Name = $ComputerName
            } 
        }
    }
}
