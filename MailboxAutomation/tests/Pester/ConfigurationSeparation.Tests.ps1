#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    $configDir = Join-Path -Path $root -ChildPath 'config'

    $script:appSettingsPath = Join-Path -Path $configDir -ChildPath 'appsettings.json'
    $script:onPremPath = Join-Path -Path $configDir -ChildPath 'environments.onprem.json'
    $script:hybridPath = Join-Path -Path $configDir -ChildPath 'environments.hybrid.json'

    $script:appRaw = Get-Content -Path $script:appSettingsPath -Raw -Encoding UTF8
    $script:onPremRaw = Get-Content -Path $script:onPremPath -Raw -Encoding UTF8
    $script:hybridRaw = Get-Content -Path $script:hybridPath -Raw -Encoding UTF8

    $script:app = $script:appRaw | ConvertFrom-Json
    $script:onPrem = $script:onPremRaw | ConvertFrom-Json
    $script:hybrid = $script:hybridRaw | ConvertFrom-Json
}

Describe 'Configuration separation and environment profiles' {
    It 'appsettings.json contains no productive KSBL markers' {
        $forbiddenPatterns = @(
            'ksbl\.local',
            'ksbl\.ch',
            'kantonsspitalbl',
            'SV02037',
            'sv00213',
            'sv00701',
            'sv00702',
            'sv01250',
            'sv00516',
            'KSBL_IAM',
            'KSBL Helpdesk GUI',
            'Process-PersonMailbox',
            'LG-ADS_GMSA_Domain_Servers',
            '98972cc8-f5bc-4dcd-8bcc-ac82925d2bf2',
            'EE3A37116AF905168D5334A8CA74970B692F4491'
        )

        foreach ($pattern in $forbiddenPatterns) {
            $script:appRaw | Should -Not -Match $pattern
        }
    }

    It 'environments.onprem.json contains required productive OnPrem values' {
        $script:onPrem.ActiveDirectory.InternalUserOu | Should -Be 'OU=Internal,OU=_Users,DC=ksbl,DC=local'
        $script:onPrem.ActiveDirectory.ExternalUserOu | Should -Be 'OU=External,OU=_Users,DC=ksbl,DC=local'
        $script:onPrem.ActiveDirectory.ServiceUserOu | Should -Be 'OU=ServiceAccounts,OU=_Users,DC=ksbl,DC=local'
        $script:onPrem.ActiveDirectory.ManagedServiceUserOu | Should -Be 'CN=Managed Service Accounts,DC=ksbl,DC=local'
        $script:onPrem.ActiveDirectory.AdminUserOu | Should -Be 'OU=Admins,OU=_Users,DC=ksbl,DC=local'
        $script:onPrem.ActiveDirectory.GenericUserOu | Should -Be 'OU=Generics,OU=_Users,DC=ksbl,DC=local'
        $script:onPrem.ActiveDirectory.UpnDomainName | Should -Be 'ksbl.ch'

        $script:onPrem.HomeDirectory.NamespaceRoot | Should -Be '\\ksbl.local\HomeDrives'
        $script:onPrem.HomeDirectory.ApplicationDirectoryShare | Should -Be '\\sv00213\Appdata$'
        $script:onPrem.HomeDirectory.DesktopDirectoryShare | Should -Be '\\sv00213\desktop$'
        $script:onPrem.HomeDirectory.DefaultHomeDrive | Should -Be 'Z:'
        @($script:onPrem.HomeDirectory.UserProfileDirectoryShares) | Should -Contain '\\sv00701\UserProfiles$'
        @($script:onPrem.HomeDirectory.UserProfileDirectoryShares) | Should -Contain '\\sv00702\UserProfiles$'

        $script:onPrem.PersonMailbox.PrimaryMailDomain | Should -Be 'ksbl.ch'
        $script:onPrem.PersonMailbox.UpnDomainName | Should -Be 'ksbl.ch'
        $script:onPrem.PersonMailbox.CloudDomain | Should -Be 'kantonsspitalbl.mail.onmicrosoft.com'
        $script:onPrem.PersonMailbox.ScheduledTaskName | Should -Be 'Hospis Sync to Active Directory'
        $script:onPrem.PersonMailbox.PrincipalsAllowedToRetrieveManagedPassword | Should -Be 'LG-ADS_GMSA_Domain_Servers'

        $script:onPrem.ExchangeOnPrem.Enabled | Should -Be $true
        $script:onPrem.ExchangeOnPrem.PrimaryMailDomain | Should -Be 'ksbl.ch'
        $script:onPrem.ExchangeOnPrem.CloudDomain | Should -Be 'kantonsspitalbl.mail.onmicrosoft.com'

        $script:onPrem.Hospis.SqlServerInstance | Should -Be 'SV02037.ksbl.local'
        $script:onPrem.Hospis.Database | Should -Be 'KSBL_IAM'

        $script:onPrem.EventLog.LogName | Should -Be 'KSBL Helpdesk GUI'
        $script:onPrem.EventLog.Source | Should -Be 'Process-PersonMailbox'
    }

    It 'environments.hybrid.json contains required productive Hybrid values' {
        $script:hybrid.ExchangeOnline.Enabled | Should -Be $true
        $script:hybrid.ExchangeOnline.AppId | Should -Be '98972cc8-f5bc-4dcd-8bcc-ac82925d2bf2'
        $script:hybrid.ExchangeOnline.CertificateThumbprint | Should -Be 'EE3A37116AF905168D5334A8CA74970B692F4491'

        @($script:hybrid.ExchangeOnline.Organization, $script:hybrid.ExchangeOnline.TenantDomain) | Should -Contain 'kantonsspitalbl.onmicrosoft.com'

        $script:hybrid.ExchangeOnPrem.PrimaryMailDomain | Should -Be 'ksbl.ch'
        $script:hybrid.ExchangeOnPrem.CloudDomain | Should -Be 'kantonsspitalbl.mail.onmicrosoft.com'
        $script:hybrid.ActiveDirectory.InternalUserOu | Should -Be 'OU=Internal,OU=_Users,DC=ksbl,DC=local'
        $script:hybrid.Hospis.Database | Should -Be 'KSBL_IAM'
    }

    It 'OnPrem RemotePowerShell URI stays sv01250 in both environment files' {
        $script:onPrem.ExchangeOnPrem.RemotePowerShell.ConnectionUri | Should -Be 'http://sv01250.ksbl.local/PowerShell'
        $script:hybrid.ExchangeOnPrem.RemotePowerShell.ConnectionUri | Should -Be 'http://sv01250.ksbl.local/PowerShell'
    }

    It 'all configuration JSON files are parseable' {
        { $null = ($script:appRaw | ConvertFrom-Json) } | Should -Not -Throw
        { $null = ($script:onPremRaw | ConvertFrom-Json) } | Should -Not -Throw
        { $null = ($script:hybridRaw | ConvertFrom-Json) } | Should -Not -Throw
    }
}
