#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $root = (Resolve-Path (Join-Path -Path $PSScriptRoot -ChildPath '..\..')).Path
    Import-Module -Name (Join-Path -Path $root -ChildPath 'infrastructure\ExchangeOnlineGateway.psm1') -Force
}

Describe 'ExchangeOnlineGateway – Verbindungsverhalten' {
    BeforeEach {
        InModuleScope ExchangeOnlineGateway {
            $script:ExchangeOnlineSessionState.Connected = $false
            $script:ExchangeOnlineSessionState.RuntimeConfig = $null

            $script:TestEXOConfig = @{
                ExchangeOnline = @{
                    Enabled                        = $true
                    AppId                          = 'test-app-id-00000000'
                    Organization                   = 'test.onmicrosoft.com'
                    CertificateThumbprint          = 'AABBCCDDEEFF'
                    ShowBanner                     = $false
                    ReuseSession                   = $true
                    ReconnectOnFailure             = $true
                    MaxReconnectAttempts           = 1
                    ValidateConnectionWithCommand  = $false
                    ConnectionValidationCommand    = 'Get-EXORecipient'
                    ConnectionValidationResultSize = 1
                }
            }
        }
    }

    # ─── Test 9: Aktive Session wird wiederverwendet, kein Connect ─────────
    It 'verwendet vorhandene aktive Verbindung wieder und ruft Connect-ExchangeOnline nicht auf (Test 9)' {
        InModuleScope ExchangeOnlineGateway {
            # Simuliere aktive Verbindung
            Mock Get-ExchangeOnlineConnectionInformationInternal {
                [PSCustomObject]@{ State = 'Connected'; ConnectionUri = 'https://outlook.office365.com' }
            }
            Mock Connect-ExchangeOnlineInternal { throw 'must not be called' }
            Mock Import-ExchangeOnlineManagementModuleInternal { }
            Mock Get-ExchangeOnlineModuleInternal { [PSCustomObject]@{ Name = 'ExchangeOnlineManagement' } }

            { Ensure-ExchangeOnlineSession -Config $script:TestEXOConfig } | Should -Not -Throw

            Should -Invoke Connect-ExchangeOnlineInternal -Times 0 -Exactly
        }
    }

    # ─── Test 10: Keine Verbindung → Connect-ExchangeOnline wird aufgerufen ─
    It 'ruft Connect-ExchangeOnline mit AppId, Organization und CertificateThumbprint auf wenn keine Verbindung besteht (Test 10)' {
        InModuleScope ExchangeOnlineGateway {
            $script:connectCallParams = $null

            # Erste Prüfung: keine Verbindung; nach Connect: Verbindung vorhanden
            $script:connCheckCount = 0
            Mock Get-ExchangeOnlineConnectionInformationInternal {
                $script:connCheckCount++
                if ($script:connCheckCount -le 1) { return $null }
                return [PSCustomObject]@{ State = 'Connected'; ConnectionUri = 'https://outlook.office365.com' }
            }
            Mock Get-ExchangeOnlineModuleInternal { [PSCustomObject]@{ Name = 'ExchangeOnlineManagement' } }
            Mock Import-ExchangeOnlineManagementModuleInternal { }
            Mock Get-ExchangeOnlineCertificateInternal {
                [PSCustomObject]@{ Thumbprint = 'AABBCCDDEEFF'; HasPrivateKey = $true; NotAfter = (Get-Date).AddYears(1) }
            }
            Mock Connect-ExchangeOnlineInternal {
                param($Parameters)
                $script:connectCallParams = $Parameters
            }

            Ensure-ExchangeOnlineSession -Config $script:TestEXOConfig

            Should -Invoke Connect-ExchangeOnlineInternal -Times 1 -Exactly
            $script:connectCallParams.AppId                 | Should -Be 'test-app-id-00000000'
            $script:connectCallParams.Organization          | Should -Be 'test.onmicrosoft.com'
            $script:connectCallParams.CertificateThumbprint | Should -Be 'AABBCCDDEEFF'
        }
    }

    # ─── Test 11: Private-Key-Fehler → verständliche Zertifikatsdiagnose ───
    It 'liefert verständliche Zertifikats-Private-Key-Diagnose bei Schlüsselsatz-Fehler (Test 11)' {
        InModuleScope ExchangeOnlineGateway {
            Mock Get-ExchangeOnlineConnectionInformationInternal { $null }
            Mock Get-ExchangeOnlineModuleInternal { [PSCustomObject]@{ Name = 'ExchangeOnlineManagement' } }
            Mock Import-ExchangeOnlineManagementModuleInternal { }
            Mock Get-ExchangeOnlineCertificateInternal {
                [PSCustomObject]@{ Thumbprint = 'AABBCCDDEEFF'; HasPrivateKey = $true; NotAfter = (Get-Date).AddYears(1) }
            }
            Mock Connect-ExchangeOnlineInternal {
                throw 'Der Schlüsselsatz ist nicht vorhanden'
            }

            { Connect-ExchangeOnlineSession -Config $script:TestEXOConfig } |
            Should -Throw -ExpectedMessage '*private*Schlüssel*nutzbar*'
        }
    }

    # ─── Test 12: ReconnectOnFailure=true → genau ein Disconnect + Connect ─
    It 'führt bei Verbindungsfehler und ReconnectOnFailure=true genau einen Disconnect und einen erneuten Connect durch (Test 12)' {
        InModuleScope ExchangeOnlineGateway {
            $script:ensureCallCount = 0
            $script:disconnectCalled = 0
            $script:sbCallCount = 0

            Mock Ensure-ExchangeOnlineSession {
                $script:ensureCallCount++
            }
            Mock Reset-ExchangeOnlineSession {
                $script:disconnectCalled++
            }

            # ScriptBlock: erster Aufruf wirft Verbindungsfehler, zweiter Aufruf liefert Erfolg
            $sb = [scriptblock]::Create(@'
                $script:sbCallCount++
                if ($script:sbCallCount -eq 1) {
                    throw 'not connected to Exchange Online'
                }
                'reconnect-success'
'@)

            $result = Invoke-ExchangeOnlineCommand -Config $script:TestEXOConfig -ScriptBlock $sb

            $result                    | Should -Be 'reconnect-success'
            $script:ensureCallCount    | Should -Be 2
            $script:disconnectCalled   | Should -Be 1
        }
    }
}
