#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeConnectionHealth.psm1') -Force -DisableNameChecking
}

Describe 'ExchangeConnectionHealth - common result model' {
    It 'creates a full health result object (Test 1)' {
        InModuleScope ExchangeConnectionHealth {
            $result = New-ExchangeConnectionHealthResult -Target 'ExchangeOnline' -ConnectionType 'ExchangeOnlineManagementAppOnly'

            $expectedProps = @(
                'Target',
                'ConnectionType',
                'Enabled',
                'IsConnected',
                'IsUsable',
                'Status',
                'Message',
                'ErrorCode',
                'ErrorCategory',
                'ConnectionUri',
                'Organization',
                'AppId',
                'CertificateThumbprint',
                'User',
                'SessionState',
                'CreatedAt',
                'LastUsedAt',
                'CheckedAt',
                'DurationMilliseconds',
                'Details'
            )

            foreach ($prop in $expectedProps) {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }
    }

    It 'uses Get-ExchangeConnectionCurrentTimeInternal when CheckedAt is not provided' {
        InModuleScope ExchangeConnectionHealth {
            $fixed = Get-Date '2024-01-01T12:00:00Z'
            Mock Get-ExchangeConnectionCurrentTimeInternal { $fixed }

            $result = New-ExchangeConnectionHealthResult -Target 'ExchangeOnPrem' -ConnectionType 'RemotePowerShellInvokeCommand'

            $result.CheckedAt | Should -Be $fixed
            Should -Invoke Get-ExchangeConnectionCurrentTimeInternal -Times 1
        }
    }
}
