# IT/Dev Connections DscPush Workshop

1. Create 2 Windows Server 2016 VMs
   - Core version works (and is faster to install)
   - IP Addresses
     - 192.0.0.251
     - 192.0.0.253
   - When you can successfully establish Cim & PS Sessions to each VM, you're ready to begin
     - Example: New-PsSession -ComputerName 192.0.0.253 -Credential administrator
1. Download this repository
   - https://github.com/devopsjesus/dscpush/archive/master.zip
   - Extract the Workshop\*.ps1 files to an accessible location (e.g. Desktop)
1. Run elevated PowerShell console
   - Change Directory to the directory containing the extracted Workshop\*.ps1 files
   - The workshop will replace the **C:\workshop** directory on your host!
1. Run WorkshopStep1.ps1
1. Run WorkshopStep2.ps1
