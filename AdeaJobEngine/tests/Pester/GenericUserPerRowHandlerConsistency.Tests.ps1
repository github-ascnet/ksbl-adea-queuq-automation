BeforeAll {
    $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path

    Import-Module -Name (Join-Path $root 'core\JobResult.psm1')    -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'core\Validation.psm1')   -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'core\Logging.psm1')      -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'usecases\GenericUser\RenameUserAccount.psm1')    -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'usecases\GenericUser\ChangeAccountSurname.psm1') -Force -DisableNameChecking
    Import-Module -Name (Join-Path $root 'usecases\GenericUser\ModifyMailboxFolderAce.psm1') -Force -DisableNameChecking

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

    function New-RenameAccountRow {
        param([string]$AdObjectName = 'gn-source', [string]$TargetAdObjectName = 'gn-target')
        [pscustomobject]@{
            ActionType              = 'RenameUserAccount'
            AdObjectName            = $AdObjectName
            TargetAdObjectName      = $TargetAdObjectName
            NewUserId               = 'newuserid'
            GivenName               = 'Max'
            SurName                 = 'Mustermann'
            NewPrimaryEMailAddress  = 'max.mustermann@ksbl.ch'
            CurrentUserName         = 'Requester'
            CurrentUserDomainName   = 'KSBL'
            CurrentUserEMailAddress = 'requester@ksbl.ch'
        }
    }

    function New-ChangeSurnameRow {
        param([string]$AdObjectName = 'gn-user')
        [pscustomobject]@{
            ActionType              = 'ChangeAccountSurname'
            AdObjectName            = $AdObjectName
            GivenName               = 'Max'
            SurName                 = 'Neuname'
            NewPrimaryEMailAddress  = 'max.neuname@ksbl.ch'
            CurrentUserName         = 'Requester'
            CurrentUserDomainName   = 'KSBL'
            CurrentUserEMailAddress = 'requester@ksbl.ch'
        }
    }

    function New-ModifyMailboxFolderAceRow {
        param([string]$AdObjectName = 'gn-mailbox', [string]$DelegatedAdObjectName = 'gn-delegate')
        [pscustomobject]@{
            ActionType              = 'ModifyMailboxFolderAce'
            AdObjectName            = $AdObjectName
            MailboxFolderName       = 'Inbox'
            DelegatedAdObjectName   = $DelegatedAdObjectName
            AclActionType           = 'Add'
            AclEntry                = 'FullAccess'
            CurrentUserName         = 'Requester'
            CurrentUserDomainName   = 'KSBL'
            CurrentUserEMailAddress = 'requester@ksbl.ch'
        }
    }

    function New-RenameServices {
        param([scriptblock]$RenameUser = { param($Ctx, $Data) })
        [pscustomobject]@{
            UserProvisioning = [pscustomobject]@{
                RenameUser = $RenameUser
            }
        }
    }

    function New-SurnameServices {
        param([scriptblock]$SetSurname = { param($Ctx, $Data) })
        [pscustomobject]@{
            UserProvisioning = [pscustomobject]@{
                SetSurname = $SetSurname
            }
        }
    }

    function New-MailboxAceServices {
        param([scriptblock]$SetMailboxFolderAce = { param($Ctx, $Data) })
        [pscustomobject]@{
            UserProvisioning = [pscustomobject]@{
                SetMailboxFolderAce = $SetMailboxFolderAce
            }
        }
    }

    # ---------------------------------------------------------------------------
    # GenericUser.RenameAccount
    # ---------------------------------------------------------------------------
}

