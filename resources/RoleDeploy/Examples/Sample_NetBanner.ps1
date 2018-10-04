<#
    .SYNOPSIS
        A DSC configuration script to install Microsoft NetBanner, enclave classification text and background color.  This partial is dependent on the AppInstall composite resource module.

    .PARAMETER TargetName
        The name of the target the configuration will be applied to.

    .PARAMETER OutputPath
        The path for the MOF file output.

    .PARAMETER Path
        Path to the Binary install file.

    .PARAMETER Credential
        The credentials used to connect/authenticate to a file share or source location.

    .PARAMETER Enclave
        Name of the enclave NetBanner is being installed on.  Accepted values are SIPR, NIPR, Colorless, and Coalition.

    .EXAMPLE
        In this first example Microsoft NetBanner will be installed with UNCLASSIFIED text and a green background.

        $parameters = @{
            TargetName  = "localhost"
            OutPutPath  = "C:\temp"
            Path        = "C:\temp\NetBanner.Setup 2.1.161.msi"
            Credential  = $Credential
            Enclave = "NIPR"
        }

        & $PSScriptRoot\NetBannerAppInstall.ps1 @parameters

#>

param
(
    [Parameter(Mandatory = $true)]
    [string]
    $TargetName,

    [Parameter(Mandatory = $true)]
    [string]
    $OutputPath,

    [Parameter(Mandatory = $true)]
    [string]
    $Path,
    
    [Parameter(Mandatory = $true)]
    [PSCredential]
    $Credential,

    [Parameter(Mandatory = $true)]
    [string]
    $Enclave
)

Configuration NetBanner
{
    Import-DscResource -ModuleName AppInstall

    node $TargetName
    {
        MicrosoftNetBanner NetBanner
        {
            Enclave    = $Enclave
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

$null = NetBanner -OutputPath $OutPutPath -ConfigurationData $ConfigData
