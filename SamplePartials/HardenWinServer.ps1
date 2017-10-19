<#
    .SYNOPSIS
        Windows Server hardening.
#>
Param
(
    [parameter(Mandatory = $true)]
    [string]
    $TargetName,

    [parameter(Mandatory = $true)]
    [string]
    $OutputPath
)

Configuration HardenWinServer
{ 
    Import-DscResource –ModuleName 'PSDesiredStateConfiguration' -ModuleVersion 1.1

    Node $TargetName 
    {
        foreach($regkey in $regkeys)
        {
            Registry $regkey[0]
            {
                Key = $regkey[1]
                ValueName = $regkey[2]
                ValueData = $regkey[3]
                ValueType = $regkey[4]
            }
        }
    }
}

$regkeys = @(
    @("LegalNotice", "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System", "LegalNoticeText", "Thank you for trying out Dsc Push! 💖", "String"),
    @("AutoAdminLogon", "HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Winlogon", "AutoAdminLogon", "0", "String"),
    @("IEStartPage", "HKEY_LOCAL_MACHINE\Software\Microsoft\Internet Explorer\Main", "Start Page", "about:blank", "String"),
    @("IEUpdateCheckKey", "HKEY_LOCAL_MACHINE\Software\Microsoft\Internet Explorer\Main", "Update_Check_Page", " ", "String"),
    @("IEIsolate64", "HKEY_LOCAL_MACHINE\Software\Microsoft\Internet Explorer\Main", "Isolation64Bit", "1", "DWORD"),
    @("W32TimeEventLog", "HKEY_LOCAL_MACHINE\System\CurrentControlSet\Services\W32Time\Config", "EventLogFlags", "2", "DWORD"),
    @("http", "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\EscDomains\127.0.0.1", "http", "1", "DWORD"),
    @("https", "HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Internet Settings\ZoneMap\EscDomains\127.0.0.1", "https", "1", "DWORD")
)

$null = HardenWinServer -OutputPath $OutputPath
