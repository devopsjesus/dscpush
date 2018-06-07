#requires -Module AzureRM, BitsTransfer

param
(
    [parameter(Mandatory)]
    [guid]
    $SubscriptionId,

    [parameter()]
    [string]
    $ResourceGroupName = "DscPushWorkshop",

    [parameter()]
    [string[]]
    $ComputerName = @("DscPushAD","DscPushCH"),

    [parameter()]
    [string]
    $Location = "westus",

    [parameter()]
    [string]
    $VmSize = "Standard_D1_v2",

    [parameter()]
    [ValidatePattern({"*.json"})]
    [string]
    $TemplateFilePath = "C:\Windows\Temp\AzureDeploy.json",

    [parameter()]
    [ValidatePattern({"*.json"})]
    [string]
    $TemplateParamFilePath = "C:\Windows\Temp\AzureDeploy.params.json",

    [parameter(Mandatory)]
    [pscredential]
    $VmAdminCred,

    [parameter()]
    [string]
    $CertPath = "C:\Windows\Temp\$ResourceGroupName.pfx",

    [parameter()]
    [switch]
    $ClobberResourceGroup
)

Write-Verbose "Logging into Azure"
$null = Login-AzureRmAccount -SubscriptionId $SubscriptionId -ErrorAction Stop
$certSecret = $VmAdminCred.Password

Write-Verbose "Checking for existing Resource Group"
if (! (Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction Ignore))
{
    Write-Verbose "Creating Resource Group"
    $null = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
}elseif ($ClobberResourceGroup)
{
    Write-Verbose "Deleting Resource Group because `$ClobberResourceGroup switch was flipped"
    $null = Remove-AzureRmResourceGroup -Name $ResourceGroupName -Force -ErrorAction Ignore
    if (Get-AzureRmResourceGroup -Name $ResourceGroupName -ErrorAction Ignore)
    {
        throw "Could not remove Resource Group"
    }

    Write-Verbose "Creating Resource Group after removal"
    $null = New-AzureRmResourceGroup -Name $ResourceGroupName -Location $Location
}

#region Security
Write-Verbose "Checking for KeyVault for enablement of remote connection"
if (! (Get-AzureRmKeyVault -VaultName $ResourceGroupName))
{
    Write-Verbose "Creating KeyVault"
    $keyVaultParams = @{
        VaultName                    = $ResourceGroupName
        ResourceGroupName            = $ResourceGroupName
        Location                     = $Location
        EnabledForDeployment         = $true
        EnabledForTemplateDeployment = $true
    }
    $null = New-AzureRmKeyVault @keyVaultParams
}

Write-Verbose "Creating the certificate for remote connection authentication"
$thumbprint = (New-SelfSignedCertificate -DnsName $ResourceGroupName -CertStoreLocation Cert:\CurrentUser\My -KeySpec KeyExchange).Thumbprint
$cert = (Get-ChildItem -Path cert:\CurrentUser\My\$thumbprint)
$null = Export-PfxCertificate -Cert $cert -FilePath $CertPath -Password $certSecret

$cert = Import-AzureKeyVaultCertificate -VaultName $ResourceGroupName -Name $ResourceGroupName -FilePath $CertPath -Password $certSecret
$keyVaultSecret = Get-AzureKeyVaultSecret -VaultName $ResourceGroupName -Name $ResourceGroupName
#endregion Security

Write-Verbose "Deployment of template commencing"
$deploymentParams = @{
    Name                  = $ResourceGroupName
    ResourceGroupName     = $ResourceGroupName
    TemplateFile          = $TemplateFilePath
    TemplateParameterFile = $TemplateParamFilePath
    AdminPassword         = $certSecret
    KeyVaultSecretUrl     = $keyVaultSecret.Id
}
New-AzureRmResourceGroupDeployment @deploymentParams -Force -Verbose

if ($deployment.ProvisioningState -ne "Succeeded")
{
    throw "Deployment was not successful."
}
