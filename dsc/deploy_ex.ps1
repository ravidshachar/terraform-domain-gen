Configuration install_exchange {
    param (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        $netbios = $DomainName.split(".")[0]
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DSCResource -ModuleName xComputerManagement
    Import-DscResource -ModuleName xExchange
    Import-DscResource -ModuleName cChoco

    Node 'localhost' 
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }

        cChocoInstaller InstallChoco
        {
            InstallDir = "c:\choco"
        }

        ### JOIN DOMAIN ###
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
            Name       = 'localhost'
            DomainName = $DomainName
            Credential = $Admincreds
            DependsOn  = '[script]Renew'
        }

        ### INSTALL PREREQS ###

        # Installs Required Components for Exchange (note: there is 1 planned automatic reboot)
        WindowsFeatureSet ExchangeFeatures 
        {
            Name                 = @("Server-Media-Foundation", "NET-Framework-45-Features", "RPC-over-HTTP-proxy", "RSAT-Clustering", "RSAT-Clustering-CmdInterface", "RSAT-Clustering-Mgmt", "RSAT-Clustering-PowerShell", "WAS-Process-Model", "Web-Asp-Net45", "Web-Basic-Auth", "Web-Client-Auth", "Web-Digest-Auth", "Web-Dir-Browsing", "Web-Dyn-Compression", "Web-Http-Errors", "Web-Http-Logging", "Web-Http-Redirect", "Web-Http-Tracing", "Web-ISAPI-Ext", "Web-ISAPI-Filter", "Web-Lgcy-Mgmt-Console", "Web-Metabase", "Web-Mgmt-Console", "Web-Mgmt-Service", "Web-Net-Ext45", "Web-Request-Monitor", "Web-Server", "Web-Stat-Compression", "Web-Static-Content", "Web-Windows-Auth", "Web-WMI", "Windows-Identity-Foundation", "RSAT-ADDS")
            Ensure               = 'Present'
            IncludeAllSubFeature = $true
        }

        # Installs pacakges from choco
        cChocoPackageInstallerSet InstallPackages
        {
            Ensure    = 'Present'
            Name      = @("netfx-4.8", "vcredist2013", "ucma4", "urlrewrite")
            DependsOn = "[cChocoInstaller]InstallChoco"
        }

        #Checks Exchange Setup Directory (can be changed it's necessary). No recurse.
        File ExchangeBinaries
        {
            Ensure          = 'Present'
            Type            = 'Directory'
            Recurse         = $false
            SourcePath      = 'C:\Exch'
            DestinationPath = 'C:\Exch'
        }

        # Download & Mount Exchange ISO
        Script DownloadMountIso
        {
            GetScript = 
            {
                @{
                    GetScript = $GetScript
                    SetScript = $SetScript
                    TestScript = $TestScript
                    Result = ('True' -in (Test-Path c:\Exch))
                }
            }

            SetScript = 
            {
                Invoke-WebRequest -Uri "https://download.microsoft.com/download/5/3/e/53e75dbd-ca33-496a-bd23-1d861feaa02a/ExchangeServer2019-x64-CU11.ISO" -OutFile "c:\exchange.iso"
                $mountResult = Mount-DiskImage c:\exchange.iso -PassThru
                $driveLetter = ($mountResult | Get-Volume).DriveLetter
                Copy-Item -Path "$driveLetter:\*" -Destination "C:\Exch\" -Recurse
            }

            TestScript = 
            {
                $Status = ('True' -in (Test-Path c:\Exch))
                $Status -eq $True
            }
        }

        #Checks if a reboot is needed before installing Exchange
        xPendingReboot BeforeExchangeInstall
        {
            Name       = "BeforeExchangeInstall"
            DependsOn  = '[Script]DownloadMountIso'
        }

        #Does the Exchange install. Verify directory with exchange binaries
        xExchInstall InstallExchange
        {
            Path       = "C:\Exch\Setup.exe"
            Arguments  = "/mode:Install /role:Mailbox /OrganizationName:""$netbios"" /IAcceptExchangeServerLicenseTerms_DiagnosticDataOFF"
            Credential = $Admincreds
 
            DependsOn  = '[xPendingReboot]BeforeExchangeInstall'
        }

        #Sees if a reboot is required after installing Exchange
        xPendingReboot AfterExchangeInstall
        {
            Name      = "AfterExchangeInstall"
            DependsOn = '[xExchInstall]InstallExchange'
        }
    }
}