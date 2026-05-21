$modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\infrastructure\ExchangeOnPremGateway.psm1'
Import-Module -Name $modulePath -Force

$adModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\infrastructure\ActiveDirectoryGateway.psm1'
Import-Module -Name $adModulePath -Force

$exoModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\infrastructure\ExchangeOnlineGateway.psm1'
Import-Module -Name $exoModulePath -Force

Describe 'Exchange On-Prem WhatIf safety' {
    It 'Set-OnPremMailboxSafe works in WhatIfMode without cmdlets' {
        $result = Set-OnPremMailboxSafe -Parameters @{ Identity = 'u1'; HiddenFromAddressListsEnabled = $true } -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Set-Mailbox'
    }

    It 'Add-OnPremMailboxPermissionSafe works in WhatIfMode without cmdlets' {
        $result = Add-OnPremMailboxPermissionSafe -Parameters @{ Identity = 'u1'; User = 'u2'; AccessRights = 'FullAccess' } -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Add-MailboxPermission'
    }

    It 'Remove-OnPremMailboxPermissionSafe works in WhatIfMode without cmdlets' {
        $result = Remove-OnPremMailboxPermissionSafe -Parameters @{ Identity = 'u1'; User = 'u2'; AccessRights = 'FullAccess' } -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Remove-MailboxPermission'
    }

    It 'Add-OnPremSendAsPermissionSafe works in WhatIfMode without cmdlets' {
        $result = Add-OnPremSendAsPermissionSafe -Parameters @{ Identity = 'u1'; Trustee = 'u2'; AccessRights = 'SendAs' } -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Add-RecipientPermission'
    }

    It 'Remove-OnPremSendAsPermissionSafe works in WhatIfMode without cmdlets' {
        $result = Remove-OnPremSendAsPermissionSafe -Parameters @{ Identity = 'u1'; Trustee = 'u2'; AccessRights = 'SendAs' } -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Remove-RecipientPermission'
    }
}

Describe 'Active Directory WhatIf safety' {
    It 'Set-AdUserSafe works in WhatIfMode without AD module' {
        $result = Set-AdUserSafe -Parameters @{ Identity = 'user1'; Description = 'Test' } -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Set-ADUser'
    }

    It 'New-AdUserSafe works in WhatIfMode without AD module' {
        $result = New-AdUserSafe -Parameters @{ Name = 'newuser'; SamAccountName = 'newuser' } -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'New-ADUser'
    }

    It 'Rename-AdObjectSafe works in WhatIfMode without AD module' {
        $result = Rename-AdObjectSafe -Parameters @{ Identity = 'CN=old,DC=dom,DC=com'; NewName = 'new' } -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Rename-ADObject'
    }

    It 'Enable-AdAccountSafe works in WhatIfMode without AD module' {
        $result = Enable-AdAccountSafe -Identity 'user1' -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Enable-ADAccount'
    }

    It 'Disable-AdAccountSafe works in WhatIfMode without AD module' {
        $result = Disable-AdAccountSafe -Identity 'user1' -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Disable-ADAccount'
    }
}

Describe 'Exchange Online WhatIf safety' {
    It 'Set-ExoMailboxSafe works in WhatIfMode without EXO connection' {
        $result = Set-ExoMailboxSafe -Parameters @{ Identity = 'u1'; HiddenFromAddressListsEnabled = $true } -Config @{} -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Set-Mailbox'
    }

    It 'Add-ExoMailboxPermissionSafe works in WhatIfMode without EXO connection' {
        $result = Add-ExoMailboxPermissionSafe -Parameters @{ Identity = 'u1'; User = 'u2'; AccessRights = 'FullAccess' } -Config @{} -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Add-MailboxPermission'
    }

    It 'Remove-ExoMailboxPermissionSafe works in WhatIfMode without EXO connection' {
        $result = Remove-ExoMailboxPermissionSafe -Parameters @{ Identity = 'u1'; User = 'u2'; AccessRights = 'FullAccess' } -Config @{} -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Remove-MailboxPermission'
    }

    It 'Add-ExoSendAsPermissionSafe works in WhatIfMode without EXO connection' {
        $result = Add-ExoSendAsPermissionSafe -Parameters @{ Identity = 'u1'; Trustee = 'u2' } -Config @{} -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Add-RecipientPermission'
    }

    It 'Remove-ExoSendAsPermissionSafe works in WhatIfMode without EXO connection' {
        $result = Remove-ExoSendAsPermissionSafe -Parameters @{ Identity = 'u1'; Trustee = 'u2' } -Config @{} -WhatIfMode $true
        $result.Simulated | Should -Be $true
        $result.Action | Should -Be 'Remove-RecipientPermission'
    }
}
