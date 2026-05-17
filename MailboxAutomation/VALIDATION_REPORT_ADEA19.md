AdeaAutomation(19) - Validation Report

Prüfungsschwerpunkte:
- environments.hybrid.json und environments.onprem.json Remote-PowerShell-Werte
- Exchange Online App-only Werte
- OnPrem Remote PowerShell Werte
- MailNotification dynamisches To aus CurrentUserEMailAddress
- statisches Cc aus appsettings.json

Befund:
- environments.hybrid.json: ExchangeOnline Werte korrekt gesetzt.
- environments.hybrid.json: ExchangeOnPrem RemotePowerShell Werte korrekt gesetzt.
- environments.onprem.json: ConnectionUri war auf http://sv01250.ksbl.local/PowerShell gesetzt und wurde auf http://sv00516.ksbl.local/PowerShell korrigiert.
- appsettings.json: Notifications.To ist entfernt, Notifications.Cc ist auf ksbl.vl.iam-administrators@ksbl.ch gesetzt.
- MailNotification.psm1: To wird zur Laufzeit aus Payload.CurrentUserEMailAddress aufgelöst.
- JobEngine.psm1: Payload wird an Success- und Failure-Notification übergeben.
- Hinweis: ExchangeOnPremGateway.psm1 liest RemotePowerShell aktuell nicht aktiv aus der Config. Die Configwerte sind vorhanden, aber die automatische Session-Erstellung ist im Gateway noch nicht implementiert.
- Hinweis: Notifications.Enabled steht in appsettings.json aktuell auf false. Für einen Mail-End-to-End-Test muss dies in der passenden Umgebung aktiviert werden.

Korrektur:
- environments.onprem.json ConnectionUri korrigiert auf http://sv00516.ksbl.local/PowerShell.
