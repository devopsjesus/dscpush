<#
    .SYNOPSIS
        A composite DSC resource to deploy core OS functionality.
#>
Configuration DomainController
{
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

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration' -ModuleVersion 1.1
    Import-DscResource -ModuleName 'xActiveDirectory' -ModuleVersion 2.21.0.0
    Import-DscResource -ModuleName 'xDnsServer' -ModuleVersion 1.11.0.0

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
