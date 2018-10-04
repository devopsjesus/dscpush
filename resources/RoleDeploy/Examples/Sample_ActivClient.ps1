<#
    .SYNOPSIS
        A DSC configuration script to install ActivClient. This partial is dependent on the AppInstall composite resource module.

    .PARAMETER TargetName
        The name of the target the configuration will be applied to.

    .PARAMETER OutputPath
        The path for the MOF file output.

    .PARAMETER Path
        Path to the Binary install file.

    .PARAMETER Credential
        The credentials used to connect/authenticate to a file share or source location.

    .EXAMPLE

        $parameters = @{
            TargetName = "localhost"
            OutPutPath = "C:\temp"
            Path       = "C:\temp\ActivClient x64 7.0.2.msi"
            Credential = $Credential
        }

        & $PSScriptRoot\Sample_ActivClient.ps1 @parameters

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

Configuration ActivClient
{
    Import-DscResource -ModuleName AppInstall

    node $TargetName
    {
        ActivClient AppInstall
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

$null = ActivClient -OutputPath $OutPutPath -ConfigurationData $ConfigData
