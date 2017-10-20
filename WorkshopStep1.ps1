$GithubDownloadUrl = "https://github.com/devopsjesus/dscpush/archive/master.zip"
$DscPushModulePath = "$env:USERPROFILE\Downloads\dscpush-master.zip"
$WorkshopPath = "C:\DscPushWorkshop"
$RequiredDscResources = @(
    "xActiveDirectory"
    "xComputerManagement"
    "xDnsServer"
    "xNetworking"
)

$null = New-Item -Path $WorkshopPath -ItemType Directory -Force

$currentDir = (Get-Item .).FullName
Set-Location $WorkshopPath

#Download DscPush from GitHub and copy to $WorkshopPath
$null = Invoke-WebRequest -Uri $GithubDownloadUrl -OutFile $DscPushModulePath
Expand-Archive $DscPushModulePath -DestinationPath $WorkshopPath -Force
Copy-Item -Path "$WorkshopPath\dscpush-master\DSCPushSetup" -Destination $WorkshopPath -Recurse -Force

#Copy DscPush module to Modules folder
$null = New-Item -Path "$WorkshopPath\Modules" -ItemType Directory -Force
Copy-Item -Path "$WorkshopPath\dscpush-master\DSCPush" -Destination "$WorkshopPath\Modules" -Force -Recurse

#Copy SamplePartials to Partials folder
$null = New-Item -Path "$WorkshopPath\Partials" -ItemType Directory -Force
Copy-Item -Path "$WorkshopPath\dscpush-master\SamplePartials\*" -Destination "$WorkshopPath\Partials" -Force

#Remove GitHub source directory
Remove-Item -Path "$workshopPath\dscpush-master" -Recurse -Force

#Install and configure required DSC Resources
$null = New-Item -Path "$WorkshopPath\Resources" -ItemType Directory -Force
$RequiredDscResources.ForEach({
    Install-Module $_ -Force
    $null = New-Item -Path "$WorkshopPath\Resources\$_" -ItemType Directory -Force
    Copy-Item -Path "C:\Program Files\WindowsPowerShell\Modules\$_\*" -Destination "$WorkshopPath\Resources\$_" -Recurse -Force
})

Set-Location $currentDir
