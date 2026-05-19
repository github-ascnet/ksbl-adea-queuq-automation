BeforeAll {
    $root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

    Import-Module -Name (Join-Path $root 'core\JobResult.psm1') -Force
    Import-Module -Name (Join-Path $root 'core\Validation.psm1') -Force
    Import-Module -Name (Join-Path $root 'core\Logging.psm1') -Force
    Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1') -Force
    Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1') -Force
    Import-Module -Name (Join-Path $root 'infrastructure\SqlGateway.psm1') -Force
    Import-Module -Name (Join-Path $root 'shared\MailboxFeatureService.psm1') -Force
    Import-Module -Name (Join-Path $root 'shared\HospisPersonService.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\Urgent\InactivateHospisPerson.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\UserPerson\HospisPersonUseCase.psm1') -Force

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
        param([object[]]$Rows)

        [pscustomobject]@{
            Payload        = $Rows
            WhatIfMode     = $true
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
