Configuration install_adfs {
    param (
        [Parameter(Mandatory)]
        [String]$DomainName,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,

        [Parameter(Mandatory)]
        [String]$FSName

        $netbios = $DomainName.split(".")[0]

        $CertificateThumbprint = ""
    )

    Import-DSCResource -ModuleName PSDesiredStateConfiguration
    Import-DSCResource -ModuleName xComputerManagement
    Import-DSCResource -ModuleName xPendingReboot
    Import-DSCResource -ModuleName AdfsDsc

    Node 'localhost' 
    {
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }

        #WindowsFeature RSAT
        #{
        #    Name                 = "RSAT-ADDS"
        #    IncludeAllSubFeature = $True
        #    Ensure               = "Present"
        #}

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

        script SelfSignedCert
        {
            GetScript            = { return $false}
            TestScript           = {(Get-ADFSThumbprint -DNSName $FSName).Length -gt 1}
            SetScript            = 
            {
                New-SelfSignedCertificate -DnsName "$FSName" -CertStoreLocation "cert:\LocalMachine\My"
            }
        }

        AdfsFarm Contoso
        {
            FederationServiceName        = $FSName
            FederationServiceDisplayName = '${netbios} ADFS Service'
            CertificateThumbprint        = "$(Get-ADFSThumbprint -DNSName $FSName)"
            ServiceAccountCredential     = $Admincreds
            Credential                   = $Admincreds
        }
    }
}

function Get-ADFSThumbprint {
    param
    (
        [Parameter(Mandatory)]
        [String]$DNSName
    )

    $thumbprint = (Get-ChildItem -Path cert:\LocalMachine\My | Where-Object {$DNSName -in $_.DnsNameList}).Thumbprint
}