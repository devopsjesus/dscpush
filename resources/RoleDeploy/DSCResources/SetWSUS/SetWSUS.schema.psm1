<#
    .SYNOPSIS
        A composite DSC resource to deploy core OS functionality.

    .PARAMETER WsusServerIP
        The IP address of the Wsus Server.

    .PARAMETER WsusServerPort
        Port the target WSUS server uses to communicate. Defaults to 8530.

    .PARAMETER WsusTargetGroup
        Name of the WSUS Group to assign target to.

    .EXAMPLE
        The following is an example of a configuration that could be used to set a node's Update Settings to point to WSUS Server.

Configuration SetWSUSExample
{
    Import-DscResource -ModuleName RoleDeploy

    node "localhost"
    {
        SetWSUS Example
        {
            WsusServerIP    = "192.0.0.26"
            WsusTargetGroup = "SetWSUSTest"
        }
    }
}
SetWSUSExample -OutputPath "$($env:Temp)"
#>
Configuration SetWSUS
{
    Param
    (
        [parameter(Mandatory)]
        [ipaddress]
        $WsusServerIP,

        [parameter()]
        [int]
        $WsusServerPort = 8530,

        [parameter()]
        [string]
        $WsusTargetGroup
    )

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration' -ModuleVersion 1.1

    $wsusRegKeyPath        = "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
    $wsusOptionsRegKeyPath = "HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU"

    $regkeys = @(
        @($wsusRegKeyPath, "AcceptTrustedPublisherCerts", "0", "DWORD"),
        @($wsusRegKeyPath, "ElevateNonAdmins", "0", "DWORD"),
        @($wsusRegKeyPath, "TargetGroup", $WsusTargetGroup, "String"),
        @($wsusRegKeyPath, "TargetGroupEnabled", "1", "DWORD"),
        @($wsusRegKeyPath, "WUServer", "http://${WsusServerIP}:$WsusServerPort", "String"),
        @($wsusRegKeyPath, "WUStatusServer", "http://${WsusServerIP}:$WsusServerPort", "String"),
        @($wsusOptionsRegKeyPath, "AUOptions", "3", "DWORD"),
        @($wsusOptionsRegKeyPath, "AUPowerManagement", "0", "DWORD"),
        @($wsusOptionsRegKeyPath, "AutoInstallMinorUpdates", "1", "DWORD"),
        @($wsusOptionsRegKeyPath, "DetectionFrequency", "16", "DWORD"),
        @($wsusOptionsRegKeyPath, "DetectionFrequencyEnabled", "1", "DWORD"),
        @($wsusOptionsRegKeyPath, "IncludeRecommendedUpdates", "1", "DWORD"),
        @($wsusOptionsRegKeyPath, "NoAUAsDefaultShutdownOption", "0", "DWORD"),
        @($wsusOptionsRegKeyPath, "NoAUShutdownOption", "0", "DWORD"),
        @($wsusOptionsRegKeyPath, "NoAutoUpdate", "0", "DWORD"),
        @($wsusOptionsRegKeyPath, "UseWUServer", "1", "DWORD")
    )

    foreach($regkey in $regkeys)
    {
        Registry "$($regkey[0])/$($regkey[1])"
        {
            Key = $regkey[0]
            ValueName = $regkey[1]
            ValueData = $regkey[2]
            ValueType = $regkey[3]
        }
    }
}
