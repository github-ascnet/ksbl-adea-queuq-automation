#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $modulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\core\MailNotification.psm1'
    Import-Module -Name $modulePath -Force -ErrorAction Stop
}

Describe 'New-JobNotificationHtmlBody' {

    Context 'Allgemeine HTML-Struktur' {

        It 'Erzeugt einen String, der mit DOCTYPE beginnt' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match 'DOCTYPE'
        }

        It 'Erzeugt einen HTML-Body mit <html>-Tag' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match '<html'
        }

        It 'Enthält eine Begrüssung (Guten Tag)' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match 'Guten Tag'
        }

        It 'Enthält eine Beschreibung (Automationsauftrag)' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match 'Automationsauftrag'
        }

        It 'Enthält eine Tabelle' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match '<table'
        }

        It 'Tabellenheader enthält hellblaue Hintergrundfarbe (#d9ecff)' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match '#d9ecff'
        }

        It 'Tabellenzellen haben weissen Hintergrund (#ffffff)' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match 'background-color: #ffffff'
        }

        It 'Enthält Zeitpunkt in der Tabelle' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match 'Zeitpunkt'
        }

        It 'Enthält den UseCase-Namen in der Tabelle' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'DistributionGroup.Create'
            $result | Should -Match 'DistributionGroup.Create'
        }
    }

    Context 'Status Success' {

        It 'Enthält Status Success im HTML-Badge' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match 'status-success'
        }

        It 'Enthält das Wort Success' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match 'Success'
        }

        It 'Enthält Beschreibung für erfolgreichen Abschluss' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Match 'erfolgreich abgeschlossen'
        }

        It 'Enthält keinen Fehlerblock-DIV bei Success' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
            $result | Should -Not -Match '<div class="error-box"'
        }
    }

    Context 'Status Failed' {

        It 'Enthält Status Failed im HTML-Badge' {
            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'GenericUser.Create' -Message 'Etwas ist schiefgelaufen.'
            $result | Should -Match 'status-failed'
        }

        It 'Enthält das Wort Failed' {
            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'GenericUser.Create' -Message 'Fehler'
            $result | Should -Match 'Failed'
        }

        It 'Enthält Beschreibung für fehlgeschlagenen Auftrag' {
            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'GenericUser.Create' -Message 'Fehler'
            $result | Should -Match 'nicht erfolgreich abgeschlossen'
        }

        It 'Enthält einen Fehlerblock (error-box)' {
            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'GenericUser.Create' -Message 'Etwas ist schiefgelaufen.'
            $result | Should -Match 'error-box'
        }

        It 'Enthält die Fehlermeldung im Fehlerblock' {
            $errorMsg = 'AD-Objekt nicht gefunden.'
            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'GenericUser.Create' -ErrorMessage $errorMsg
            $result | Should -Match 'AD-Objekt nicht gefunden'
        }

        It 'Enthält den ErrorCode aus JobResult' {
            $jobResult = [pscustomobject]@{
                Status    = 'Failed'
                Message   = 'Fehler'
                ErrorCode = 'AD_NOT_FOUND'
                Exception = $null
                Output    = $null
            }
            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'GenericUser.Create' -JobResult $jobResult
            $result | Should -Match 'AD_NOT_FOUND'
        }

        It 'Enthält Exception-Meldung aus JobResult' {
            $ex = [System.Exception]::new('Verbindungsfehler zum DC.')
            $jobResult = [pscustomobject]@{
                Status    = 'Failed'
                Message   = 'Fehler'
                ErrorCode = 'CONNECT_FAILED'
                Exception = $ex
                Output    = $null
            }
            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'GenericUser.Create' -JobResult $jobResult
            $result | Should -Match 'Verbindungsfehler zum DC'
        }
    }

    Context 'FailedRows' {

        It 'Zeigt FailedRows in einer Fehlertabelle an' {
            $rows = @(
                [pscustomobject]@{ Object = 'user1'; ErrorCode = 'E001'; Message = 'Fehler 1' }
                [pscustomobject]@{ Object = 'user2'; ErrorCode = 'E002'; Message = 'Fehler 2' }
            )
            $output = [pscustomobject]@{ FailedRows = $rows }
            $jobResult = [pscustomobject]@{ Status = 'Failed'; Message = 'Fehler'; ErrorCode = $null; Exception = $null; Output = $output }

            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'GenericUser.Create' -JobResult $jobResult
            $result | Should -Match 'user1'
            $result | Should -Match 'E001'
        }

        It 'Zeigt maximal 20 FailedRows an' {
            $rows = 1..30 | ForEach-Object {
                [pscustomobject]@{ Object = "user$_"; ErrorCode = "E$_"; Message = "Fehler $_" }
            }
            $output = [pscustomobject]@{ FailedRows = $rows }
            $jobResult = [pscustomobject]@{ Status = 'Failed'; Message = 'Fehler'; ErrorCode = $null; Exception = $null; Output = $output }

            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'GenericUser.Create' -JobResult $jobResult
            $result | Should -Match 'Weitere Fehler wurden aus Platzgr'
            $result | Should -Not -Match 'user21'
        }
    }

    Context 'HTML-Encoding dynamischer Werte' {

        It 'Enkodiert Sonderzeichen in UseCaseName' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'Test<>&UseCase'
            $result | Should -Match 'Test&lt;&gt;&amp;UseCase'
        }

        It 'Enkodiert Sonderzeichen in der Fehlermeldung' {
            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'GenericUser.Create' -ErrorMessage 'Fehler: <script>alert(1)</script>'
            $result | Should -Match '&lt;script&gt;'
            $result | Should -Not -Match '<script>'
        }

        It 'Enkodiert Sonderzeichen in Message' {
            $result = New-JobNotificationHtmlBody -Status 'Failed' -UseCaseName 'Test' -Message 'A & B < C > D'
            $result | Should -Match 'A &amp; B'
        }
    }

    Context 'Optionale Felder' {

        It 'Enthält Queue in der Tabelle wenn angegeben' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'Test' -Queue 'standard'
            $result | Should -Match 'standard'
        }

        It 'Enthält JobId in der Tabelle wenn angegeben' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'Test' -JobId 'abc-123'
            $result | Should -Match 'abc-123'
        }

        It 'Enthält Dateiname aus SourceFile in der Tabelle' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'Test' -SourceFile 'C:\queue\incoming\job_sample.csv'
            $result | Should -Match 'job_sample.csv'
        }

        It 'Enthält MovedPath in der Tabelle wenn angegeben' {
            $result = New-JobNotificationHtmlBody -Status 'Succeeded' -UseCaseName 'Test' -MovedPath 'C:\queue\done\job_sample.csv'
            $result | Should -Match 'C:\\queue\\done'
        }
    }
}

