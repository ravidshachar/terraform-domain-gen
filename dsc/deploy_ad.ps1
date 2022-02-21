#Publish-AzVMDscConfiguration .\deploy-ADRole.ps1 -OutputArchivePath '.\deploy-ADRole.zip'

Configuration ad_setup {

    param
    (
         [Parameter(Mandatory)]
         [String]$DomainName,

         [Parameter(Mandatory)]
         [System.Management.Automation.PSCredential]$Admincreds
 
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xActiveDirectory 
    Import-DscResource -ModuleName xPendingReboot
    ##Import-DscResource -ModuleName xNetworking

    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)

    Node 'localhost'
    {

        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }
        
        WindowsFeature ADRole
        {
            Name = "AD-Domain-Services"
            IncludeAllSubFeature = $True
            Ensure = "Present"
        }

        WindowsFeature RSAT
        {
            Name = "RSAT-ADDS"
            IncludeAllSubFeature = $True
            Ensure = "Present"
        }

          xADDomain FirstDS
          {
              DomainName = $DomainName
              DomainAdministratorCredential = $DomainCreds
              SafemodeAdministratorPassword = $DomainCreds
              DatabasePath = "C:\NTDS"
              LogPath = "C:\NTDS"
              SysvolPath = "C:\SYSVOL"
              DependsOn = '[WindowsFeature]ADRole';
          }

        WindowsFeature DNS
        {
             Ensure = "Present"
             Name = "DNS"
        }

          WindowsFeature DnsTools
        {
            Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
        }

        xPendingReboot RebootAfterPromotion{
            Name = "RebootAfterPromotion"
            DependsOn = "[xADDomain]FirstDS"
        }
    }
}

# Install aditional DC

Configuration AdditionalDC {

    param
    (
         [Parameter(Mandatory)]
         [String]$DomainName,

         [Parameter(Mandatory)]
         [String]$Site1Name,

         [Parameter(Mandatory)]
         [String]$Site2Name,

         [Parameter(Mandatory)]
         [String]$Site1Subnet,

         [Parameter(Mandatory)]
         [String]$Site2Subnet,
 
         [Parameter(Mandatory)]
         [System.Management.Automation.PSCredential]$Admincreds
 
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xActiveDirectory 
    Import-DscResource -ModuleName xPendingReboot
    Import-DscResource -ModuleName ActiveDirectoryDsc
    ##Import-DscResource -ModuleName xNetworking

    [System.Management.Automation.PSCredential ]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)

    Node 'localhost'
    {

        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }
        
        WindowsFeature ADRole
        {
            Name = "AD-Domain-Services"
            IncludeAllSubFeature = $True
            Ensure = "Present"
        }

        WindowsFeature RSAT
        {
            Name = "RSAT-ADDS"
            IncludeAllSubFeature = $True
            Ensure = "Present"
        }

        xWaitForADDomain DscForestWait
        {
            DomainName = $DomainName
            DomainUserCredential= $DomainCreds
            RetryCount = 30
            RetryIntervalSec = 10
            DependsOn = '[script]Renew'
        }

        xADDomainController BDC
        {
            DomainName = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $DomainCreds
            DatabasePath = "C:\NTDS"
            LogPath = "C:\NTDS"
            SysvolPath = "C:\SYSVOL"
            DependsOn = "[xWaitForADDomain]DscForestWait"
            
        }

          WindowsFeature DNS
          {
              Ensure = "Present"
              Name = "DNS"
          }

          WindowsFeature DnsTools
        {
            Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
        }

        xPendingReboot RebootAfterPromotion{
            Name = "RebootAfterPromotion"
            DependsOn = "[xADDomainController]BDC"
        }

        script 'Renew'
        {
            GetScript            = { return $false}
            TestScript           = { return $false}
            SetScript            = 
                {
                    Invoke-Expression -Command "ipconfig /renew"
                }
        }
        ADReplicationSite 'Site1'
        {
            Name  = $Site1Name
            Ensure  = 'Present'
            DependsOn = "[xPendingReboot]RebootAfterPromotion"
        }
        ADReplicationSite 'Site2'
        {
            Name  = $Site2Name
            Ensure  = 'Present'
            DependsOn = "[xPendingReboot]RebootAfterPromotion"
        }
        
        ADReplicationSubnet 'Subnet1'
        {
            Name  = $Site1Subnet
            Site  = $Site1Name
            DependsOn = '[ADReplicationSite]Site1'
            Ensure  = 'Present'
        }
        ADReplicationSubnet 'Subnet2'
        {
            Name  = $Site2Subnet
            Site  = $Site2Name
            DependsOn = '[ADReplicationSite]Site2'
            Ensure  = 'Present'
        }
        
        ADReplicationSiteLink 'ADSS1'
        {
            Name       = "${Site1Name}'-'${Site2Name}"
            SitesIncluded     = @($Site1Name, $Site2Name)
            Cost       = 20
            ReplicationFrequencyInMinutes = 15
            Ensure      = 'Present'
            DependsOn      = @('[ADReplicationSite]Site1','[ADReplicationSite]Site2')
        }
    }
}



# Domain Join member servers

Configuration DomainJoin
{
    param
    (
         [Parameter(Mandatory)]
         [String]$DomainName,
 
         [Parameter(Mandatory)]
         [System.Management.Automation.PSCredential]$Admincreds
 
    )
    
    

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DSCResource -Module xComputerManagement




    Node 'localhost' 
    {
        script 'Renew'
        {
            GetScript            = { return $false}
            TestScript           = { return $false}
            SetScript            = 
                {
                    Invoke-Expression -Command "ipconfig /renew"
                }
        }
        xComputer JoinDomain
        {
            Name = 'localhost'
            DomainName = $DomainName
            Credential = $Admincreds
            DependsOn = '[script]Renew'
        }

    }
}