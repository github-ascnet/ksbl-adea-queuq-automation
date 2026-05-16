BeforeAll {
    $root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

    Import-Module -Name (Join-Path $root 'core\JobResult.psm1') -Force
    Import-Module -Name (Join-Path $root 'core\Validation.psm1') -Force
    Import-Module -Name (Join-Path $root 'core\Logging.psm1') -Force
    Import-Module -Name (Join-Path $root 'core\JobState.psm1') -Force
    Import-Module -Name (Join-Path $root 'shared\PasswordGenerator.psm1') -Force
    Import-Module -Name (Join-Path $root 'shared\PersonMailboxService.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\PersonMailbox\CreateNonStdPersonMailbox.psm1') -Force

    function New-TestLogger {
        [pscustomobject]@{
            RunId           = 'test'
            LogFile         = (Join-Path $TestDrive 'test.log')
            ConsoleEnabled  = $false
            FileEnabled     = $false
            EventLogEnabled = $false
            EventLogName    = 'Application'
            EventSource     = 'MailboxAutomation.Tests'
            VerboseLogging  = $false
        }
    }

    function New-PersonMailboxRow {
        param([string]$EmployeeType = 'P', [string]$MailboxEnable = 'True')
        [pscustomobject]@{
            ActionType                 = 'CreateNonStdPersonMailbox'
            TargetAdObjectName          = 'ex01234'
            TargetDomain                = 'example.test'
            TargetUserDomainOU          = 'OU=External,DC=example,DC=test'
            TargetUserAdDisplayname     = 'Muster Max'
            TargetUserAdGivenname       = 'Max'
            TargetUserAdSurname         = 'Muster'
            TargetUserAdEmployeeType    = $EmployeeType
            TargetLocation              = 'LI'
            MailboxEnable               = $MailboxEnable
            CurrentUserName             = 'Requester'
            CurrentUserDomainName       = 'EXAMPLE'
            CurrentUserEMailAddress     = 'requester@example.test'
        }
    }

    function New-TestContext {
        param([object[]]$Rows, [string]$StableJobKey = 'CreateNonStdPersonMailbox_test_pshjob_')
        $rootPath = Join-Path $TestDrive 'MailboxAutomation'
        New-Item -Path (Join-Path $rootPath 'state') -ItemType Directory -Force | Out-Null
        [pscustomobject]@{
            JobId          = 'job001'
            StableJobKey   = $StableJobKey
            UseCaseName    = 'PersonMailbox.CreateNonStandard'
            Payload        = $Rows
            WhatIfMode     = $true
            Logger         = New-TestLogger
            RootPath       = $rootPath
            Config         = @{
                Paths = @{ StatePath = 'state' }
                PersonMailbox = @{ PrimaryMailDomain = 'example.test' }
                ExchangeOnPrem = @{ DefaultMailboxDatabases = @('DB01','DB02'); PrimaryMailDomain = 'example.test' }
            }
            Services       = @{}
        }
    }

}

Describe 'PersonMailbox.CreateNonStandard migration' {
    It 'builds legacy-compatible display name for normal person accounts' {
        $plan = New-NonStandardPersonMailboxPlan -Context (New-TestContext -Rows @()) -Data (New-PersonMailboxRow -EmployeeType 'P')
        $plan.DisplayName | Should -Be 'Muster Max'
        $plan.Location.City | Should -Be 'Liestal'
        $plan.MailboxEnable | Should -Be $true
    }

    It 'builds admin display name according to legacy rule' {
        $plan = New-NonStandardPersonMailboxPlan -Context (New-TestContext -Rows @()) -Data (New-PersonMailboxRow -EmployeeType 'A')
        $plan.DisplayName | Should -Be 'Admin Muster Max'
    }

    It 'derives LDAP filter for HNP accounts' {
        $row = New-PersonMailboxRow -EmployeeType 'HNP'
        $filter = New-NonStandardPersonMailboxLdapFilter -Data $row
        $filter | Should -Match 'employeeType=HNP'
        $filter | Should -Match 'displayName='
    }

    It 'prepare AD account returns WhatIf result without AD module' {
        $context = New-TestContext -Rows @()
        $result = Invoke-PrepareNonStandardPersonMailboxAdAccount -Context $context -Data (New-PersonMailboxRow)
        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Output.Action | Should -Contain 'UpdateExistingOrCreateAdUser'
    }

    It 'prepare mailbox returns WhatIf Enable-Mailbox operation' {
        $context = New-TestContext -Rows @()
        $result = Invoke-PrepareNonStandardPersonMailboxMailbox -Context $context -Data (New-PersonMailboxRow)
        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Output.Action | Should -Contain 'Enable-Mailbox'
    }

    It 'handler advances state machine one step per invocation in WhatIfMode' {
        $context = New-TestContext -Rows @((New-PersonMailboxRow))
        $result1 = Invoke-CreateNonStdPersonMailbox -Context $context
        $result1.Status | Should -Be 'Retry'
        $statePath = Get-JobStatePath -RootPath $context.RootPath -StatePath $context.Config.Paths.StatePath -StableJobKey $context.StableJobKey -JobId $context.JobId
        $state1 = Get-JobState -StateFilePath $statePath
        $state1.CurrentStep | Should -Be 20

        $result2 = Invoke-CreateNonStdPersonMailbox -Context $context
        $result2.Status | Should -Be 'Retry'
        $state2 = Get-JobState -StateFilePath $statePath
        $state2.CurrentStep | Should -Be 30
    }

    It 'handler accepts legacy TargetUserDomainOU and backwards-compatible TargetDomainUserOU alias' {
        $row = New-PersonMailboxRow
        $row.PSObject.Properties.Remove('TargetUserDomainOU')
        $row | Add-Member -NotePropertyName 'TargetDomainUserOU' -NotePropertyValue 'OU=External,DC=example,DC=test'
        $context = New-TestContext -Rows @($row) -StableJobKey 'CreateNonStdPersonMailbox_alias_pshjob_'
        { Invoke-CreateNonStdPersonMailbox -Context $context } | Should -Not -Throw
    }
}
