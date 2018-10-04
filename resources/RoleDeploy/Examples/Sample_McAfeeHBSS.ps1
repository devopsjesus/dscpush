<#
    .SYNOPSIS
        A DSC configuration script to install McAfee HBSS. This partial is dependent on the AppInstall composite resource module.

    .PARAMETER TargetName
        The name of the target the configuration will be applied to.

    .PARAMETER OutputPath
        The path for the MOF file output.

    .PARAMETER Credential
        The credentials used to connect/authenticate to a file share or source location.

    .PARAMETER McAfeeAgentPath
        Path to the McAfee Agent Binary install file.

    .PARAMETER McAfeePAPath
        Path to the McAfee Policy Auditor Binary install file.

    .PARAMETER McAfeeACCMPath
        Path to the McAfee ACCM Binary install file.

    .PARAMETER McaFeeDLPPath
        Path to the McaFee DLP Endpoint Binary install file.

    .PARAMETER McAfeeRSDPath
        Path to the  McAfee RSD Sensor Binary install file.

    .PARAMETER McAfeeHIPSPath
        Path to the McAfee Host Intrusion Prevention Setup Binary install file.

    .PARAMETER McAfeeHIPSHFPath
        Path to the McAfee Host Intrusion Prevention Hot Fix Binary install file.

    .PARAMETER McafeeVSEPath
        Path to the McaFee Virus Scan Enterprise Binary install file.

    .PARAMETER Ensure
        Ensure is set to Present.

    .EXAMPLE
        In this first example, McAfee HBSS will be installed on the Local Host.

    $parameters = @{
        TargetName       = 'localhost'
        OutputPath       = 'C:\temp\RPS_MN\DSC'
        Credential       = Get-Credential
        McAfeeAgentPath  = 'C:\temp\Applications\McAfee Agent 5.0.4.449\FramePkg.exe'
        McAfeePAPath     = 'C:\temp\Applications\McAfee PA 6.2.0.342\Setup.exe'
        McAfeeACCMPath   = 'C:\temp\Applications\McAfee ACCM 3.0.5.4\ACCM_MSI.msi'
        McAfeeDLPPath    = 'C:\temp\Applications\McAfee DLP 10.0.100.372\DLPAgentInstaller.x64.exe'
        McAfeeRSDPath    = 'C:\temp\Applications\McAfee RSD 5.0.4.113\RSDInstaller.exe'
        McAfeeHIPSPath   = 'C:\temp\Applications\McAfee HIPS 8.0.0.4210\McAfeeHIP_ClientSetup.exe'
        McAfeeHIPSHFPath = 'C:\temp\Applications\McAfee HIPS 8.0.0.4210 HF1188590\McAfeeHIP_ClientHotfix9_1188590.exe'
        McAfeeVSEPath    = 'C:\temp\Applications\McAfee VSE 8.8.0.1804\setupvse.exe'
    }
        & $PSScriptRoot\Sample_McAfeeHBSS.ps1 @parameters
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
    [PSCredential]
    $Credential,

    [Parameter(Mandatory = $true)]
    [string]
    $McAfeeAgentPath,

    [Parameter(Mandatory = $true)]
    [string]
    $McAfeePAPath,

    [Parameter(Mandatory = $true)]
    [string]
    $McAfeeACCMPath,

    [Parameter(Mandatory = $true)]
    [string]
    $McAfeeDLPPath,

    [Parameter(Mandatory = $true)]
    [string]
    $McAfeeRSDPath,

    [Parameter(Mandatory = $true)]
    [string]
    $McAfeeHIPSPath,

    [Parameter(Mandatory = $true)]
    [string]
    $McAfeeHIPSHFPath,

    [Parameter(Mandatory = $true)]
    [string]
    $McAfeeVSEPath
)

Configuration McAfeeHBSS
{
    Import-DscResource -ModuleName AppInstall

    node $TargetName
    {
        McAfeeHBSS Applications
        {
            McAfeeAgentPath     = $McAfeeAgentPath
            McAfeePAPath        = $McAfeePAPath
            McAfeeACCMPath      = $McAfeeACCMPath
            McAfeeDLPPath       = $McAfeeDLPPath
            McAfeeRSDPath       = $McAfeeRSDPath
            McAfeeHIPSPath      = $McAfeeHIPSPath
            McAfeeHIPSHFPath    = $McAfeeHIPSHFPath
            McAfeeVSEPath       = $McAfeeVSEPath
            Credential          = $Credential
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

$null = McAfeeHBSS -OutputPath $OutPutPath -ConfigurationData $ConfigData
