Set-StrictMode -Version Latest


# ---------------------------------------------------------------------------
# ConvertTo-HtmlEncodedText
# ---------------------------------------------------------------------------
# Enkodiert einen Wert HTML-sicher. Alle dynamischen Inhalte in Mail-Bodies
# müssen über diese Funktion laufen, damit Sonderzeichen (<, >, & usw.)
# keine HTML-Struktur zerstören können.
function ConvertTo-HtmlEncodedText {
    [CmdletBinding()]
    param([object]$Value)

    if ($null -eq $Value) { return '' }
    return [System.Net.WebUtility]::HtmlEncode([string]$Value)
}


# ---------------------------------------------------------------------------
# New-HtmlTableRow (intern, nicht exportiert)
# ---------------------------------------------------------------------------
function New-HtmlTableRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Label,
        [object]$Value
    )

    $encLabel = ConvertTo-HtmlEncodedText -Value $Label
    $encValue = ConvertTo-HtmlEncodedText -Value $Value
    return "<tr><td><strong>$encLabel</strong></td><td>$encValue</td></tr>"
}


# ---------------------------------------------------------------------------
# New-JobNotificationSubject
# ---------------------------------------------------------------------------
# Erzeugt die Betreffzeile der Benachrichtigungsmail.
# Format:
#   [Success] MailboxAutomation - UseCaseName
#   [Failed]  MailboxAutomation - UseCaseName - JobId
function New-JobNotificationSubject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$UseCaseName,
        [string]$JobId
    )

    $tag = if ($Status -eq 'Succeeded') { 'Success' } else { 'Failed' }

    if ($JobId) {
        return "[$tag] MailboxAutomation - $UseCaseName - $JobId"
    }
    return "[$tag] MailboxAutomation - $UseCaseName"
}


