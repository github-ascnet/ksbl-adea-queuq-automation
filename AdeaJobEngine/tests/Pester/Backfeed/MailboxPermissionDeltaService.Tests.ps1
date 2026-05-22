Describe 'MailboxPermission DeltaService and Delta SQL' {
    BeforeAll {
        $root = if ($PSScriptRoot) {
            Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        }
        else {
            (Get-Location).Path
        }

        Set-Variable -Scope Script -Name root -Value $root
        Set-Variable -Scope Script -Name workspaceRoot -Value (Split-Path -Parent $root)

        Set-Variable -Scope Script -Name deltaServicePath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionDeltaService.psm1')
        Set-Variable -Scope Script -Name servicePath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionBackfeedService.psm1')
        Set-Variable -Scope Script -Name deltaSqlPath -Value (Join-Path -Path $root -ChildPath 'sql\backfeed\mailbox-permission\get-mailbox-permission-backfeed-delta-counts.sql')
        Set-Variable -Scope Script -Name stateCreateSqlPath -Value (Join-Path -Path $root -ChildPath 'sql\backfeed\mailbox-permission\create-mailbox-permission-backfeed-state.sql')
        Set-Variable -Scope Script -Name stateInitializeSqlPath -Value (Join-Path -Path $root -ChildPath 'sql\backfeed\mailbox-permission\initialize-mailbox-permission-backfeed-state-insert-only.sql')

        Set-Variable -Scope Script -Name backfeedSqlRunnerPath -Value (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedSqlScriptRunner.psm1')
        Set-Variable -Scope Script -Name sqlGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\SqlGateway.psm1')
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

    It 'get-mailbox-permission-backfeed-delta-counts.sql exists' {
        Test-Path -Path $script:deltaSqlPath | Should -Be $true
    }

    It 'delta sql contains BackfeedRunId parameter and SELECT' {
        $sql = Get-Content -Path $script:deltaSqlPath -Raw
        $sql -match '@BackfeedRunId' | Should -Be $true
        $sql -match '\bSELECT\b' | Should -Be $true
    }

    It 'delta sql contains no forbidden write DDL DML operations' {
        $sql = Get-Content -Path $script:deltaSqlPath -Raw
        $sql -match '\bINSERT\b' | Should -Be $false
        $sql -match '\bUPDATE\b' | Should -Be $false
        $sql -match '\bDELETE\b' | Should -Be $false
        $sql -match '\bMERGE\b' | Should -Be $false
        $sql -match '\bTRUNCATE\b' | Should -Be $false
        $sql -match '\bALTER\b' | Should -Be $false
    }

    It 'delta sql does not write to MailboxPermissions or hist_MailboxPermissions' {
        $sql = Get-Content -Path $script:deltaSqlPath -Raw
        $sql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?MailboxPermissions\]?\b' | Should -Be $false
        $sql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?hist_MailboxPermissions\]?\b' | Should -Be $false
    }

    It 'MailboxPermissionDeltaService file and function exist' {
        Test-Path -Path $script:deltaServicePath | Should -Be $true
        (Get-Content -Path $script:deltaServicePath -Raw) -match 'function\s+Get-MailboxPermissionBackfeedDelta' | Should -Be $true
    }

    It 'invalid BackfeedRunId returns INVALID_BACKFEED_RUN_ID' {
        Import-Module -Name $script:deltaServicePath -Force -DisableNameChecking -Global
        $result = MailboxPermissionDeltaService\Get-MailboxPermissionBackfeedDelta -BackfeedContext ([pscustomobject]@{ BackfeedRunId = 'bad-guid'; Config = [pscustomobject]@{}; WhatIfMode = $true }) -BackfeedRunId 'still-bad'
        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Be 'INVALID_BACKFEED_RUN_ID'
    }

    It 'maps SQL count result to delta counters' {
        Import-Module -Name $script:deltaServicePath -Force -DisableNameChecking -Global
        Mock -ModuleName MailboxPermissionDeltaService -CommandName Invoke-MailboxPermissionBackfeedDeltaSql {
            @([pscustomobject]@{ InsertedCount = 7; UpdatedCount = 8; DeletedCount = 9; UnchangedCount = 10 })
        }

        $result = MailboxPermissionDeltaService\Get-MailboxPermissionBackfeedDelta -BackfeedContext ([pscustomobject]@{ BackfeedRunId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'; Config = [pscustomobject]@{}; WhatIfMode = $true })

        $result.Success | Should -Be $true
        $result.InsertedCount | Should -Be 7
        $result.UpdatedCount | Should -Be 8
        $result.DeletedCount | Should -Be 9
        $result.UnchangedCount | Should -Be 10
    }

    It 'SQL error returns MAILBOX_PERMISSION_DELTA_FAILED' {
        Import-Module -Name $script:deltaServicePath -Force -DisableNameChecking -Global
        Mock -ModuleName MailboxPermissionDeltaService -CommandName Invoke-MailboxPermissionBackfeedDeltaSql {
            throw 'delta sql failure'
        }

        $result = MailboxPermissionDeltaService\Get-MailboxPermissionBackfeedDelta -BackfeedContext ([pscustomobject]@{ BackfeedRunId = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; Config = [pscustomobject]@{}; WhatIfMode = $true })
        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Be 'MAILBOX_PERMISSION_DELTA_FAILED'
    }

    It 'delta service contains no forbidden direct SQL logic or merge writes' {
        $content = Get-Content -Path $script:deltaServicePath -Raw
        $content -match '\bInvoke-Sqlcmd\b' | Should -Be $false
        $content -match 'System\.Data\.(SqlClient\.)?SqlConnection|Microsoft\.Data\.SqlClient' | Should -Be $false
        $content -match '\bMERGE\b' | Should -Be $false
        $content -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?MailboxPermissions\]?\b' | Should -Be $false
        $content -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?hist_MailboxPermissions\]?\b' | Should -Be $false
    }

    It 'service contains delta call after stage' {
        $content = Get-Content -Path $script:servicePath -Raw
        $content -match 'Get-MailboxPermissionBackfeedDelta' | Should -Be $true
    }

    It 'service contains state initialization call after delta' {
        $content = Get-Content -Path $script:servicePath -Raw
        $content -match 'Initialize-MailboxPermissionBackfeedStateInsertOnly' | Should -Be $true
    }

    It 'service maps delta counts into BackfeedResult' {
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
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; InsertedCount = 11; UpdatedCount = 12; DeletedCount = 13; UnchangedCount = 14; FailedCount = 0; Message = 'Delta counts resolved.'; ErrorCode = $null; Errors = @() }
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Initialize-MailboxPermissionBackfeedStateInsertOnly {
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; InsertedCount = 5; UpdatedCount = 0; DeletedCount = 0; ReactivatedCount = 0; UnchangedCount = 14; FailedCount = 0; Message = 'State initialized.'; ErrorCode = $null; Errors = @() }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-delta-1' -BackfeedType 'MailboxPermission' -Mode 'Delta'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.InsertedCount | Should -Be 5
        $result.UpdatedCount | Should -Be 0
        $result.DeletedCount | Should -Be 0
        $result.UnchangedCount | Should -Be 14
        $result.BackfeedRunId | Should -Be 'cccccccc-cccc-cccc-cccc-cccccccccccc'
    }

    It 'delta failure sets result status to Failed and keeps BackfeedRunId' {
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
            [pscustomobject]@{ Success = $false; BackfeedRunId = 'dddddddd-dddd-dddd-dddd-dddddddddddd'; InsertedCount = 1; UpdatedCount = 0; DeletedCount = 0; UnchangedCount = 0; FailedCount = 1; Message = 'Delta failed'; ErrorCode = 'MAILBOX_PERMISSION_DELTA_FAILED'; Errors = @([pscustomobject]@{ Message = 'Delta failed'; ErrorCode = 'MAILBOX_PERMISSION_DELTA_FAILED'; BackfeedRunId = 'dddddddd-dddd-dddd-dddd-dddddddddddd' }) }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-delta-2' -BackfeedType 'MailboxPermission' -Mode 'Delta'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Failed'
        $result.BackfeedRunId | Should -Be 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        $result.Errors.Count | Should -Be 1
    }

    It 'BackfeedSqlScriptRunner and SqlGateway support query execution for delta' {
        (Get-Content -Path $script:backfeedSqlRunnerPath -Raw) -match 'Invoke-BackfeedSqlQueryScript' | Should -Be $true
        (Get-Content -Path $script:sqlGatewayPath -Raw) -match 'Invoke-SqlQueryParameterizedSafe' | Should -Be $true
    }

    It 'state SQL files do not write to MailboxPermissions or hist_MailboxPermissions' {
        $stateSql = (Get-Content -Path $script:stateCreateSqlPath -Raw) + "`n" + (Get-Content -Path $script:stateInitializeSqlPath -Raw)
        $stateSql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?MailboxPermissions\]?\b' | Should -Be $false
        $stateSql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?hist_MailboxPermissions\]?\b' | Should -Be $false
    }

    It 'JobEngine and JobFileQueue remain free of Backfeed implementation details' {
        (Get-Content -Path $script:jobEnginePath -Raw) -match 'MailboxPermissionDeltaService|Get-MailboxPermissionBackfeedDelta' | Should -Be $false
        (Get-Content -Path $script:jobFileQueuePath -Raw) -match 'MailboxPermissionDeltaService|Get-MailboxPermissionBackfeedDelta' | Should -Be $false
    }

    It 'usecases.json contains no Backfeed entries' {
        (Get-Content -Path $script:usecasesPath -Raw) -match 'Backfeed' | Should -Be $false
    }

    It 'Exchange and AD gateways remain unchanged by delta phase' {
        (Get-Content -Path $script:exchangeOnPremGatewayPath -Raw) -match 'MailboxPermissionDeltaService|get-mailbox-permission-backfeed-delta-counts.sql' | Should -Be $false
        (Get-Content -Path $script:exchangeOnlineGatewayPath -Raw) -match 'MailboxPermissionDeltaService|get-mailbox-permission-backfeed-delta-counts.sql' | Should -Be $false
        (Get-Content -Path $script:activeDirectoryGatewayPath -Raw) -match 'MailboxPermissionDeltaService|get-mailbox-permission-backfeed-delta-counts.sql' | Should -Be $false
    }

    It 'legacy mailbox script remains unchanged regarding delta integration' {
        (Get-Content -Path $script:legacyScriptPath -Raw) -match 'MailboxPermissionDeltaService|get-mailbox-permission-backfeed-delta-counts.sql' | Should -Be $false
    }

    It 'no backfeed mailbox-permission SQL file writes to hist_MailboxPermissions' {
        $allSql = @(Get-ChildItem -Path $script:sqlFolderPath -Filter '*.sql' | ForEach-Object { Get-Content -Path $_.FullName -Raw }) -join "`n"
        $allSql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?hist_MailboxPermissions\]?\b' | Should -Be $false
    }
}