Describe 'GenericUser.RenameAccount handler' {

    It 'Returns Succeeded with SuccessCount=1 when single row succeeds' {
        $ctx = [pscustomobject]@{
            Payload    = @(New-RenameAccountRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-RenameServices
        }

        $result = Invoke-RenameUserAccount -Context $ctx

        $result.Status              | Should -Be 'Succeeded'
        $result.Output.SuccessCount | Should -Be 1
    }

    It 'Returns Succeeded with SuccessCount=2 when two rows succeed' {
        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-RenameAccountRow -AdObjectName 'gn-a' -TargetAdObjectName 'gn-a2')
                (New-RenameAccountRow -AdObjectName 'gn-b' -TargetAdObjectName 'gn-b2')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-RenameServices
        }

        $result = Invoke-RenameUserAccount -Context $ctx

        $result.Status              | Should -Be 'Succeeded'
        $result.Output.SuccessCount | Should -Be 2
    }

    It 'Returns Failed with PARTIAL_FAILURE when one row throws and another succeeds' {
        $script:callCount = 0
        $service = {
            param($Ctx, $Data)
            $script:callCount++
            if ($script:callCount -eq 1) { throw 'Simulated rename error' }
        }

        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-RenameAccountRow -AdObjectName 'gn-fail' -TargetAdObjectName 'gn-fail2')
                (New-RenameAccountRow -AdObjectName 'gn-ok'   -TargetAdObjectName 'gn-ok2')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-RenameServices -RenameUser $service
        }

        $result = Invoke-RenameUserAccount -Context $ctx

        $result.Status                    | Should -Be 'Failed'
        $result.ErrorCode                 | Should -Be 'PARTIAL_FAILURE'
        $result.Output.SuccessCount       | Should -Be 1
        $result.Output.FailedCount        | Should -Be 1
        $result.Output.FailedRows.Count   | Should -Be 1
        $result.Output.FailedRows[0].ErrorCode | Should -Be 'ROW_PROCESSING_ERROR'
    }

    It 'Returns Failed with PARTIAL_FAILURE when all rows throw' {
        $service = { param($Ctx, $Data) throw 'Always fails' }

        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-RenameAccountRow -AdObjectName 'gn-a' -TargetAdObjectName 'gn-a2')
                (New-RenameAccountRow -AdObjectName 'gn-b' -TargetAdObjectName 'gn-b2')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-RenameServices -RenameUser $service
        }

        $result = Invoke-RenameUserAccount -Context $ctx

        $result.Status              | Should -Be 'Failed'
        $result.ErrorCode           | Should -Be 'PARTIAL_FAILURE'
        $result.Output.SuccessCount | Should -Be 0
        $result.Output.FailedCount  | Should -Be 2
        $result.Output.FailedRows.Count | Should -Be 2
    }

    It 'Continues processing remaining rows after a row exception' {
        $script:processed = [System.Collections.Generic.List[string]]::new()
        $service = {
            param($Ctx, $Data)
            $script:processed.Add($Data.AdObjectName)
            if ($Data.AdObjectName -eq 'gn-bad') { throw 'Bad row' }
        }

        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-RenameAccountRow -AdObjectName 'gn-bad'  -TargetAdObjectName 'gn-bad2')
                (New-RenameAccountRow -AdObjectName 'gn-good' -TargetAdObjectName 'gn-good2')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-RenameServices -RenameUser $service
        }

        Invoke-RenameUserAccount -Context $ctx | Out-Null

        $script:processed | Should -Contain 'gn-bad'
        $script:processed | Should -Contain 'gn-good'
    }

    It 'Returns Failed with USECASE_ERROR when required fields are missing' {
        $incompleteRow = [pscustomobject]@{
            ActionType   = 'RenameUserAccount'
            AdObjectName = 'gn-test'
            # TargetAdObjectName missing
        }

        $ctx = [pscustomobject]@{
            Payload    = @($incompleteRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-RenameServices
        }

        $result = Invoke-RenameUserAccount -Context $ctx

        $result.Status    | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'USECASE_ERROR'
    }
}

# ---------------------------------------------------------------------------
# GenericUser.ChangeSurname
# ---------------------------------------------------------------------------
Describe 'GenericUser.ChangeSurname handler' {

    It 'Returns Succeeded with SuccessCount=1 when single row succeeds' {
        $ctx = [pscustomobject]@{
            Payload    = @(New-ChangeSurnameRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-SurnameServices
        }

        $result = Invoke-ChangeAccountSurname -Context $ctx

        $result.Status              | Should -Be 'Succeeded'
        $result.Output.SuccessCount | Should -Be 1
    }

    It 'Returns Succeeded with SuccessCount=2 when two rows succeed' {
        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-ChangeSurnameRow -AdObjectName 'gn-a')
                (New-ChangeSurnameRow -AdObjectName 'gn-b')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-SurnameServices
        }

        $result = Invoke-ChangeAccountSurname -Context $ctx

        $result.Status              | Should -Be 'Succeeded'
        $result.Output.SuccessCount | Should -Be 2
    }

    It 'Returns Failed with PARTIAL_FAILURE when one row throws and another succeeds' {
        $script:callCount2 = 0
        $service = {
            param($Ctx, $Data)
            $script:callCount2++
            if ($script:callCount2 -eq 1) { throw 'Simulated surname error' }
        }

        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-ChangeSurnameRow -AdObjectName 'gn-fail')
                (New-ChangeSurnameRow -AdObjectName 'gn-ok')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-SurnameServices -SetSurname $service
        }

        $result = Invoke-ChangeAccountSurname -Context $ctx

        $result.Status                         | Should -Be 'Failed'
        $result.ErrorCode                      | Should -Be 'PARTIAL_FAILURE'
        $result.Output.SuccessCount            | Should -Be 1
        $result.Output.FailedCount             | Should -Be 1
        $result.Output.FailedRows.Count        | Should -Be 1
        $result.Output.FailedRows[0].ErrorCode | Should -Be 'ROW_PROCESSING_ERROR'
    }

    It 'Continues processing remaining rows after a row exception' {
        $script:processed2 = [System.Collections.Generic.List[string]]::new()
        $service = {
            param($Ctx, $Data)
            $script:processed2.Add($Data.AdObjectName)
            if ($Data.AdObjectName -eq 'gn-bad') { throw 'Bad row' }
        }

        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-ChangeSurnameRow -AdObjectName 'gn-bad')
                (New-ChangeSurnameRow -AdObjectName 'gn-good')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-SurnameServices -SetSurname $service
        }

        Invoke-ChangeAccountSurname -Context $ctx | Out-Null

        $script:processed2 | Should -Contain 'gn-bad'
        $script:processed2 | Should -Contain 'gn-good'
    }

    It 'Returns Failed with USECASE_ERROR when required fields are missing' {
        $incompleteRow = [pscustomobject]@{
            ActionType   = 'ChangeAccountSurname'
            AdObjectName = 'gn-test'
            # GivenName, SurName etc. missing
        }

        $ctx = [pscustomobject]@{
            Payload    = @($incompleteRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-SurnameServices
        }

        $result = Invoke-ChangeAccountSurname -Context $ctx

        $result.Status    | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'USECASE_ERROR'
    }
}