# ---------------------------------------------------------------------------
# New-JobNotificationHtmlBody
# ---------------------------------------------------------------------------
# Erzeugt den vollständigen HTML-Body der Benachrichtigungsmail.
# Enthält:
# - Begrüssung und Beschreibung
# - Status-Badge (Success/Failed)
# - Tabelle mit Job-/Objektdaten (hellblauer Header, weisse Zellen)
# - Fehlerblock (nur bei Failed) inkl. FailedRows-Tabelle (max. 20 Zeilen)
function New-JobNotificationHtmlBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$UseCaseName,
        [string]$Message,
        [object]$JobResult,
        [object]$Metadata,
        [string]$JobId,
        [string]$Queue,
        [string]$SourceFile,
        [string]$MovedPath,
        [string]$ErrorMessage
    )

    $isSuccess = $Status -eq 'Succeeded'
    $statusLabel = if ($isSuccess) { 'Success' } else { 'Failed' }
    $statusClass = if ($isSuccess) { 'status-success' } else { 'status-failed' }
    $description = if ($isSuccess) {
        'Der Auftrag wurde erfolgreich abgeschlossen.'
    }
    else {
        'Der Auftrag konnte nicht erfolgreich abgeschlossen werden.'
    }
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')

    # --- Haupttabelle aufbauen ---
    $tableRowsSb = [System.Text.StringBuilder]::new()
    [void]$tableRowsSb.AppendLine((New-HtmlTableRow -Label 'Status'   -Value $statusLabel))
    [void]$tableRowsSb.AppendLine((New-HtmlTableRow -Label 'UseCase'  -Value $UseCaseName))

    if ($Queue) { [void]$tableRowsSb.AppendLine((New-HtmlTableRow -Label 'Queue'          -Value $Queue)) }
    if ($JobId) { [void]$tableRowsSb.AppendLine((New-HtmlTableRow -Label 'JobId'          -Value $JobId)) }
    if ($SourceFile) { [void]$tableRowsSb.AppendLine((New-HtmlTableRow -Label 'Objekt / Datei' -Value (Split-Path -Leaf $SourceFile))) }
    if ($MovedPath) { [void]$tableRowsSb.AppendLine((New-HtmlTableRow -Label 'Zielpfad'       -Value $MovedPath)) }
    if ($Message) { [void]$tableRowsSb.AppendLine((New-HtmlTableRow -Label 'Meldung'        -Value $Message)) }
    [void]$tableRowsSb.AppendLine((New-HtmlTableRow -Label 'Zeitpunkt' -Value $timestamp))

    # Strukturierte Output-Felder aus JobResult auslesen (nur einfache Skalare)
    if ($null -ne $JobResult -and $JobResult.PSObject.Properties['Output'] -and $null -ne $JobResult.Output) {
        $output = $JobResult.Output
        $simpleProps = @('SuccessCount', 'FailedCount', 'AdObjectName', 'DisplayName', 'PrimarySmtpAddress')
        foreach ($prop in $simpleProps) {
            if ($output.PSObject.Properties[$prop] -and $null -ne $output.$prop) {
                $val = $output.$prop
                # Komplexe Objekte (Arrays, Listen) werden ausgelassen
                if ($val -isnot [System.Collections.IEnumerable] -or $val -is [string]) {
                    [void]$tableRowsSb.AppendLine((New-HtmlTableRow -Label $prop -Value $val))
                }
            }
        }
        # Anzahl fehlgeschlagener Zeilen als Zusammenfassung
        if ($output.PSObject.Properties['FailedRows'] -and $null -ne $output.FailedRows) {
            $frCount = @($output.FailedRows).Count
            if ($frCount -gt 0) {
                [void]$tableRowsSb.AppendLine((New-HtmlTableRow -Label 'Fehlgeschlagene Zeilen' -Value $frCount))
            }
        }
    }

    # --- Fehlerblock (nur bei Failed) ---
    $errorBlockHtml = ''
    if (-not $isSuccess) {
        $errSb = [System.Text.StringBuilder]::new()

        $effectiveError = if ($ErrorMessage) { $ErrorMessage } elseif ($Message) { $Message } else { '' }
        if ($effectiveError) {
            [void]$errSb.AppendLine('<strong>Fehlermeldung</strong><br/>')
            [void]$errSb.AppendLine((ConvertTo-HtmlEncodedText -Value $effectiveError))
        }

        if ($null -ne $JobResult) {
            if ($JobResult.PSObject.Properties['ErrorCode'] -and $JobResult.ErrorCode) {
                [void]$errSb.AppendLine('<br/><strong>ErrorCode:</strong> ' + (ConvertTo-HtmlEncodedText -Value $JobResult.ErrorCode))
            }
            if ($JobResult.PSObject.Properties['Exception'] -and $null -ne $JobResult.Exception) {
                [void]$errSb.AppendLine('<br/><strong>Exception:</strong> ' + (ConvertTo-HtmlEncodedText -Value $JobResult.Exception.Message))
            }

            # FailedRows-Tabelle (max. 20 Zeilen)
            if ($JobResult.PSObject.Properties['Output'] -and $null -ne $JobResult.Output) {
                $output = $JobResult.Output
                if ($output.PSObject.Properties['FailedRows'] -and $null -ne $output.FailedRows) {
                    $rows = @($output.FailedRows)
                    if ($rows.Count -gt 0) {
                        [void]$errSb.AppendLine('<br/><strong>Fehlgeschlagene Zeilen:</strong>')
                        [void]$errSb.AppendLine('<table>')
                        [void]$errSb.AppendLine('<tr><th>Zeile</th><th>Objekt</th><th>ErrorCode</th><th>Meldung</th></tr>')
                        $limit = [Math]::Min($rows.Count, 20)
                        for ($i = 0; $i -lt $limit; $i++) {
                            $row = $rows[$i]
                            $rowNum = ConvertTo-HtmlEncodedText -Value ($i + 1)
                            $objRaw = if ($row.PSObject.Properties['Object']) { [string]$row.Object }    elseif ($row.PSObject.Properties['Name']) { [string]$row.Name } else { '' }
                            $ecRaw = if ($row.PSObject.Properties['ErrorCode']) { [string]$row.ErrorCode } else { '' }
                            $msgRaw = if ($row.PSObject.Properties['Message']) { [string]$row.Message }   else { '' }
                            $obj = ConvertTo-HtmlEncodedText -Value $objRaw
                            $ec = ConvertTo-HtmlEncodedText -Value $ecRaw
                            $msg = ConvertTo-HtmlEncodedText -Value $msgRaw
                            [void]$errSb.AppendLine("<tr><td>$rowNum</td><td>$obj</td><td>$ec</td><td>$msg</td></tr>")
                        }
                        [void]$errSb.AppendLine('</table>')
                        if ($rows.Count -gt 20) {
                            [void]$errSb.AppendLine('<p><em>Weitere Fehler wurden aus Platzgründen nicht angezeigt.</em></p>')
                        }
                    }
                }
            }
        }

        $errContent = $errSb.ToString().Trim()
        if ($errContent) {
            $errorBlockHtml = @"
<div class="error-box">
$errContent
</div>
"@
        }
    }

    # --- CSS (inline, damit Mailclients es rendern) ---
    $css = @'
