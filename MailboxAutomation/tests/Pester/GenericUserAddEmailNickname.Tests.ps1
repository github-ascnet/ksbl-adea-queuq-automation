$root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

Import-Module -Name (Join-Path $root 'core\JobResult.psm1') -Force
Import-Module -Name (Join-Path $root 'core\Validation.psm1') -Force
Import-Module -Name (Join-Path $root 'core\Logging.psm1') -Force
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1') -Force
Import-Module -Name (Join-Path $root 'shared\UserProvisioningService.psm1') -Force
Import-Module -Name (Join-Path $root 'usecases\GenericUser\AddEmailNickname.psm1') -Force

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

function New-AddEmailNicknameRow {
    param(
        [string]$ActionType = 'AddEMailNickName',
        [string]$AdObjectName = 'test.user',
        [string]$NewPrimaryEMailAddress = 'test.user.alias@example.org',
        [string]$CurrentUserName = 'Requester',
        [string]$CurrentUserDomainName = 'DOMAIN',
        [string]$CurrentUserEMailAddress = 'requester@example.org'
    )

    [pscustomobject]@{
        ActionType               = $ActionType
        AdObjectName             = $AdObjectName
        NewPrimaryEMailAddress   = $NewPrimaryEMailAddress
        CurrentUserName          = $CurrentUserName
        CurrentUserDomainName    = $CurrentUserDomainName
        CurrentUserEMailAddress  = $CurrentUserEMailAddress
    }
}

Describe 'GenericUser.AddEmailNickname handler' {
    It 'returns Succeeded when the service succeeds' {
        $context = [pscustomobject]@{
            Payload    = @(New-AddEmailNicknameRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = [pscustomobject]@{
                UserProvisioning = [pscustomobject]@{
                    AddEmailNickname = {
                        param($Context, $Data)
                        [pscustomobject]@{
                            Success = $true
                            Changed = $true
                            Message = 'ok'
                            ErrorCode = $null
                        }
                    }
                }
            }
        }

        $result = Invoke-AddEmailNickname -Context $context
        $result.Status | Should -Be 'Succeeded'
        $result.Output.Count | Should -Be 1
    }

    It 'returns Failed when the service reports failure' {
        $context = [pscustomobject]@{
            Payload    = @(New-AddEmailNicknameRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = [pscustomobject]@{
                UserProvisioning = [pscustomobject]@{
                    AddEmailNickname = {
                        param($Context, $Data)
                        [pscustomobject]@{
                            Success = $false
                            Changed = $false
                            Message = 'mailbox not found'
                            ErrorCode = 'MAILBOX_NOT_FOUND'
                        }
                    }
                }
            }
        }

        $result = Invoke-AddEmailNickname -Context $context
        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'ADD_EMAIL_NICKNAME_FAILED'
    }

    It 'fails when required CSV fields are missing or empty' {
        $context = [pscustomobject]@{
            Payload    = @([pscustomobject]@{ ActionType = 'AddEMailNickName'; AdObjectName = '' })
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = [pscustomobject]@{
                UserProvisioning = [pscustomobject]@{
                    AddEmailNickname = { param($Context, $Data) throw 'should not be called' }
                }
            }
        }

        $result = Invoke-AddEmailNickname -Context $context
        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'USECASE_ERROR'
    }
}

Describe 'Add-GenericUserEmailNickname service' {
    It 'returns a simulated result in WhatIfMode without requiring Exchange cmdlets' {
        $context = [pscustomobject]@{
            Logger     = New-TestLogger
            WhatIfMode = $true
        }
        $row = New-AddEmailNicknameRow

        $result = Add-GenericUserEmailNickname -Context $context -Data $row

        $result.Success | Should -Be $true
        $result.Changed | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Set-Mailbox'
        $result.Parameters.PrimarySmtpAddress | Should -Be $row.NewPrimaryEMailAddress
        $result.Parameters.EmailAddressPolicyEnabled | Should -Be $false
    }

    It 'returns a controlled failure when mailbox lookup fails outside WhatIfMode' {
        $context = [pscustomobject]@{
            Logger     = New-TestLogger
            WhatIfMode = $false
        }
        $row = New-AddEmailNicknameRow

        $result = Add-GenericUserEmailNickname -Context $context -Data $row

        $result.Success | Should -Be $false
        $result.Changed | Should -Be $false
        $result.ErrorCode | Should -Be 'MAILBOX_GET_FAILED'
    }
}
