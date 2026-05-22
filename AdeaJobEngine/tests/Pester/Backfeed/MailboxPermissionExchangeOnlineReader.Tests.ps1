Describe 'MailboxPermission ExchangeOnline Gateway integration' {
    BeforeAll {
        $root = if ($PSScriptRoot) {
            Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
        }
        else {
            (Get-Location).Path
        }

        Set-Variable -Scope Script -Name root -Value $root
        Set-Variable -Scope Script -Name workspaceRoot -Value (Split-Path -Parent $root)
        Set-Variable -Scope Script -Name readerPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionSourceReader.psm1')
        Set-Variable -Scope Script -Name mapperPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionMapper.psm1')
        Set-Variable -Scope Script -Name servicePath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionBackfeedService.psm1')
        Set-Variable -Scope Script -Name writerPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionStagingWriter.psm1')
        Set-Variable -Scope Script -Name exchangeOnlineGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1')
        Set-Variable -Scope Script -Name exchangeOnPremGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnPremGateway.psm1')
        Set-Variable -Scope Script -Name activeDirectoryGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ActiveDirectoryGateway.psm1')
        Set-Variable -Scope Script -Name sqlGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\SqlGateway.psm1')
        Set-Variable -Scope Script -Name jobEnginePath -Value (Join-Path -Path $root -ChildPath 'core\JobEngine.psm1')
        Set-Variable -Scope Script -Name jobFileQueuePath -Value (Join-Path -Path $root -ChildPath 'core\JobFileQueue.psm1')
        Set-Variable -Scope Script -Name usecasesPath -Value (Join-Path -Path $root -ChildPath 'config\usecases.json')
        Set-Variable -Scope Script -Name legacyScriptPath -Value (Join-Path -Path $script:workspaceRoot -ChildPath 'current-scripts\Import-MailboxPermissions-Into-Staging-Update-Model.ps1')

        Remove-Module -Name 'ExchangeOnlineGateway' -ErrorAction SilentlyContinue
        Remove-Module -Name 'BackfeedContext' -ErrorAction SilentlyContinue
        Remove-Module -Name 'BackfeedResult' -ErrorAction SilentlyContinue

        Import-Module -Name (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedContext.psm1') -Force -DisableNameChecking -Global
        Import-Module -Name (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedResult.psm1') -Force -DisableNameChecking -Global
        Import-Module -Name $script:exchangeOnlineGatewayPath -Force -DisableNameChecking -Global

        $readerScriptText = Get-Content -Path $script:readerPath -Raw
        $readerModuleRoot = Split-Path -Parent $script:readerPath
        $readerScriptText = $readerScriptText -replace [regex]::Escape('$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path'), ('$moduleRoot = ''' + $readerModuleRoot + '''')
        $readerScriptText = [regex]::Replace($readerScriptText, '(?ms)^Export-ModuleMember\s+-Function\s+@\(.*?\)\s*$', '')
        . ([scriptblock]::Create($readerScriptText))

        $mapperScriptText = Get-Content -Path $script:mapperPath -Raw
        $mapperScriptText = [regex]::Replace($mapperScriptText, '(?ms)^Export-ModuleMember\s+-Function\s+@\(.*?\)\s*$', '')
        . ([scriptblock]::Create($mapperScriptText))

        $serviceScriptText = Get-Content -Path $script:servicePath -Raw
        $serviceModuleRoot = Split-Path -Parent $script:servicePath
        $serviceScriptText = $serviceScriptText -replace [regex]::Escape('$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path'), ('$moduleRoot = ''' + $serviceModuleRoot + '''')
        $serviceScriptText = [regex]::Replace($serviceScriptText, '(?ms)^Export-ModuleMember\s+-Function\s+@\(.*?\)\s*$', '')
        . ([scriptblock]::Create($serviceScriptText))

        $writerScriptText = Get-Content -Path $script:writerPath -Raw
        $writerScriptText = [regex]::Replace($writerScriptText, '(?ms)^Export-ModuleMember\s+-Function\s+@\(.*?\)\s*$', '')
        . ([scriptblock]::Create($writerScriptText))
    }

    It 'EXO FullAccess path calls mailbox list and FullAccess gateway call' {
        Mock Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead {
            @([pscustomobject]@{ Identity = 'exo-mbx-1'; DistinguishedName = 'CN=exo-mbx-1,OU=Cloud,DC=example,DC=local' })
        }
        Mock Invoke-ExchangeOnlineMailboxFullAccessGatewayRead {
            @([pscustomobject]@{ MailboxIdentity = 'exo-mbx-1'; MailboxName = 'EXO Mailbox 1'; MailboxDistinguishedName = 'CN=exo-mbx-1,OU=Cloud,DC=example,DC=local'; MailboxGuid = '10000000-0000-0000-0000-000000000001'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\exo.user1'; TrusteeName = 'exo.user1'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=exo.user1,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-10-10-10-101'; TrusteeObjectClass = 'user'; AccessRights = 'FullAccess'; IsInherited = $false; Deny = $false })
        }
        Mock Invoke-ExchangeOnlineMailboxSendAsGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedExchangeOnlineRawRows -Context ([pscustomobject]@{}))

        $rows.Count | Should -Be 1
        Should -Invoke -CommandName Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead -Times 2
        Should -Invoke -CommandName Invoke-ExchangeOnlineMailboxFullAccessGatewayRead -Times 1
    }

    It 'EXO SendAs path calls mailbox list and SendAs gateway call' {
        Mock Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead {
            @([pscustomobject]@{ Identity = 'exo-mbx-2'; DistinguishedName = 'CN=exo-mbx-2,OU=Cloud,DC=example,DC=local' })
        }
        Mock Invoke-ExchangeOnlineMailboxSendAsGatewayRead {
            @([pscustomobject]@{ MailboxIdentity = 'exo-mbx-2'; MailboxName = 'EXO Mailbox 2'; MailboxDistinguishedName = 'CN=exo-mbx-2,OU=Cloud,DC=example,DC=local'; MailboxGuid = '20000000-0000-0000-0000-000000000002'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\exo.user2'; TrusteeName = 'exo.user2'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=exo.user2,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-20-20-20-202'; TrusteeObjectClass = 'user'; AccessRights = 'SendAs'; IsInherited = $false; Deny = $false })
        }
        Mock Invoke-ExchangeOnlineMailboxFullAccessGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedExchangeOnlineRawRows -Context ([pscustomobject]@{}))

        $rows.Count | Should -Be 1
        Should -Invoke -CommandName Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead -Times 2
        Should -Invoke -CommandName Invoke-ExchangeOnlineMailboxSendAsGatewayRead -Times 1
    }

    It 'EXO FullAccess rows carry SourceSystem ExchangeOnline and PermissionType FullAccess' {
        Mock Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead { @([pscustomobject]@{ Identity = 'exo-mbx-3'; DistinguishedName = 'CN=exo-mbx-3,OU=Cloud,DC=example,DC=local' }) }
        Mock Invoke-ExchangeOnlineMailboxFullAccessGatewayRead { @([pscustomobject]@{ MailboxIdentity = 'exo-mbx-3'; MailboxName = 'EXO Mailbox 3'; MailboxDistinguishedName = 'CN=exo-mbx-3,OU=Cloud,DC=example,DC=local'; MailboxGuid = '30000000-0000-0000-0000-000000000003'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\exo.user3'; TrusteeName = 'exo.user3'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=exo.user3,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-30-30-30-303'; TrusteeObjectClass = 'user'; AccessRights = 'FullAccess'; IsInherited = $false; Deny = $false }) }
        Mock Invoke-ExchangeOnlineMailboxSendAsGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedExchangeOnlineRawRows -Context ([pscustomobject]@{}))
        $rows[0].SourceSystem | Should -Be 'ExchangeOnline'
        $rows[0].PermissionType | Should -Be 'FullAccess'
    }

    It 'EXO SendAs rows carry SourceSystem ExchangeOnline and PermissionType SendAs' {
        Mock Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead { @([pscustomobject]@{ Identity = 'exo-mbx-4'; DistinguishedName = 'CN=exo-mbx-4,OU=Cloud,DC=example,DC=local' }) }
        Mock Invoke-ExchangeOnlineMailboxSendAsGatewayRead { @([pscustomobject]@{ MailboxIdentity = 'exo-mbx-4'; MailboxName = 'EXO Mailbox 4'; MailboxDistinguishedName = 'CN=exo-mbx-4,OU=Cloud,DC=example,DC=local'; MailboxGuid = '40000000-0000-0000-0000-000000000004'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\exo.user4'; TrusteeName = 'exo.user4'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=exo.user4,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-40-40-40-404'; TrusteeObjectClass = 'user'; AccessRights = 'SendAs'; IsInherited = $false; Deny = $false }) }
        Mock Invoke-ExchangeOnlineMailboxFullAccessGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedExchangeOnlineRawRows -Context ([pscustomobject]@{}))
        $rows[0].SourceSystem | Should -Be 'ExchangeOnline'
        $rows[0].PermissionType | Should -Be 'SendAs'
    }

    It 'Multiple EXO mailboxes are processed' {
        Mock Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead {
            @([pscustomobject]@{ Identity = 'exo-a'; DistinguishedName = 'CN=exo-a,OU=Cloud,DC=example,DC=local' }, [pscustomobject]@{ Identity = 'exo-b'; DistinguishedName = 'CN=exo-b,OU=Cloud,DC=example,DC=local' })
        }
        Mock Invoke-ExchangeOnlineMailboxFullAccessGatewayRead {
            param([string]$Identity)
            @([pscustomobject]@{ MailboxIdentity = $Identity; MailboxName = $Identity; MailboxDistinguishedName = "CN=$Identity,OU=Cloud,DC=example,DC=local"; MailboxGuid = '50000000-0000-0000-0000-000000000005'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\exo.user'; TrusteeName = 'exo.user'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=exo.user,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-50-50-50-505'; TrusteeObjectClass = 'user'; AccessRights = 'FullAccess'; IsInherited = $false; Deny = $false })
        }
        Mock Invoke-ExchangeOnlineMailboxSendAsGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedExchangeOnlineRawRows -Context ([pscustomobject]@{}))
        $rows.Count | Should -Be 2
        Should -Invoke -CommandName Invoke-ExchangeOnlineMailboxFullAccessGatewayRead -Times 2
    }

    It 'EXO mailbox without permissions yields no row' {
        Mock Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead { @([pscustomobject]@{ Identity = 'exo-empty'; DistinguishedName = 'CN=exo-empty,OU=Cloud,DC=example,DC=local' }) }
        Mock Invoke-ExchangeOnlineMailboxFullAccessGatewayRead { @() }
        Mock Invoke-ExchangeOnlineMailboxSendAsGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedExchangeOnlineRawRows -Context ([pscustomobject]@{}))
        $rows.Count | Should -Be 0
    }

    It 'Gateway error for EXO mailbox is propagated by SourceReader' {
        Mock Invoke-ExchangeOnlineMailboxPermissionBackfeedMailboxesGatewayRead { @([pscustomobject]@{ Identity = 'exo-fail'; DistinguishedName = 'CN=exo-fail,OU=Cloud,DC=example,DC=local' }) }
        Mock Invoke-ExchangeOnlineMailboxFullAccessGatewayRead { throw 'exo gateway failure' }
        Mock Invoke-ExchangeOnlineMailboxSendAsGatewayRead { @() }

        { Get-MailboxPermissionBackfeedExchangeOnlineRawRows -Context ([pscustomobject]@{}) } | Should -Throw
    }

    It 'SourceReader contains no forbidden direct cmdlets' {
        $content = Get-Content -Path $script:readerPath -Raw
        $content -match '\b(Get-EXOMailbox|Get-EXOMailboxPermission|Get-MailboxPermission|Get-RecipientPermission|Get-EXORecipient|Get-Recipient|Connect-ExchangeOnline|Disconnect-ExchangeOnline|New-PSSession|Get-ADUser|Get-ADObject|Invoke-Sqlcmd)\b' | Should -Be $false
    }

    It 'ExchangeOnlineGateway exports required backfeed read functions' {
        $content = Get-Content -Path $script:exchangeOnlineGatewayPath -Raw
        $content -match "'Get-ExchangeOnlineMailboxPermissionBackfeedMailboxes'" | Should -Be $true
        $content -match "'Get-ExchangeOnlineMailboxFullAccessPermissionsSafe'" | Should -Be $true
        $content -match "'Get-ExchangeOnlineMailboxSendAsPermissionsSafe'" | Should -Be $true
    }

    It 'ExchangeOnlineGateway read functions contain no OnPrem remote session logic or New-PSSession' {
        $content = Get-Content -Path $script:exchangeOnlineGatewayPath -Raw
        $content -match 'function\s+Get-ExchangeOnlineMailboxPermissionBackfeedMailboxes[\s\S]*New-PSSession' | Should -Be $false
        $content -match 'function\s+Get-ExchangeOnlineMailboxFullAccessPermissionsSafe[\s\S]*New-PSSession' | Should -Be $false
        $content -match 'function\s+Get-ExchangeOnlineMailboxSendAsPermissionsSafe[\s\S]*New-PSSession' | Should -Be $false
        $content -match 'function\s+Get-ExchangeOnlineMailboxPermissionBackfeedMailboxes[\s\S]*Invoke-ExchangeOnPremCommand' | Should -Be $false
        $content -match 'function\s+Get-ExchangeOnlineMailboxFullAccessPermissionsSafe[\s\S]*Invoke-ExchangeOnPremCommand' | Should -Be $false
        $content -match 'function\s+Get-ExchangeOnlineMailboxSendAsPermissionsSafe[\s\S]*Invoke-ExchangeOnPremCommand' | Should -Be $false
    }

    It 'ExchangeOnlineGateway read functions use existing EXO connection wrapper' {
        $content = Get-Content -Path $script:exchangeOnlineGatewayPath -Raw
        $content -match 'Get-ExchangeOnlineMailboxPermissionBackfeedMailboxes[\s\S]*Invoke-ExchangeOnlineCommand' | Should -Be $true
        $content -match 'Get-ExchangeOnlineMailboxFullAccessPermissionsSafe[\s\S]*Invoke-ExchangeOnlineCommand' | Should -Be $true
        $content -match 'Get-ExchangeOnlineMailboxSendAsPermissionsSafe[\s\S]*Invoke-ExchangeOnlineCommand' | Should -Be $true
    }

    It 'Mapper normalizes EXO FullAccess gateway rows' {
        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions @([pscustomobject]@{ SourceSystem = 'ExchangeOnline'; PermissionType = 'FullAccess'; MailboxIdentity = 'exo-map-1'; MailboxName = 'EXO Map 1'; MailboxDistinguishedName = 'CN=exo-map-1,OU=Cloud,DC=example,DC=local'; MailboxGuid = '60000000-0000-0000-0000-000000000006'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\exo.map1'; TrusteeName = 'exo.map1'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=exo.map1,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-60-60-60-606'; TrusteeObjectClass = 'user'; AccessRights = 'FullAccess'; IsInherited = $false; Deny = $false }))
        $rows.Count | Should -Be 1
        $rows[0].SourceSystem | Should -Be 'ExchangeOnline'
        $rows[0].PermissionType | Should -Be 'FullAccess'
    }

    It 'Mapper normalizes EXO SendAs gateway rows' {
        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions @([pscustomobject]@{ SourceSystem = 'ExchangeOnline'; PermissionType = 'SendAs'; MailboxIdentity = 'exo-map-2'; MailboxName = 'EXO Map 2'; MailboxDistinguishedName = 'CN=exo-map-2,OU=Cloud,DC=example,DC=local'; MailboxGuid = '70000000-0000-0000-0000-000000000007'; MailboxHiddenFromAddressListsEnabled = $true; TrusteeIdentity = 'EXAMPLE\exo.map2'; TrusteeName = 'exo.map2'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=exo.map2,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-70-70-70-707'; TrusteeObjectClass = 'user'; AccessRights = 'SendAs'; IsInherited = $false; Deny = $false }))
        $rows.Count | Should -Be 1
        $rows[0].SourceSystem | Should -Be 'ExchangeOnline'
        $rows[0].PermissionType | Should -Be 'SendAs'
    }

    It 'Service pipeline succeeds with mocked EXO rows and correct counters' {
        Mock Read-MailboxPermissionBackfeedSources {
            @(
                [pscustomobject]@{ SourceSystem = 'ExchangeOnline'; PermissionType = 'FullAccess'; MailboxIdentity = 'exo-svc'; MailboxName = 'EXO Service'; MailboxDistinguishedName = 'CN=exo-svc,OU=Cloud,DC=example,DC=local'; MailboxGuid = '80000000-0000-0000-0000-000000000008'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\exo.svc1'; TrusteeName = 'exo.svc1'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=exo.svc1,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-80-80-80-808'; TrusteeObjectClass = 'user'; AccessRights = 'FullAccess'; IsInherited = $false; Deny = $false },
                [pscustomobject]@{ SourceSystem = 'ExchangeOnline'; PermissionType = 'SendAs'; MailboxIdentity = 'exo-svc'; MailboxName = 'EXO Service'; MailboxDistinguishedName = 'CN=exo-svc,OU=Cloud,DC=example,DC=local'; MailboxGuid = '80000000-0000-0000-0000-000000000008'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\exo.svc2'; TrusteeName = 'exo.svc2'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=exo.svc2,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-81-81-81-818'; TrusteeObjectClass = 'user'; AccessRights = 'SendAs'; IsInherited = $false; Deny = $false }
            )
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{ BackfeedTypes = [pscustomobject]@{ MailboxPermission = [pscustomobject]@{ Sources = @('ExchangeOnline') } } }) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-exo-1' -BackfeedType 'MailboxPermission' -Mode 'Full'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.ReadCount | Should -Be 2
        $result.StagedCount | Should -Be 2
    }

    It 'OnPrem reader test file remains present' {
        Test-Path -Path (Join-Path -Path $root -ChildPath 'tests\Pester\Backfeed\MailboxPermissionOnPremReader.Tests.ps1') | Should -Be $true
    }

    It 'JobEngine remains free of backfeed business wiring' {
        (Get-Content -Path $script:jobEnginePath -Raw) -match 'Invoke-MailboxPermissionBackfeed|MailboxPermissionBackfeedService|MailboxPermissionSourceReader' | Should -Be $false
    }

    It 'JobFileQueue remains free of backfeed business wiring' {
        (Get-Content -Path $script:jobFileQueuePath -Raw) -match 'Invoke-MailboxPermissionBackfeed|MailboxPermissionBackfeedService|MailboxPermissionSourceReader' | Should -Be $false
    }

    It 'usecases.json contains no backfeed entries' {
        (Get-Content -Path $script:usecasesPath -Raw) -match 'Backfeed' | Should -Be $false
    }

    It 'Legacy script remains unchanged for backfeed integration' {
        (Get-Content -Path $script:legacyScriptPath -Raw) -match 'Invoke-MailboxPermissionBackfeed|Get-ExchangeOnlineMailboxPermissionBackfeedMailboxes' | Should -Be $false
    }

    It 'ExchangeOnPremGateway was not touched by EXO reader integration checks' {
        $content = Get-Content -Path $script:exchangeOnPremGatewayPath -Raw
        $content -match 'Get-ExchangeOnlineMailboxPermissionBackfeedMailboxes|Get-ExchangeOnlineMailboxFullAccessPermissionsSafe|Get-ExchangeOnlineMailboxSendAsPermissionsSafe' | Should -Be $false
    }

    It 'ActiveDirectoryGateway and SqlGateway remain without MailboxPermission backfeed additions' {
        (Get-Content -Path $script:activeDirectoryGatewayPath -Raw) -match 'MailboxPermissionBackfeed|Get-ExchangeOnlineMailboxPermissionBackfeedMailboxes' | Should -Be $false
        (Get-Content -Path $script:sqlGatewayPath -Raw) -match 'MailboxPermissionBackfeed|Get-ExchangeOnlineMailboxPermissionBackfeedMailboxes' | Should -Be $false
    }
}
