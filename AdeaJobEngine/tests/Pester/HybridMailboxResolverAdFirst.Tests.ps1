Set-StrictMode -Version Latest

$script:root = Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')

Import-Module -Name (Join-Path $root 'infrastructure\ActiveDirectoryGateway.psm1') -Force -DisableNameChecking
Import-Module -Name (Join-Path $root 'infrastructure\HybridMailboxResolver.psm1') -Force -DisableNameChecking

BeforeAll {
    function New-TestAdObject {
        param(
            [string]$Sam = 'user',
            [string]$Upn = 'user@example.org',
            [string]$Mail = 'user@example.org',
            [string]$HomeMdb = '',
            [string]$TargetAddress = '',
            [string]$RemoteRecipientType = '',
            [string]$RecipientTypeDetails = '',
            [string]$MailboxGuid = ''
        )

        [pscustomobject]@{
            SamAccountName = $Sam
            userPrincipalName = $Upn
            mail = $Mail
            homeMDB = $HomeMdb
            targetAddress = $TargetAddress
            msExchRemoteRecipientType = $RemoteRecipientType
            msExchRecipientTypeDetails = $RecipientTypeDetails
            msExchMailboxGuid = $MailboxGuid
            distinguishedName = "CN=$Sam,OU=Users,DC=example,DC=org"
        }
    }

    function New-TestConfig {
        param([string]$CloudDomain = 'tenant.mail.onmicrosoft.com')
        @{
            ExchangeOnline = @{ Enabled = $true; CloudDomain = $CloudDomain }
            ExchangeOnPrem = @{ CloudDomain = $CloudDomain }
            PersonMailbox = @{ CloudDomain = $CloudDomain }
        }
    }
}

