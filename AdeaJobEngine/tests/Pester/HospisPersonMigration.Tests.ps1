BeforeAll {
    $root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

    Import-Module -Name (Join-Path $root 'core\JobResult.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'core\Validation.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'core\Logging.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'infrastructure\SqlGateway.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'shared\MailboxFeatureService.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'shared\HospisPersonService.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'usecases\Urgent\InactivateHospisPerson.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'usecases\UserPerson\HospisPersonUseCase.psm1') -Force -DisableNameChecking

    function New-TestLogger {
        [pscustomobject]@{
            RunId           = 'test'
            LogFile         = (Join-Path $TestDrive 'test.log')
            ConsoleEnabled  = $false
            FileEnabled     = $false
            EventLogEnabled = $false
            EventLogName    = 'Application'
            EventSource     = 'AdeaJobEngine.Tests'
            VerboseLogging  = $false
        }
    }

    function New-HospisTestContext {
        param(
            [object[]]$Rows,
            [bool]$WhatIfMode = $true
        )

        [pscustomobject]@{
            Payload        = $Rows
            WhatIfMode     = $WhatIfMode
            Logger         = New-TestLogger
            Config         = @{
                Paths = @{
                    StatePath = 'state'
                }
                Hospis = @{
                    ArchiveRoot = 'D:\IAM\Archive'
                    SqlServerInstance = 'sql.test.local'
                    Database = 'KSBL_Hospis_Staging'
                    ConnectionString = ''
                    AustrittOOOExternalMessage = 'External'
                    AustrittOOOInternalMessage = 'Internal'
                }
            }
            Services       = @{
                HospisPerson = [pscustomobject]@{
                    SubmitTransaction   = { param($Context, $Data) Submit-HospisPersonTransaction -Context $Context -Data $Data }
                    UrgentInactivation = { param($Context, $Data) Invoke-UrgentHospisPersonInactivation -Context $Context -Data $Data }
                }
            }
            SourceFile     = 'HospisPersonUseCase_sample_pshjob_.csv'
            WorkingFile    = 'HospisPersonUseCase_sample_pshjob_.csv'
            RootPath       = [string]$root
        }
    }

}

Describe 'Hospis person use case migration' {
    It 'builds Erstellen SQL using the legacy stored procedure' {
        $row = [pscustomobject]@{
            ActionType = 'Erstellen'
            PersId = '12345'
            DisplayName = 'Test Person'
            RefUserId = 'ref01'
            RefUserDomain = 'KSBL'
            LocationName = ''
            MigrateUser = ''
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }

        $sql = New-HospisPersonTransactionSql -Data $row -ArchiveFilePath 'D:\IAM\Archive\job.csv'
        $sql | Should -Match 'usp_create_erstellen_transaction'
        $sql | Should -Match '12345'
        $sql | Should -Match 'ref01'
    }

    It 'builds urgent inactivation SQL using the legacy stored procedure' {
        $row = [pscustomobject]@{
            ActionType = 'Inaktivieren'
            PersId = '12345'
            DisplayName = 'Test Person'
            MigrateUser = 'false'
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }

        $sql = New-UrgentHospisInactivationSql -Data $row
        $sql | Should -Match 'usp_create_urgent_inaktivieren_transaction'
        $sql | Should -Match '12345'
        $sql | Should -Match 'KSBL\\operator'
    }

    It 'UserPerson.HospisPersonUseCase succeeds in WhatIf mode' {
        $row = [pscustomobject]@{
            ActionType = 'Aktivieren'
            PersId = '12345'
            DisplayName = 'Test Person'
            RefUserId = 'ref01'
            RefUserDomain = 'KSBL'
            LocationName = ''
            MigrateUser = 'true'
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }

        $context = New-HospisTestContext -Rows @($row)
        $result = Invoke-HospisPersonUseCase -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.Output[0].Success | Should -Be $true
        $result.Output[0].Simulated | Should -Be $true
    }

    It 'UserPerson.HospisPersonUseCase keeps AdObjectName optional' {
        $row = [pscustomobject]@{
            ActionType = 'Inaktivieren'
            PersId = '12345'
            DisplayName = 'Test Person'
            MigrateUser = 'false'
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }

        $context = New-HospisTestContext -Rows @($row)
        $result = Invoke-HospisPersonUseCase -Context $context

        $result.Status | Should -Be 'Succeeded'
    }

    It 'UserPerson.HospisPersonUseCase validates action-specific Standortwechsel fields' {
        $row = [pscustomobject]@{
            ActionType = 'Standortwechsel'
            PersId = '12345'
            DisplayName = 'Test Person'
            RefUserId = 'ref01'
            RefUserDomain = 'KSBL'
            LocationName = ''
            MigrateUser = 'true'
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }

        $context = New-HospisTestContext -Rows @($row)
        $result = Invoke-HospisPersonUseCase -Context $context

        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'USECASE_ERROR'
    }

    It 'Urgent.InactivateHospisPerson succeeds in WhatIf mode without AD or Exchange modules' {
        $row = [pscustomobject]@{
            ActionType = 'Inaktivieren'
            PersId = '12345'
            DisplayName = 'Test Person'
            MigrateUser = 'false'
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }

        $context = New-HospisTestContext -Rows @($row)
        $result = Invoke-InactivateHospisPerson -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.Output[0].Success | Should -Be $true
        $result.Output[0].Simulated | Should -Be $true
    }
}

Describe 'Urgent.InactivateHospisPerson handler behavior' {
    It 'fails when one of multiple rows fails and keeps all row results in output' {
        $row1 = [pscustomobject]@{
            ActionType = 'Inaktivieren'
            PersId = '10001'
            DisplayName = 'A'
            MigrateUser = 'false'
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }
        $row2 = [pscustomobject]@{
            ActionType = 'Inaktivieren'
            PersId = '10002'
            DisplayName = 'B'
            MigrateUser = 'false'
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }

        $context = New-HospisTestContext -Rows @($row1, $row2)
        $context.Services.HospisPerson.UrgentInactivation = {
            param($Context, $Data)
            if ([string]$Data.PersId -eq '10002') {
                return [pscustomobject]@{ Success = $false; Message = 'failed'; ErrorCode = 'X'; PersId = $Data.PersId }
            }
            [pscustomobject]@{ Success = $true; Message = 'ok'; ErrorCode = $null; PersId = $Data.PersId }
        }

        $result = Invoke-InactivateHospisPerson -Context $context
        $result.Status | Should -Be 'Failed'
        @($result.Output).Count | Should -Be 2
        @($result.Output | Where-Object { -not $_.Success }).Count | Should -Be 1
    }

    It 'does not call AD, Exchange or SQL cmdlets directly in handler' {
        $content = Get-Content -Path (Join-Path $root 'usecases\Urgent\InactivateHospisPerson.psm1') -Raw
        $content | Should -Not -Match '(?i)Set-ADUser|Disable-ADAccount|Remove-ADGroupMember|Set-MailboxAutoReplyConfiguration|Invoke-Sqlcmd'
    }

    It 'does not reference ExchangeOnline or TenantState in handler' {
        $content = Get-Content -Path (Join-Path $root 'usecases\Urgent\InactivateHospisPerson.psm1') -Raw
        $content | Should -Not -Match '(?i)ExchangeOnline|Connect-ExchangeOnline|EXO|TenantState|Set-TenantState|Get-TenantState'
    }
}

Describe 'Hospis urgent inactivation service behavior' {
    It 'returns structured success and executes AD, ExchangeOnPrem and SQL steps when homeMdb exists' {
        Mock -ModuleName 'HospisPersonService' -CommandName Get-AdUsersByEmployeeIdSafe {
            @([pscustomobject]@{
                SamAccountName = 'u123'
                mailNickname = 'u123'
                homeMdb = 'MDB1'
                memberof = @(
                    'CN=TPL-TEST,OU=Groups,DC=example,DC=test',
                    'CN=GG-KSBL-VDI-Remote-TEST,OU=Groups,DC=example,DC=test',
                    'CN=GG-OneSign-TEST,OU=Groups,DC=example,DC=test'
                )
            })
        }
        Mock -ModuleName 'HospisPersonService' -CommandName Disable-AdAccountSafe { [pscustomobject]@{ Action = 'Disable-ADAccount' } }
        Mock -ModuleName 'HospisPersonService' -CommandName Set-MailboxVisibility { [pscustomobject]@{ Action = 'Set-MailboxVisibility' } }
        Mock -ModuleName 'HospisPersonService' -CommandName Set-OnPremMailboxAutoReplyConfigurationSafe { [pscustomobject]@{ Action = 'Set-MailboxAutoReplyConfiguration' } }
        Mock -ModuleName 'HospisPersonService' -CommandName Remove-AdGroupMemberSafe { [pscustomobject]@{ Success = $true } }
        Mock -ModuleName 'HospisPersonService' -CommandName Set-AdUserSafe { [pscustomobject]@{ Action = 'Set-ADUser' } }
        Mock -ModuleName 'HospisPersonService' -CommandName Invoke-HospisSqlNonQuery { [pscustomobject]@{ Action = 'Invoke-SqlNonQuerySafe' } }

        $row = [pscustomobject]@{
            ActionType = 'Inaktivieren'
            PersId = '12345'
            DisplayName = 'Test Person'
            MigrateUser = 'false'
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }
        $context = New-HospisTestContext -Rows @($row) -WhatIfMode:$false

        $result = Invoke-UrgentHospisPersonInactivation -Context $context -Data $row

        $result.Success | Should -Be $true
        $result.Disabled | Should -Be $true
        $result.MailboxHandled | Should -Be $true
        $result.AutoReplyConfigured | Should -Be $true
        $result.EmailRevocationsClosed | Should -Be $true
        $result.ExtensionAttribute6Cleared | Should -Be $true
        $result.CloudExtensionAttribute15Cleared | Should -Be $true
        $result.DescriptionSet | Should -Be $true
        $result.UrgentTransactionCreated | Should -Be $true
        $result.GroupsRemoved | Should -Be 3
        Should -Invoke Set-OnPremMailboxAutoReplyConfigurationSafe -ModuleName 'HospisPersonService' -Times 1
        Should -Invoke Remove-AdGroupMemberSafe -ModuleName 'HospisPersonService' -Times 3
        Should -Invoke Set-AdUserSafe -ModuleName 'HospisPersonService' -Times 2
        Should -Invoke Invoke-HospisSqlNonQuery -ModuleName 'HospisPersonService' -Times 2
    }

    It 'does not configure auto reply and email revocations when homeMdb is empty' {
        Mock -ModuleName 'HospisPersonService' -CommandName Get-AdUsersByEmployeeIdSafe {
            @([pscustomobject]@{
                SamAccountName = 'u123'
                mailNickname = 'u123'
                homeMdb = ''
                memberof = @()
            })
        }
        Mock -ModuleName 'HospisPersonService' -CommandName Disable-AdAccountSafe { [pscustomobject]@{ Action = 'Disable-ADAccount' } }
        Mock -ModuleName 'HospisPersonService' -CommandName Set-OnPremMailboxAutoReplyConfigurationSafe { [pscustomobject]@{ Action = 'Set-MailboxAutoReplyConfiguration' } }
        Mock -ModuleName 'HospisPersonService' -CommandName Set-AdUserSafe { [pscustomobject]@{ Action = 'Set-ADUser' } }
        Mock -ModuleName 'HospisPersonService' -CommandName Invoke-HospisSqlNonQuery { [pscustomobject]@{ Action = 'Invoke-SqlNonQuerySafe' } }

        $row = [pscustomobject]@{
            ActionType = 'Aktivieren'
            PersId = '12345'
            DisplayName = 'Test Person'
            MigrateUser = 'false'
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }
        $context = New-HospisTestContext -Rows @($row) -WhatIfMode:$false

        $result = Invoke-UrgentHospisPersonInactivation -Context $context -Data $row
        $result.Success | Should -Be $true
        $result.MailboxHandled | Should -Be $false
        $result.AutoReplyConfigured | Should -Be $false
        $result.EmailRevocationsClosed | Should -Be $false
        $result.UrgentTransactionCreated | Should -Be $false
        Should -Invoke Set-OnPremMailboxAutoReplyConfigurationSafe -ModuleName 'HospisPersonService' -Times 0
        Should -Invoke Invoke-HospisSqlNonQuery -ModuleName 'HospisPersonService' -Times 0 -ParameterFilter { $Query -match 'EMailRevocations' }
    }

    It 'sets description in expected urgent format' {
        Mock -ModuleName 'HospisPersonService' -CommandName Get-AdUsersByEmployeeIdSafe {
            @([pscustomobject]@{ SamAccountName = 'u123'; homeMdb = ''; memberof = @() })
        }
        Mock -ModuleName 'HospisPersonService' -CommandName Disable-AdAccountSafe { [pscustomobject]@{ Action = 'Disable-ADAccount' } }
        Mock -ModuleName 'HospisPersonService' -CommandName Set-AdUserSafe { [pscustomobject]@{ Action = 'Set-ADUser' } }

        $row = [pscustomobject]@{
            ActionType = 'Aktivieren'
            PersId = '12345'
            DisplayName = 'Test Person'
            MigrateUser = 'false'
            CurrentUserName = 'operator'
            CurrentUserDomainName = 'KSBL'
            CurrentUserEMailAddress = 'operator@example.test'
        }
        $context = New-HospisTestContext -Rows @($row) -WhatIfMode:$false

        [void](Invoke-UrgentHospisPersonInactivation -Context $context -Data $row)

        Should -Invoke Set-AdUserSafe -ModuleName 'HospisPersonService' -Times 1 -ParameterFilter {
            $Parameters.Description -match '^Inaktiviert \(Urgent\) am \d{4}-\d{2}-\d{2} von operator$'
        }
    }

    It 'does not reference ExchangeOnline or TenantState in HospisPersonService' {
        $content = Get-Content -Path (Join-Path $root 'shared\HospisPersonService.psm1') -Raw
        $content | Should -Not -Match '(?i)ExchangeOnline|Connect-ExchangeOnline|EXO|TenantState|Set-TenantState|Get-TenantState'
    }
}
