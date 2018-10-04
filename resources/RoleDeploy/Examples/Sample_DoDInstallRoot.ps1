<#
    .SYNOPSIS
        A DSC configuration script to install DoD InstallRoot. This partial is dependent on the AppInstall composite resource module.

    .PARAMETER TargetName
        The name of the target the configuration will be applied to.

    .PARAMETER OutputPath
        The path for the MOF file output.

    .PARAMETER Path
        Path to the Binary install file.

    .PARAMETER Ensure
        Ensures software is Present or Absent.

    .PARAMETER InstallRootGroup
        Specifies the InstallRootGroup of certificates to manage.

    .PARAMETER InstallRootPath
        Specifies the Install path of InstallRoot.exe.

    .PARAMETER Credential
        The credentials used to connect/authenticate to a file share or source location.

    .EXAMPLE

        $parameters = @{
            TargetName          = "localhost"
            OutPutPath          = "C:\temp"
            Path                = "C:\temp\InstallRoot_5.0.1x64.msi"
            Credential          = $Credential
            Ensure              = "Present"
            InstallRootGroup    = "DOD"
            InstallRootPath     = "$env:ProgramFiles\DoD-PKE\InstallRoot\InstallRoot.exe"
        }

        & $PSScriptRoot\Sample_DoDInstallRoot.ps1 @parameters

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
    [ValidateSet('DOD', 'JITC', 'ECA')]
    [string]
    $InstallRootGroup,

    [Parameter()]
    [string]
    $InstallRootPath = "$env:ProgramFiles\DoD-PKE\InstallRoot\InstallRoot.exe",

    [Parameter()] 
    [ValidateSet("Present", "Absent")]
    [String]
    $Ensure = "Present"
)

Configuration InstallRootDsc
{

    node $TargetName
    {
        DoDInstallRoot "AppInstall"
        {
            Credential          = $Credential
            Path                = $Path
            Ensure              = $Ensure
            InstallRootGroup    = $InstallRootGroup
            InstallRootPath     = $InstallRootPath
        }
    }
}

$configData = @{
    AllNodes = @(
        @{
            NodeName                    = $TargetName
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser        = $true
        }
    )
}

InstallRootDsc -ConfigurationData $configData -OutputPath $OutputPath
