<#
    .SYNOPSIS
        Core OS Settings
#>
Param
(
    [parameter(Mandatory)]
    [string]
    $TargetName,

    [parameter(Mandatory)]
    [string]
    $OutputPath,

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

    [parameter(Mandatory)]
    $NetworkConfig,

    [parameter(Mandatory)]
    [string]
    $ContentStore,

    [parameter()]
    [string]
    $JoinDomain
)

Configuration OSCore 
{ 
    Import-DscResource –ModuleName "PSDesiredStateConfiguration" -ModuleVersion 1.1
    Import-DscResource -ModuleName "xNetworking"
    Import-DscResource -ModuleName "xComputerManagement"
 
    Node $TargetName
    {
        #Collate Domain Join Partial object Dependencies
        $domainJoinDependsOn = @()

        foreach($network in $networks)
        {
            $adapterMAC = $network.MACAddress
            $adapterAlias = $network.Alias
            $ipAddress = $network.IPAddress
            $defaultGateway = $network.DefaultGateway
            $netmask = $network.SubnetBitMask
            $dnsAddress = $network.DNSServer
            $networkProfile = $network.NetworkCategory

            if ($ipAddress.Contains(":"))
            {
                $addressFamily = "IPv6"
            }
            else
            {
                $addressFamily = "IPv4"
            }

            if ($adapterMAC)
            {
                $targetAdapter = Invoke-Command -ComputerName $TargetName -ScriptBlock { Get-NetAdapter | Where-Object {$_.MacAddress -eq $using:adapterMAC}} -Credential $DomainCredential -ErrorAction SilentlyContinue
                $uid = $adapterMAC
            }
            else
            {
                $targetAdapter = Invoke-Command -ComputerName $TargetName -ScriptBlock { Get-NetIPInterface -InterfaceAlias $using:adapterAlias -AddressFamily $using:addressFamily } -Credential $DomainCredential -ErrorAction SilentlyContinue
                $uid = $adapterAlias
            }

            $interfaceAlias = $null
            $interfaceAlias = $targetAdapter.InterfaceAlias

            if ($null -eq $interfaceAlias)
            {
                Write-Error "Network adapter with provided identifier ($uid) not found on target." -ErrorAction Continue
                break
            }

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

            xDNSServerAddress "$interfaceAlias-$dnsAddress"
            {
                Address = $dnsAddress
                InterfaceAlias = $interfaceAlias
                AddressFamily = $addressFamily
            }
        }

        Registry NlaDelayedStart
        {
            Key = "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\NlaSvc"
            ValueName = "DelayedAutoStart"
            ValueData = "1"
            ValueType = "DWORD"
        }

        Registry DnsSearchSuffix
        {
            Key = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters"
            ValueName = "SearchList"
            ValueData = $DomainName
            ValueType = "String"
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

$networks = ConvertFrom-Json $NetworkConfig

$ConfigData = @{ 
    AllNodes = @(  
        @{ 
            NodeName = $TargetName
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        }
    ) 
} 

$null = OSCore -ConfigurationData $ConfigData -OutputPath $OutputPath
