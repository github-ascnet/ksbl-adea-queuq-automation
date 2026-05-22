Describe 'MailboxPermission Backfeed skeleton' {
    BeforeAll {
        $root = if ($PSScriptRoot) {
            Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        }
        else {
            (Get-Location).Path
        }

        Set-Variable -Scope Script -Name root -Value $root
        Set-Variable -Scope Script -Name readerPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionSourceReader.psm1')
        Set-Variable -Scope Script -Name mapperPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionMapper.psm1')
        Set-Variable -Scope Script -Name writerPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionStagingWriter.psm1')
        Set-Variable -Scope Script -Name servicePath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionBackfeedService.psm1')
        Set-Variable -Scope Script -Name jobEnginePath -Value (Join-Path -Path $root -ChildPath 'core\JobEngine.psm1')
        Set-Variable -Scope Script -Name jobFileQueuePath -Value (Join-Path -Path $root -ChildPath 'core\JobFileQueue.psm1')
        Set-Variable -Scope Script -Name usecasesPath -Value (Join-Path -Path $root -ChildPath 'config\usecases.json')

        Import-Module -Name $script:readerPath -Force -DisableNameChecking
        Import-Module -Name $script:mapperPath -Force -DisableNameChecking
        Import-Module -Name $script:writerPath -Force -DisableNameChecking
        Import-Module -Name $script:servicePath -Force -DisableNameChecking
    }

    It 'creates the SourceReader file and exports the function' {
        Test-Path -Path $script:readerPath | Should -Be $true
        $content = Get-Content -Path $script:readerPath -Raw
        $content -match 'Export-ModuleMember -Function' | Should -Be $true
        $content -match 'Read-MailboxPermissionBackfeedSources' | Should -Be $true
    }

    It 'SourceReader contains no direct Exchange or AD cmdlets' {
        $content = Get-Content -Path $script:readerPath -Raw
        $content -match '\b(Get-MailboxPermission|Get-RecipientPermission|Connect-ExchangeOnline|New-PSSession|Get-ADUser|Get-ADObject)\b' | Should -Be $false
    }

    It 'SourceReader can be driven with mocked OnPrem and ExchangeOnline helpers' {
        $content = Get-Content -Path $script:readerPath -Raw
        $content -match 'Get-MailboxPermissionBackfeedOnPremRawRows' | Should -Be $true
        $content -match 'Get-MailboxPermissionBackfeedExchangeOnlineRawRows' | Should -Be $true
        $content -match 'Read-MailboxPermissionBackfeedSources' | Should -Be $true
    }

    It 'creates the Mapper file and exports the function' {
        Test-Path -Path $script:mapperPath | Should -Be $true
        $content = Get-Content -Path $script:mapperPath -Raw
        $content -match 'Export-ModuleMember -Function' | Should -Be $true
        $content -match 'ConvertTo-MailboxPermissionBackfeedRows' | Should -Be $true
    }

    It 'Mapper normalizes FullAccess and SendAs into the same DTO schema' {
        $content = Get-Content -Path $script:mapperPath -Raw
        $content -match 'Resolve-MailboxPermissionKey' | Should -Be $true
        $content -match 'Resolve-MailboxPermissionTrusteeKey' | Should -Be $true
        $content -match 'Get-MailboxPermissionRowHash' | Should -Be $true
        $content -match 'ConvertTo-MailboxPermissionBackfeedRows' | Should -Be $true
    }

    It 'creates the StagingWriter file and exports the function' {
        Test-Path -Path $script:writerPath | Should -Be $true
        $content = Get-Content -Path $script:writerPath -Raw
        $content -match 'Export-ModuleMember -Function' | Should -Be $true
        $content -match 'Write-MailboxPermissionBackfeedStaging' | Should -Be $true
    }

    It 'StagingWriter skips SQL on empty rows' {
        $content = Get-Content -Path $script:writerPath -Raw
        $content -match '\$rowCount -eq 0' | Should -Be $true
        $content -match 'Invoke-MailboxPermissionBackfeedSqlWrite' | Should -Be $true
    }

    It 'StagingWriter calls a mockable SQL helper for rows' {
        $content = Get-Content -Path $script:writerPath -Raw
        $content -match 'Invoke-MailboxPermissionBackfeedSqlWrite' | Should -Be $true
        $content -match 'StagedCount' | Should -Be $true
    }

    It 'creates the service file and runs Read Map Stage Result' {
        Test-Path -Path $script:servicePath | Should -Be $true
        $content = Get-Content -Path $script:servicePath -Raw
        $content -match 'Read-MailboxPermissionBackfeedSources' | Should -Be $true
        $content -match 'ConvertTo-MailboxPermissionBackfeedRows' | Should -Be $true
        $content -match 'Write-MailboxPermissionBackfeedStaging' | Should -Be $true
        $content -match 'New-BackfeedResult' | Should -Be $true
    }

    It 'returns Failed when the reader throws' {
        $content = Get-Content -Path $script:servicePath -Raw
        $content -match 'catch' | Should -Be $true
        $content -match 'reader failed|Failed' | Should -Be $true
    }

    It 'returns Failed when staging reports failure' {
        $content = Get-Content -Path $script:servicePath -Raw
        $content -match 'if \(-not \$stageResult.Success\)' | Should -Be $true
        $content -match 'MAILBOX_PERMISSION_STAGE_FAILED|ErrorCode' | Should -Be $true
    }

    It 'contains no direct Exchange, AD or SQL cmdlets in the service' {
        $content = Get-Content -Path $script:servicePath -Raw
        $content -match '\b(Get-MailboxPermission|Get-RecipientPermission|Connect-ExchangeOnline|New-PSSession|Get-ADUser|Get-ADObject|Invoke-Sqlcmd)\b' | Should -Be $false
    }

    It 'keeps JobEngine, JobFileQueue and usecases free of Backfeed logic' {
        (Get-Content -Path $script:jobEnginePath -Raw) -match 'Invoke-MailboxPermissionBackfeed|MailboxPermissionBackfeedService|MailboxPermissionSourceReader|MailboxPermissionMapper|MailboxPermissionStagingWriter' | Should -Be $false
        (Get-Content -Path $script:jobFileQueuePath -Raw) -match 'Invoke-MailboxPermissionBackfeed|MailboxPermissionBackfeedService|MailboxPermissionSourceReader|MailboxPermissionMapper|MailboxPermissionStagingWriter' | Should -Be $false
        (Get-Content -Path $script:usecasesPath -Raw) -match 'Backfeed' | Should -Be $false
    }
}