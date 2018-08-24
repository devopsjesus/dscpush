<#
    .SYNOPSIS
        Domain Controller
#>
Param
(
    [parameter(Mandatory)]
    [ValidateScript({[System.Uri]::CheckHostName($_) -eq 'Dns'})]
    [ValidateLength(1,15)]
    [string]
    $ComputerName,
    
    [parameter(Mandatory = $true)]
    [ValidateScript({[System.Uri]::CheckHostName($_) -eq 'Dns'})]
    [ValidateLength(1,64)]
    [string]
    $DomainName,

    [parameter(Mandatory = $true)]
    [pscredential]
    $DomainCredential
)

Configuration DomainController
{ 
    Import-DscResource -ModuleName 'PSDesiredStateConfiguration' -ModuleVersion 1.1
    Import-DscResource -ModuleName 'xActiveDirectory'
    Import-DscResource -ModuleName 'xDnsServer'
 
    Node $TargetIP
    {
        WindowsFeature ADDSInstall 
        { 
            Ensure = "Present" 
            Name = "AD-Domain-Services" 
        }

        xADDomain CreateDomain 
        { 
            DomainName = $DomainName 
            DomainAdministratorCredential = $DomainCredential
            SafemodeAdministratorPassword = $DomainCredential
            DomainNetbiosName = $DomainName.Split(".")[0]
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        xADUser SetupAdmin 
        { 
            DomainName = $DomainName 
            UserName = "Administrator" 
            PasswordNeverExpires = $true
            DependsOn = "[WindowsFeature]ADDSInstall","[xADDomain]CreateDomain"
        }

        WindowsFeature RSAT-AD-AdminCenter 
        { 
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter" 
            DependsOn = "[WindowsFeature]ADDSInstall"
        }

        WindowsFeature RSAT-ADDS-Tools 
        { 
            Ensure = "Present" 
            Name = "RSAT-ADDS-Tools" 
            DependsOn = "[WindowsFeature]ADDSInstall"
        }
    }
}
