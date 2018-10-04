#Fill in the values below and save to your content store.

#region Node Definition: Master
$Master = New-Node -Name 'Master' -NodeId '1883264f-9536-4466-a81c-77d8fbfec315' -Type 'DscTestMasterNode'

#region Target Config: DscTest
$DscTest = New-TargetConfig -Properties @{
    ConfigName = 'DscTest'
    ContentHost = $True
    ContentStorePath = 'C:\ContentStore'
    RoleList = @(
        "Windows2016Baseline"
    )
}
$DscTestAdapterProperties = @{
    InterfaceAlias  = ''
    PhysicalAddress = '00-15-5d-36-F2-12'
    NetworkAddress  = '192.0.0.30'
    SubnetBits      = '24'
    DnsAddress      = '192.0.0.30'
    AddressFamily   = 'IPv4'
    Description     = ''
}
$DscTest.TargetAdapter = New-TargetAdapter @DscTestAdapterProperties
$DscTest.Variables += @{
    ComputerName='DscTest'
    DomainName='dscpush.local'
    JoinDomain='false'
    AxwayDVInstallerPath="$($DscTest.ContentStorePath)\CoreApps\DESKTOPVALIDATOR_412\Desktop_Validator_4.12.1_Install_Standard_win-x86-32_BN140.exe"
    ActivClientInstallerPath="$($DscTest.ContentStorePath)\CoreApps\ActivClient_710159\ActivID ActivClient x64 7.1.msi"
    ActivClientCertificatePath="$($DscTest.ContentStorePath)\Certificates\HIDGlobalCorp2.cer"
    ActivClientHotFixPath="$($DscTest.ContentStorePath)\CoreApps\ActivClient_710159\AC_7.1.0.159_FIXS1612003_x64.msp"
    SCM90MeterInstallerPath="$($DscTest.ContentStorePath)\CoreApps\90METERSCM_1431S\SCM_1.4.31_64Bit_S.msi"
    SCM90MeterCertificateList=@(
        @{
            Name       = "NSSRootCA1"
            Path       = "$($DscTest.ContentStorePath)\Certificates\NSSRootCA1.cer"
            Thumbprint = "4d96a58e74c1d5ec06c018459c3dde71c0dbef41"
            Location   = "LocalMachine"
            Store      = "90MeterSipr"
        }
        @{
            Name       = "NSSDoDIntermediateCA1"
            Path       = "$($DscTest.ContentStorePath)\Certificates\NSSDoDIntermediateCA1.cer"
            Thumbprint = "978e78302921d93a7258851c39516797985b329b"
            Location   = "LocalMachine"
            Store      = "90MeterSipr"
        }
        @{
            Name       = "NSSDoDSubordinateCA1"
            Path       = "$($DscTest.ContentStorePath)\Certificates\NSSDoDSubordinateCA1.cer"
            Thumbprint = "46c73355d3e2bc5b01ff0982c945511fb9d4592e"
            Location   = "LocalMachine"
            Store      = "90MeterSipr"
        }

    )
    SEPInstallerPath="$($DscTest.ContentStorePath)\CoreApps\SEP14RU1MP1_x64\Setup.exe"
    NetbackupInstallerPath="$($DscTest.ContentStorePath)\CoreApps\NetbackupForW2K12\NetBackup_7.5.0.6_W2K12\PC_Clnt\x64\setup.exe"
}
$Master.Configs += $DscTest
#endregion Target Config: DscTest

#endregion Node Definition: Master


@($Master)
