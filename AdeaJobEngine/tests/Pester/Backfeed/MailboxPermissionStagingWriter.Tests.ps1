Describe 'MailboxPermission StagingWriter SQL integration' {
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
        Set-Variable -Scope Script -Name truncateScriptPath -Value (Join-Path -Path $script:sqlFolderPath -ChildPath 'truncate-stg-mailbox-permissions.sql')
        Set-Variable -Scope Script -Name insertScriptPath -Value (Join-Path -Path $script:sqlFolderPath -ChildPath 'insert-stg-mailbox-permission-row.sql')

        Set-Variable -Scope Script -Name writerPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionStagingWriter.psm1')
        Set-Variable -Scope Script -Name servicePath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionBackfeedService.psm1')
        Set-Variable -Scope Script -Name processorPath -Value (Join-Path -Path $root -ChildPath 'backfeed\Invoke-BackfeedProcessor.ps1')
        Set-Variable -Scope Script -Name contextPath -Value (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedContext.psm1')
        Set-Variable -Scope Script -Name resultPath -Value (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedResult.psm1')
        Set-Variable -Scope Script -Name mapperPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionMapper.psm1')
        Set-Variable -Scope Script -Name sourceReaderPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionSourceReader.psm1')

        Set-Variable -Scope Script -Name jobEnginePath -Value (Join-Path -Path $root -ChildPath 'core\JobEngine.psm1')
        Set-Variable -Scope Script -Name jobFileQueuePath -Value (Join-Path -Path $root -ChildPath 'core\JobFileQueue.psm1')
        Set-Variable -Scope Script -Name usecasesPath -Value (Join-Path -Path $root -ChildPath 'config\usecases.json')
        Set-Variable -Scope Script -Name exchangeOnPremGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnPremGateway.psm1')
        Set-Variable -Scope Script -Name exchangeOnlineGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1')
        Set-Variable -Scope Script -Name appSettingsPath -Value (Join-Path -Path $root -ChildPath 'config\appsettings.json')
        Set-Variable -Scope Script -Name envHybridPath -Value (Join-Path -Path $root -ChildPath 'config\environments.hybrid.json')
        Set-Variable -Scope Script -Name envOnPremPath -Value (Join-Path -Path $root -ChildPath 'config\environments.onprem.json')
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

        $serviceScriptText = Get-Content -Path $script:servicePath -Raw
        $serviceModuleRoot = Split-Path -Parent $script:servicePath
        $serviceScriptText = $serviceScriptText -replace [regex]::Escape('$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path'), ('$moduleRoot = ''' + $serviceModuleRoot + '''')
        $serviceScriptText = [regex]::Replace($serviceScriptText, '(?m)^Import-Module\s+-Name\s+.*MailboxPermissionSourceReader\.psm1.*$', '')
        $serviceScriptText = [regex]::Replace($serviceScriptText, '(?m)^Import-Module\s+-Name\s+.*MailboxPermissionMapper\.psm1.*$', '')
        $serviceScriptText = [regex]::Replace($serviceScriptText, '(?m)^Import-Module\s+-Name\s+.*MailboxPermissionStagingWriter\.psm1.*$', '')
        $serviceScriptText = [regex]::Replace($serviceScriptText, '(?ms)^Export-ModuleMember\s+-Function\s+@\(.*?\)\s*$', '')
        . ([scriptblock]::Create($serviceScriptText))
    }

    It 'sql/backfeed/mailbox-permission folder exists' {
        Test-Path -Path $script:sqlFolderPath | Should -Be $true
    }

    It 'staging sql files exist' {
        Test-Path -Path $script:truncateScriptPath | Should -Be $true
        Test-Path -Path $script:insertScriptPath | Should -Be $true
    }

    It 'sql files contain no write logic for target table MailboxPermissions' {
        $truncateSql = Get-Content -Path $script:truncateScriptPath -Raw
        $insertSql = Get-Content -Path $script:insertScriptPath -Raw
        ($truncateSql + "`n" + $insertSql) -match '\b(?:INSERT\s+INTO|UPDATE|DELETE\s+FROM|TRUNCATE\s+TABLE)\s+\[?dbo\]?\.?\[?MailboxPermissions\]?\b' | Should -Be $false
    }

    It 'sql files contain no write logic for hist_MailboxPermissions' {
        $truncateSql = Get-Content -Path $script:truncateScriptPath -Raw
        $insertSql = Get-Content -Path $script:insertScriptPath -Raw
        ($truncateSql + "`n" + $insertSql) -match 'hist_MailboxPermissions' | Should -Be $false
    }

    It 'sql files contain no MERGE' {
        $truncateSql = Get-Content -Path $script:truncateScriptPath -Raw
        $insertSql = Get-Content -Path $script:insertScriptPath -Raw
        ($truncateSql + "`n" + $insertSql) -match '\bMERGE\b' | Should -Be $false
    }

    It 'sql files contain no hardcoded server or database names' {
        $truncateSql = Get-Content -Path $script:truncateScriptPath -Raw
        $insertSql = Get-Content -Path $script:insertScriptPath -Raw
        ($truncateSql + "`n" + $insertSql) -match '\bKSBL_Hospis_Staging\b|\bServer=' | Should -Be $false
    }

    It 'empty rows produce no sql write and staged count 0' {
        Mock Invoke-MailboxPermissionBackfeedSqlWrite { throw 'must not be called' }

        $result = Write-MailboxPermissionBackfeedStaging -BackfeedContext ([pscustomobject]@{ Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows @()

        $result.Success | Should -Be $true
        $result.StagedCount | Should -Be 0
        Should -Invoke -CommandName Invoke-MailboxPermissionBackfeedSqlWrite -Times 0
    }

    It 'one valid row triggers one sql insert call' {
        Mock Invoke-MailboxPermissionBackfeedSqlScript { [pscustomobject]@{ Success = $true; RowsAffected = 1 } }

        $rows = @([pscustomobject]@{
            MailboxName = 'Mailbox One'
            TrusteeName = 'user.one'
            TrusteeDomain = 'EXAMPLE'
            ObjectClass = 'user'
            AcePermissions = 'FullAccess'
            DistinguishedName = 'CN=Mailbox One,OU=Mailboxes,DC=example,DC=local'
            ExchHideFromAddressLists = $false
            AdReferenceObjectGuid = '11111111-1111-1111-1111-111111111111'
        })

        $result = Invoke-MailboxPermissionBackfeedSqlWrite -Context ([pscustomobject]@{ Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows $rows

        $result.StagedCount | Should -Be 1
        Should -Invoke -CommandName Invoke-MailboxPermissionBackfeedSqlScript -Times 1 -ParameterFilter { $ScriptPath -like '*insert-stg-mailbox-permission-row.sql' }
    }

    It 'multiple valid rows produce staged count equal to row count' {
        Mock Invoke-MailboxPermissionBackfeedSqlScript { [pscustomobject]@{ Success = $true; RowsAffected = 1 } }

        $rows = @(
            [pscustomobject]@{ MailboxName = 'M1'; TrusteeName = 'u1'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'FullAccess'; DistinguishedName = 'CN=M1,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $false; AdReferenceObjectGuid = 'aaaaaaaa-1111-1111-1111-111111111111' },
            [pscustomobject]@{ MailboxName = 'M2'; TrusteeName = 'u2'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'SendAs'; DistinguishedName = 'CN=M2,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $true; AdReferenceObjectGuid = 'bbbbbbbb-2222-2222-2222-222222222222' },
            [pscustomobject]@{ MailboxName = 'M3'; TrusteeName = 'u3'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'FullAccess'; DistinguishedName = 'CN=M3,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $null; AdReferenceObjectGuid = 'cccccccc-3333-3333-3333-333333333333' }
        )

        $result = Invoke-MailboxPermissionBackfeedSqlWrite -Context ([pscustomobject]@{ Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows $rows

        $result.StagedCount | Should -Be 3
        Should -Invoke -CommandName Invoke-MailboxPermissionBackfeedSqlScript -Times 3 -ParameterFilter { $ScriptPath -like '*insert-stg-mailbox-permission-row.sql' }
    }

    It 'sql error returns success false from staging writer' {
        Mock Invoke-MailboxPermissionBackfeedSqlWrite { throw 'sql failed' }

        $rows = @([pscustomobject]@{ MailboxName = 'M'; TrusteeName = 'u'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'FullAccess'; DistinguishedName = 'CN=M,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $false; AdReferenceObjectGuid = 'dddddddd-4444-4444-4444-444444444444' })
        $result = Write-MailboxPermissionBackfeedStaging -BackfeedContext ([pscustomobject]@{ Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows $rows

        $result.Success | Should -Be $false
        $result.ErrorCode | Should -Be 'MAILBOX_PERMISSION_STAGE_FAILED'
    }

    It 'writer error contains error code and message' {
        Mock Invoke-MailboxPermissionBackfeedSqlWrite { throw 'sql failed hard' }

        $rows = @([pscustomobject]@{ MailboxName = 'M'; TrusteeName = 'u'; TrusteeDomain = 'EXAMPLE'; ObjectClass = 'user'; AcePermissions = 'FullAccess'; DistinguishedName = 'CN=M,OU=Mailboxes,DC=example,DC=local'; ExchHideFromAddressLists = $false; AdReferenceObjectGuid = 'eeeeeeee-5555-5555-5555-555555555555' })
        $result = Write-MailboxPermissionBackfeedStaging -BackfeedContext ([pscustomobject]@{ Config = [pscustomobject]@{}; WhatIfMode = $true }) -Rows $rows

        $result.Message | Should -Be 'sql failed hard'
        $result.Errors.Count | Should -Be 1
        $result.Errors[0].ErrorCode | Should -Be 'MAILBOX_PERMISSION_STAGE_FAILED'
    }

    It 'writer contains no Invoke-Sqlcmd usage' {
        $content = Get-Content -Path $script:writerPath -Raw
        $content -match '\bInvoke-Sqlcmd\b' | Should -Be $false
    }

    It 'writer contains no direct SqlConnection usage' {
        $content = Get-Content -Path $script:writerPath -Raw
        $content -match 'System\.Data\.(SqlClient\.)?SqlConnection|Microsoft\.Data\.SqlClient' | Should -Be $false
    }

    It 'writer contains no target table write logic for MailboxPermissions' {
        $content = Get-Content -Path $script:writerPath -Raw
        $content -match '\bMailboxPermissions\b' | Should -Be $false
    }

    It 'writer contains no hist_MailboxPermissions write logic' {
        $content = Get-Content -Path $script:writerPath -Raw
        $content -match 'hist_MailboxPermissions' | Should -Be $false
    }

    It 'writer contains no MERGE logic' {
        $content = Get-Content -Path $script:writerPath -Raw
        $content -match '\bMERGE\b' | Should -Be $false
    }

    It 'dto fields map correctly to staging sql parameters' {
        $parameters = ConvertTo-MailboxPermissionStagingSqlParameters -Row ([pscustomobject]@{
            MailboxName = 'Mailbox Map'
            TrusteeName = 'map.user'
            TrusteeDomain = 'EXAMPLE'
            ObjectClass = 'user'
            AcePermissions = 'FullAccess'
            DistinguishedName = 'CN=Mailbox Map,OU=Mailboxes,DC=example,DC=local'
            ExchHideFromAddressLists = $true
            AdReferenceObjectGuid = 'ffffffff-6666-6666-6666-666666666666'
            SourceSystem = 'ExchangeOnline'
            PermissionType = 'FullAccess'
            MailboxKey = 'mbx-key'
            TrusteeKey = 'trustee-key'
            RowHash = 'hash-value'
        })

        $parameters.Name | Should -Be 'Mailbox Map'
        $parameters.TrusteeName | Should -Be 'map.user'
        $parameters.TrusteeDomain | Should -Be 'EXAMPLE'
        $parameters.ObjectClass | Should -Be 'user'
        $parameters.AcePermissions | Should -Be 'FullAccess'
        $parameters.DistinguishedName | Should -Be 'CN=Mailbox Map,OU=Mailboxes,DC=example,DC=local'
    }

    It 'future delta fields are not written to sql script columns' {
        $insertSql = Get-Content -Path $script:insertScriptPath -Raw
        $insertSql -match '\[(SourceSystem|PermissionType|MailboxKey|TrusteeKey|RowHash)\]' | Should -Be $false
    }

    It 'AdReferenceObjectGuid is mapped from DTO into sql parameters' {
        $parameters = ConvertTo-MailboxPermissionStagingSqlParameters -Row ([pscustomobject]@{ AdReferenceObjectGuid = '12121212-1212-1212-1212-121212121212' })
        $parameters.AdReferenceObjectGuid | Should -Be '12121212-1212-1212-1212-121212121212'
    }

    It 'ExchHideFromAddressLists is mapped from DTO into sql parameters' {
        $parameters = ConvertTo-MailboxPermissionStagingSqlParameters -Row ([pscustomobject]@{ ExchHideFromAddressLists = $false })
        $parameters.ExchHideFromAddressLists | Should -Be $false
    }

    It 'service uses staged count from writer result' {
        Mock Read-MailboxPermissionBackfeedSources { @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem' }) }
        Mock ConvertTo-MailboxPermissionBackfeedRows { @([pscustomobject]@{ MailboxName = 'M'; TrusteeName = 'U' }) }
        Mock Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $true; StagedCount = 5; FailedCount = 0; Message = 'Rows staged.'; ErrorCode = $null; Errors = @() }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-stage-1' -BackfeedType 'MailboxPermission' -Mode 'Full'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.StagedCount | Should -Be 5
    }

    It 'service returns failed when writer fails' {
        Mock Read-MailboxPermissionBackfeedSources { @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem' }) }
        Mock ConvertTo-MailboxPermissionBackfeedRows { @([pscustomobject]@{ MailboxName = 'M'; TrusteeName = 'U' }) }
        Mock Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $false; StagedCount = 0; FailedCount = 1; Message = 'writer failed'; ErrorCode = 'MAILBOX_PERMISSION_STAGE_FAILED'; Errors = @([pscustomobject]@{ Message = 'writer failed'; ErrorCode = 'MAILBOX_PERMISSION_STAGE_FAILED' }) }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-stage-2' -BackfeedType 'MailboxPermission' -Mode 'Full'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Failed'
        $result.Errors.Count | Should -Be 1
        $result.Errors[0].ErrorCode | Should -Be 'MAILBOX_PERMISSION_STAGE_FAILED'
    }

    It 'service keeps delta merge counters at zero' {
        Mock Read-MailboxPermissionBackfeedSources { @([pscustomobject]@{ PermissionType = 'SendAs'; SourceSystem = 'ExchangeOnline' }) }
        Mock ConvertTo-MailboxPermissionBackfeedRows { @([pscustomobject]@{ MailboxName = 'M'; TrusteeName = 'U' }) }
        Mock Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $true; StagedCount = 1; FailedCount = 0; Message = 'Rows staged.'; ErrorCode = $null; Errors = @() }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-stage-3' -BackfeedType 'MailboxPermission' -Mode 'Delta'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.InsertedCount | Should -Be 0
        $result.UpdatedCount | Should -Be 0
        $result.DeletedCount | Should -Be 0
        $result.UnchangedCount | Should -Be 0
    }

    It 'service result remains output json compatible' {
        Mock Read-MailboxPermissionBackfeedSources { @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem' }) }
        Mock ConvertTo-MailboxPermissionBackfeedRows { @([pscustomobject]@{ MailboxName = 'M'; TrusteeName = 'U' }) }
        Mock Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $true; StagedCount = 1; FailedCount = 0; Message = 'Rows staged.'; ErrorCode = $null; Errors = @() }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'json-stage-1' -BackfeedType 'MailboxPermission' -Mode 'Delta'
        $resultObject = Invoke-MailboxPermissionBackfeed -Context $context
        $json = $resultObject | ConvertTo-Json -Depth 20 -Compress
        { $json | ConvertFrom-Json | Out-Null } | Should -Not -Throw
        $result = $json | ConvertFrom-Json
        $result.BackfeedType | Should -Be 'MailboxPermission'
        $result.Mode | Should -Be 'Delta'
    }

    It 'JobEngine remains free of backfeed mailbox permission logic' {
        (Get-Content -Path $script:jobEnginePath -Raw) -match 'Invoke-MailboxPermissionBackfeed|MailboxPermissionBackfeedService|MailboxPermissionStagingWriter' | Should -Be $false
    }

    It 'JobFileQueue remains free of backfeed mailbox permission logic' {
        (Get-Content -Path $script:jobFileQueuePath -Raw) -match 'Invoke-MailboxPermissionBackfeed|MailboxPermissionBackfeedService|MailboxPermissionStagingWriter' | Should -Be $false
    }

    It 'usecases.json contains no backfeed entries' {
        (Get-Content -Path $script:usecasesPath -Raw) -match 'Backfeed' | Should -Be $false
    }

    It 'legacy mailbox permission script remains free of backfeed integration' {
        (Get-Content -Path $script:legacyScriptPath -Raw) -match 'Invoke-MailboxPermissionBackfeed|Write-MailboxPermissionBackfeedStaging' | Should -Be $false
    }

    It 'exchange gateways contain no sql staging writer references' {
        (Get-Content -Path $script:exchangeOnPremGatewayPath -Raw) -match 'BackfeedSqlScriptRunner|stg_MailboxPermissions|insert-stg-mailbox-permission-row.sql' | Should -Be $false
        (Get-Content -Path $script:exchangeOnlineGatewayPath -Raw) -match 'BackfeedSqlScriptRunner|stg_MailboxPermissions|insert-stg-mailbox-permission-row.sql' | Should -Be $false
    }

    It 'environment related config files remain free of mailbox permission staging sql script references' {
        (Get-Content -Path $script:appSettingsPath -Raw) -match 'stg_MailboxPermissions|insert-stg-mailbox-permission-row.sql|truncate-stg-mailbox-permissions.sql' | Should -Be $false
        (Get-Content -Path $script:envHybridPath -Raw) -match 'stg_MailboxPermissions|insert-stg-mailbox-permission-row.sql|truncate-stg-mailbox-permissions.sql' | Should -Be $false
        (Get-Content -Path $script:envOnPremPath -Raw) -match 'stg_MailboxPermissions|insert-stg-mailbox-permission-row.sql|truncate-stg-mailbox-permissions.sql' | Should -Be $false
    }
}
