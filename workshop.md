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
   - NOTE: The following scripts will replace the **C:\DscPushWorkshop** directory on your host.
1. Run WorkshopStep1.ps1 on your workstation.  It is possible to run on one of the target VMs, but you run the risk of the VM rebooting while it's still compiling Partial configurations.
1. Run WorkshopStep2.ps1 on your workstation.
   - Credential pop-up is to store the protected property values (i.e. secrets).  The workshop only require a single credential, because the same one is used for both VMs. The credential being stored is for domain admin.
   - The second credential pop-up is to kick-off the Configuration Deployment.  The same credential is used to keep it simple for both cases (local and domain admin).

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
  - Works in Azure
- Protected parameter values are stored securely
  - Any [PSCredential] type values are securely stored & encrypted with a 256bit AES key
  - Management and service account credentials are not exposed