Describe 'New-JobNotificationSubject' {

    It 'Erzeugt Betreff mit [Success] für Succeeded' {
        $result = New-JobNotificationSubject -Status 'Succeeded' -UseCaseName 'DistributionGroup.Create'
        $result | Should -Match '^\[Success\]'
    }

    It 'Erzeugt Betreff mit [Failed] für Failed' {
        $result = New-JobNotificationSubject -Status 'Failed' -UseCaseName 'DistributionGroup.Create'
        $result | Should -Match '^\[Failed\]'
    }

    It 'Enthält UseCase-Namen im Betreff' {
        $result = New-JobNotificationSubject -Status 'Succeeded' -UseCaseName 'GenericUser.RenameAccount'
        $result | Should -Match 'GenericUser.RenameAccount'
    }

    It 'Enthält JobId im Betreff wenn angegeben' {
        $result = New-JobNotificationSubject -Status 'Failed' -UseCaseName 'GenericUser.RenameAccount' -JobId 'abc-456'
        $result | Should -Match 'abc-456'
    }

    It 'Enthält keine JobId wenn nicht angegeben' {
        $result = New-JobNotificationSubject -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
        $result | Should -Not -Match ' - $'
    }

    It 'Enthält MailboxAutomation im Betreff' {
        $result = New-JobNotificationSubject -Status 'Succeeded' -UseCaseName 'GenericUser.Create'
        $result | Should -Match 'MailboxAutomation'
    }
}