Describe 'HybridMailboxResolver AD-first resolution' {
    It 'RemoteMailbox detected when msExchRemoteRecipientType is set (Test 1)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -RemoteRecipientType '1'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        $result.IsRemoteMailbox | Should -Be $true
        $result.MailboxLocation | Should -Be 'ExchangeOnline'
    }

    It 'RemoteMailbox detected when msExchRemoteRecipientType >= 1 (Test 2)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -RemoteRecipientType '2'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        $result.IsRemoteMailbox | Should -Be $true
    }

    It 'RemoteMailbox detected when msExchRemoteRecipientType bit 1 is set (Test 3)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -RemoteRecipientType '1'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        $result.IsRemoteMailbox | Should -Be $true
    }

    It 'RemoteMailbox detected when msExchRemoteRecipientType bit 4 is set (Test 4)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -RemoteRecipientType '4'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        $result.IsRemoteMailbox | Should -Be $true
    }

    It 'RemoteMailbox detected when targetAddress ends with CloudDomain (Test 5)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -TargetAddress 'SMTP:user@tenant.mail.onmicrosoft.com'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig -CloudDomain 'tenant.mail.onmicrosoft.com')
        $result.IsRemoteMailbox | Should -Be $true
    }

    It 'OnPrem mailbox detected when homeMDB is set (Test 6)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -HomeMdb 'MDB1'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        $result.IsOnPremMailbox | Should -Be $true
        $result.MailboxLocation | Should -Be 'OnPrem'
    }

    It 'OnPrem mailbox detected when RecipientTypeDetails UserMailbox (Test 7)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -RecipientTypeDetails '1'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        $result.IsOnPremMailbox | Should -Be $true
    }

    It 'OnPrem mailbox detected when RecipientTypeDetails SharedMailbox (Test 8)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -RecipientTypeDetails '4'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        $result.IsOnPremMailbox | Should -Be $true
    }

    It 'OnPrem mailbox detected when MailboxGuid is set and no remote type (Test 9)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -MailboxGuid '11111111-1111-1111-1111-111111111111'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        $result.IsOnPremMailbox | Should -Be $true
    }

    It 'AD object without indicators yields MailboxLocation None (Test 10)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        $result.MailboxLocation | Should -Be 'None'
    }

    It 'Not found yields ErrorCode NotFound (Test 11)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject { @() }
        $result = Resolve-MailboxExecutionContext -Identity 'missing' -Config (New-TestConfig)
        $result.ErrorCode | Should -Be 'NotFound'
    }

    It 'Conflicting indicators yield IsAmbiguous and RequiresRemoteValidation (Test 12)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -HomeMdb 'MDB1' -RemoteRecipientType '1'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        $result.IsAmbiguous | Should -Be $true
        $result.RequiresRemoteValidation | Should -Be $true
    }

    It 'FastAdOnly does not call Get-OnPremRecipientSafe (Test 13)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject { New-TestAdObject -RemoteRecipientType '1' }
        Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {}
        $null = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        Should -Invoke Get-OnPremRecipientSafe -ModuleName 'HybridMailboxResolver' -Times 0
    }

    It 'FastAdOnly does not call Get-ExoRecipientSafe (Test 14)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject { New-TestAdObject -RemoteRecipientType '1' }
        Mock -ModuleName 'HybridMailboxResolver' Get-ExoRecipientSafe {}
        $null = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        Should -Invoke Get-ExoRecipientSafe -ModuleName 'HybridMailboxResolver' -Times 0
    }

    It 'ValidateRemote allows remote validation (Test 15)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -HomeMdb 'MDB1' -RemoteRecipientType '1'
        }
        Mock -ModuleName 'HybridMailboxResolver' Get-OnPremRecipientSafe {
            [pscustomobject]@{ RecipientTypeDetails = 'UserMailbox' }
        }
        $null = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig) -Mode ValidateRemote
        Should -Invoke Get-OnPremRecipientSafe -ModuleName 'HybridMailboxResolver' -Times 1
    }

    It 'CloudDomain is read from config (Test 16)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -TargetAddress 'SMTP:user@custom.cloud.example'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig -CloudDomain 'custom.cloud.example')
        $result.IsRemoteMailbox | Should -Be $true
    }

    It 'Result contains key routing properties (Test 17)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject { New-TestAdObject -HomeMdb 'MDB1' }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig)
        ($result.PSObject.Properties.Name -contains 'PermissionExecutionTarget') | Should -Be $true
        ($result.PSObject.Properties.Name -contains 'RecipientAttributeAuthority') | Should -Be $true
        ($result.PSObject.Properties.Name -contains 'AccountAuthority') | Should -Be $true
    }

    It 'targetAddress comparison is case-insensitive (Test 18)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject {
            New-TestAdObject -TargetAddress 'SMTP:USER@CUSTOM.CLOUD.EXAMPLE'
        }
        $result = Resolve-MailboxExecutionContext -Identity 'user' -Config (New-TestConfig -CloudDomain 'custom.cloud.example')
        $result.IsCloudRouted | Should -Be $true
    }

    It 'LDAP identity is handled via gateway lookup (Test 19)' {
        Mock -ModuleName 'HybridMailboxResolver' Get-MailboxExecutionAdObject { New-TestAdObject }
        Mock -ModuleName 'HybridMailboxResolver' Search-AdUserByLdapFilterSafe { throw 'should not be called' }
        $null = Resolve-MailboxExecutionContext -Identity 'user*(test)' -Config (New-TestConfig)
        Should -Invoke Get-MailboxExecutionAdObject -ModuleName 'HybridMailboxResolver' -Times 1
    }

    It 'TenantState is not used for mailbox location (Test 20)' {
        $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        $resolverPath = Join-Path $repoRoot 'infrastructure\HybridMailboxResolver.psm1'
        if ([string]::IsNullOrWhiteSpace($resolverPath) -or -not (Test-Path -Path $resolverPath)) {
            throw "HybridMailboxResolver.psm1 not found. Path: '$resolverPath'"
        }
        $content = Get-Content -Path $resolverPath -Raw
        $content | Should -Not -Match '(?i)TenantState'
    }
}
