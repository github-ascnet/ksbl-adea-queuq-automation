Describe 'MailboxPermission StagingWriter Backfeed delta-ready staging' {
    BeforeAll {
        $root = if ($PSScriptRoot) {
            Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        }
        else {
            (Get-Location).Path
        }

        Set-Variable -Scope Script -Name root -Value $root
        Set-Variable -Scope Script -Name workspaceRoot -Value (Split-Path -Parent $root)

        Set-Variable -Scope Script -Name sqlFolderPath -Value (Join-Path -Path $root -ChildPath 'sql\backfeed\mailbox-permission')
        Set-Variable -Scope Script -Name createBackfeedStagePath -Value (Join-Path -Path $script:sqlFolderPath -ChildPath 'create-stg-mailbox-permissions-backfeed.sql')
        Set-Variable -Scope Script -Name insertBackfeedStagePath -Value (Join-Path -Path $script:sqlFolderPath -ChildPath 'insert-stg-mailbox-permission-backfeed-row.sql')
        Set-Variable -Scope Script -Name legacyTruncatePath -Value (Join-Path -Path $script:sqlFolderPath -ChildPath 'truncate-stg-mailbox-permissions.sql')
        Set-Variable -Scope Script -Name legacyInsertPath -Value (Join-Path -Path $script:sqlFolderPath -ChildPath 'insert-stg-mailbox-permission-row.sql')

        Set-Variable -Scope Script -Name writerPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionStagingWriter.psm1')
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

        Remove-Module -Name 'BackfeedContext' -ErrorAction SilentlyContinue
        Remove-Module -Name 'BackfeedResult' -ErrorAction SilentlyContinue

        Import-Module -Name $script:contextPath -Force -DisableNameChecking -Global
        Import-Module -Name $script:resultPath -Force -DisableNameChecking -Global

        $writerScriptText = Get-Content -Path $script:writerPath -Raw
        $writerModuleRoot = Split-Path -Parent $script:writerPath
        $writerScriptText = $writerScriptText -replace [regex]::Escape('$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path'), ('$moduleRoot = ''' + $writerModuleRoot + '''')
        $writerScriptText = [regex]::Replace($writerScriptText, '(?m)^Import-Module\s+-Name\s+.*BackfeedSqlScriptRunner\.psm1.*$', '')
        $writerScriptText = [regex]::Replace($writerScriptText, '(?ms)^Export-ModuleMember\s+-Function\s+@\(.*?\)\s*$', '')
        . ([scriptblock]::Create($writerScriptText))

        $deltaServiceScriptText = Get-Content -Path $script:deltaServicePath -Raw
        $deltaServiceModuleRoot = Split-Path -Parent $script:deltaServicePath
        $deltaServiceScriptText = $deltaServiceScriptText -replace [regex]::Escape('$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path'), ('$moduleRoot = ''' + $deltaServiceModuleRoot + '''')
        $deltaServiceScriptText = [regex]::Replace($deltaServiceScriptText, '(?m)^Import-Module\s+-Name\s+.*BackfeedSqlScriptRunner\.psm1.*$', '')
        $deltaServiceScriptText = [regex]::Replace($deltaServiceScriptText, '(?ms)^Export-ModuleMember\s+-Function\s+@\(.*?\)\s*$', '')
        . ([scriptblock]::Create($deltaServiceScriptText))

        $serviceScriptText = Get-Content -Path $script:servicePath -Raw
        $serviceModuleRoot = Split-Path -Parent $script:servicePath
        $serviceScriptText = $serviceScriptText -replace [regex]::Escape('$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path'), ('$moduleRoot = ''' + $serviceModuleRoot + '''')
        $serviceScriptText = [regex]::Replace($serviceScriptText, '(?m)^Import-Module\s+-Name\s+.*MailboxPermissionSourceReader\.psm1.*$', '')
        $serviceScriptText = [regex]::Replace($serviceScriptText, '(?m)^Import-Module\s+-Name\s+.*MailboxPermissionMapper\.psm1.*$', '')
        $serviceScriptText = [regex]::Replace($serviceScriptText, '(?m)^Import-Module\s+-Name\s+.*MailboxPermissionStagingWriter\.psm1.*$', '')
        $serviceScriptText = [regex]::Replace($serviceScriptText, '(?m)^Import-Module\s+-Name\s+.*MailboxPermissionDeltaService\.psm1.*$', '')
        $serviceScriptText = [regex]::Replace($serviceScriptText, '(?ms)^Export-ModuleMember\s+-Function\s+@\(.*?\)\s*$', '')
        . ([scriptblock]::Create($serviceScriptText))
    }

    It 'create-stg-mailbox-permissions-backfeed.sql exists' {
        Test-Path -Path $script:createBackfeedStagePath | Should -Be $true
    }

    It 'insert-stg-mailbox-permission-backfeed-row.sql exists' {
        Test-Path -Path $script:insertBackfeedStagePath | Should -Be $true
    }

    It 'legacy stage sql files remain present' {
        Test-Path -Path $script:legacyTruncatePath | Should -Be $true
        Test-Path -Path $script:legacyInsertPath | Should -Be $true
    }

    It 'new sql files reference stg_MailboxPermissions_Backfeed' {
        $createSql = Get-Content -Path $script:createBackfeedStagePath -Raw
        $insertSql = Get-Content -Path $script:insertBackfeedStagePath -Raw

        $createSql -match 'stg_MailboxPermissions_Backfeed' | Should -Be $true
        $insertSql -match 'stg_MailboxPermissions_Backfeed' | Should -Be $true
    }

    It 'new sql files do not write to MailboxPermissions target table' {
        $allSql = (Get-Content -Path $script:createBackfeedStagePath -Raw) + "`n" + (Get-Content -Path $script:insertBackfeedStagePath -Raw)
        $allSql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?MailboxPermissions\]?\b' | Should -Be $false
    }

    It 'new sql files do not write to hist_MailboxPermissions' {
        $allSql = (Get-Content -Path $script:createBackfeedStagePath -Raw) + "`n" + (Get-Content -Path $script:insertBackfeedStagePath -Raw)
        $allSql -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?hist_MailboxPermissions\]?\b' | Should -Be $false
    }

    It 'new sql files contain no MERGE' {
        $allSql = (Get-Content -Path $script:createBackfeedStagePath -Raw) + "`n" + (Get-Content -Path $script:insertBackfeedStagePath -Raw)
        $allSql -match '\bMERGE\b' | Should -Be $false
    }

    It 'new sql files contain no hardcoded productive server or database names' {
        $allSql = (Get-Content -Path $script:createBackfeedStagePath -Raw) + "`n" + (Get-Content -Path $script:insertBackfeedStagePath -Raw)
        $allSql -match '\bSV\d+\.ksbl\.local\b|\bKSBL_IAM\b|\bServer=' | Should -Be $false
    }

    It 'create sql defines SourceSystem PermissionType MailboxKey TrusteeKey RowHash and BackfeedRunId' {
        $createSql = Get-Content -Path $script:createBackfeedStagePath -Raw
        $createSql -match '\[BackfeedRunId\]' | Should -Be $true
        $createSql -match '\[SourceSystem\]' | Should -Be $true
        $createSql -match '\[PermissionType\]' | Should -Be $true
        $createSql -match '\[MailboxKey\]' | Should -Be $true
        $createSql -match '\[TrusteeKey\]' | Should -Be $true
        $createSql -match '\[RowHash\]' | Should -Be $true
    }

    It 'writer passes BackfeedRunId to SQL parameters' {
        Mock Invoke-MailboxPermissionBackfeedSqlScript { [pscustomobject]@{ Success = $true; RowsAffected = 1 } }

        $rows = @([pscustomobject]@{ SourceSystem = 'OnPrem'; PermissionType = 'FullAccess'; MailboxKey = 'mbx'; MailboxName = 'Mailbox'; TrusteeKey = 'trustee'; TrusteeName = 'user'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'FullAccess'; DistinguishedName = 'CN=Mailbox,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $false; AdReferenceObjectGuid = '11111111-1111-1111-1111-111111111111'; IsInherited = $false; Deny = $false; AccessRights = 'FullAccess'; RowHash = 'hash1' })

        $null = Invoke-MailboxPermissionBackfeedSqlWrite -Context ([pscustomobject]@{ Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows $rows -BackfeedRunId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'

        Should -Invoke -CommandName Invoke-MailboxPermissionBackfeedSqlScript -Times 1 -ParameterFilter {
            $ScriptPath -like '*insert-stg-mailbox-permission-backfeed-row.sql' -and $Parameters.BackfeedRunId -eq 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        }
    }

    It 'writer uses Context.BackfeedRunId for all SQL row parameters' {
        Mock Invoke-MailboxPermissionBackfeedSqlScript { [pscustomobject]@{ Success = $true; RowsAffected = 1 } }

        $rows = @(
            [pscustomobject]@{ SourceSystem = 'OnPrem'; PermissionType = 'FullAccess'; MailboxKey = 'm1'; MailboxName = 'M1'; TrusteeKey = 't1'; TrusteeName = 'u1'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'FullAccess'; DistinguishedName = 'CN=M1,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $false; AdReferenceObjectGuid = 'aaaaaaa1-1111-1111-1111-111111111111'; IsInherited = $false; Deny = $false; AccessRights = 'FullAccess'; RowHash = 'h1' },
            [pscustomobject]@{ SourceSystem = 'ExchangeOnline'; PermissionType = 'SendAs'; MailboxKey = 'm2'; MailboxName = 'M2'; TrusteeKey = 't2'; TrusteeName = 'u2'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'SendAs'; DistinguishedName = 'CN=M2,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $true; AdReferenceObjectGuid = 'bbbbbbb2-2222-2222-2222-222222222222'; IsInherited = $false; Deny = $false; AccessRights = 'SendAs'; RowHash = 'h2' }
        )

        $context = [pscustomobject]@{ BackfeedRunId = '12345678-1234-1234-1234-1234567890ab'; CorrelationId = 'ignored'; Config = [pscustomobject]@{}; WhatIfMode = $true }
        $result = Write-MailboxPermissionBackfeedStaging -BackfeedContext $context -Rows $rows

        $result.BackfeedRunId | Should -Be '12345678-1234-1234-1234-1234567890ab'
        Should -Invoke -CommandName Invoke-MailboxPermissionBackfeedSqlScript -Times 2 -ParameterFilter {
            $ScriptPath -like '*insert-stg-mailbox-permission-backfeed-row.sql' -and $Parameters.BackfeedRunId -eq '12345678-1234-1234-1234-1234567890ab'
        }
    }

    It 'writer persists SourceSystem PermissionType MailboxKey TrusteeKey and RowHash' {
        Mock Invoke-MailboxPermissionBackfeedSqlScript { [pscustomobject]@{ Success = $true; RowsAffected = 1 } }

        $rows = @([pscustomobject]@{ SourceSystem = 'ExchangeOnline'; PermissionType = 'SendAs'; MailboxKey = 'mailbox-key-1'; MailboxName = 'Mailbox'; TrusteeKey = 'trustee-key-1'; TrusteeName = 'user'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'SendAs'; DistinguishedName = 'CN=Mailbox,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $true; AdReferenceObjectGuid = '22222222-2222-2222-2222-222222222222'; IsInherited = $false; Deny = $false; AccessRights = 'SendAs'; RowHash = 'hash-xyz' })

        $null = Invoke-MailboxPermissionBackfeedSqlWrite -Context ([pscustomobject]@{ Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows $rows -BackfeedRunId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'

        Should -Invoke -CommandName Invoke-MailboxPermissionBackfeedSqlScript -Times 1 -ParameterFilter {
            $ScriptPath -like '*insert-stg-mailbox-permission-backfeed-row.sql' -and
            $Parameters.SourceSystem -eq 'ExchangeOnline' -and
            $Parameters.PermissionType -eq 'SendAs' -and
            $Parameters.MailboxKey -eq 'mailbox-key-1' -and
            $Parameters.TrusteeKey -eq 'trustee-key-1' -and
            $Parameters.RowHash -eq 'hash-xyz'
        }
    }

    It 'empty rows produce no sql call and return success true staged count 0' {
        Mock Invoke-MailboxPermissionBackfeedSqlWrite { throw 'must not be called' }

        $result = Write-MailboxPermissionBackfeedStaging -BackfeedContext ([pscustomobject]@{ Config = [pscustomobject]@{}; CorrelationId = 'cccccccc-cccc-cccc-cccc-cccccccccccc'; WhatIfMode = $true }) -Rows @()

        $result.Success | Should -Be $true
        $result.StagedCount | Should -Be 0
        Should -Invoke -CommandName Invoke-MailboxPermissionBackfeedSqlWrite -Times 0
    }

    It 'multiple rows produce staged count equal to row count' {
        Mock Invoke-MailboxPermissionBackfeedSqlScript { [pscustomobject]@{ Success = $true; RowsAffected = 1 } }

        $rows = @(
            [pscustomobject]@{ SourceSystem = 'OnPrem'; PermissionType = 'FullAccess'; MailboxKey = 'm1'; MailboxName = 'M1'; TrusteeKey = 't1'; TrusteeName = 'u1'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'FullAccess'; DistinguishedName = 'CN=M1,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $false; AdReferenceObjectGuid = '33333333-3333-3333-3333-333333333333'; IsInherited = $false; Deny = $false; AccessRights = 'FullAccess'; RowHash = 'h1' },
            [pscustomobject]@{ SourceSystem = 'ExchangeOnline'; PermissionType = 'SendAs'; MailboxKey = 'm2'; MailboxName = 'M2'; TrusteeKey = 't2'; TrusteeName = 'u2'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'SendAs'; DistinguishedName = 'CN=M2,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $true; AdReferenceObjectGuid = '44444444-4444-4444-4444-444444444444'; IsInherited = $false; Deny = $false; AccessRights = 'SendAs'; RowHash = 'h2' }
        )

        $result = Invoke-MailboxPermissionBackfeedSqlWrite -Context ([pscustomobject]@{ Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows $rows -BackfeedRunId 'dddddddd-dddd-dddd-dddd-dddddddddddd'

        $result.StagedCount | Should -Be 2
        Should -Invoke -CommandName Invoke-MailboxPermissionBackfeedSqlScript -Times 3
        Should -Invoke -CommandName Invoke-MailboxPermissionBackfeedSqlScript -Times 2 -ParameterFilter { $ScriptPath -like '*insert-stg-mailbox-permission-backfeed-row.sql' }
    }

    It 'sql error returns success false and ErrorCode' {
        Mock Invoke-MailboxPermissionBackfeedSqlWrite { throw 'sql broke' }

        $rows = @([pscustomobject]@{ SourceSystem = 'OnPrem'; PermissionType = 'FullAccess'; MailboxKey = 'm'; MailboxName = 'M'; TrusteeKey = 't'; TrusteeName = 'u'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'FullAccess'; DistinguishedName = 'CN=M,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $false; AdReferenceObjectGuid = '55555555-5555-5555-5555-555555555555'; IsInherited = $false; Deny = $false; AccessRights = 'FullAccess'; RowHash = 'hx' })

        $result = Write-MailboxPermissionBackfeedStaging -BackfeedContext ([pscustomobject]@{ Config = [pscustomobject]@{}; CorrelationId = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'; WhatIfMode = $true }) -Rows $rows

        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Be 'MAILBOX_PERMISSION_STAGE_FAILED'
        $result.BackfeedRunId | Should -Be 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
        $result.Errors[0].BackfeedRunId | Should -Be 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
    }

    It 'writer contains no Invoke-Sqlcmd' {
        (Get-Content -Path $script:writerPath -Raw) -match '\bInvoke-Sqlcmd\b' | Should -Be $false
    }

    It 'writer contains no direct SqlConnection usage' {
        (Get-Content -Path $script:writerPath -Raw) -match 'System\.Data\.(SqlClient\.)?SqlConnection|Microsoft\.Data\.SqlClient' | Should -Be $false
    }

    It 'writer contains no MailboxPermissions target table writes' {
        (Get-Content -Path $script:writerPath -Raw) -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?MailboxPermissions\]?\b' | Should -Be $false
    }

    It 'writer contains no hist_MailboxPermissions writes' {
        (Get-Content -Path $script:writerPath -Raw) -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?hist_MailboxPermissions\]?\b' | Should -Be $false
    }

    It 'writer contains no MERGE logic' {
        (Get-Content -Path $script:writerPath -Raw) -match '\bMERGE\b' | Should -Be $false
    }

    It 'service consumes staged count from writer' {
        Mock Read-MailboxPermissionBackfeedSources { @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem' }) }
        Mock ConvertTo-MailboxPermissionBackfeedRows { @([pscustomobject]@{ MailboxName = 'M'; TrusteeName = 'U' }) }
        Mock Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'ffffffff-ffff-ffff-ffff-ffffffffffff'; StagedCount = 3; FailedCount = 0; Message = 'Rows staged.'; ErrorCode = $null; Errors = @() }
        }
        Mock Get-MailboxPermissionBackfeedDelta {
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'ffffffff-ffff-ffff-ffff-ffffffffffff'; InsertedCount = 3; UpdatedCount = 0; DeletedCount = 0; UnchangedCount = 0; FailedCount = 0; Message = 'Delta counts resolved.'; ErrorCode = $null; Errors = @() }
        }
        Mock Initialize-MailboxPermissionBackfeedStateInsertOnly {
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'ffffffff-ffff-ffff-ffff-ffffffffffff'; InsertedCount = 3; UpdatedCount = 0; DeletedCount = 0; ReactivatedCount = 0; UnchangedCount = 0; FailedCount = 0; Message = 'State initialized.'; ErrorCode = $null; Errors = @() }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-bf-1' -BackfeedType 'MailboxPermission' -Mode 'Full' -BackfeedRunId 'ffffffff-ffff-ffff-ffff-ffffffffffff'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.StagedCount | Should -Be 3
        $result.InsertedCount | Should -Be 3
        $result.BackfeedRunId | Should -Be 'ffffffff-ffff-ffff-ffff-ffffffffffff'
    }

    It 'service applies InsertedCount from state initialization' {
        Mock Read-MailboxPermissionBackfeedSources { @([pscustomobject]@{ PermissionType = 'SendAs'; SourceSystem = 'ExchangeOnline' }) }
        Mock ConvertTo-MailboxPermissionBackfeedRows { @([pscustomobject]@{ MailboxName = 'M'; TrusteeName = 'U' }) }
        Mock Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $true; BackfeedRunId = '11111111-aaaa-bbbb-cccc-111111111111'; StagedCount = 1; FailedCount = 0; Message = 'Rows staged.'; ErrorCode = $null; Errors = @() }
        }
        Mock Get-MailboxPermissionBackfeedDelta {
            [pscustomobject]@{ Success = $true; BackfeedRunId = '11111111-aaaa-bbbb-cccc-111111111111'; InsertedCount = 1; UpdatedCount = 2; DeletedCount = 3; UnchangedCount = 4; FailedCount = 0; Message = 'Delta counts resolved.'; ErrorCode = $null; Errors = @() }
        }
        Mock Initialize-MailboxPermissionBackfeedStateInsertOnly {
            [pscustomobject]@{ Success = $true; BackfeedRunId = '11111111-aaaa-bbbb-cccc-111111111111'; InsertedCount = 7; UpdatedCount = 0; DeletedCount = 0; ReactivatedCount = 0; UnchangedCount = 4; FailedCount = 0; Message = 'State initialized.'; ErrorCode = $null; Errors = @() }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-bf-2' -BackfeedType 'MailboxPermission' -Mode 'Delta'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.InsertedCount | Should -Be 7
        $result.UpdatedCount | Should -Be 0
        $result.DeletedCount | Should -Be 0
        $result.UnchangedCount | Should -Be 4
    }

    It 'service returns failed when writer fails' {
        Mock Read-MailboxPermissionBackfeedSources { @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem' }) }
        Mock ConvertTo-MailboxPermissionBackfeedRows { @([pscustomobject]@{ MailboxName = 'M'; TrusteeName = 'U' }) }
        Mock Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $false; BackfeedRunId = '22222222-aaaa-bbbb-cccc-222222222222'; StagedCount = 0; FailedCount = 1; Message = 'writer failed'; ErrorCode = 'MAILBOX_PERMISSION_STAGE_FAILED'; Errors = @([pscustomobject]@{ Message = 'writer failed'; ErrorCode = 'MAILBOX_PERMISSION_STAGE_FAILED'; BackfeedRunId = '22222222-aaaa-bbbb-cccc-222222222222' }) }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-bf-3' -BackfeedType 'MailboxPermission' -Mode 'Full' -BackfeedRunId 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Failed'
        $result.Errors.Count | Should -Be 1
        $result.BackfeedRunId | Should -Be '22222222-aaaa-bbbb-cccc-222222222222'
        $result.Errors[0].BackfeedRunId | Should -Be '22222222-aaaa-bbbb-cccc-222222222222'
    }

    It 'writer derives BackfeedRunId from Context.BackfeedRunId' {
        $result = Write-MailboxPermissionBackfeedStaging -BackfeedContext ([pscustomobject]@{ BackfeedRunId = '33333333-aaaa-bbbb-cccc-333333333333'; CorrelationId = 'ignored'; Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows @()
        $result.BackfeedRunId | Should -Be '33333333-aaaa-bbbb-cccc-333333333333'
    }

    It 'writer derives BackfeedRunId from Context.CorrelationId when BackfeedRunId is missing' {
        $result = Write-MailboxPermissionBackfeedStaging -BackfeedContext ([pscustomobject]@{ CorrelationId = '44444444-aaaa-bbbb-cccc-444444444444'; Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows @()
        $result.BackfeedRunId | Should -Be '44444444-aaaa-bbbb-cccc-444444444444'
    }

    It 'writer generates a new guid BackfeedRunId when no guid input exists' {
        $result = Write-MailboxPermissionBackfeedStaging -BackfeedContext ([pscustomobject]@{ CorrelationId = 'not-a-guid'; Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows @()
        [guid]::Parse($result.BackfeedRunId).ToString() | Should -Be $result.BackfeedRunId
    }

    It 'JobEngine remains free of mailbox permission backfeed logic' {
        (Get-Content -Path $script:jobEnginePath -Raw) -match 'Invoke-MailboxPermissionBackfeed|MailboxPermissionBackfeedService|MailboxPermissionStagingWriter' | Should -Be $false
    }

    It 'JobFileQueue remains free of mailbox permission backfeed logic' {
        (Get-Content -Path $script:jobFileQueuePath -Raw) -match 'Invoke-MailboxPermissionBackfeed|MailboxPermissionBackfeedService|MailboxPermissionStagingWriter' | Should -Be $false
    }

    It 'usecases.json contains no backfeed entries' {
        (Get-Content -Path $script:usecasesPath -Raw) -match 'Backfeed' | Should -Be $false
    }

    It 'ExchangeOnPremGateway remains unchanged by this phase checks' {
        (Get-Content -Path $script:exchangeOnPremGatewayPath -Raw) -match 'stg_MailboxPermissions_Backfeed|insert-stg-mailbox-permission-backfeed-row.sql|create-stg-mailbox-permissions-backfeed.sql' | Should -Be $false
    }

    It 'ExchangeOnlineGateway remains unchanged by this phase checks' {
        (Get-Content -Path $script:exchangeOnlineGatewayPath -Raw) -match 'stg_MailboxPermissions_Backfeed|insert-stg-mailbox-permission-backfeed-row.sql|create-stg-mailbox-permissions-backfeed.sql' | Should -Be $false
    }

    It 'ActiveDirectoryGateway remains unchanged by this phase checks' {
        (Get-Content -Path $script:activeDirectoryGatewayPath -Raw) -match 'stg_MailboxPermissions_Backfeed|insert-stg-mailbox-permission-backfeed-row.sql|create-stg-mailbox-permissions-backfeed.sql' | Should -Be $false
    }

    It 'legacy mailbox script remains unchanged regarding backfeed integration' {
        (Get-Content -Path $script:legacyScriptPath -Raw) -match 'Invoke-MailboxPermissionBackfeed|stg_MailboxPermissions_Backfeed' | Should -Be $false
    }
}