# ---------------------------------------------------------------------------
# GenericUser.ModifyMailboxFolderAce
# ---------------------------------------------------------------------------
Describe 'GenericUser.ModifyMailboxFolderAce handler' {

    It 'Returns Succeeded with SuccessCount=1 when single row succeeds' {
        $ctx = [pscustomobject]@{
            Payload    = @(New-ModifyMailboxFolderAceRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-MailboxAceServices
        }

        $result = Invoke-ModifyMailboxFolderAce -Context $ctx

        $result.Status              | Should -Be 'Succeeded'
        $result.Output.SuccessCount | Should -Be 1
    }

    It 'Returns Succeeded with SuccessCount=2 when two rows succeed' {
        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-ModifyMailboxFolderAceRow -AdObjectName 'gn-mb1' -DelegatedAdObjectName 'gn-del1')
                (New-ModifyMailboxFolderAceRow -AdObjectName 'gn-mb2' -DelegatedAdObjectName 'gn-del2')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-MailboxAceServices
        }

        $result = Invoke-ModifyMailboxFolderAce -Context $ctx

        $result.Status              | Should -Be 'Succeeded'
        $result.Output.SuccessCount | Should -Be 2
    }

    It 'Returns Failed with PARTIAL_FAILURE when one row throws and another succeeds' {
        $script:callCount3 = 0
        $service = {
            param($Ctx, $Data)
            $script:callCount3++
            if ($script:callCount3 -eq 1) { throw 'Simulated ACE error' }
        }

        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-ModifyMailboxFolderAceRow -AdObjectName 'gn-fail' -DelegatedAdObjectName 'gn-del-fail')
                (New-ModifyMailboxFolderAceRow -AdObjectName 'gn-ok'   -DelegatedAdObjectName 'gn-del-ok')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-MailboxAceServices -SetMailboxFolderAce $service
        }

        $result = Invoke-ModifyMailboxFolderAce -Context $ctx

        $result.Status                         | Should -Be 'Failed'
        $result.ErrorCode                      | Should -Be 'PARTIAL_FAILURE'
        $result.Output.SuccessCount            | Should -Be 1
        $result.Output.FailedCount             | Should -Be 1
        $result.Output.FailedRows.Count        | Should -Be 1
        $result.Output.FailedRows[0].ErrorCode | Should -Be 'ROW_PROCESSING_ERROR'
    }

    It 'Continues processing remaining rows after a row exception' {
        $script:processed3 = [System.Collections.Generic.List[string]]::new()
        $service = {
            param($Ctx, $Data)
            $script:processed3.Add($Data.AdObjectName)
            if ($Data.AdObjectName -eq 'gn-bad') { throw 'Bad row' }
        }

        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-ModifyMailboxFolderAceRow -AdObjectName 'gn-bad'  -DelegatedAdObjectName 'gn-del')
                (New-ModifyMailboxFolderAceRow -AdObjectName 'gn-good' -DelegatedAdObjectName 'gn-del')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-MailboxAceServices -SetMailboxFolderAce $service
        }

        Invoke-ModifyMailboxFolderAce -Context $ctx | Out-Null

        $script:processed3 | Should -Contain 'gn-bad'
        $script:processed3 | Should -Contain 'gn-good'
    }

    It 'Returns Failed with USECASE_ERROR when required fields are missing' {
        $incompleteRow = [pscustomobject]@{
            ActionType   = 'ModifyMailboxFolderAce'
            AdObjectName = 'gn-test'
            # MailboxFolderName, DelegatedAdObjectName etc. missing
        }

        $ctx = [pscustomobject]@{
            Payload    = @($incompleteRow)
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-MailboxAceServices
        }

        $result = Invoke-ModifyMailboxFolderAce -Context $ctx

        $result.Status    | Should -Be 'Failed'
        $result.ErrorCode | Should -Be 'USECASE_ERROR'
    }
}


