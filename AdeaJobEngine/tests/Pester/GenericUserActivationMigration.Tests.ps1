BeforeAll {
    $root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

    Import-Module -Name (Join-Path $root 'core\JobResult.psm1') -Force
    Import-Module -Name (Join-Path $root 'core\Validation.psm1') -Force
    Import-Module -Name (Join-Path $root 'core\Logging.psm1') -Force
    Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1') -Force
    Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1') -Force
    Import-Module -Name (Join-Path $root 'infrastructure\DfsGateway.psm1') -Force
    Import-Module -Name (Join-Path $root 'shared\MailboxFeatureService.psm1') -Force
    Import-Module -Name (Join-Path $root 'shared\UserProvisioningService.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\GenericUser\EnableGenericUser.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\GenericUser\DisableGenericUser.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\GenericUser\EnableAdAccountWithGracePeriod.psm1') -Force
    Import-Module -Name (Join-Path $root 'usecases\GenericUser\ModifyMobilePhoneNumber.psm1') -Force

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

    function New-TestContext {
        param(
            [object[]]$Payload,
            [hashtable]$Services,
            [bool]$WhatIfMode = $true
        )

        if (-not $Services) {
            $Services = @{
                UserProvisioning = [pscustomobject]@{
                    EnableUser            = { param($Context, $Data) Enable-GenericUser -Context $Context -Data $Data }
                    DisableUser           = { param($Context, $Data) Disable-GenericUser -Context $Context -Data $Data }
                    EnableWithGracePeriod = { param($Context, $Data) Enable-GenericUserWithGracePeriod -Context $Context -Data $Data }
                    SetMobilePhoneNumber  = { param($Context, $Data) Set-GenericUserMobilePhoneNumber -Context $Context -Data $Data }
                }
            }
        }

        [pscustomobject]@{
            Payload    = $Payload
            Logger     = New-TestLogger
            WhatIfMode = $WhatIfMode
            Config     = @{}
            Services   = [pscustomobject]$Services
        }
    }

    function New-EnableDisableRow {
        param(
            [string]$ActionType = 'EnableNonStdPersonMailbox',
            [string]$AdObjectName = 'user01'
        )

        [pscustomobject]@{
            ActionType              = $ActionType
            AdObjectName            = $AdObjectName
            CurrentUserName         = 'Requester'
            CurrentUserDomainName   = 'DOMAIN'
            CurrentUserEMailAddress = 'requester@example.org'
        }
    }

    function New-GraceRow {
        [pscustomobject]@{
            ActionType              = 'EnableAdAccountWithGracePeriod'
            AdObjectName            = 'user01'
            TargetAdObjectName      = 'user01'
            GracePeriod             = '2099-12-31'
            CurrentUserName         = 'Requester'
            CurrentUserDomainName   = 'DOMAIN'
            CurrentUserEMailAddress = 'requester@example.org'
        }
    }

    function New-MobileRow {
        [pscustomobject]@{
            ActionType              = 'ModifyMobilePhoneNumber'
            AdObjectName            = 'user01'
            MobileNumber            = '+41791234567'
            CurrentUserName         = 'Requester'
            CurrentUserDomainName   = 'DOMAIN'
            CurrentUserEMailAddress = 'requester@example.org'
        }
    }

}

Describe 'GenericUser enable/disable migration handlers' {
    It 'Enable handler returns Succeeded when service succeeds' {
        $services = @{
            UserProvisioning = [pscustomobject]@{
                EnableUser = {
                    param($Context, $Data)
                    [pscustomobject]@{ Success = $true; Message = 'enabled'; ErrorCode = $null }
                }
            }
        }
        $context = New-TestContext -Payload @(New-EnableDisableRow) -Services $services

        $result = Invoke-EnableGenericUser -Context $context

        $result.Status | Should -Be 'Succeeded'
    }

    It 'Disable handler returns Failed when service fails' {
        $services = @{
            UserProvisioning = [pscustomobject]@{
                DisableUser = {
                    param($Context, $Data)
                    [pscustomobject]@{ Success = $false; Message = 'failed'; ErrorCode = 'TEST_ERROR' }
                }
            }
        }
        $row = New-EnableDisableRow -ActionType 'DisableNonStdPersonMailbox'
        $context = New-TestContext -Payload @($row) -Services $services

        $result = Invoke-DisableGenericUser -Context $context

        $result.Status | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'DISABLE_GENERIC_USER_FAILED'
    }

    It 'Enable with grace period handler validates and succeeds in WhatIf mode' {
        $context = New-TestContext -Payload @(New-GraceRow)

        $result = Invoke-EnableAdAccountWithGracePeriod -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.Output[0].Simulated | Should -Be $true
    }

    It 'Modify mobile number handler validates and succeeds in WhatIf mode' {
        $context = New-TestContext -Payload @(New-MobileRow)

        $result = Invoke-ModifyMobilePhoneNumber -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.Output[0].Simulated | Should -Be $true
    }
}

Describe 'GenericUser migrated service functions in WhatIf mode' {
    It 'Enable-GenericUser does not require Active Directory in WhatIf mode' {
        $context = New-TestContext -Payload @() -WhatIfMode $true

        $result = Enable-GenericUser -Context $context -Data (New-EnableDisableRow)

        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'EnableNonStdPersonMailbox'
    }

    It 'Disable-GenericUser does not require Active Directory in WhatIf mode' {
        $context = New-TestContext -Payload @() -WhatIfMode $true
        $row = New-EnableDisableRow -ActionType 'DisableNonStdPersonMailbox'

        $result = Disable-GenericUser -Context $context -Data $row

        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'DisableNonStdPersonMailbox'
    }

    It 'Enable-GenericUserWithGracePeriod does not require Active Directory in WhatIf mode' {
        $context = New-TestContext -Payload @() -WhatIfMode $true

        $result = Enable-GenericUserWithGracePeriod -Context $context -Data (New-GraceRow)

        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'EnableAdAccountWithGracePeriod'
    }

    It 'Set-GenericUserMobilePhoneNumber does not require Active Directory in WhatIf mode' {
        $context = New-TestContext -Payload @() -WhatIfMode $true

        $result = Set-GenericUserMobilePhoneNumber -Context $context -Data (New-MobileRow)

        $result.Success | Should -Be $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'ModifyMobilePhoneNumber'
    }
}