body {
    font-family: Arial, Helvetica, sans-serif;
    font-size: 14px;
    color: #1f2933;
    background-color: #ffffff;
}
.container {
    max-width: 900px;
    margin: 0 auto;
    padding: 20px;
}
h2 {
    color: #12395b;
}
.status-success {
    display: inline-block;
    padding: 6px 12px;
    background-color: #d9f7e8;
    color: #146c43;
    border-radius: 4px;
    font-weight: bold;
}
.status-failed {
    display: inline-block;
    padding: 6px 12px;
    background-color: #fde2e2;
    color: #b42318;
    border-radius: 4px;
    font-weight: bold;
}
table {
    border-collapse: collapse;
    width: 100%;
    margin-top: 16px;
}
th {
    background-color: #d9ecff;
    color: #12395b;
    text-align: left;
    padding: 8px;
    border: 1px solid #b7d7f0;
}
td {
    background-color: #ffffff;
    padding: 8px;
    border: 1px solid #d0d7de;
}
.error-box {
    margin-top: 18px;
    padding: 12px;
    background-color: #fff5f5;
    border: 1px solid #f5b5b5;
    color: #7a1f1f;
    white-space: pre-wrap;
}
.footer {
    margin-top: 24px;
    font-size: 12px;
    color: #667085;
}
'@

    $tableRows = $tableRowsSb.ToString().Trim()

    return @"
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8"/>
<style>
$css
</style>
</head>
<body>
<div class="container">
<h2>MailboxAutomation &ndash; Auftragsverarbeitung</h2>
<p>Guten Tag</p>
<p>Der folgende Automationsauftrag wurde verarbeitet.</p>
<p>$(ConvertTo-HtmlEncodedText -Value $description)</p>
<p><span class="$statusClass">$statusLabel</span></p>
<table>
<tr><th>Feld</th><th>Wert</th></tr>
$tableRows
</table>
$errorBlockHtml
<div class="footer">
Diese Nachricht wurde automatisch von MailboxAutomation generiert. Bitte nicht antworten.
</div>
</div>
</body>
</html>
"@
}