Describe 'Send-JobNotification' {

    BeforeAll {
        # Mock Send-MailMessage um echten Versand zu verhindern
        Mock Send-MailMessage { } -ModuleName 'MailNotification'
    }

    Context 'Notifications deaktiviert' {

        It 'Sendet keine Mail wenn Notifications.Enabled = false' {
            $config = @{
                Notifications = @{
                    Enabled    = $false
                    SmtpServer = 'smtp.example.local'
                    Port       = 25
                    From       = 'noreply@example.local'
                    To         = @('admin@example.local')
                }
            }
            Send-JobNotification -Config $config -Status 'Succeeded' -UseCaseName 'Test'
            Should -Invoke Send-MailMessage -Times 0 -ModuleName 'MailNotification'
        }

        It 'Sendet keine Mail wenn Notifications-Sektion fehlt' {
            $config = @{}
            Send-JobNotification -Config $config -Status 'Succeeded' -UseCaseName 'Test'
            Should -Invoke Send-MailMessage -Times 0 -ModuleName 'MailNotification'
        }
    }

    Context 'SendSuccess deaktiviert' {

        It 'Sendet keine Success-Mail wenn SendSuccess = false' {
            $config = @{
                Notifications = @{
                    Enabled     = $true
                    SendSuccess = $false
                    SmtpServer  = 'smtp.example.local'
                    Port        = 25
                    From        = 'noreply@example.local'
                    To          = @('admin@example.local')
                }
            }
            Send-JobNotification -Config $config -Status 'Succeeded' -UseCaseName 'Test'
            Should -Invoke Send-MailMessage -Times 0 -ModuleName 'MailNotification'
        }
    }

    Context 'SendFailure deaktiviert' {

        It 'Sendet keine Failure-Mail wenn SendFailure = false' {
            $config = @{
                Notifications = @{
                    Enabled     = $true
                    SendFailure = $false
                    SmtpServer  = 'smtp.example.local'
                    Port        = 25
                    From        = 'noreply@example.local'
                    To          = @('admin@example.local')
                }
            }
            Send-JobNotification -Config $config -Status 'Failed' -UseCaseName 'Test'
            Should -Invoke Send-MailMessage -Times 0 -ModuleName 'MailNotification'
        }
    }

    Context 'Mailversand-Fehler' {

        It 'Wirft keine Exception wenn Mailversand fehlschlägt' {
            Mock Send-MailMessage { throw 'SMTP-Fehler' } -ModuleName 'MailNotification'

            $config = @{
                Notifications = @{
                    Enabled    = $true
                    SmtpServer = 'smtp.example.local'
                    Port       = 25
                    From       = 'noreply@example.local'
                    To         = @('admin@example.local')
                }
            }

            { Send-JobNotification -Config $config -Status 'Failed' -UseCaseName 'Test' } | Should -Not -Throw
        }
    }

    Context 'Kein SMTP-Server konfiguriert' {

        It 'Sendet keine Mail wenn SmtpServer leer ist' {
            Mock Send-MailMessage { } -ModuleName 'MailNotification'

            $config = @{
                Notifications = @{
                    Enabled    = $true
                    SmtpServer = ''
                    Port       = 25
                    From       = 'noreply@example.local'
                    To         = @('admin@example.local')
                }
            }
            Send-JobNotification -Config $config -Status 'Succeeded' -UseCaseName 'Test'
            Should -Invoke Send-MailMessage -Times 0 -ModuleName 'MailNotification'
        }
    }

    Context 'Empfaengeraufloesung aus Payload' {

        It 'Verwendet CurrentUserEMailAddress aus Payload als To und statisches Cc aus Config' {
            Mock Send-MailMessage { } -ModuleName 'MailNotification'

            $config = @{
                Notifications = @{
                    Enabled    = $true
                    SmtpServer = 'smtp.example.local'
                    Port       = 25
                    From       = 'noreply@example.local'
                    Cc         = @('ksbl.vl.iam-administrators@ksbl.ch')
                }
            }
            $payload = @(
                [pscustomobject]@{ CurrentUserEMailAddress = 'requester@ksbl.ch' }
            )

            Send-JobNotification -Config $config -Status 'Succeeded' -UseCaseName 'Test' -Payload $payload

            Should -Invoke Send-MailMessage -Times 1 -ModuleName 'MailNotification' -ParameterFilter {
                $To -contains 'requester@ksbl.ch' -and $Cc -contains 'ksbl.vl.iam-administrators@ksbl.ch'
            }
        }

        It 'Sendet keine Mail wenn im Payload keine CurrentUserEMailAddress vorhanden ist' {
            Mock Send-MailMessage { } -ModuleName 'MailNotification'

            $config = @{
                Notifications = @{
                    Enabled    = $true
                    SmtpServer = 'smtp.example.local'
                    Port       = 25
                    From       = 'noreply@example.local'
                    Cc         = @('ksbl.vl.iam-administrators@ksbl.ch')
                }
            }
            $payload = @(
                [pscustomobject]@{ AdObjectName = 'u12345' }
            )

            Send-JobNotification -Config $config -Status 'Succeeded' -UseCaseName 'Test' -Payload $payload
            Should -Invoke Send-MailMessage -Times 0 -ModuleName 'MailNotification'
        }
    }
}

Describe 'ConvertTo-HtmlEncodedText' {

    It 'Enkodiert <' {
        ConvertTo-HtmlEncodedText -Value '<b>' | Should -Be '&lt;b&gt;'
    }

    It 'Enkodiert &' {
        ConvertTo-HtmlEncodedText -Value 'A & B' | Should -Be 'A &amp; B'
    }

    It 'Gibt leeren String für null zurück' {
        ConvertTo-HtmlEncodedText -Value $null | Should -Be ''
    }

    It 'Gibt normalen Text unverändert zurück' {
        ConvertTo-HtmlEncodedText -Value 'HelloWorld' | Should -Be 'HelloWorld'
    }
}
