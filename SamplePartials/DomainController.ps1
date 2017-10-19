<#
    .SYNOPSIS
        Domain Controller
#>
Param(
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
 
    Node $targetName 
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

$ConfigData = @{ 
    AllNodes = @(  
        @{ 
            NodeName = $TargetName
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        }
    ) 
} 

$null = DomainController -ConfigurationData $ConfigData -OutputPath $outputPath
