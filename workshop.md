# IT/Dev Connections DscPush Workshop

1. Create 2 Windows Server 2016 VMs
   - Full Interface or Core version
   - Server 2012 R2 with WMF5.1 is supported as well
   - IP Addresses
     - 192.0.0.251
     - 192.0.0.253
   - When you can successfully establish Cim & PS Sessions to each VM, you're ready to begin
     - Example: *New-PsSession -ComputerName 192.0.0.253 -Credential administrator*
1. Download this repository
   - https://github.com/devopsjesus/dscpush/archive/master.zip
   - Extract the Workshop\*.ps1 files to an accessible location (e.g. Desktop)
1. Run elevated PowerShell console
   - Change Directory to the directory containing the extracted Workshop\*.ps1 files
   - The following scripts will replace the **C:\DscPushWorkshop** directory on your host.
1. Run WorkshopStep1.ps1
   - Credential pop-up is for the VM's local admin (administsrator & the password for VMs' local admin account)
1. Run WorkshopStep2.ps1
   - Same credential is used for domain admin, so just keep using the same credential from your image

# What's going on?

- The two VMs are being sent separate compiled mof files derived from compiling multiple DSC Partial Configurations (We're publishing DSC Partial Configurations to the VMs.)
- One VM is being promoted to a DC
- The other VM will join the newly-created domain
- Both VMs will be "hardened"

# Why is this cool?

- DSC Push provides a DSC Configuration Management framework to securely publish Configurations.
  - The data required to publish the partials lives in a single repository
  - Hosts can be managed in logical groups ("Nodes")
  - New Configurations can be scheduled and published at will.
- 100% PowerShell
  - Class-based
  - Partial Parsing Engine 
  - Single Module
- Protected parameter values are stored securely
  - Any [PSCredential] type values are securely stored & encrypted with a 256bit AES key
  - Management and service account credentials are not exposed
