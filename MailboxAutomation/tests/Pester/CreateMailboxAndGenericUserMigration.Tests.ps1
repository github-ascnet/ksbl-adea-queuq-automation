$root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

Import-Module -Name (Join-Path $root 'core\JobResult.psm1') -Force
Import-Module -Name (Join-Path $root 'core\Validation.psm1') -Force
Import-Module -Name (Join-Path $root 'core\Logging.psm1') -Force
Import-Module -Name (Join-Path $root 'shared\Naming.psm1') -Force
Import-Module -Name (Join-Path $root 'shared\AccountNameGenerator.psm1') -Force
Import-Module -Name (Join-Path $root 'shared\PasswordGenerator.psm1') -Force
Import-Module -Name (Join-Path $root 'shared\TenantState.psm1') -Force
Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1') -Force
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1') -Force
Import-Module -Name (Join-Path $root 'shared\GroupMailboxService.psm1') -Force
Import-Module -Name (Join-Path $root 'shared\UserProvisioningService.psm1') -Force
Import-Module -Name (Join-Path $root 'usecases\GroupMailbox\CreateGroupMailbox.psm1') -Force
Import-Module -Name (Join-Path $root 'usecases\GenericUser\CreateMultiFunctionGenericUser.psm1') -Force

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

function New-TestContext {
    param([object[]]$Rows)

    [pscustomobject]@{
        Payload        = $Rows
        WhatIfMode     = $true
        Logger         = New-TestLogger
        Config         = @{
            ExchangeOnPrem = @{
                Enabled = $true
                DefaultMailboxDatabases = @('DB01','DB02')
                CloudDomain = 'cloud.example.test'
            }
            ActiveDirectory = @{
                Enabled = $true
                InternalUserOu = 'OU=Generic,DC=example,DC=test'
                HomeDirectory = '\\fileserver\home'
                HomeDirectoryDrive = 'H:'
                ApplicationDirectoryShare = '\\fileserver\apps'
                DesktopDirectoryShare = '\\fileserver\desktop'
            }
        }
        Services       = @{
            GroupMailbox = [pscustomobject]@{
                Create = { param($Context, $Data) New-GroupMailbox -Context $Context -Data $Data }
            }
            UserProvisioning = [pscustomobject]@{
                NewUser = { param($Context, $Data) New-GenericUser -Context $Context -Data $Data }
            }
        }
    }
}

function New-GroupMailboxCreateRow {
    [pscustomobject]@{
        ActionType               = 'CreateGroupMailbox'
        DisplayName              = 'Test Group Mailbox'
        FirstName                = 'Test'
        LastName                 = 'Group Mailbox'
        PrimarySmtpAddress       = 'gmb.test@example.test'
        NewPrimaryEMailAddress   = 'gmb.new@example.test'
        AdObjectName             = 'gmb00001'
        OrgUnit                  = 'OU=GroupMailboxes,DC=example,DC=test'
        HideInAb                 = 'True'
        Manager                  = 'manager01[]ADD'
        FullAccessMembers        = 'user01[]ADD!user02[]ADD'
        CurrentUserName          = 'Requester'
        CurrentUserDomainName    = 'EXAMPLE'
        CurrentUserEMailAddress  = 'requester@example.test'
    }
}

function New-CreateMultiFunctionRow {
    [pscustomobject]@{
        ActionType                  = 'CreateMultiFunctionGenericUser'
        TargetAdObjectName          = 'generic001'
        TargetDomain                = 'example.test'
        TargetUserAdDisplayname     = 'Generic User 001'
        TargetUserAdEmployeeType    = 'GENERIC'
        Description                 = 'Generic account'
        Manager                     = 'manager01[]ADD'
        CurrentUserName             = 'Requester'
        CurrentUserDomainName       = 'EXAMPLE'
        CurrentUserEMailAddress     = 'requester@example.test'
    }
}

Describe 'GroupMailbox.Create migration' {
    It 'service returns WhatIf operations without Exchange cmdlets' {
        $context = New-TestContext -Rows @()
        $result = New-GroupMailbox -Context $context -Data (New-GroupMailboxCreateRow)

        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Changed | Should -Be $true
        $result.Operations.Action | Should -Contain 'New-Mailbox'
        $result.Operations.Action | Should -Contain 'Add-ADGroupMember'
    }

    It 'handler validates and aggregates successful service result' {
        $row = New-GroupMailboxCreateRow
        $context = New-TestContext -Rows @($row)

        $result = Invoke-CreateGroupMailbox -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.Output[0].Success | Should -Be $true
    }
}

Describe 'GenericUser.CreateMultiFunction migration' {
    It 'service returns WhatIf operations without AD module' {
        $context = New-TestContext -Rows @()
        $result = New-GenericUser -Context $context -Data (New-CreateMultiFunctionRow)

        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Changed | Should -Be $true
        $result.Output.Action | Should -Contain 'New-ADUser'
        $result.Output.Action | Should -Contain 'Set-ADUser'
    }

    It 'handler validates and aggregates successful service result' {
        $row = New-CreateMultiFunctionRow
        $context = New-TestContext -Rows @($row)

        $result = Invoke-CreateMultiFunctionGenericUser -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.Output[0].Success | Should -Be $true
    }
}
