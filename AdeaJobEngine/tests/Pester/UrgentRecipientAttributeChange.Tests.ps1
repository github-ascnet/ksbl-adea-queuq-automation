Set-StrictMode -Version Latest

$root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

Import-Module -Name (Join-Path $root 'core\JobResult.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'core\Validation.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'core\Logging.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'shared\UrgentRecipientService.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'usecases\Urgent\UrgentRecipientAttributeChange.psm1') -Force -DisableNameChecking

BeforeAll {
    function New-TestLogger {
        [pscustomobject]@{
            RunId           = 'test-urgent-recipient'
            LogFile         = (Join-Path $TestDrive 'urgent-recipient.log')
            ConsoleEnabled  = $false
            FileEnabled     = $false
            EventLogEnabled = $false
            EventLogName    = 'Application'
            EventSource     = 'AdeaJobEngine.Tests'
            VerboseLogging  = $false
        }
    }
}

Describe 'Urgent recipient attribute change handler' {
    It 'fails when required fields are missing' {
        $context = [pscustomobject]@{
            Payload = @([pscustomobject]@{ Identity = 'user1' })
            Logger  = New-TestLogger
        }

        $result = Invoke-UrgentRecipientAttributeChange -Context $context
        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'USECASE_ERROR'
    }

    It 'returns Succeeded when service succeeds' {
        Mock -ModuleName 'UrgentRecipientAttributeChange' -CommandName Set-UrgentRecipientAttribute {
            [pscustomobject]@{ Success = $true; Changed = $true; Identity = 'user1'; AttributeName = 'description'; Operation = 'Set'; Message = 'ok'; ErrorCode = $null }
        }

        $context = [pscustomobject]@{
            Payload = @([pscustomobject]@{ Identity = 'user1'; AttributeName = 'description'; AttributeValue = 'test'; Operation = 'Set' })
            Logger  = New-TestLogger
        }

        $result = Invoke-UrgentRecipientAttributeChange -Context $context
        $result.Status | Should -Be 'Succeeded'
        $result.Output.Count | Should -Be 1
    }

    It 'returns Failed when service fails' {
        Mock -ModuleName 'UrgentRecipientAttributeChange' -CommandName Set-UrgentRecipientAttribute {
            [pscustomobject]@{ Success = $false; Changed = $false; Identity = 'user1'; AttributeName = 'description'; Operation = 'Set'; Message = 'bad'; ErrorCode = 'UNSUPPORTED_ATTRIBUTE' }
        }

        $context = [pscustomobject]@{
            Payload = @([pscustomobject]@{ Identity = 'user1'; AttributeName = 'description'; AttributeValue = 'test'; Operation = 'Set' })
            Logger  = New-TestLogger
        }

        $result = Invoke-UrgentRecipientAttributeChange -Context $context
        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'URGENT_RECIPIENT_ATTRIBUTE_CHANGE_FAILED'
    }

    It 'processes multiple payload rows successfully' {
        $calls = [System.Collections.ArrayList]::new()

        $context = [pscustomobject]@{
            Payload = @(
                [pscustomobject]@{ Identity = 'user1'; AttributeName = 'description'; AttributeValue = 'test1'; Operation = 'Set' },
                [pscustomobject]@{ Identity = 'user2'; AttributeName = 'mail'; AttributeValue = 'user2@example.org'; Operation = 'Set' }
            )
            Logger = New-TestLogger
        }

        $result = InModuleScope UrgentRecipientAttributeChange -Parameters @{
            TestContext = $context
            Calls       = $calls
        } {
            param($TestContext, $Calls)

            Mock -CommandName Set-UrgentRecipientAttribute {
                param($Context, $Identity, $AttributeName, $AttributeValue, $Operation)

                [void]$Calls.Add([pscustomobject]@{
                    Identity       = $Identity
                    AttributeName  = $AttributeName
                    AttributeValue = $AttributeValue
                    Operation      = $Operation
                })

                [pscustomobject]@{
                    Success       = $true
                    Changed       = $true
                    Identity      = $Identity
                    AttributeName = $AttributeName
                    Operation     = $Operation
                    Message       = 'ok'
                    ErrorCode     = $null
                }
            }

            Invoke-UrgentRecipientAttributeChange -Context $TestContext
        }

        $result.Status | Should -Be 'Succeeded'
        $result.Output.Count | Should -Be 2
        $calls.Count | Should -Be 2
    }

    It 'fails when one payload row fails and includes row results' {
        $context = [pscustomobject]@{
            Payload = @(
                [pscustomobject]@{ Identity = 'user1'; AttributeName = 'description'; AttributeValue = 'test1'; Operation = 'Set' },
                [pscustomobject]@{ Identity = 'user2'; AttributeName = 'description'; AttributeValue = 'test2'; Operation = 'Set' }
            )
            Logger = New-TestLogger
        }

        $result = InModuleScope UrgentRecipientAttributeChange -Parameters @{
            TestContext = $context
        } {
            param($TestContext)

            Mock -CommandName Set-UrgentRecipientAttribute {
                param($Context, $Identity, $AttributeName, $AttributeValue, $Operation)

                if ($Identity -eq 'user2') {
                    return [pscustomobject]@{
                        Success       = $false
                        Changed       = $false
                        Identity      = $Identity
                        AttributeName = $AttributeName
                        Operation     = $Operation
                        Message       = 'bad'
                        ErrorCode     = 'UNSUPPORTED_ATTRIBUTE'
                    }
                }

                [pscustomobject]@{
                    Success       = $true
                    Changed       = $true
                    Identity      = $Identity
                    AttributeName = $AttributeName
                    Operation     = $Operation
                    Message       = 'ok'
                    ErrorCode     = $null
                }
            }

            Invoke-UrgentRecipientAttributeChange -Context $TestContext
        }

        $result.Status | Should -Be 'Failed'
        $result.Output.Count | Should -Be 2
        @($result.Output | Where-Object { -not $_.Success }).Count | Should -Be 1
    }

    It 'does not call Set-ADUser directly in handler' {
        $content = Get-Content -Path (Join-Path $root 'usecases\Urgent\UrgentRecipientAttributeChange.psm1') -Raw
        $content | Should -Not -Match '(?i)Set-ADUser'
    }

    It 'does not reference ExchangeOnline in handler' {
        $content = Get-Content -Path (Join-Path $root 'usecases\Urgent\UrgentRecipientAttributeChange.psm1') -Raw
        $content | Should -Not -Match '(?i)ExchangeOnline|Connect-ExchangeOnline|EXO'
    }

    It 'does not reference TenantState or mailbox resolver in handler' {
        $content = Get-Content -Path (Join-Path $root 'usecases\Urgent\UrgentRecipientAttributeChange.psm1') -Raw
        $content | Should -Not -Match '(?i)TenantState|Resolve-MailboxExecutionContext'
    }
}

