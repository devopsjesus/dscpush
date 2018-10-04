# RoleDeploy

The RoleDeploy module contains composite resources to install and configure specific applications.

## Composite Resources

The following resources are available in this composite.

* [MicrosoftNetBanner](DSCResources\MicrosoftNetBanner\MicrosoftNetBanner.schema.psm1)

## DSC Resources

The composite resources above leverage the following MOF based resources from the PowerShell gallery.
These resources must be installed on the target DSC nodes either manually or automatically through the built-in DSC resource delivery mechanism or other scripted solution.

* [PSDesiredStateConfiguration](https://technet.microsoft.com/en-us/library/dn391651.aspx)
* [xPSDesiredStateConfiguration](https://github.com/PowerShell/xPSDesiredStateConfiguration)

## Examples

Sample files to help you get started with this module can be found below.

* [RoleDeploy](Examples\Sample_RoleDeploy.ps1)
