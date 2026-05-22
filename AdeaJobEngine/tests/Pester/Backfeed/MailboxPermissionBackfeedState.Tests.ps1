Describe 'MailboxPermission Backfeed State insert-only initialization' {
    BeforeAll {
        $root = if ($PSScriptRoot) {
            Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        }
        else {
            (Get-Location).Path
        }

        Set-Variable -Scope Script -Name root -Value $root
        Set-Variable -Scope Script -Name workspaceRoot -Value (Split-Path -Parent $root)

        Set-Variable -Scope Script -Name stateCreateSqlPath -Value (Join-Path -Path $root -ChildPath 'sql\backfeed\mailbox-permission\create-mailbox-permission-backfeed-state.sql')
        Set-Variable -Scope Script -Name stateInitializeSqlPath -Value (Join-Path -Path $root -ChildPath 'sql\backfeed\mailbox-permission\initialize-mailbox-permission-backfeed-state-insert-only.sql')
        Set-Variable -Scope Script -Name stateCountsSqlPath -Value (Join-Path -Path $root -ChildPath 'sql\backfeed\mailbox-permission\get-mailbox-permission-backfeed-state-counts.sql')
        Set-Variable -Scope Script -Name deltaServicePath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionDeltaService.psm1')
        Set-Variable -Scope Script -Name servicePath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionBackfeedService.psm1')
        Set-Variable -Scope Script -Name contextPath -Value (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedContext.psm1')
        Set-Variable -Scope Script -Name resultPath -Value (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedResult.psm1')
        Set-Variable -Scope Script -Name jobEnginePath -Value (Join-Path -Path $root -ChildPath 'core\JobEngine.psm1')
        Set-Variable -Scope Script -Name jobFileQueuePath -Value (Join-Path -Path $root -ChildPath 'core\JobFileQueue.psm1')
        Set-Variable -Scope Script -Name usecasesPath -Value (Join-Path -Path $root -ChildPath 'config\usecases.json')
        Set-Variable -Scope Script -Name exchangeOnPremGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnPremGateway.psm1')
        Set-Variable -Scope Script -Name exchangeOnlineGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1')
        Set-Variable -Scope Script -Name activeDirectoryGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ActiveDirectoryGateway.psm1')
        Set-Variable -Scope Script -Name legacyScriptPath -Value (Join-Path -Path $script:workspaceRoot -ChildPath 'current-scripts\Import-MailboxPermissions-Into-Staging-Update-Model.ps1')
        Set-Variable -Scope Script -Name sqlFolderPath -Value (Join-Path -Path $root -ChildPath 'sql\backfeed\mailbox-permission')

        Remove-Module -Name 'BackfeedContext' -ErrorAction SilentlyContinue
        Remove-Module -Name 'BackfeedResult' -ErrorAction SilentlyContinue
        Remove-Module -Name 'MailboxPermissionDeltaService' -ErrorAction SilentlyContinue
        Remove-Module -Name 'MailboxPermissionBackfeedService' -ErrorAction SilentlyContinue

        Import-Module -Name $script:contextPath -Force -DisableNameChecking -Global
        Import-Module -Name $script:resultPath -Force -DisableNameChecking -Global
        Import-Module -Name $script:deltaServicePath -Force -DisableNameChecking -Global
        Import-Module -Name $script:servicePath -Force -DisableNameChecking -Global
    }

    It 'create-mailbox-permission-backfeed-state.sql exists' {
        Test-Path -Path $script:stateCreateSqlPath | Should -Be $true
    }

    It 'state DDL defines MailboxPermissionBackfeedState and key fields' {
        $sql = Get-Content -Path $script:stateCreateSqlPath -Raw
        $sql -match 'MailboxPermissionBackfeedState' | Should -Be $true
        $sql -match '\[SourceSystem\]' | Should -Be $true
        $sql -match '\[PermissionType\]' | Should -Be $true
        $sql -match '\[MailboxKey\]' | Should -Be $true
        $sql -match '\[TrusteeKey\]' | Should -Be $true
        $sql -match '\[RowHash\]' | Should -Be $true
        $sql -match '\[FirstSeenBackfeedRunId\]' | Should -Be $true
        $sql -match '\[LastSeenBackfeedRunId\]' | Should -Be $true
        $sql -match '\[IsDeleted\]' | Should -Be $true
        $sql -match '\[DeletedAt\]' | Should -Be $true
        $sql -match '\[DeletedBackfeedRunId\]' | Should -Be $true
    }

    It 'state DDL contains unique business key without IsDeleted' {
        $sql = Get-Content -Path $script:stateCreateSqlPath -Raw
        $sql -match 'CREATE\s+UNIQUE\s+NONCLUSTERED\s+INDEX\s+\[UX_MailboxPermissionBackfeedState_BusinessKey\]' | Should -Be $true
        $sql -match '\[SourceSystem\][\s\S]*\[PermissionType\][\s\S]*\[MailboxKey\][\s\S]*\[TrusteeKey\]' | Should -Be $true
        $sql -match 'UX_MailboxPermissionBackfeedState_BusinessKey[\s\S]*\[IsDeleted\]' | Should -Be $false
    }

    It 'state DDL does not write to MailboxPermissions or hist_MailboxPermissions' {
        $sql = Get-Content -Path $script:stateCreateSqlPath -Raw
        $sql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?MailboxPermissions\]?\b' | Should -Be $false
        $sql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?hist_MailboxPermissions\]?\b' | Should -Be $false
    }

    It 'initialize-mailbox-permission-backfeed-state-insert-only.sql exists and is insert-only' {
        $sql = Get-Content -Path $script:stateInitializeSqlPath -Raw
        Test-Path -Path $script:stateInitializeSqlPath | Should -Be $true
        $sql -match 'INSERT\s+INTO\s+\[dbo\]\.\[MailboxPermissionBackfeedState\]' | Should -Be $true
        $sql -match 'WHERE\s+NOT\s+EXISTS' | Should -Be $true
        $sql -match '@BackfeedRunId' | Should -Be $true
        $sql -match 'InsertedCount' | Should -Be $true
        $sql -match '\bUPDATE\b' | Should -Be $false
        $sql -match '\bDELETE\b' | Should -Be $false
        $sql -match '\bMERGE\b' | Should -Be $false
        $sql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?MailboxPermissions\]?\b' | Should -Be $false
        $sql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?hist_MailboxPermissions\]?\b' | Should -Be $false
    }

    It 'get-mailbox-permission-backfeed-state-counts.sql exists and contains only select logic' {
        $sql = Get-Content -Path $script:stateCountsSqlPath -Raw
        Test-Path -Path $script:stateCountsSqlPath | Should -Be $true
        $sql -match '\bSELECT\b' | Should -Be $true
        $sql -match 'CurrentRunSeenCount' | Should -Be $true
        $sql -match 'TotalActiveCount' | Should -Be $true
        $sql -match 'TotalDeletedCount' | Should -Be $true
        $sql -match 'CurrentRunInsertedOrSeenCount' | Should -Be $true
        $sql -match '\bINSERT\b' | Should -Be $false
        $sql -match '\bUPDATE\b' | Should -Be $false
        $sql -match '\bDELETE\b' | Should -Be $false
        $sql -match '\bMERGE\b' | Should -Be $false
    }

    It 'Initialize-MailboxPermissionBackfeedStateInsertOnly exists' {
        (Get-Content -Path $script:deltaServicePath -Raw) -match 'function\s+Initialize-MailboxPermissionBackfeedStateInsertOnly' | Should -Be $true
    }

    It 'invalid BackfeedRunId returns INVALID_BACKFEED_RUN_ID for state initialization' {
        Import-Module -Name $script:deltaServicePath -Force -DisableNameChecking -Global
        $result = MailboxPermissionDeltaService\Initialize-MailboxPermissionBackfeedStateInsertOnly -BackfeedContext ([pscustomobject]@{ BackfeedRunId = 'bad-guid'; Config = [pscustomobject]@{}; WhatIfMode = $true }) -BackfeedRunId 'still-bad'
        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Be 'INVALID_BACKFEED_RUN_ID'
    }

    It 'successful state initialization maps SQL counts' {
        Import-Module -Name $script:deltaServicePath -Force -DisableNameChecking -Global
        Mock -ModuleName MailboxPermissionDeltaService -CommandName Invoke-MailboxPermissionBackfeedStateInitializationSql {
            @([pscustomobject]@{ InsertedCount = 4; UpdatedCount = 0; DeletedCount = 0; ReactivatedCount = 0; UnchangedCount = 6 })
        }

        $result = MailboxPermissionDeltaService\Initialize-MailboxPermissionBackfeedStateInsertOnly -BackfeedContext ([pscustomobject]@{ BackfeedRunId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; Config = [pscustomobject]@{}; WhatIfMode = $true })

        $result.Success | Should -Be $true
        $result.InsertedCount | Should -Be 4
        $result.UpdatedCount | Should -Be 0
        $result.DeletedCount | Should -Be 0
        $result.ReactivatedCount | Should -Be 0
        $result.UnchangedCount | Should -Be 6
    }

    It 'state initialization SQL error returns MAILBOX_PERMISSION_STATE_INITIALIZE_FAILED' {
        Import-Module -Name $script:deltaServicePath -Force -DisableNameChecking -Global
        Mock -ModuleName MailboxPermissionDeltaService -CommandName Invoke-MailboxPermissionBackfeedStateInitializationSql {
            throw 'state init sql failure'
        }

        $result = MailboxPermissionDeltaService\Initialize-MailboxPermissionBackfeedStateInsertOnly -BackfeedContext ([pscustomobject]@{ BackfeedRunId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; Config = [pscustomobject]@{}; WhatIfMode = $true })
        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Be 'MAILBOX_PERMISSION_STATE_INITIALIZE_FAILED'
    }

    It 'state initialization function contains no Invoke-Sqlcmd SqlConnection Update Delete or Merge' {
        $content = Get-Content -Path $script:deltaServicePath -Raw
        $content -match '\bInvoke-Sqlcmd\b' | Should -Be $false
        $content -match 'System\.Data\.(SqlClient\.)?SqlConnection|Microsoft\.Data\.SqlClient' | Should -Be $false
        $content -match 'function\s+Initialize-MailboxPermissionBackfeedStateInsertOnly[\s\S]*\bUPDATE\b' | Should -Be $false
        $content -match 'function\s+Initialize-MailboxPermissionBackfeedStateInsertOnly[\s\S]*\bDELETE\b' | Should -Be $false
        $content -match 'function\s+Initialize-MailboxPermissionBackfeedStateInsertOnly[\s\S]*\bMERGE\b' | Should -Be $false
    }

    It 'MailboxPermissionBackfeedService calls state initialization after delta' {
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Read-MailboxPermissionBackfeedSources {
            @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName ConvertTo-MailboxPermissionBackfeedRows {
            @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem'; RowHash = 'hash' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; StagedCount = 1; FailedCount = 0; Message = 'Rows staged.'; ErrorCode = $null; Errors = @() }
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Get-MailboxPermissionBackfeedDelta {
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; InsertedCount = 1; UpdatedCount = 0; DeletedCount = 0; UnchangedCount = 2; FailedCount = 0; Message = 'Delta counts resolved.'; ErrorCode = $null; Errors = @() }
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Initialize-MailboxPermissionBackfeedStateInsertOnly {
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; InsertedCount = 9; UpdatedCount = 0; DeletedCount = 0; ReactivatedCount = 0; UnchangedCount = 2; FailedCount = 0; Message = 'State initialized.'; ErrorCode = $null; Errors = @() }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-state-1' -BackfeedType 'MailboxPermission' -Mode 'Delta'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        Should -Invoke -ModuleName MailboxPermissionBackfeedService -CommandName Initialize-MailboxPermissionBackfeedStateInsertOnly -Times 1
        $result.Status | Should -Be 'Succeeded'
        $result.InsertedCount | Should -Be 9
        $result.UpdatedCount | Should -Be 0
        $result.DeletedCount | Should -Be 0
        $result.BackfeedRunId | Should -Be 'cccccccc-cccc-cccc-cccc-cccccccccccc'
    }

    It 'state initialization failure returns Failed result and keeps BackfeedRunId' {
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Read-MailboxPermissionBackfeedSources {
            @([pscustomobject]@{ PermissionType = 'SendAs'; SourceSystem = 'ExchangeOnline' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName ConvertTo-MailboxPermissionBackfeedRows {
            @([pscustomobject]@{ PermissionType = 'SendAs'; SourceSystem = 'ExchangeOnline'; RowHash = 'hash' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'dddddddd-dddd-dddd-dddd-dddddddddddd'; StagedCount = 1; FailedCount = 0; Message = 'Rows staged.'; ErrorCode = $null; Errors = @() }
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Get-MailboxPermissionBackfeedDelta {
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'dddddddd-dddd-dddd-dddd-dddddddddddd'; InsertedCount = 1; UpdatedCount = 0; DeletedCount = 0; UnchangedCount = 0; FailedCount = 0; Message = 'Delta counts resolved.'; ErrorCode = $null; Errors = @() }
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Initialize-MailboxPermissionBackfeedStateInsertOnly {
            [pscustomobject]@{ Success = $false; BackfeedRunId = 'dddddddd-dddd-dddd-dddd-dddddddddddd'; InsertedCount = 0; UpdatedCount = 0; DeletedCount = 0; ReactivatedCount = 0; UnchangedCount = 0; FailedCount = 1; Message = 'State init failed'; ErrorCode = 'MAILBOX_PERMISSION_STATE_INITIALIZE_FAILED'; Errors = @([pscustomobject]@{ Message = 'State init failed'; ErrorCode = 'MAILBOX_PERMISSION_STATE_INITIALIZE_FAILED'; BackfeedRunId = 'dddddddd-dddd-dddd-dddd-dddddddddddd' }) }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-state-2' -BackfeedType 'MailboxPermission' -Mode 'Delta'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Failed'
        $result.BackfeedRunId | Should -Be 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        $result.Errors.Count | Should -Be 1
    }

    It 'JobEngine JobFileQueue and usecases remain unchanged' {
        (Get-Content -Path $script:jobEnginePath -Raw) -match 'MailboxPermissionBackfeedState|Initialize-MailboxPermissionBackfeedStateInsertOnly' | Should -Be $false
        (Get-Content -Path $script:jobFileQueuePath -Raw) -match 'MailboxPermissionBackfeedState|Initialize-MailboxPermissionBackfeedStateInsertOnly' | Should -Be $false
        (Get-Content -Path $script:usecasesPath -Raw) -match 'Backfeed' | Should -Be $false
    }

    It 'Exchange AD gateways and legacy scripts remain unchanged' {
        (Get-Content -Path $script:exchangeOnPremGatewayPath -Raw) -match 'MailboxPermissionBackfeedState|initialize-mailbox-permission-backfeed-state-insert-only.sql' | Should -Be $false
        (Get-Content -Path $script:exchangeOnlineGatewayPath -Raw) -match 'MailboxPermissionBackfeedState|initialize-mailbox-permission-backfeed-state-insert-only.sql' | Should -Be $false
        (Get-Content -Path $script:activeDirectoryGatewayPath -Raw) -match 'MailboxPermissionBackfeedState|initialize-mailbox-permission-backfeed-state-insert-only.sql' | Should -Be $false
        (Get-Content -Path $script:legacyScriptPath -Raw) -match 'MailboxPermissionBackfeedState|initialize-mailbox-permission-backfeed-state-insert-only.sql' | Should -Be $false
    }

    It 'no mailbox permission backfeed SQL file writes to MailboxPermissions or hist_MailboxPermissions and no history projection is implemented' {
        $allSql = @(Get-ChildItem -Path $script:sqlFolderPath -Filter '*.sql' | ForEach-Object { Get-Content -Path $_.FullName -Raw }) -join "`n"
        $allSql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?MailboxPermissions\]?\b' | Should -Be $false
        $allSql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?hist_MailboxPermissions\]?\b' | Should -Be $false
        $allSql -match '\bProjection\b' | Should -Be $false
        $allSql -match '\bhistory\b' | Should -Be $false
    }
}