Describe 'Urgent recipient attribute service' {
    It 'sets allowed attribute via Set-AdUserSafe' {
        Mock -ModuleName 'UrgentRecipientService' -CommandName Set-AdUserSafe {}
        $context = [pscustomobject]@{ WhatIfMode = $false }

        $result = Set-UrgentRecipientAttribute -Context $context -Identity 'user1' -AttributeName 'description' -AttributeValue 'hello'
        $result.Success | Should -Be $true
        Should -Invoke Set-AdUserSafe -ModuleName 'UrgentRecipientService' -Times 1 -ParameterFilter {
            $Parameters.Identity -eq 'user1' -and $Parameters.Description -eq 'hello'
        }
    }

    It 'clears attribute when AttributeValue is empty' {
        Mock -ModuleName 'UrgentRecipientService' -CommandName Set-AdUserSafe {}
        $context = [pscustomobject]@{ WhatIfMode = $false }

        $result = Set-UrgentRecipientAttribute -Context $context -Identity 'user1' -AttributeName 'extensionAttribute6' -AttributeValue ''
        $result.Success | Should -Be $true
        $result.Operation | Should -Be 'Clear'
        Should -Invoke Set-AdUserSafe -ModuleName 'UrgentRecipientService' -Times 1 -ParameterFilter {
            $Parameters.Identity -eq 'user1' -and $Parameters.Clear -contains 'extensionAttribute6'
        }
    }

    It 'clears attribute when Operation is Clear' {
        Mock -ModuleName 'UrgentRecipientService' -CommandName Set-AdUserSafe {}
        $context = [pscustomobject]@{ WhatIfMode = $false }

        $result = Set-UrgentRecipientAttribute -Context $context -Identity 'user1' -AttributeName 'msDS-cloudExtensionAttribute15' -AttributeValue 'x' -Operation 'Clear'
        $result.Success | Should -Be $true
        $result.Operation | Should -Be 'Clear'
    }

    It 'rejects unsupported attributes' {
        $context = [pscustomobject]@{ WhatIfMode = $false }

        $result = Set-UrgentRecipientAttribute -Context $context -Identity 'user1' -AttributeName 'badAttribute' -AttributeValue 'x'
        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Be 'UNSUPPORTED_ATTRIBUTE'
    }

    It 'rejects unsupported operations' {
        $context = [pscustomobject]@{ WhatIfMode = $false }

        $result = Set-UrgentRecipientAttribute -Context $context -Identity 'user1' -AttributeName 'description' -AttributeValue 'x' -Operation 'Move'
        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Be 'URGENT_RECIPIENT_ATTRIBUTE_INVALID_OPERATION'
    }

    It 'rejects proxyAddresses until explicit semantics exist' {
        $context = [pscustomobject]@{ WhatIfMode = $false }

        $result = Set-UrgentRecipientAttribute -Context $context -Identity 'user1' -AttributeName 'proxyAddresses' -AttributeValue 'smtp:user1@example.org'
        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Be 'UNSUPPORTED_ATTRIBUTE'
    }

    It 'does not reference ExchangeOnline in service' {
        $content = Get-Content -Path (Join-Path $root 'shared\UrgentRecipientService.psm1') -Raw
        $content | Should -Not -Match '(?i)ExchangeOnline|Connect-ExchangeOnline|EXO'
    }
}