# ---------------------------------------------------------------------------
# Service result objects with Success = false
# ---------------------------------------------------------------------------
Describe 'GenericUser per-row handler consistency - failed service result objects' {

    It 'RenameUserAccount treats service Success=false as row failure and continues' {
        $service = {
            param($Ctx, $Data)
            if ($Data.AdObjectName -eq 'gn-bad') {
                return [pscustomobject]@{
                    Success   = $false
                    Message   = 'Business failure from service.'
                    ErrorCode = 'BUSINESS_FAILURE'
                }
            }

            return [pscustomobject]@{
                Success = $true
                Message = 'OK'
            }
        }

        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-RenameAccountRow -AdObjectName 'gn-bad' -TargetAdObjectName 'gn-bad2')
                (New-RenameAccountRow -AdObjectName 'gn-ok'  -TargetAdObjectName 'gn-ok2')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-RenameServices -RenameUser $service
        }

        $result = Invoke-RenameUserAccount -Context $ctx

        $result.Status                         | Should -Be 'Failed'
        $result.ErrorCode                      | Should -Be 'PARTIAL_FAILURE'
        $result.Output.SuccessCount            | Should -Be 1
        $result.Output.FailedCount             | Should -Be 1
        $result.Output.FailedRows[0].ErrorCode | Should -Be 'BUSINESS_FAILURE'
    }

    It 'ChangeAccountSurname treats service Success=false as row failure and continues' {
        $service = {
            param($Ctx, $Data)
            if ($Data.AdObjectName -eq 'gn-bad') {
                return [pscustomobject]@{
                    Success   = $false
                    Message   = 'Business failure from service.'
                    ErrorCode = 'BUSINESS_FAILURE'
                }
            }

            return [pscustomobject]@{
                Success = $true
                Message = 'OK'
            }
        }

        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-ChangeSurnameRow -AdObjectName 'gn-bad')
                (New-ChangeSurnameRow -AdObjectName 'gn-ok')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-SurnameServices -SetSurname $service
        }

        $result = Invoke-ChangeAccountSurname -Context $ctx

        $result.Status                         | Should -Be 'Failed'
        $result.ErrorCode                      | Should -Be 'PARTIAL_FAILURE'
        $result.Output.SuccessCount            | Should -Be 1
        $result.Output.FailedCount             | Should -Be 1
        $result.Output.FailedRows[0].ErrorCode | Should -Be 'BUSINESS_FAILURE'
    }

    It 'ModifyMailboxFolderAce treats service Success=false as row failure and continues' {
        $service = {
            param($Ctx, $Data)
            if ($Data.AdObjectName -eq 'gn-bad') {
                return [pscustomobject]@{
                    Success   = $false
                    Message   = 'Business failure from service.'
                    ErrorCode = 'BUSINESS_FAILURE'
                }
            }

            return [pscustomobject]@{
                Success = $true
                Message = 'OK'
            }
        }

        $ctx = [pscustomobject]@{
            Payload    = @(
                (New-ModifyMailboxFolderAceRow -AdObjectName 'gn-bad'  -DelegatedAdObjectName 'gn-del1')
                (New-ModifyMailboxFolderAceRow -AdObjectName 'gn-good' -DelegatedAdObjectName 'gn-del2')
            )
            Logger     = New-TestLogger
            WhatIfMode = $true
            Services   = New-MailboxAceServices -SetMailboxFolderAce $service
        }

        $result = Invoke-ModifyMailboxFolderAce -Context $ctx

        $result.Status                         | Should -Be 'Failed'
        $result.ErrorCode                      | Should -Be 'PARTIAL_FAILURE'
        $result.Output.SuccessCount            | Should -Be 1
        $result.Output.FailedCount             | Should -Be 1
        $result.Output.FailedRows[0].ErrorCode | Should -Be 'BUSINESS_FAILURE'
    }
}
