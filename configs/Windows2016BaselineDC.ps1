Configuration Windows2016BaselineDC
{
    Import-DscResource -ModuleName RoleDeploy -ModuleVersion 1.0.0.0

    Node $TargetIP
    {
        OSCore Deploy
        {
            ComputerName     = $Node.ComputerName
            DomainName       = $Node.DomainName
            DomainCredential = $Node.DomainCredential
            JoinDomain       = $Node.JoinDomain
        }

        DomainController Install
        {
            ComputerName     = $Node.ComputerName
            DomainName       = $Node.DomainName
            DomainCredential = $Node.DomainCredential
            DependsOn        = "[OSCore]Deploy"
        }
    }
}
