$root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1') -Force

Describe 'ExchangeOnPrem session management' {
    InModuleScope ExchangeOnPremGateway {
        BeforeEach {
            $script:TestOnPremConfig = @{
                ExchangeOnPrem = @{
                    RemotePowerShell = @{
                        Enabled                   = $true
                        User                      = 'TESTDOMAIN\ServiceAccount'
                        SecretPath                = 'C:\\TestSecrets\\service.sec'
                        ConnectionUri             = 'http://exchange.test.local/PowerShell'
                        Authentication            = 'Kerberos'
                        ReuseSession              = $true
                        UseImportPSSession        = $false
                        ExecutionMode             = 'InvokeCommand'
                        SessionIdleTimeoutMinutes = 120
                        MaxSessionAgeMinutes      = 240
                        ReconnectOnFailure        = $true
                        MaxReconnectAttempts      = 1
                    }
                }
            }
            $script:ExchangeOnPremSessionState.Session = $null
            $script:ExchangeOnPremSessionState.SessionInfo = $null
            $script:ExchangeOnPremSessionState.ImportedModuleName = $null
            Reset-ExchangeOnPremSession
            Set-ExchangeOnPremRuntimeConfig -Config $script:TestOnPremConfig
        }

        It 'reads RemotePowerShell config with defaults' {
            $config = @{
                ExchangeOnPrem = @{
                    RemotePowerShell = @{
                        Enabled       = $true
                        User          = 'TESTDOMAIN\ServiceAccount'
                        SecretPath    = 'C:\\TestSecrets\\service.sec'
                        ConnectionUri = 'http://exchange.test.local/PowerShell'
                        Authentication = 'Kerberos'
                    }
                }
            }

            $result = Get-ExchangeOnPremRemotePowerShellConfig -Config $config

            $result.ConnectionUri | Should -Be 'http://sv01250.ksbl.local/PowerShell'
            $result.ExecutionMode | Should -Be 'InvokeCommand'
            $result.UseImportPSSession | Should -Be $false
            $result.ReconnectOnFailure | Should -Be $true
        }

        It 'throws controlled error when RemotePowerShell is disabled' {
            $config = @{
                ExchangeOnPrem = @{
                    RemotePowerShell = @{
                        Enabled                   = $true
                        User                      = 'ksbl\ServiceIAMJobs10'
                        SecretPath                = 'D:\iam\Secrets\serviceiamjobs10.sec'
                        ConnectionUri             = 'http://sv01250.ksbl.local/PowerShell'
                        Authentication            = 'Kerberos'
                        ReuseSession              = $true
                        UseImportPSSession        = $false
                        ExecutionMode             = 'InvokeCommand'
                        SessionIdleTimeoutMinutes = 120
                        MaxSessionAgeMinutes      = 240
                        ReconnectOnFailure        = $true
                        MaxReconnectAttempts      = 1
                    }
                }
            }
            $config.ExchangeOnPrem.RemotePowerShell.Enabled = $false

            { Get-ExchangeOnPremRemotePowerShellConfig -Config $config } | Should -Throw '*disabled*'
        }

        It 'creates PSCredential from SecretPath content' {
            Mock -ModuleName ExchangeOnPremGateway Test-Path { $true }
            Mock -ModuleName ExchangeOnPremGateway Get-Content { '01000000d08c9ddf0115d1118c7a00c04fc297eb' }
            Mock -ModuleName ExchangeOnPremGateway ConvertTo-SecureString { [System.Security.SecureString]::new() }

            $credential = New-ExchangeOnPremCredential -Config $script:TestOnPremConfig

            $credential.UserName | Should -Be 'ksbl\ServiceIAMJobs10'
            Should -Invoke Get-Content -ModuleName ExchangeOnPremGateway -Times 1
            Should -Invoke ConvertTo-SecureString -ModuleName ExchangeOnPremGateway -Times 1
        }

        It 'creates a new session when none exists' {
            $session = [pscustomobject]@{ State = 'Opened'; Id = 1 }
            Mock -ModuleName ExchangeOnPremGateway New-ExchangeOnPremCredential { New-Object System.Management.Automation.PSCredential('ksbl\ServiceIAMJobs10', ([System.Security.SecureString]::new())) }
            Mock -ModuleName ExchangeOnPremGateway New-ExchangeOnPremPSSessionInternal { $session }

            $result = Get-ExchangeOnPremSession -Config $script:TestOnPremConfig

            $result | Should -Be $session
            Should -Invoke New-ExchangeOnPremPSSessionInternal -ModuleName ExchangeOnPremGateway -Times 1
        }

        It 'reuses an open non-expired session' {
            $session = [pscustomobject]@{ State = 'Opened'; Id = 2 }
            Mock -ModuleName ExchangeOnPremGateway New-ExchangeOnPremCredential { New-Object System.Management.Automation.PSCredential('ksbl\ServiceIAMJobs10', ([System.Security.SecureString]::new())) }
            Mock -ModuleName ExchangeOnPremGateway New-ExchangeOnPremPSSessionInternal { $session }

            $null = Get-ExchangeOnPremSession -Config $script:TestOnPremConfig
            $null = Get-ExchangeOnPremSession -Config $script:TestOnPremConfig

            Should -Invoke New-ExchangeOnPremPSSessionInternal -ModuleName ExchangeOnPremGateway -Times 1
        }

        It 'rebuilds a broken session' {
            $script:ExchangeOnPremSessionState.Session = [pscustomobject]@{ State = 'Broken'; Id = 3 }
            $script:ExchangeOnPremSessionState.SessionInfo = @{
                CreatedAt  = Get-Date
                LastUsedAt = Get-Date
            }

            $newSession = [pscustomobject]@{ State = 'Opened'; Id = 4 }
            Mock -ModuleName ExchangeOnPremGateway Remove-ExchangeOnPremPSSessionInternal {}
            Mock -ModuleName ExchangeOnPremGateway New-ExchangeOnPremCredential { New-Object System.Management.Automation.PSCredential('ksbl\ServiceIAMJobs10', ([System.Security.SecureString]::new())) }
            Mock -ModuleName ExchangeOnPremGateway New-ExchangeOnPremPSSessionInternal { $newSession }

            $result = Get-ExchangeOnPremSession -Config $script:TestOnPremConfig

            $result.Id | Should -Be 4
            Should -Invoke Remove-ExchangeOnPremPSSessionInternal -ModuleName ExchangeOnPremGateway -Times 1
            Should -Invoke New-ExchangeOnPremPSSessionInternal -ModuleName ExchangeOnPremGateway -Times 1
        }

        It 'reconnects when session age exceeds MaxSessionAgeMinutes' {
            $script:ExchangeOnPremSessionState.Session = [pscustomobject]@{ State = 'Opened'; Id = 5 }
            $script:ExchangeOnPremSessionState.SessionInfo = @{
                CreatedAt  = (Get-Date).AddMinutes(-300)
                LastUsedAt = (Get-Date).AddMinutes(-10)
            }

            $newSession = [pscustomobject]@{ State = 'Opened'; Id = 6 }
            Mock -ModuleName ExchangeOnPremGateway Remove-ExchangeOnPremPSSessionInternal {}
            Mock -ModuleName ExchangeOnPremGateway New-ExchangeOnPremCredential { New-Object System.Management.Automation.PSCredential('TESTDOMAIN\ServiceAccount', ([System.Security.SecureString]::new())) }
            Mock -ModuleName ExchangeOnPremGateway New-ExchangeOnPremPSSessionInternal { $newSession }

            $result = Get-ExchangeOnPremSession -Config $script:TestOnPremConfig

            $result.Id | Should -Be 6
            Should -Invoke New-ExchangeOnPremPSSessionInternal -ModuleName ExchangeOnPremGateway -Times 1
        }

        It 'invokes remote command through Invoke-Command with session' {
            Mock -ModuleName ExchangeOnPremGateway Get-ExchangeOnPremSession { [pscustomobject]@{ State = 'Opened'; Id = 7 } }
            Mock -ModuleName ExchangeOnPremGateway Invoke-ExchangeOnPremCommandInternal { 'ok' }

            $result = Invoke-ExchangeOnPremCommand -Config $script:TestOnPremConfig -ScriptBlock { param($x) $x } -ArgumentList @('value')

            $result | Should -Be 'ok'
            Should -Invoke Invoke-ExchangeOnPremCommandInternal -ModuleName ExchangeOnPremGateway -Times 1
        }

        It 'reconnects exactly once on session failure when enabled' {
            $script:invokeAttempt = 0
            Mock -ModuleName ExchangeOnPremGateway Get-ExchangeOnPremSession { [pscustomobject]@{ State = 'Opened'; Id = 8 } }
            Mock -ModuleName ExchangeOnPremGateway Reset-ExchangeOnPremSession {}
            Mock -ModuleName ExchangeOnPremGateway Invoke-ExchangeOnPremCommandInternal {
                if ($script:invokeAttempt -eq 0) {
                    $script:invokeAttempt++
                    throw [System.Management.Automation.RuntimeException]::new('The client cannot connect because the destination computer is unreachable.')
                }
                'ok-after-reconnect'
            }

            $result = Invoke-ExchangeOnPremCommand -Config $script:TestOnPremConfig -ScriptBlock { 'x' }

            $result | Should -Be 'ok-after-reconnect'
            Should -Invoke Reset-ExchangeOnPremSession -ModuleName ExchangeOnPremGateway -Times 1
            Should -Invoke Invoke-ExchangeOnPremCommandInternal -ModuleName ExchangeOnPremGateway -Times 2
        }

        It 'uses UseImportPSSession false as default' {
            $config = @{
                ExchangeOnPrem = @{
                    RemotePowerShell = @{
                        Enabled       = $true
                        User          = 'TESTDOMAIN\ServiceAccount'
                        SecretPath    = 'C:\\TestSecrets\\service.sec'
                        ConnectionUri = 'http://exchange.test.local/PowerShell'
                    }
                }
            }

            $result = Get-ExchangeOnPremRemotePowerShellConfig -Config $config
            $result.UseImportPSSession | Should -Be $false
        }
    }
}

