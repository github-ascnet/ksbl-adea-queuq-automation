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

    Import-Module -Name (Join-Path -Path $root -ChildPath 'core\JobEngine.psm1') -Force

    $mergeConfig = {
        param(
            [Parameter(Mandatory = $true)][string]$AppSettingsPath,
            [Parameter(Mandatory = $true)][string]$EnvironmentPath,
            [Parameter(Mandatory = $true)][string]$RootPath
        )

        InModuleScope -ModuleName JobEngine -Parameters @{
            AppSettingsPath = $AppSettingsPath
            EnvironmentPath = $EnvironmentPath
            RootPath = $RootPath
        } -ScriptBlock {
            param(
                [Parameter(Mandatory = $true)][string]$AppSettingsPath,
                [Parameter(Mandatory = $true)][string]$EnvironmentPath,
                [Parameter(Mandatory = $true)][string]$RootPath
            )

            $baseConfig = Read-JsonAsHashtable -Path $AppSettingsPath
            $environmentConfig = Read-JsonAsHashtable -Path $EnvironmentPath
            $mergedConfig = Merge-Hashtable -Base $baseConfig -Override $environmentConfig
            $mergedConfig['RootPath'] = $RootPath
            $mergedConfig
        }
    }

    $script:mergedOnPrem = & $mergeConfig -AppSettingsPath $script:appSettingsPath -EnvironmentPath $script:onPremPath -RootPath $root
    $script:mergedHybrid = & $mergeConfig -AppSettingsPath $script:appSettingsPath -EnvironmentPath $script:hybridPath -RootPath $root
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

    It 'merged OnPrem runtime config contains base defaults and productive OnPrem overrides' {
        $script:mergedOnPrem.EnvironmentName | Should -Be 'OnPrem'
        $script:mergedOnPrem.RootPath | Should -Be (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
        $script:mergedOnPrem.Paths.QueueRoot | Should -Be 'queues'
        $script:mergedOnPrem.CsvDelimiter | Should -Be '|'
        $script:mergedOnPrem.WhatIfDefault | Should -Be $true

        $script:mergedOnPrem.ExchangeOnline.Enabled | Should -Be $false
        $script:mergedOnPrem.ExchangeOnline.AppId | Should -Be ''
        $script:mergedOnPrem.ExchangeOnPrem.RemotePowerShell.User | Should -Be 'ksbl\ServiceIAMJobs10'
        $script:mergedOnPrem.ExchangeOnPrem.RemotePowerShell.SecretPath | Should -Be 'D:\iam\Secrets\serviceiamjobs10.sec'
        $script:mergedOnPrem.ExchangeOnPrem.RemotePowerShell.ConnectionUri | Should -Be 'http://sv01250.ksbl.local/PowerShell'
        $script:mergedOnPrem.ExchangeOnPrem.RemotePowerShell.Authentication | Should -Be 'Kerberos'

        $script:mergedOnPrem.Notifications.Cc | Should -Contain 'ksbl.vl.iam-administrators@ksbl.ch'
        $script:mergedOnPrem.HomeDirectory.NamespaceRoot | Should -Be '\\ksbl.local\HomeDrives'
        $script:mergedOnPrem.HomeDirectory.DefaultHomeDrive | Should -Be 'Z:'
        $script:mergedOnPrem.EventLog.LogName | Should -Be 'KSBL Helpdesk GUI'
    }

    It 'merged Hybrid runtime config contains OnPrem runtime values plus Exchange Online values' {
        $script:mergedHybrid.EnvironmentName | Should -Be 'Hybrid'
        $script:mergedHybrid.Paths.QueueRoot | Should -Be 'queues'
        $script:mergedHybrid.CsvDelimiter | Should -Be '|'
        $script:mergedHybrid.WhatIfDefault | Should -Be $true

        $script:mergedHybrid.ExchangeOnline.Enabled | Should -Be $true
        $script:mergedHybrid.ExchangeOnline.AppId | Should -Be '98972cc8-f5bc-4dcd-8bcc-ac82925d2bf2'
        $script:mergedHybrid.ExchangeOnline.Organization | Should -Be 'kantonsspitalbl.onmicrosoft.com'
        $script:mergedHybrid.ExchangeOnline.TenantDomain | Should -Be 'kantonsspitalbl.onmicrosoft.com'
        $script:mergedHybrid.ExchangeOnline.CertificateThumbprint | Should -Be 'EE3A37116AF905168D5334A8CA74970B692F4491'

        $script:mergedHybrid.ExchangeOnPrem.RemotePowerShell.User | Should -Be 'ksbl\ServiceIAMJobs10'
        $script:mergedHybrid.ExchangeOnPrem.RemotePowerShell.SecretPath | Should -Be 'D:\iam\Secrets\serviceiamjobs10.sec'
        $script:mergedHybrid.ExchangeOnPrem.RemotePowerShell.ConnectionUri | Should -Be 'http://sv01250.ksbl.local/PowerShell'
        $script:mergedHybrid.ExchangeOnPrem.RemotePowerShell.Authentication | Should -Be 'Kerberos'

        $script:mergedHybrid.Notifications.Cc | Should -Contain 'ksbl.vl.iam-administrators@ksbl.ch'
        $script:mergedHybrid.ActiveDirectory.DefaultDomain | Should -Be 'ksbl.local'
        $script:mergedHybrid.HomeDirectory.ApplicationDirectoryShare | Should -Be '\\sv00213\Appdata$'
        $script:mergedHybrid.Hospis.Database | Should -Be 'KSBL_IAM'
    }

    It 'all configuration JSON files are parseable' {
        { $null = ($script:appRaw | ConvertFrom-Json) } | Should -Not -Throw
        { $null = ($script:onPremRaw | ConvertFrom-Json) } | Should -Not -Throw
        { $null = ($script:hybridRaw | ConvertFrom-Json) } | Should -Not -Throw
    }
}
