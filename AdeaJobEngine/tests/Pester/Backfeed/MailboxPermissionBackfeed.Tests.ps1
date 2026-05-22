Describe 'MailboxPermission Backfeed Read-Map' {
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
        Set-Variable -Scope Script -Name writerPath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionStagingWriter.psm1')
        Set-Variable -Scope Script -Name servicePath -Value (Join-Path -Path $root -ChildPath 'backfeed\MailboxPermission\MailboxPermissionBackfeedService.psm1')
        Set-Variable -Scope Script -Name jobEnginePath -Value (Join-Path -Path $root -ChildPath 'core\JobEngine.psm1')
        Set-Variable -Scope Script -Name jobFileQueuePath -Value (Join-Path -Path $root -ChildPath 'core\JobFileQueue.psm1')
        Set-Variable -Scope Script -Name usecasesPath -Value (Join-Path -Path $root -ChildPath 'config\usecases.json')

        Set-Variable -Scope Script -Name exchangeOnPremGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnPremGateway.psm1')
        Set-Variable -Scope Script -Name exchangeOnlineGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1')
        Set-Variable -Scope Script -Name activeDirectoryGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\ActiveDirectoryGateway.psm1')
        Set-Variable -Scope Script -Name sqlGatewayPath -Value (Join-Path -Path $root -ChildPath 'infrastructure\SqlGateway.psm1')
        Set-Variable -Scope Script -Name legacyScriptPath -Value (Join-Path -Path $script:workspaceRoot -ChildPath 'current-scripts\Import-MailboxPermissions-Into-Staging-Update-Model.ps1')

        Remove-Module -Name 'MailboxPermissionSourceReader' -ErrorAction SilentlyContinue
        Remove-Module -Name 'MailboxPermissionMapper' -ErrorAction SilentlyContinue
        Remove-Module -Name 'MailboxPermissionStagingWriter' -ErrorAction SilentlyContinue
        Remove-Module -Name 'MailboxPermissionBackfeedService' -ErrorAction SilentlyContinue
        Remove-Module -Name 'BackfeedContext' -ErrorAction SilentlyContinue
        Remove-Module -Name 'BackfeedResult' -ErrorAction SilentlyContinue

        Import-Module -Name (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedContext.psm1') -Force -DisableNameChecking -Global
        Import-Module -Name (Join-Path -Path $root -ChildPath 'shared\Backfeed\BackfeedResult.psm1') -Force -DisableNameChecking -Global
        Import-Module -Name $script:readerPath -Force -DisableNameChecking -Global
        Import-Module -Name $script:mapperPath -Force -DisableNameChecking -Global
        Import-Module -Name $script:writerPath -Force -DisableNameChecking -Global
        Import-Module -Name $script:servicePath -Force -DisableNameChecking -Global

        $mapperScriptText = Get-Content -Path $script:mapperPath -Raw
        $mapperScriptText = [regex]::Replace($mapperScriptText, '(?m)^Export-ModuleMember.*$', '')
        . ([scriptblock]::Create($mapperScriptText))

    }

    It 'SourceReader contains Read-MailboxPermissionBackfeedSources' {
        $content = Get-Content -Path $script:readerPath -Raw
        $content -match 'function\s+Read-MailboxPermissionBackfeedSources' | Should -Be $true
    }

    It 'SourceReader contains separated OnPrem and ExchangeOnline paths' {
        $content = Get-Content -Path $script:readerPath -Raw
        $content -match 'Read-OnPremMailboxFullAccessPermissions' | Should -Be $true
        $content -match 'Read-OnPremMailboxSendAsPermissions' | Should -Be $true
        $content -match 'Read-ExchangeOnlineMailboxFullAccessPermissions' | Should -Be $true
        $content -match 'Read-ExchangeOnlineMailboxSendAsPermissions' | Should -Be $true
    }

    It 'SourceReader contains FullAccess and SendAs flows' {
        $content = Get-Content -Path $script:readerPath -Raw
        $content -match "-PermissionType\s+'FullAccess'" | Should -Be $true
        $content -match "-PermissionType\s+'SendAs'" | Should -Be $true
    }

    It 'SourceReader contains no forbidden direct cmdlets' {
        $content = Get-Content -Path $script:readerPath -Raw
        $content -match '\b(Get-MailboxPermission|Get-RecipientPermission|Get-Mailbox|Get-EXOMailbox|Get-EXOMailboxPermission|Get-Recipient|Connect-ExchangeOnline|New-PSSession|Get-ADUser|Get-ADObject|Invoke-Sqlcmd)\b' | Should -Be $false
    }

    It 'Mapper returns empty array for empty input' {
        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions @())
        $rows.Count | Should -Be 0
    }

    It 'Mapper normalizes OnPrem FullAccess' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'OnPrem'
            PermissionType = 'FullAccess'
            MailboxIdentity = 'mbx-a'
            MailboxName = 'Mailbox A'
            MailboxDistinguishedName = 'CN=Mailbox A,OU=Mailboxes,DC=example,DC=local'
            MailboxGuid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            MailboxHiddenFromAddressListsEnabled = $true
            TrusteeIdentity = 'user-a'
            TrusteeName = 'User A'
            TrusteeDomain = 'EXAMPLE'
            TrusteeDistinguishedName = 'CN=User A,OU=Users,DC=example,DC=local'
            TrusteeSid = 'S-1-5-21-111-222-333-444'
            TrusteeObjectClass = 'user'
            AccessRights = 'FullAccess'
            IsInherited = $false
            Deny = $false
        })

        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)
        $rows.Count | Should -Be 1
        $rows[0].SourceSystem | Should -Be 'OnPrem'
        $rows[0].PermissionType | Should -Be 'FullAccess'
        $rows[0].AcePermissions | Should -Be 'FullAccess'
    }

    It 'Mapper normalizes OnPrem SendAs' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'OnPrem'
            PermissionType = 'SendAs'
            MailboxIdentity = 'mbx-b'
            MailboxName = 'Mailbox B'
            MailboxDistinguishedName = 'CN=Mailbox B,OU=Mailboxes,DC=example,DC=local'
            MailboxGuid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
            MailboxHiddenFromAddressListsEnabled = $false
            TrusteeIdentity = 'user-b'
            TrusteeName = 'User B'
            TrusteeDomain = 'EXAMPLE'
            TrusteeDistinguishedName = 'CN=User B,OU=Users,DC=example,DC=local'
            TrusteeSid = 'S-1-5-21-111-222-333-445'
            TrusteeObjectClass = 'user'
            AccessRights = 'SendAs'
            IsInherited = $false
            Deny = $false
        })

        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)
        $rows.Count | Should -Be 1
        $rows[0].SourceSystem | Should -Be 'OnPrem'
        $rows[0].PermissionType | Should -Be 'SendAs'
        $rows[0].AcePermissions | Should -Be 'SendAs'
    }

    It 'Mapper normalizes ExchangeOnline FullAccess' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'ExchangeOnline'
            PermissionType = 'FullAccess'
            MailboxIdentity = 'mbx-c'
            MailboxName = 'Mailbox C'
            MailboxDistinguishedName = 'CN=Mailbox C,OU=Mailboxes,DC=example,DC=local'
            MailboxGuid = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
            MailboxHiddenFromAddressListsEnabled = $false
            TrusteeIdentity = 'user-c'
            TrusteeName = 'User C'
            TrusteeDomain = 'EXAMPLE'
            TrusteeDistinguishedName = 'CN=User C,OU=Users,DC=example,DC=local'
            TrusteeSid = 'S-1-5-21-111-222-333-446'
            TrusteeObjectClass = 'user'
            AccessRights = 'FullAccess'
            IsInherited = $true
            Deny = $false
        })

        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)
        $rows.Count | Should -Be 1
        $rows[0].SourceSystem | Should -Be 'ExchangeOnline'
        $rows[0].PermissionType | Should -Be 'FullAccess'
    }

    It 'Mapper normalizes ExchangeOnline SendAs' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'ExchangeOnline'
            PermissionType = 'SendAs'
            MailboxIdentity = 'mbx-d'
            MailboxName = 'Mailbox D'
            MailboxDistinguishedName = 'CN=Mailbox D,OU=Mailboxes,DC=example,DC=local'
            MailboxGuid = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
            MailboxHiddenFromAddressListsEnabled = $true
            TrusteeIdentity = 'user-d'
            TrusteeName = 'User D'
            TrusteeDomain = 'EXAMPLE'
            TrusteeDistinguishedName = 'CN=User D,OU=Users,DC=example,DC=local'
            TrusteeSid = 'S-1-5-21-111-222-333-447'
            TrusteeObjectClass = 'user'
            AccessRights = 'SendAs'
            IsInherited = $false
            Deny = $false
        })

        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)
        $rows.Count | Should -Be 1
        $rows[0].SourceSystem | Should -Be 'ExchangeOnline'
        $rows[0].PermissionType | Should -Be 'SendAs'
    }

    It 'Mapper prefers MailboxGuid for MailboxKey' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'OnPrem'
            PermissionType = 'FullAccess'
            MailboxIdentity = 'mbx-e'
            MailboxDistinguishedName = 'CN=Mailbox E,OU=Mailboxes,DC=example,DC=local'
            MailboxGuid = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
            TrusteeIdentity = 'user-e'
            TrusteeSid = 'S-1-5-21-111-222-333-448'
            AccessRights = 'FullAccess'
            IsInherited = $false
            Deny = $false
        })

        $row = (ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)[0]
        $row.MailboxKey | Should -Be 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
    }

    It 'Mapper falls back to DistinguishedName for MailboxKey when MailboxGuid is missing' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'OnPrem'
            PermissionType = 'FullAccess'
            MailboxIdentity = 'mbx-f'
            MailboxDistinguishedName = 'CN=Mailbox F,OU=Mailboxes,DC=example,DC=local'
            TrusteeIdentity = 'user-f'
            TrusteeSid = 'S-1-5-21-111-222-333-449'
            AccessRights = 'FullAccess'
            IsInherited = $false
            Deny = $false
        })

        $row = (ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)[0]
        $row.MailboxKey | Should -Be 'CN=Mailbox F,OU=Mailboxes,DC=example,DC=local'
    }

    It 'Mapper prefers TrusteeSid for TrusteeKey' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'OnPrem'
            PermissionType = 'FullAccess'
            MailboxIdentity = 'mbx-g'
            MailboxGuid = 'gggggggg-0000-0000-0000-000000000000'
            TrusteeIdentity = 'user-g'
            TrusteeDistinguishedName = 'CN=User G,OU=Users,DC=example,DC=local'
            TrusteeSid = 'S-1-5-21-111-222-333-450'
            AccessRights = 'FullAccess'
            IsInherited = $false
            Deny = $false
        })

        $row = (ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)[0]
        $row.TrusteeKey | Should -Be 'S-1-5-21-111-222-333-450'
    }

    It 'Mapper falls back to DistinguishedName for TrusteeKey when SID is missing' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'OnPrem'
            PermissionType = 'FullAccess'
            MailboxIdentity = 'mbx-h'
            MailboxGuid = 'hhhhhhhh-0000-0000-0000-000000000000'
            TrusteeIdentity = 'user-h'
            TrusteeDistinguishedName = 'CN=User H,OU=Users,DC=example,DC=local'
            AccessRights = 'FullAccess'
            IsInherited = $false
            Deny = $false
        })

        $row = (ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)[0]
        $row.TrusteeKey | Should -Be 'CN=User H,OU=Users,DC=example,DC=local'
    }

    It 'Mapper falls back to Domain plus Name for TrusteeKey when SID and DN are missing' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'OnPrem'
            PermissionType = 'SendAs'
            MailboxIdentity = 'mbx-i'
            MailboxGuid = 'iiiiiiii-0000-0000-0000-000000000000'
            TrusteeName = 'user.i'
            TrusteeDomain = 'EXAMPLE'
            AccessRights = 'SendAs'
            IsInherited = $false
            Deny = $false
        })

        $row = (ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)[0]
        $row.TrusteeKey | Should -Be 'EXAMPLE\user.i'
    }

    It 'Mapper RowHash is deterministic' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'ExchangeOnline'
            PermissionType = 'SendAs'
            MailboxIdentity = 'mbx-j'
            MailboxGuid = 'jjjjjjjj-0000-0000-0000-000000000000'
            TrusteeIdentity = 'user-j'
            TrusteeSid = 'S-1-5-21-111-222-333-451'
            AccessRights = 'SendAs'
            IsInherited = $false
            Deny = $false
        })

        $row1 = (ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)[0]
        $row2 = (ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)[0]

        $row1.RowHash | Should -Be $row2.RowHash
    }

    It 'Mapper accepts only FullAccess and SendAs' {
        $raw = @(
            [pscustomobject]@{
                SourceSystem = 'OnPrem'
                PermissionType = 'FullAccess'
                MailboxIdentity = 'mbx-k1'
                TrusteeIdentity = 'user-k1'
                AccessRights = 'FullAccess'
                IsInherited = $false
                Deny = $false
            },
            [pscustomobject]@{
                SourceSystem = 'OnPrem'
                PermissionType = 'ReadPermission'
                MailboxIdentity = 'mbx-k2'
                TrusteeIdentity = 'user-k2'
                AccessRights = 'ReadPermission'
                IsInherited = $false
                Deny = $false
            },
            [pscustomobject]@{
                SourceSystem = 'ExchangeOnline'
                PermissionType = 'SendAs'
                MailboxIdentity = 'mbx-k3'
                TrusteeIdentity = 'user-k3'
                AccessRights = 'SendAs'
                IsInherited = $false
                Deny = $false
            }
        )

        $rows = @(ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)

        $rows.Count | Should -Be 2
        @($rows | Where-Object { $_.PermissionType -eq 'FullAccess' }).Count | Should -Be 1
        @($rows | Where-Object { $_.PermissionType -eq 'SendAs' }).Count | Should -Be 1
    }

    It 'Mapper DTO contains required key fields' {
        $raw = @([pscustomobject]@{
            SourceSystem = 'OnPrem'
            PermissionType = 'FullAccess'
            MailboxIdentity = 'mbx-l'
            MailboxGuid = 'llllllll-0000-0000-0000-000000000000'
            TrusteeIdentity = 'user-l'
            TrusteeSid = 'S-1-5-21-111-222-333-452'
            AccessRights = 'FullAccess'
            IsInherited = $false
            Deny = $false
        })

        $row = (ConvertTo-MailboxPermissionBackfeedRows -RawPermissions $raw)[0]
        @($row.PSObject.Properties.Name) | Should -Contain 'SourceSystem'
        @($row.PSObject.Properties.Name) | Should -Contain 'PermissionType'
        @($row.PSObject.Properties.Name) | Should -Contain 'MailboxKey'
        @($row.PSObject.Properties.Name) | Should -Contain 'TrusteeKey'
        @($row.PSObject.Properties.Name) | Should -Contain 'AcePermissions'
        @($row.PSObject.Properties.Name) | Should -Contain 'RowHash'
    }

    It 'Service pipeline returns Succeeded with ReadCount and StagedCount' {
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Read-MailboxPermissionBackfeedSources {
            @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName ConvertTo-MailboxPermissionBackfeedRows {
            @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem'; RowHash = 'hash' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $true; StagedCount = 1; Message = 'Rows staged.'; ErrorCode = $null }
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Get-MailboxPermissionBackfeedDelta {
            [pscustomobject]@{ Success = $true; BackfeedRunId = 'aaaaaaaa-1111-1111-1111-111111111111'; InsertedCount = 1; UpdatedCount = 0; DeletedCount = 0; UnchangedCount = 0; FailedCount = 0; Message = 'Delta counts resolved.'; ErrorCode = $null; Errors = @() }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-1' -BackfeedType 'MailboxPermission' -Mode 'Full'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Succeeded'
        $result.ReadCount | Should -Be 1
        $result.StagedCount | Should -Be 1
        $result.InsertedCount | Should -Be 1
        $result.FailedCount | Should -Be 0
    }

    It 'Service returns Failed on reader error' {
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Read-MailboxPermissionBackfeedSources {
            throw 'reader exploded'
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-2' -BackfeedType 'MailboxPermission' -Mode 'Full'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Failed'
        $result.FailedCount | Should -Be 1
        $result.Errors.Count | Should -Be 1
    }

    It 'Service returns Failed on writer error' {
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Read-MailboxPermissionBackfeedSources {
            @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName ConvertTo-MailboxPermissionBackfeedRows {
            @([pscustomobject]@{ PermissionType = 'FullAccess'; SourceSystem = 'OnPrem'; RowHash = 'hash' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Write-MailboxPermissionBackfeedStaging {
            throw 'writer exploded'
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-3' -BackfeedType 'MailboxPermission' -Mode 'Full'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Failed'
        $result.FailedCount | Should -Be 1
        $result.Errors.Count | Should -Be 1
    }

    It 'Service maps delta counters from delta service result' {
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Read-MailboxPermissionBackfeedSources {
            @([pscustomobject]@{ PermissionType = 'SendAs'; SourceSystem = 'ExchangeOnline' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName ConvertTo-MailboxPermissionBackfeedRows {
            @([pscustomobject]@{ PermissionType = 'SendAs'; SourceSystem = 'ExchangeOnline'; RowHash = 'hash' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $true; StagedCount = 1; Message = 'Rows staged.'; ErrorCode = $null }
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Get-MailboxPermissionBackfeedDelta {
            [pscustomobject]@{ Success = $true; BackfeedRunId = '55555555-aaaa-bbbb-cccc-555555555555'; InsertedCount = 1; UpdatedCount = 2; DeletedCount = 3; UnchangedCount = 4; FailedCount = 0; Message = 'Delta counts resolved.'; ErrorCode = $null; Errors = @() }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-4' -BackfeedType 'MailboxPermission' -Mode 'Delta'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.InsertedCount | Should -Be 1
        $result.UpdatedCount | Should -Be 2
        $result.DeletedCount | Should -Be 3
        $result.UnchangedCount | Should -Be 4
    }

    It 'Service returns Failed when delta service fails after staging' {
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Read-MailboxPermissionBackfeedSources {
            @([pscustomobject]@{ PermissionType = 'SendAs'; SourceSystem = 'ExchangeOnline' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName ConvertTo-MailboxPermissionBackfeedRows {
            @([pscustomobject]@{ PermissionType = 'SendAs'; SourceSystem = 'ExchangeOnline'; RowHash = 'hash' })
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Write-MailboxPermissionBackfeedStaging {
            [pscustomobject]@{ Success = $true; BackfeedRunId = '66666666-aaaa-bbbb-cccc-666666666666'; StagedCount = 1; FailedCount = 0; Message = 'Rows staged.'; ErrorCode = $null; Errors = @() }
        }
        Mock -ModuleName MailboxPermissionBackfeedService -CommandName Get-MailboxPermissionBackfeedDelta {
            [pscustomobject]@{ Success = $false; BackfeedRunId = '66666666-aaaa-bbbb-cccc-666666666666'; InsertedCount = 1; UpdatedCount = 0; DeletedCount = 0; UnchangedCount = 0; FailedCount = 1; Message = 'delta failed'; ErrorCode = 'MAILBOX_PERMISSION_DELTA_FAILED'; Errors = @([pscustomobject]@{ Message = 'delta failed'; ErrorCode = 'MAILBOX_PERMISSION_DELTA_FAILED'; BackfeedRunId = '66666666-aaaa-bbbb-cccc-666666666666' }) }
        }

        $context = New-BackfeedContext -Environment 'Test' -Config ([pscustomobject]@{}) -Logger ([pscustomobject]@{}) -StartedAt (Get-Date) -CorrelationId 'svc-5' -BackfeedType 'MailboxPermission' -Mode 'Delta'
        $result = Invoke-MailboxPermissionBackfeed -Context $context

        $result.Status | Should -Be 'Failed'
        $result.Errors.Count | Should -Be 1
        $result.BackfeedRunId | Should -Be '66666666-aaaa-bbbb-cccc-666666666666'
    }

    It 'Service contains no direct Exchange AD or SQL cmdlets' {
        $content = Get-Content -Path $script:servicePath -Raw
        $content -match '\b(Get-MailboxPermission|Get-RecipientPermission|Get-Mailbox|Get-EXOMailbox|Get-EXOMailboxPermission|Get-Recipient|Connect-ExchangeOnline|New-PSSession|Get-ADUser|Get-ADObject|Invoke-Sqlcmd)\b' | Should -Be $false
    }

    It 'JobEngine stays free of MailboxPermission backfeed logic' {
        (Get-Content -Path $script:jobEnginePath -Raw) -match 'Invoke-MailboxPermissionBackfeed|MailboxPermissionBackfeedService|MailboxPermissionSourceReader|MailboxPermissionMapper|MailboxPermissionStagingWriter' | Should -Be $false
    }

    It 'JobFileQueue stays free of Backfeed logic' {
        (Get-Content -Path $script:jobFileQueuePath -Raw) -match 'Invoke-MailboxPermissionBackfeed|MailboxPermissionBackfeedService|MailboxPermissionSourceReader|MailboxPermissionMapper|MailboxPermissionStagingWriter' | Should -Be $false
    }

    It 'usecases.json contains no Backfeed entries' {
        (Get-Content -Path $script:usecasesPath -Raw) -match 'Backfeed' | Should -Be $false
    }

    It 'Only Exchange gateways may contain MailboxPermission Backfeed references' {
        (Get-Content -Path $script:exchangeOnPremGatewayPath -Raw) -match 'Get-OnPremMailboxPermissionBackfeedMailboxes|Get-OnPremMailboxFullAccessPermissionsSafe|Get-OnPremMailboxSendAsPermissionsSafe' | Should -Be $true
        (Get-Content -Path $script:exchangeOnlineGatewayPath -Raw) -match 'Get-ExchangeOnlineMailboxPermissionBackfeedMailboxes|Get-ExchangeOnlineMailboxFullAccessPermissionsSafe|Get-ExchangeOnlineMailboxSendAsPermissionsSafe' | Should -Be $true
        (Get-Content -Path $script:activeDirectoryGatewayPath -Raw) -match 'MailboxPermissionBackfeed' | Should -Be $false
        (Get-Content -Path $script:sqlGatewayPath -Raw) -match 'MailboxPermissionBackfeed' | Should -Be $false
    }

    It 'Legacy script contains no new Backfeed integration' {
        (Get-Content -Path $script:legacyScriptPath -Raw) -match 'Invoke-MailboxPermissionBackfeed|Read-MailboxPermissionBackfeedSources|ConvertTo-MailboxPermissionBackfeedRows' | Should -Be $false
    }
}
