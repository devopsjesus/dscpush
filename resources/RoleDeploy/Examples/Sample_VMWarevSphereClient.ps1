<#
    .SYNOPSIS
        A DSC configuration script to install VMWare vSphere Client. This partial is dependent on the AppInstall composite resource module.

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
            TargetName  = "localhost"
            OutPutPath  = "C:\temp"
            Path        = "C:\temp\VMware-viclient-all-6.0.0-3016447.exe"
            Credential  = $Credential
        }

        & $PSScriptRoot\Sample_VMWarevSphereClient.ps1 @parameters

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

Configuration vSphereClient
{
    Import-DscResource -ModuleName AppInstall

    node $TargetName
    {
        VMWarevSphereClient AppInstall
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

$null = vSphereClient -OutputPath $OutPutPath -ConfigurationData $ConfigData
