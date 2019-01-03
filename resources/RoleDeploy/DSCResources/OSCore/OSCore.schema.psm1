<#
    .SYNOPSIS
        A composite DSC resource to deploy core OS functionality.

    .PARAMETER Credential
        The credential used to connect/authenticate to the target node.

    .PARAMETER Path
        Path to the Binary install file.

    .PARAMETER Ensure
        Ensures configuration is Present or Absent.

    .EXAMPLE
        The following is an example of a configuration that could be used to deploy OSCore.

Configuration DesktopValidatorStandard
{
    Import-DscResource -ModuleName AppInstall

    node $TargetName
    {
        OSCore OSCore
        {
            Credential = $Credential
            Path       = $Path
        }
    }
}

$ConfigData = @{
    AllNodes = @(
        @{
            NodeName                    = $TargetName
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser        = $true
        }
    )
}

$null = OSCore -OutputPath $OutPutPath -ConfigurationData $ConfigData
#>
Configuration OSCore 
{ 
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

    Import-DscResource -ModuleName "PSDesiredStateConfiguration" -ModuleVersion 1.1
    Import-DscResource -ModuleName "xNetworking" -ModuleVersion 5.7.0.0
    Import-DscResource -ModuleName "xComputerManagement" -ModuleVersion 4.1.0.0
    Import-DscResource -ModuleName "xPSDesiredStateConfiguration" -ModuleVersion 8.3.0.0
    
    #Collate Domain Join Partial object Dependencies
    $domainJoinDependsOn = @()

    #DscPush type TargetConfig objects are passed in as $AllNodes.TargetConfig
    $adapterMAC     = $AllNodes.TargetConfig.TargetAdapter.PhysicalAddress
    $interfaceAlias = $AllNodes.TargetConfig.TargetAdapter.InterfaceAlias
    $ipAddress      = $AllNodes.TargetConfig.TargetAdapter.NetworkAddress[0].ToString()
    $defaultGateway = $AllNodes.TargetConfig.TargetAdapter.Gateway
    $netmask        = $AllNodes.TargetConfig.TargetAdapter.SubnetBits
    $dnsAddress     = $AllNodes.TargetConfig.TargetAdapter.DNSAddress
    $networkProfile = $AllNodes.TargetConfig.TargetAdapter.NetworkCategory
    $addressFamily  = $AllNodes.TargetConfig.TargetAdapter.AddressFamily
        
    if ($adapterMAC)
    {
        try
        {
            $sessionOption = New-PSSessionOption -OpenTimeout 2000 -OperationTimeout 2000
            $targetAdapter = Invoke-Command -ComputerName $ipAddress -SessionOption $sessionOption -ScriptBlock { Get-NetAdapter | Where-Object {$_.MacAddress -eq $using:adapterMAC}} -Credential $DomainCredential -ErrorAction Stop
            $interfaceAlias = $targetAdapter.InterfaceAlias
        }
        catch
        {
            Write-Verbose "Could not connect to remote machine to get alias, assuming 'Ethernet'"
            $interfaceAlias = "Ethernet"
        }
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
            Credential = $DomainCredential
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
