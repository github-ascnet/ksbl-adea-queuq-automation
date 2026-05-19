Manuelle JobEngine-Testdateien für AdeaAutomation / AdeaJobEngine
Erzeugt für die 19 aktiven UseCases aus usecases.json.
Alle Dateien verwenden das Trennzeichen |.
Ablage ist nach Queue/incoming vorbereitet.
CurrentUserName = ex00013, CurrentUserDomainName = ksbl, CurrentUserEMailAddress = peter.silie@ksbl.ch.
AdObjectName-basierte Werte beginnen mit uat und fünf Ziffern.

Testbeispiel:
1. Den Inhalt des passenden Queue-Ordners in AdeaJobEngine/queues/<queue>/incoming kopieren.
2. In AdeaJobEngine wechseln.
3. CorrelationId erzeugen und Processor starten:
   $correlationId = [guid]::NewGuid().ToString()
   .\Invoke-JobProcessor.ps1 -Queue standard -CorrelationId $correlationId -OutputJson

Für urgent entsprechend -Queue urgent verwenden.
Für person-mailbox-longrunning entsprechend -Queue person-mailbox-longrunning verwenden.
Hinweis zur aktuellen Projektvalidierung:
Die produktive Standardkonfiguration AdeaJobEngine/config/appsettings.json verwendet nun CsvDelimiter |, damit diese manuellen Queue-Dateien ohne Zusatzkonfiguration direkt importiert werden können.
