<#
    .SYNOPSIS
        A DSC configuration script to install Axway Desktop Validator Standard. This partial is dependent on the AppInstall composite resource module.

    .PARAMETER TargetName
        The name of the target the configuration will be applied to.

    .PARAMETER OutputPath
        The path for the MOF file output.

    .PARAMETER Path
        Path to the Binary install file.

    .PARAMETER Credential
        The credentials used to connect/authenticate to a file share or source location.

    .EXAMPLE
        In this first example Microsoft NetBanner will be installed with UNCLASSIFIED text and a green background.

        $parameters = @{
            TargetName  = "localhost"
            OutPutPath  = "C:\temp"
            Path        = "C:\temp\Desktop_Validator_4.12.0_SP4_Standard_win-x86-64_BN134.exe"
            Credential  = $Credential
        }

        & $PSScriptRoot\Sample_AxwayDesktopValidatorStandard.ps1 @parameters

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
    $Credential
)

Configuration DesktopValidatorStandard
{
    Import-DscResource -ModuleName AppInstall

    node $TargetName
    {
        AxwayDesktopValidatorStandard AppInstall
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

$null = DesktopValidatorStandard -OutputPath $OutPutPath -ConfigurationData $ConfigData