# ---------------------------------------------------------------------------
# Send-JobNotification
# ---------------------------------------------------------------------------
# Zentrale Versandfunktion. Prüft Config-Flags, erzeugt Subject und Body,
# sendet die Mail via SMTP.
# Wichtig: Mailfehler werden geloggt, aber NICHT geworfen. Der Jobstatus
# (Succeeded/Failed) wird durch einen Mailversandfehler nicht beeinflusst.
function Send-JobNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$UseCaseName,
        [string]$Message,
        [object]$JobResult,
        [object]$Metadata,
        [string]$JobId,
        [string]$Queue,
        [string]$SourceFile,
        [string]$MovedPath,
        [object]$Logger
    )

    # Notifications-Konfiguration auslesen
    $notifConfig = $null
    if ($Config.ContainsKey('Notifications') -and $Config['Notifications'] -is [hashtable]) {
        $notifConfig = $Config['Notifications']
    }

    if ($null -eq $notifConfig -or -not ($notifConfig.ContainsKey('Enabled') -and $notifConfig['Enabled'])) {
        if ($Logger) { Write-LogDebug -Logger $Logger -Message 'Notifications are disabled.' }
        return
    }

    # Typ-spezifische Flags prüfen
    $isSuccess = $Status -eq 'Succeeded'
    if ($isSuccess -and $notifConfig.ContainsKey('SendSuccess') -and -not $notifConfig['SendSuccess']) {
        if ($Logger) { Write-LogDebug -Logger $Logger -Message 'Success notifications are disabled (SendSuccess=false).' }
        return
    }
    if (-not $isSuccess -and $notifConfig.ContainsKey('SendFailure') -and -not $notifConfig['SendFailure']) {
        if ($Logger) { Write-LogDebug -Logger $Logger -Message 'Failure notifications are disabled (SendFailure=false).' }
        return
    }

    # Empfänger bestimmen
    $toAddresses = @()
    if ($notifConfig.ContainsKey('To') -and $null -ne $notifConfig['To']) {
        $toAddresses = @($notifConfig['To'])
    }
    if ($toAddresses.Count -eq 0) {
        if ($Logger) { Write-LogWarn -Logger $Logger -Message 'No notification recipients configured. Skipping mail.' }
        return
    }

    $from = if ($notifConfig.ContainsKey('From') -and $notifConfig['From']) { [string]$notifConfig['From'] }       else { 'noreply@example.local' }
    $smtpServer = if ($notifConfig.ContainsKey('SmtpServer') -and $notifConfig['SmtpServer']) { [string]$notifConfig['SmtpServer'] } else { '' }
    $smtpPort = if ($notifConfig.ContainsKey('Port') -and $notifConfig['Port']) { [int]$notifConfig['Port'] }          else { 25 }
    $useSsl = if ($notifConfig.ContainsKey('UseSsl')) { [bool]$notifConfig['UseSsl'] }       else { $false }

    if (-not $smtpServer) {
        if ($Logger) { Write-LogWarn -Logger $Logger -Message 'No SMTP server configured. Skipping mail.' }
        return
    }

    # Fehlermeldung für den Fehlerblock ermitteln
    $errorMsg = ''
    if (-not $isSuccess) {
        if ($null -ne $JobResult -and $JobResult.PSObject.Properties['Exception'] -and $null -ne $JobResult.Exception) {
            $errorMsg = $JobResult.Exception.Message
        }
        elseif ($Message) {
            $errorMsg = $Message
        }
    }

    $subject = New-JobNotificationSubject -Status $Status -UseCaseName $UseCaseName -JobId $JobId
    $body = New-JobNotificationHtmlBody `
        -Status      $Status `
        -UseCaseName $UseCaseName `
        -Message     $Message `
        -JobResult   $JobResult `
        -Metadata    $Metadata `
        -JobId       $JobId `
        -Queue       $Queue `
        -SourceFile  $SourceFile `
        -MovedPath   $MovedPath `
        -ErrorMessage $errorMsg

    try {
        $mailParams = @{
            From        = $from
            To          = $toAddresses
            Subject     = $subject
            Body        = $body
            BodyAsHtml  = $true
            SmtpServer  = $smtpServer
            Port        = $smtpPort
            UseSsl      = $useSsl
            Encoding    = [System.Text.Encoding]::UTF8
            ErrorAction = 'Stop'
        }
        Send-MailMessage @mailParams
        if ($Logger) { Write-LogInfo -Logger $Logger -Message "Notification sent: $subject" }
    }
    catch {
        # Mailfehler dürfen den Jobstatus nicht beeinflussen: nur loggen, nie werfen.
        if ($Logger) { Write-LogError -Logger $Logger -Message "Failed to send notification '$subject'." -Exception $_.Exception }
    }
}


# ---------------------------------------------------------------------------
# Send-JobFailureNotification
# ---------------------------------------------------------------------------
function Send-JobFailureNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string]$UseCaseName,
        [string]$Message,
        [object]$JobResult,
        [object]$Metadata,
        [string]$JobId,
        [string]$Queue,
        [string]$SourceFile,
        [string]$MovedPath,
        [object]$Logger
    )

    Send-JobNotification `
        -Config      $Config `
        -Status      'Failed' `
        -UseCaseName $UseCaseName `
        -Message     $Message `
        -JobResult   $JobResult `
        -Metadata    $Metadata `
        -JobId       $JobId `
        -Queue       $Queue `
        -SourceFile  $SourceFile `
        -MovedPath   $MovedPath `
        -Logger      $Logger
}


# ---------------------------------------------------------------------------
# Send-JobSuccessNotification
# ---------------------------------------------------------------------------
function Send-JobSuccessNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string]$UseCaseName,
        [string]$Message,
        [object]$JobResult,
        [object]$Metadata,
        [string]$JobId,
        [string]$Queue,
        [string]$SourceFile,
        [string]$MovedPath,
        [object]$Logger
    )

    Send-JobNotification `
        -Config      $Config `
        -Status      'Succeeded' `
        -UseCaseName $UseCaseName `
        -Message     $Message `
        -JobResult   $JobResult `
        -Metadata    $Metadata `
        -JobId       $JobId `
        -Queue       $Queue `
        -SourceFile  $SourceFile `
        -MovedPath   $MovedPath `
        -Logger      $Logger
}


Export-ModuleMember -Function @(
    'ConvertTo-HtmlEncodedText',
    'New-JobNotificationSubject',
    'New-JobNotificationHtmlBody',
    'Send-JobNotification',
    'Send-JobFailureNotification',
    'Send-JobSuccessNotification'
)
