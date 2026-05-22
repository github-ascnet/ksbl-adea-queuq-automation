Describe 'MailboxPermission OnPrem Gateway integration' {
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
        Set-Variable -Scope Script -Name exchangeOnPremGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnPremGateway.psm1')
        Set-Variable -Scope Script -Name exchangeOnlineGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1')
        Set-Variable -Scope Script -Name jobEnginePath -Value (Join-Path -Path $root -ChildPath 'core\JobEngine.psm1')
        Set-Variable -Scope Script -Name jobFileQueuePath -Value (Join-Path -Path $root -ChildPath 'core\JobFileQueue.psm1')
        Set-Variable -Scope Script -Name usecasesPath -Value (Join-Path -Path $root -ChildPath 'config\usecases.json')
        Set-Variable -Scope Script -Name legacyScriptPath -Value (Join-Path -Path $script:workspaceRoot -ChildPath 'current-scripts\Import-MailboxPermissions-Into-Staging-Update-Model.ps1')

        Remove-Module -Name 'ExchangeOnPremGateway' -ErrorAction SilentlyContinue
        Remove-Module -Name 'BackfeedContext' -ErrorAction SilentlyContinue
        Remove-Module -Name 'BackfeedResult' -ErrorAction SilentlyContinue

        Import-Module -Name (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedContext.psm1') -Force -DisableNameChecking -Global
        Import-Module -Name (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedResult.psm1') -Force -DisableNameChecking -Global
        Import-Module -Name $script:exchangeOnPremGatewayPath -Force -DisableNameChecking -Global

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

    It 'OnPrem FullAccess path calls mailbox list and FullAccess gateway call' {
        Mock Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead {
            @([pscustomobject]@{ Identity = 'mbx-1'; DistinguishedName = 'CN=mbx-1,OU=Mailboxes,DC=example,DC=local' })
        }
        Mock Invoke-OnPremMailboxFullAccessGatewayRead {
            @([pscustomobject]@{ MailboxIdentity = 'mbx-1'; MailboxName = 'Mailbox 1'; MailboxDistinguishedName = 'CN=mbx-1,OU=Mailboxes,DC=example,DC=local'; MailboxGuid = '11111111-1111-1111-1111-111111111111'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\user1'; TrusteeName = 'user1'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=user1,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-1-2-3-4'; TrusteeObjectClass = 'user'; AccessRights = 'FullAccess'; IsInherited = $false; Deny = $false })
        }
        Mock Invoke-OnPremMailboxSendAsGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedOnPremRawRows -Context ([pscustomobject]@{}))

        $rows.Count | Should -Be 1
        Should -Invoke -CommandName Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead -Times 2
        Should -Invoke -CommandName Invoke-OnPremMailboxFullAccessGatewayRead -Times 1
    }

    It 'OnPrem SendAs path calls mailbox list and SendAs gateway call' {
        Mock Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead {
            @([pscustomobject]@{ Identity = 'mbx-2'; DistinguishedName = 'CN=mbx-2,OU=Mailboxes,DC=example,DC=local' })
        }
        Mock Invoke-OnPremMailboxSendAsGatewayRead {
            @([pscustomobject]@{ MailboxIdentity = 'mbx-2'; MailboxName = 'Mailbox 2'; MailboxDistinguishedName = 'CN=mbx-2,OU=Mailboxes,DC=example,DC=local'; MailboxGuid = '22222222-2222-2222-2222-222222222222'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\user2'; TrusteeName = 'user2'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=user2,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-1-2-3-5'; TrusteeObjectClass = 'user'; AccessRights = 'SendAs'; IsInherited = $false; Deny = $false })
        }
        Mock Invoke-OnPremMailboxFullAccessGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedOnPremRawRows -Context ([pscustomobject]@{}))

        $rows.Count | Should -Be 1
        Should -Invoke -CommandName Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead -Times 2
        Should -Invoke -CommandName Invoke-OnPremMailboxSendAsGatewayRead -Times 1
    }

    It 'FullAccess rows carry SourceSystem OnPrem and PermissionType FullAccess' {
        Mock Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead { @([pscustomobject]@{ Identity = 'mbx-3'; DistinguishedName = 'CN=mbx-3,OU=Mailboxes,DC=example,DC=local' }) }
        Mock Invoke-OnPremMailboxFullAccessGatewayRead { @([pscustomobject]@{ MailboxIdentity = 'mbx-3'; MailboxName = 'Mailbox 3'; MailboxDistinguishedName = 'CN=mbx-3,OU=Mailboxes,DC=example,DC=local'; MailboxGuid = '33333333-3333-3333-3333-333333333333'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\user3'; TrusteeName = 'user3'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=user3,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-1-2-3-6'; TrusteeObjectClass = 'user'; AccessRights = 'FullAccess'; IsInherited = $false; Deny = $false }) }
        Mock Invoke-OnPremMailboxSendAsGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedOnPremRawRows -Context ([pscustomobject]@{}))
        $rows[0].SourceSystem | Should -Be 'OnPrem'
        $rows[0].PermissionType | Should -Be 'FullAccess'
    }

    It 'SendAs rows carry SourceSystem OnPrem and PermissionType SendAs' {
        Mock Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead { @([pscustomobject]@{ Identity = 'mbx-4'; DistinguishedName = 'CN=mbx-4,OU=Mailboxes,DC=example,DC=local' }) }
        Mock Invoke-OnPremMailboxSendAsGatewayRead { @([pscustomobject]@{ MailboxIdentity = 'mbx-4'; MailboxName = 'Mailbox 4'; MailboxDistinguishedName = 'CN=mbx-4,OU=Mailboxes,DC=example,DC=local'; MailboxGuid = '44444444-4444-4444-4444-444444444444'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\user4'; TrusteeName = 'user4'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=user4,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-1-2-3-7'; TrusteeObjectClass = 'user'; AccessRights = 'SendAs'; IsInherited = $false; Deny = $false }) }
        Mock Invoke-OnPremMailboxFullAccessGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedOnPremRawRows -Context ([pscustomobject]@{}))
        $rows[0].SourceSystem | Should -Be 'OnPrem'
        $rows[0].PermissionType | Should -Be 'SendAs'
    }

    It 'Multiple mailboxes are processed' {
        Mock Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead {
            @([pscustomobject]@{ Identity = 'mbx-a'; DistinguishedName = 'CN=mbx-a,OU=Mailboxes,DC=example,DC=local' }, [pscustomobject]@{ Identity = 'mbx-b'; DistinguishedName = 'CN=mbx-b,OU=Mailboxes,DC=example,DC=local' })
        }
        Mock Invoke-OnPremMailboxFullAccessGatewayRead {
            param([string]$Identity)
            @([pscustomobject]@{ MailboxIdentity = $Identity; MailboxName = $Identity; MailboxDistinguishedName = "CN=$Identity,OU=Mailboxes,DC=example,DC=local"; MailboxGuid = '55555555-5555-5555-5555-555555555555'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\user'; TrusteeName = 'user'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=user,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-1-2-3-8'; TrusteeObjectClass = 'user'; AccessRights = 'FullAccess'; IsInherited = $false; Deny = $false })
        }
        Mock Invoke-OnPremMailboxSendAsGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedOnPremRawRows -Context ([pscustomobject]@{}))
        $rows.Count | Should -Be 2
        Should -Invoke -CommandName Invoke-OnPremMailboxFullAccessGatewayRead -Times 2
    }

    It 'Mailbox without permissions yields no row' {
        Mock Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead { @([pscustomobject]@{ Identity = 'mbx-empty'; DistinguishedName = 'CN=mbx-empty,OU=Mailboxes,DC=example,DC=local' }) }
        Mock Invoke-OnPremMailboxFullAccessGatewayRead { @() }
        Mock Invoke-OnPremMailboxSendAsGatewayRead { @() }

        $rows = @(Get-MailboxPermissionBackfeedOnPremRawRows -Context ([pscustomobject]@{}))
        $rows.Count | Should -Be 0
    }

    It 'Gateway error per mailbox is propagated by SourceReader' {
        Mock Invoke-OnPremMailboxPermissionBackfeedMailboxesGatewayRead { @([pscustomobject]@{ Identity = 'mbx-fail'; DistinguishedName = 'CN=mbx-fail,OU=Mailboxes,DC=example,DC=local' }) }
        Mock Invoke-OnPremMailboxFullAccessGatewayRead { throw 'gateway failure' }
        Mock Invoke-OnPremMailboxSendAsGatewayRead { @() }

        { Get-MailboxPermissionBackfeedOnPremRawRows -Context ([pscustomobject]@{}) } | Should -Throw
    }

    It 'SourceReader contains no forbidden direct cmdlets' {
        $content = Get-Content -Path $script:readerPath -Raw
        $content -match '\b(Get-MailboxPermission|Get-RecipientPermission|Get-Mailbox|Get-ADUser|Get-ADObject|Get-Acl|Connect-ExchangeOnline|New-PSSession|Invoke-Sqlcmd)\b' | Should -Be $false
    }

    It 'Gateway exports required backfeed read functions' {
        $content = Get-Content -Path $script:exchangeOnPremGatewayPath -Raw
        $content -match "'Get-OnPremMailboxPermissionBackfeedMailboxes'" | Should -Be $true
        $content -match "'Get-OnPremMailboxFullAccessPermissionsSafe'" | Should -Be $true
        $content -match "'Get-OnPremMailboxSendAsPermissionsSafe'" | Should -Be $true
    }

    It 'Gateway read functions contain no ExchangeOnline references' {
        $content = Get-Content -Path $script:exchangeOnPremGatewayPath -Raw
        $content -match 'function\s+Get-OnPremMailboxPermissionBackfeedMailboxes[\s\S]*?ExchangeOnline' | Should -Be $false
        $content -match 'function\s+Get-OnPremMailboxFullAccessPermissionsSafe[\s\S]*?ExchangeOnline' | Should -Be $false
        $content -match 'function\s+Get-OnPremMailboxSendAsPermissionsSafe[\s\S]*?ExchangeOnline' | Should -Be $false
    }

    It 'Gateway read functions are mockable and use safe wrappers' {
        $content = Get-Content -Path $script:exchangeOnPremGatewayPath -Raw
        $content -match 'Get-OnPremMailboxPermissionBackfeedMailboxes[\s\S]*Get-Mailbox' | Should -Be $true
        $content -match 'Get-OnPremMailboxFullAccessPermissionsSafe[\s\S]*Get-OnPremMailboxPermissionSafe' | Should -Be $true
        $content -match 'Get-OnPremMailboxSendAsPermissionsSafe[\s\S]*Get-OnPremAdPermissionSafe' | Should -Be $true
    }

    It 'Mapper normalizes OnPrem FullAccess gateway rows' {
        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions @([pscustomobject]@{ SourceSystem = 'OnPrem'; PermissionType = 'FullAccess'; MailboxIdentity = 'mbx-map-1'; MailboxName = 'Mailbox Map 1'; MailboxDistinguishedName = 'CN=mbx-map-1,OU=Mailboxes,DC=example,DC=local'; MailboxGuid = 'aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\user-map-1'; TrusteeName = 'user-map-1'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=user-map-1,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-10-20-30-40'; TrusteeObjectClass = 'user'; AccessRights = 'FullAccess'; IsInherited = $false; Deny = $false }))
        $rows.Count | Should -Be 1
        $rows[0].PermissionType | Should -Be 'FullAccess'
    }

    It 'Mapper normalizes OnPrem SendAs gateway rows' {
        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions @([pscustomobject]@{ SourceSystem = 'OnPrem'; PermissionType = 'SendAs'; MailboxIdentity = 'mbx-map-2'; MailboxName = 'Mailbox Map 2'; MailboxDistinguishedName = 'CN=mbx-map-2,OU=Mailboxes,DC=example,DC=local'; MailboxGuid = 'bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb'; MailboxHiddenFromAddressListsEnabled = $true; TrusteeIdentity = 'EXAMPLE\user-map-2'; TrusteeName = 'user-map-2'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=user-map-2,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-11-22-33-44'; TrusteeObjectClass = 'user'; AccessRights = 'SendAs'; IsInherited = $false; Deny = $false }))
        $rows.Count | Should -Be 1
        $rows[0].PermissionType | Should -Be 'SendAs'
    }

    It 'Service pipeline succeeds with mocked OnPrem rows and correct counters' {
        Mock Read-MailboxPermissionBackfeedSources {
            @(
                [pscustomobject]@{ SourceSystem = 'OnPrem'; PermissionType = 'FullAccess'; MailboxIdentity = 'mbx-svc'; MailboxName = 'Mailbox Service'; MailboxDistinguishedName = 'CN=mbx-svc,OU=Mailboxes,DC=example,DC=local'; MailboxGuid = 'cccccccc-3333-3333-3333-cccccccccccc'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\svc-user'; TrusteeName = 'svc-user'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=svc-user,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-12-23-34-45'; TrusteeObjectClass = 'user'; AccessRights = 'FullAccess'; IsInherited = $false; Deny = $false },
                [pscustomobject]@{ SourceSystem = 'OnPrem'; PermissionType = 'SendAs'; MailboxIdentity = 'mbx-svc'; MailboxName = 'Mailbox Service'; MailboxDistinguishedName = 'CN=mbx-svc,OU=Mailboxes,DC=example,DC=local'; MailboxGuid = 'cccccccc-3333-3333-3333-cccccccccccc'; MailboxHiddenFromAddressListsEnabled = $false; TrusteeIdentity = 'EXAMPLE\svc-user2'; TrusteeName = 'svc-user2'; TrusteeDomain = 'EXAMPLE'; TrusteeDistinguishedName = 'CN=svc-user2,OU=Users,DC=example,DC=local'; TrusteeSid = 'S-1-5-21-13-24-35-46'; TrusteeObjectClass = 'user'; AccessRights = 'SendAs'; IsInherited = $false; Deny = $false }
            )
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{ BackfeedTypes = [pscustomobject]@{ MailboxPermission = [pscustomobject]@{ Sources = @('ExchangeOnPrem') } } }) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-onprem-1' -BackfeedType 'MailboxPermission' -Mode 'Full'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.ReadCount | Should -Be 2
        $result.StagedCount | Should -Be 2
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

    It 'Legacy script remains unchanged regarding backfeed integration' {
        (Get-Content -Path $script:legacyScriptPath -Raw) -match 'Invoke-MailboxPermissionBackfeed|Get-OnPremMailboxPermissionBackfeedMailboxes' | Should -Be $false
    }

    It 'ExchangeOnlineGateway contains no OnPrem backfeed additions' {
        $content = Get-Content -Path $script:exchangeOnlineGatewayPath -Raw
        $content -match 'Get-OnPremMailboxPermissionBackfeedMailboxes|Get-OnPremMailboxFullAccessPermissionsSafe|Get-OnPremMailboxSendAsPermissionsSafe' | Should -Be $false
    }
}
