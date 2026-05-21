$root = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$global:AdeaProjectRootForTests = $root
Import-Module -Name (Join-Path $root 'infrastructure\ExchangeOnPremGateway.psm1') -Force -DisableNameChecking

Describe 'ExchangeOnPrem gateway connection behavior' {
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
            Reset-ExchangeOnPremSession
            Set-ExchangeOnPremRuntimeConfig -Config $script:TestOnPremConfig
        }

        It 'does not require Assert-OnPremCmdlet in InvokeCommand mode' {
            Mock -ModuleName ExchangeOnPremGateway Assert-OnPremCmdlet { throw 'must not be called in InvokeCommand mode' }
            Mock -ModuleName ExchangeOnPremGateway Invoke-ExchangeOnPremCommand { [pscustomobject]@{ Identity = 'u1' } }

            $result = Get-OnPremMailboxSafe -Identity 'u1' -Config $script:TestOnPremConfig

            $result.Identity | Should -Be 'u1'
            Should -Invoke Invoke-ExchangeOnPremCommand -ModuleName ExchangeOnPremGateway -Times 1
            Should -Invoke Assert-OnPremCmdlet -ModuleName ExchangeOnPremGateway -Times 0
        }

        It 'keeps ConnectionUri value on sv01250 in environment files' {
            $onPremPath = Join-Path $global:AdeaProjectRootForTests 'config\environments.onprem.json'
            $hybridPath = Join-Path $global:AdeaProjectRootForTests 'config\environments.hybrid.json'

            $onPrem = Get-Content -Path $onPremPath -Raw | ConvertFrom-Json
            $hybrid = Get-Content -Path $hybridPath -Raw | ConvertFrom-Json

            $onPrem.ExchangeOnPrem.RemotePowerShell.ConnectionUri | Should -Be 'http://sv01250.ksbl.local/PowerShell'
            $hybrid.ExchangeOnPrem.RemotePowerShell.ConnectionUri | Should -Be 'http://sv01250.ksbl.local/PowerShell'
        }

        It 'contains no hardcoded productive credentials in gateway source' {
            $gatewayPath = Join-Path $global:AdeaProjectRootForTests 'infrastructure\ExchangeOnPremGateway.psm1'
            $source = Get-Content -Path $gatewayPath -Raw

            $source | Should -Not -Match 'ksbl\\ServiceIAMJobs10'
            $source | Should -Not -Match 'D:\\iam\\Secrets\\serviceiamjobs10\.sec'
            $source | Should -Not -Match 'http://sv01250\.ksbl\.local/PowerShell'
        }
    }
}

