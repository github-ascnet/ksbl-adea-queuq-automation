# MailboxAutomation

## 1. Ziel der Loesung
Dieses Projekt refaktoriert eine historisch gewachsene AD-/Exchange-On-Prem-Automation in ein modulares, testbares und erweiterbares JobProcessor-Framework.

## 2. Warum die Alt-Skripte refaktoriert werden
Die bisherigen Prozess-Skripte sind über viele Jahre gewachsen. Ziel ist die Reduktion von Duplikaten, klare Verantwortlichkeiten pro UseCase und sichere Kapselung produktiver Aenderungen über Gateways.

## 3. Projektstruktur
- config: Laufzeitkonfiguration und UseCase-Registry
- core: Engine, Queue, Context, Result, Logging, Validation, CSV, State
- infrastructure: AD/Exchange/SQL/DFS/Dateisystem-Gateways
- shared: wiederverwendbare Services
- usecases: ein Handler pro UseCase
- queues: incoming, processing, retry, paused, done, failed, archive
- state: Persistenz fuer longRunning-Zustaende
- tests: Pester-Tests und Testdaten

## 4. Queue-Konzept
Logische Queues:
- standard
- urgent
- person-mailbox-longrunning

Physischer Dateilifecycle:
- incoming -> processing -> done/failed/retry/paused
- optional archive

Metadaten (.meta.json) bleiben bei allen Statuswechseln neben der CSV erhalten, auch bei done und failed.

## 5. UseCase-Konzept
Jeder UseCase ist in usecases.json registriert und enthaelt:
- Name
- Pattern
- Module
- Handler
- Queue
- Priority
- SupportsPause
- MaxParallelism
- Enabled

## 6. Job-Lifecycle
1. Engine laedt Config, Environment und Registry.
2. Queue-Filter waehlt UseCases.
3. Pattern-Matching findet Jobdateien.
4. Datei wird atomar nach processing geclaimt.
5. CSV wird importiert.
6. JobContext wird gebaut.
7. Handler wird dynamisch geladen/aufgerufen.
8. JobResult steuert Move nach done/failed/retry/paused.

Stabile Job-Metadaten enthalten u.a.:
- JobId (persistente GUID)
- StableJobKey
- OriginalFileName und CurrentFileName
- UseCaseName und Queue
- Status, Attempts, RetryAfter, ResumeAfter, PauseReason
- LastMessage und LastErrorCode

## 7. Warum nur PersonMailbox.CreateNonStandard longRunning ist
Dieser UseCase ist fachlich der einzige mit mehrstufigem asynchronem Ablauf und Wiederaufnahmepunkten. Alle anderen UseCases bleiben kurzlaufend.

## 8. Warum fruehere PersonMailbox-Funktionen jetzt GenericUser sind
Folgende Faelle wurden fachlich im Bereich GenericUser konsolidiert:
- EnableNonStandard -> GenericUser.Enable
- DisableNonStandard -> GenericUser.Disable
- EnableAdAccountWithGracePeriod
- ModifyMobilePhoneNumber
- ModifyMailboxFolderAce

## 9. State-Machine fuer PersonMailbox.CreateNonStandard
Schritte:
- 10 ValidateInput
- 20 PrepareAdAccount
- 30 PrepareMailbox
- 40 WaitForMailboxVisibility
- 50 ApplyMailboxAttributes
- 60 Finalize
- 90 Done

State wird als JSON in state/ gespeichert und pro Lauf fortgeschrieben.
Der State-Dateiname basiert primaer auf StableJobKey (Fallback JobId).

## 10. Hybrid-Vorbereitung
Vorbereitet sind:
- ExchangeOnPremGateway
- ExchangeOnlineGateway
- HybridMailboxResolver
- MailboxPermissionService

Exchange Online ist per Config deaktivierbar. Bei deaktivierter EXO-Nutzung werden EXO-Schreiboperationen kontrolliert abgebrochen.

## 11. Neuen UseCase hinzufuegen
1. Neues Handler-Modul in usecases/<Kategorie>/ erstellen.
2. Genau eine oeffentliche Invoke-Funktion mit Parameter [object]$Context implementieren.
3. Eintrag in config/usecases.json anlegen.
4. Testdaten und Pester-Test ergaenzen.

## 12. Runner starten
Aus Projektwurzel MailboxAutomation:

```powershell
.\Invoke-JobProcessor.ps1
```

## 13. Beispiele
Standard-Queue:

```powershell
powershell -ExecutionPolicy Bypass -File .\MailboxAutomation\Invoke-JobProcessor.ps1 -Queue standard -WhatIfMode $true
```

Urgent-Queue:

```powershell
powershell -ExecutionPolicy Bypass -File .\MailboxAutomation\Invoke-JobProcessor.ps1 -Queue urgent -WhatIfMode $true
```

LongRunning-Queue (PersonMailbox):

```powershell
powershell -ExecutionPolicy Bypass -File .\MailboxAutomation\Invoke-JobProcessor.ps1 -Queue person-mailbox-longrunning -WhatIfMode $true
```

LongRunning-Queue inklusive faelliger paused Jobs:

```powershell
powershell -ExecutionPolicy Bypass -File .\MailboxAutomation\Invoke-JobProcessor.ps1 -Queue person-mailbox-longrunning -IncludePaused $true -WhatIfMode $true
```

LongRunning-Queue mit ResumePaused-Scan:

```powershell
powershell -ExecutionPolicy Bypass -File .\MailboxAutomation\Invoke-JobProcessor.ps1 -Queue person-mailbox-longrunning -ResumePaused $true -WhatIfMode $true
```

## 14. WhatIfMode
Schreibende AD-/Exchange-/DFS-/SQL-Operationen sind gekapselt. Bei WhatIfMode werden keine produktiven Aenderungen ausgefuehrt.
Exchange-OnPrem, Exchange-Online und Active-Directory Write-Operationen pruefen WhatIfMode vor Cmdlet-Verfuegbarkeitspruefungen.

## 15. HTML-Mail-Benachrichtigung

### Zentrale Umsetzung

Die gesamte Mailbenachrichtigung ist in `core/MailNotification.psm1` zentralisiert. UseCase-Handler versenden **keine** eigenen E-Mails. Die JobEngine ruft nach Abschluss jedes Jobs automatisch die passende Funktion auf.

### Funktionen

| Funktion | Zweck |
|---|---|
| `New-JobNotificationHtmlBody` | Erzeugt den vollständigen HTML-Body |
| `New-JobNotificationSubject` | Erzeugt die Betreffzeile |
| `Send-JobNotification` | Zentrale Versandfunktion (intern) |
| `Send-JobSuccessNotification` | Wrapper für Succeeded-Status |
| `Send-JobFailureNotification` | Wrapper für Failed-Status |
| `ConvertTo-HtmlEncodedText` | HTML-Encoding aller dynamischen Werte |

### Success-Mail

- Status-Badge: grün (`Success`)
- Beschreibung: "Der Auftrag wurde erfolgreich abgeschlossen."
- Tabelle mit: Status, UseCase, Queue, JobId, Dateiname, Zielpfad, Meldung, Zeitpunkt
- Strukturierte Output-Felder aus `JobResult.Output` (sofern vorhanden): `SuccessCount`, `FailedCount`, `AdObjectName`, `DisplayName`, `PrimarySmtpAddress`

### Failure-Mail

- Status-Badge: rot (`Failed`)
- Beschreibung: "Der Auftrag konnte nicht erfolgreich abgeschlossen werden."
- Gleiche Tabelle wie Success-Mail
- Zusätzlicher Fehlerblock unterhalb der Tabelle mit: genauer Fehlermeldung, ErrorCode, Exception-Message
- Wenn `JobResult.Output.FailedRows` vorhanden: Fehlertabelle mit max. 20 Zeilen (Zeile, Objekt, ErrorCode, Meldung)
- Bei mehr als 20 Fehlerzeilen: Hinweis "Weitere Fehler wurden aus Platzgründen nicht angezeigt."

### HTML-Layout

- Tabellenheader: hellblauer Hintergrund (`#d9ecff`)
- Tabellenzellen: weisser Hintergrund (`#ffffff`)
- Klare Rahmen, lesbare Schrift (Arial/Helvetica)
- Kein externes CSS, alles inline – kompatibel mit Standard-Mailclients
- Alle dynamischen Werte werden HTML-encoded (`ConvertTo-HtmlEncodedText`)

### Konfiguration (`config/appsettings.json`)

```json
"Notifications": {
  "Enabled": false,
  "SendSuccess": true,
  "SendFailure": true,
  "From": "noreply@example.local",
  "To": [ "admin@example.local" ],
  "SmtpServer": "smtp.example.local",
  "Port": 25,
  "UseSsl": false
}
```

- `Enabled`: Hauptschalter – bei `false` werden keine Mails versendet
- `SendSuccess`: bei `false` werden Success-Mails unterdrückt
- `SendFailure`: bei `false` werden Failure-Mails unterdrückt
- Versand über `Send-MailMessage` (PowerShell 5.1, leicht ersetzbar)

### Fehlerverhalten

Mailfehler beeinflussen den Jobstatus **nicht**. Wenn der Mailversand fehlschlägt, wird der Fehler nur geloggt (`Write-LogError`). Der Job bleibt `Succeeded` oder `Failed` – unabhängig vom Mailversand.
WhatIf-Tests decken AD-, Exchange-On-Prem- und Exchange-Online-Schreiboperationen ab.

## 15. Technische Stabilitaets-Merkmale

**Atomisches File-Locking**  
`New-FileLock` verwendet .NET `FileStream` mit `FileMode.CreateNew`, was Race Conditions bei parallelen Runner-Instanzen verhindert.
Stale File-Locks werden automatisch entfernt, wenn sie aelter als `StaleLockMinutes` (konfigurierbar) sind.
Use-Case-Locks (`Enter-UseCaseLock`) verwenden ebenfalls atomisches FileStream-Locking.
Lock-Konflikte (anderer Runner) sind keine fatalen Fehler und werden mit `$null` signalisiert.
Unerwartete Lock-Fehler (Access Denied, ungueltige Pfade) werden nicht still geschluckt, sondern als Exception weitergegeben.

**Ziel-Dateikollisionen**  
`Get-NonConflictingPath` verhindert das Ueberschreiben vorhandener Audit-Dateien in done, failed, retry, paused und archive.
Ein Pfad gilt nur dann als frei, wenn weder die CSV noch die zugehoerige `.meta.json` existieren.
Wenn nur die `.meta.json` (ohne CSV) existiert, wird ebenfalls ein neuer, eindeutiger Name erzeugt.
Bei Kollision wird ein eindeutiger Name mit Zeitstempel und kurzer GUID erzeugt (z.B. `file__20260514_153012_ab12.csv`).

**Robustes Metadata-Handling**  
`.meta.json` bleibt immer neben der CSV-Datei und wird bei jedem Statuswechsel neu geschrieben.
`Move-JobFileToStatus` liest zuerst die Quell-Metadata, bestimmt dann den konfliktfreien Zielpfad, verschiebt die CSV und schreibt die `.meta.json` zum Zielpfad.
`Read-JobMetadata` gibt `$null` zurueck, wenn die `.meta.json` nicht existiert.
Wenn die `.meta.json` existiert, aber korrupt (ungueltige JSON) ist, wird eine Exception geworfen. Stille Fehler und Verlust der originalen JobId werden so verhindert.
`Move-JobFileToStatus` wirft standardmaessig eine Exception, wenn keine Metadata vorhanden ist. Nur mit `-AllowMetadataFallback` wird ein Fallback auf `Unknown.UseCase` verwendet.

**paused / IncludePaused / ResumePaused**  
Paused-Dateien werden nie standardmaessig verarbeitet.
`-IncludePaused` scannt den paused-Ordner und gibt faellige Dateien zurueck (ResumeAfter leer oder in der Vergangenheit).
`-ResumePaused` hat dieselbe Fael ligkeitslogik, signalisiert aber am Aufrufpunkt bewusste Wiederaufnahme.
Falls beide gesetzt sind, gilt dieselbe Due-Pruefung.

**Claim-Fehlerbehandlung**  
`Claim-JobFile` gibt `$null` zurueck, wenn die Datei nicht gelockt werden kann (Lock-Konflikt).
Bei Fehlern nach erfolgreichem Lock wird die Exception nach dem Lock-Release weitergegeben.

**Step-basierte Attempts in PersonMailbox.CreateNonStandard**  
`CurrentStepAttempts` zaehlt Versuche pro State-Machine-Schritt.
Beim Wechsel zu einem neuen Step wird `CurrentStepAttempts` auf 0 zurueckgesetzt.
`Attempts` bleibt als Gesamtzaehler aller Handler-Laeufe bestehen.
`Complete-JobState` setzt `Status = Completed` und `CompletedAt`.

**Bekannte nicht-blockierende PowerShell-Warnungen**  
Funktionen wie `Claim-JobFile`, `Ensure-QueueFolders`, `Enter-UseCaseLock` und `Increment-JobStateStepAttempt` verwenden nicht-genehmigte Verben (unapproved verbs).
Diese Warnungen sind nicht funktional kritisch. Auf Umbenennungen wird bewusst verzichtet, da dadurch Tests, Registry-Eintraege und Handler brechen wuerden.
Die Warnungen koennen mit `Import-Module ... -DisableNameChecking` oder `$WarningPreference = 'SilentlyContinue'` unterdrueckt werden.

## 16. Altlogik schrittweise migrieren
Stellen mit "TODO: Migrate legacy logic here" markieren gezielt die Punkte, an denen bestehende Fachlogik aus current-scripts übernommen werden soll.

## 17. Welche TODO-Stellen ersetzt werden muessen
- Fachlogik in UseCase-Handlern ohne direkte Infrastrukturzugriffe
- SQL- und DFS-Produktivzugriffe
- Erweiterte User- und Mailbox-Sonderregeln
- Detailierte Benachrichtigungslogik
- Verfeinerte State-Machine-Regeln fuer PersonMailbox.CreateNonStandard
- Vollstaendige Migration von Schritt 10-60 in CreateNonStdPersonMailbox.psm1

## 18. Pilotmigration: GenericUser.AddEmailNickname

Der erste kontrolliert migrierte Pilot-UseCase ist `GenericUser.AddEmailNickname`.

Quelle der Altlogik ist `current-scripts/Process-UserGenericJobs.ps1`, der Block mit dem Dateimuster `*AddEMailNickName*_pshjob_.csv`. Der neue Handler liegt unter `usecases/GenericUser/AddEmailNickname.psm1`, die fachliche Servicefunktion unter `shared/UserProvisioningService.psm1`.

Die migrierte On-Prem-Logik entspricht dem alten Ablauf: Das Zielpostfach wird über `AdObjectName` gelesen, die aktuelle `PrimarySmtpAddress` wird ermittelt und anschliessend wird über `Set-Mailbox` die neue Adresse aus `NewPrimaryEMailAddress` als `PrimarySmtpAddress` gesetzt, wobei `EmailAddressPolicyEnabled` auf `$false` gesetzt wird. Produktive Exchange-Zugriffe laufen nicht im Handler, sondern gekapselt über `ExchangeOnPremGateway.psm1`.

Der Handler verarbeitet nur Payload-Daten aus dem `JobContext`, validiert die Pflichtfelder, ruft `Add-GenericUserEmailNickname` auf und gibt ein standardisiertes `JobResult` zurück. Er sucht keine Dateien, verschiebt keine Queue-Dateien und enthält keine eigene Lifecycle-Logik.

Im `WhatIfMode` werden keine Exchange-Cmdlets benötigt und keine produktiven Änderungen ausgeführt. Die Servicefunktion gibt stattdessen ein simuliertes Ergebnis zurück. Die spätere Hybrid-/Exchange-Online-Erweiterung ist bewusst noch nicht implementiert und bleibt als separater Migrationsschritt offen.


## Pilotmigrationen: GroupMailbox- und DistributionGroup-Verantwortlichenlogik

Folgende UseCases wurden aus den Originalskripten unter `current-scripts` in die neue modulare Struktur migriert:

| UseCase | Quelle | Pattern | Handler | Service |
|---|---|---|---|---|
| `GroupMailbox.AddFmaMembers` | `current-scripts/Process-GroupMailboxJobs.ps1` | `*AddGroupMailboxFmaMembers*_pshjob_.csv` | `usecases/GroupMailbox/AddGroupMailboxFmaMembers.psm1` | `shared/GroupMailboxService.psm1` |
| `GroupMailbox.ChangeManager` | `current-scripts/Process-GroupMailboxJobs.ps1` | `*ChangeManagerGroupMailbox*_pshjob_.csv` | `usecases/GroupMailbox/ChangeManagerGroupMailbox.psm1` | `shared/GroupMailboxService.psm1` |
| `DistributionGroup.AddResponsibles` | `current-scripts/Process-DistributionsGroupJobs.ps1` | `*AddDistributionListResponsibles*_pshjob_.csv` | `usecases/DistributionGroup/AddDistributionListResponsibles.psm1` | `shared/DistributionGroupService.psm1` |
| `DistributionGroup.ChangeManager` | `current-scripts/Process-DistributionsGroupJobs.ps1` | `*ChangeManagerDistribList*_pshjob_.csv` | `usecases/DistributionGroup/ChangeManagerDistribList.psm1` | `shared/DistributionGroupService.psm1` |

Die migrierte Logik bildet die bisherigen On-Prem-Aktionen kontrolliert nach: FullAccess-/SendAs-Mutationen auf Gruppenmailboxen, Managerwechsel auf Gruppenmailboxen, ManagedBy-/WriteMembers-Verantwortlichenlogik bei Verteilerlisten und Managerwechsel bei Verteilerlisten. Produktive Änderungen laufen über die Gateway-Funktionen in `ExchangeOnPremGateway.psm1` und `ActiveDirectoryGateway.psm1`; im `WhatIfMode` werden keine AD- oder Exchange-Cmdlets benötigt.

Die Hybrid-/Exchange-Online-Erweiterung ist in diesen UseCases bewusst noch nicht enthalten und bleibt ein separater späterer Migrationsschritt.


## Pilotmigration: GenericUser Enable/Disable, Grace Period und Mobile Number

Die folgenden UseCases wurden als nächster Migrationsschritt aus den Originalskripten kontrolliert in die modulare Struktur überführt:

| UseCase | Quelle | Pattern | Zielmodul |
|---|---|---|---|
| `GenericUser.Enable` | `current-scripts/Process-UserGenericJobs.ps1` | `*EnableNonStdPersonMailbox*_pshjob_.csv` | `usecases/GenericUser/EnableGenericUser.psm1` |
| `GenericUser.Disable` | `current-scripts/Process-UserGenericJobs.ps1` | `*DisableNonStdPersonMailbox*_pshjob_.csv` | `usecases/GenericUser/DisableGenericUser.psm1` |
| `GenericUser.EnableAdAccountWithGracePeriod` | `current-scripts/Process-PersonMailboxJobs.ps1` | `*EnableAdAccountWithGracePeriod*_pshjob_.csv` | `usecases/GenericUser/EnableAdAccountWithGracePeriod.psm1` |
| `GenericUser.ModifyMobilePhoneNumber` | `current-scripts/Process-PersonMailboxJobs.ps1` | `*ModifyMobilePhoneNumber*_pshjob_.csv` | `usecases/GenericUser/ModifyMobilePhoneNumber.psm1` |

Die fachliche Verarbeitung liegt zentral in `shared/UserProvisioningService.psm1`. Produktive Schreiboperationen laufen über `ActiveDirectoryGateway.psm1`, `ExchangeOnPremGateway.psm1`, `DfsGateway.psm1` und `MailboxFeatureService.psm1`. Im `WhatIfMode` werden keine produktiven AD- oder Exchange-Cmdlets benötigt.

Migrierte Kernlogik:

- `GenericUser.Enable` aktiviert nicht standardisierte Personenmailbox-Accounts, setzt bei Bedarf ein Initialkennwort, erzwingt Passwortänderung bei Anmeldung, blendet die Mailbox ein und bereitet die alte `Hospis2AdDeleted`-Behandlung mit DFS-/OU-Schritten vor.
- `GenericUser.Disable` deaktiviert nicht standardisierte Personenmailbox-Accounts, blendet die Mailbox aus und markiert die alte Tenant-Disable-Logik als gezielt zu migrierenden TODO.
- `GenericUser.EnableAdAccountWithGracePeriod` aktiviert ein Konto bei Bedarf, setzt `AccountExpirationDate`, setzt `hrmsIsExpired` und blendet die Mailbox ein.
- `GenericUser.ModifyMobilePhoneNumber` schreibt `MobileNumber` in das AD-Attribut `smsPasscodeMobile`.

Bewusst offengebliebene TODOs:

- Die Legacy-Hilfsfunktion `EnableDisable-Mailbox` muss separat migriert werden, bevor mailboxlose Accounts produktiv automatisch mailbox-enabled werden.
- Die alte `Set-TenantState -Mode TenantDisable`-Logik ist vorbereitet, aber noch nicht als produktive Fachfunktion implementiert.
- `Update-DfsShareSettings` ist als Gateway-Funktion vorbereitet, die echte DFS-Logik muss noch aus der Altlogik überführt werden.
- Hybrid-/Exchange-Online-Routing wurde in diesem Schritt bewusst noch nicht implementiert.


## Pilotmigration: GroupMailbox.Create und GenericUser.CreateMultiFunction

In diesem Migrationsschritt wurden zwei weitere echte UseCases aus den Originalskripten unter `current-scripts` in die modulare Framework-Struktur überführt.

| UseCase | Quelle | Pattern | Handler | Service |
|---|---|---|---|---|
| `GroupMailbox.Create` | `current-scripts/Process-GroupMailboxJobs.ps1` | `*CreateGroupMailbox*_pshjob_.csv` | `usecases/GroupMailbox/CreateGroupMailbox.psm1` | `shared/GroupMailboxService.psm1` |
| `GenericUser.CreateMultiFunction` | `current-scripts/Process-UserGenericJobs.ps1` | `*CreateMultiFunctionGenericUser*_pshjob_.csv` | `usecases/GenericUser/CreateMultiFunctionGenericUser.psm1` | `shared/UserProvisioningService.psm1` |

### GroupMailbox.Create

Die migrierte Logik bildet den bisherigen Ablauf zur Erstellung einer Gruppenmailbox ab. Dazu gehören die Prüfung auf eine bestehende Mailbox anhand der Primary SMTP Address, die Vorbereitung eines SamAccountName, die Erstellung einer Shared Mailbox, die Deaktivierung der Junk-Mail-Konfiguration, das optionale Ausblenden aus dem Adressbuch, das Setzen von Beschreibung und Manager, das Setzen von `employeeType = G`, das Hinzufügen von FullAccess-/SendAs-Berechtigungen, die optionale Änderung der Primary SMTP Address, die Aufnahme in `GG-EV-Users` sowie die vorbereitete Tenant-State-Aktivierung.

Im `WhatIfMode` werden keine Exchange- oder AD-Cmdlets ausgeführt. Stattdessen gibt der Service die geplanten Operationen als simulierte Schritte zurück.

### GenericUser.CreateMultiFunction

Die migrierte Logik bildet den bisherigen Ablauf zur Erstellung eines Multifunktions-/Generic-Users ab. Dazu gehören die Prüfung auf ein bestehendes AD-Objekt, die deterministische Passwortbildung gemäss Altlogik, `New-ADUser`, das Setzen von Manager, `employeeType`, Beschreibung, HomeDirectory, HomeDrive und `kisAccountName`. DFS-, HomeDrive- und Applikationsberechtigungslogik ist als TODO markiert und bleibt für die spätere Detailmigration aus `current-scripts/Process-UserGenericJobs.ps1` erhalten.

Im `WhatIfMode` werden keine AD-Cmdlets oder DFS-Operationen ausgeführt. Der Service gibt stattdessen die geplanten AD- und Berechtigungsschritte als simulierte Operationen zurück.

### Tests

Die Datei `tests/Pester/CreateMailboxAndGenericUserMigration.Tests.ps1` enthält Pester-5.7.1-kompatible Tests für beide UseCases. Die Tests prüfen insbesondere, dass die Handler ihre Services aufrufen, erfolgreiche `JobResult`-Objekte zurückgeben und die Services im `WhatIfMode` ohne produktive AD-/Exchange-Cmdlets funktionieren.


## Pilotmigration: Urgent.InactivateHospisPerson und UserPerson.HospisPersonUseCase

Diese Version migriert die fachliche Altlogik für zwei Hospis-Personenprozesse aus den Originalskripten unter `current-scripts`.

### Urgent.InactivateHospisPerson

Quelle:

- `current-scripts/Process-UrgentJobs.ps1`

Pattern:

- `*Inaktivieren_HospisPersonUrgentUseCase*_pshjob_.csv`

Handler:

- `usecases/Urgent/InactivateHospisPerson.psm1`

Service:

- `shared/HospisPersonService.psm1`
- Funktion: `Invoke-UrgentHospisPersonInactivation`

Migrierte Logik:

- Ermittlung von AD-Benutzern über `employeeID = PersId`
- Deaktivieren der gefundenen AD-Konten
- Ausblenden von Postfächern, sofern `homeMdb` gesetzt ist
- Setzen der Abwesenheitsmeldung über Exchange On-Prem Gateway
- Schliessen offener E-Mail-Revocations via SQL
- Entfernen bestimmter Gruppenmitgliedschaften aus `TPL-*`, `GG-KSBL-VDI-Remote*` und `GG-OneSign*`
- Entfernen von `extensionAttribute6` und `msDS-cloudExtensionAttribute15`
- Setzen der Inaktivierungsbeschreibung
- Erstellen der dringenden Hospis-SQL-Transaktion `usp_create_urgent_inaktivieren_transaction`

### UserPerson.HospisPersonUseCase

Quelle:

- `current-scripts/Process-UserPersonJobs.ps1`

Pattern:

- `*HospisPersonUseCase*_pshjob_.csv`

Handler:

- `usecases/UserPerson/HospisPersonUseCase.psm1`

Service:

- `shared/HospisPersonService.psm1`
- Funktion: `Submit-HospisPersonTransaction`

Migrierte Logik:

- ActionType `Erstellen` → `usp_create_erstellen_transaction`
- ActionType `Aktivieren` → `usp_create_aktivieren_transaction`
- ActionType `Inaktivieren` / `Terminieren` → `usp_create_terminieren_transaction`
- ActionType `Standortwechsel` → `usp_create_standortwechsel_transaction`
- ActionType `UebertrittM2` / `ÜbertrittM2` → `usp_create_uebertritt_m1_to_m2_transaction`
- ActionType `UebertrittM1` / `ÜbertrittM1` → `usp_create_uebertritt_m2_to_m1_transaction`

`AdObjectName` bleibt bewusst optional, da diese Validierung im Originalskript auskommentiert war. Die actiontype-spezifischen Felder wie `RefUserId`, `RefUserDomain`, `LocationName` und `MigrateUser` werden im Handler differenziert validiert.

### Konfiguration

Die Hospis-bezogenen Werte befinden sich in `config/appsettings.json` unter `Hospis`.

```json
"Hospis": {
  "ArchiveRoot": "D:\\IAM\\Archive",
  "SqlServerInstance": "",
  "Database": "KSBL_Hospis_Staging",
  "ConnectionString": "",
  "AustrittOOOExternalMessage": "",
  "AustrittOOOInternalMessage": ""
}
```

Für den produktiven Betrieb muss entweder `ConnectionString` oder `SqlServerInstance` gesetzt werden. Im `WhatIfMode` werden keine produktiven SQL-, AD- oder Exchange-Änderungen ausgeführt.


## Pilotmigration: PersonMailbox.CreateNonStandard

Der UseCase `PersonMailbox.CreateNonStandard` wurde als letzter aktiver UseCase in die modulare Struktur migriert. Die Quelle ist `current-scripts/Process-PersonMailboxJobs.ps1`, der Dateipattern lautet `*CreateNonStdPersonMailbox*_pshjob_.csv` und die Verarbeitung läuft ausschliesslich über die Queue `person-mailbox-longrunning`.

Die Migration bildet die alte blockierende Verarbeitung als nicht-blockierende State-Machine ab. Die Schritte sind `10 ValidateInput`, `20 PrepareAdAccount`, `30 PrepareMailbox`, `40 WaitForMailboxVisibility`, `50 ApplyMailboxAttributes`, `60 Finalize` und `90 Done`. Wartezustände werden nicht mehr mit `Start-Sleep` gelöst, sondern über `Retry` und `RetryAfter` in Verbindung mit stabiler `.meta.json` und `StableJobKey`.

Die fachliche Logik wurde in `shared/PersonMailboxService.psm1` gekapselt. Dort sind die aus dem Alt-Skript abgeleiteten Regeln für DisplayName-Bildung, Standortattribute, Service-Account-Typen, LDAP-Suchfilter, Mailadressbildung, AD-Vorbereitung, Mailbox-Vorbereitung, Sichtbarkeitsprüfung, Attributanwendung und Finalisierung enthalten. Produktive AD- und Exchange-Operationen laufen über die vorhandenen Gateways. Im `WhatIfMode` werden keine produktiven Cmdlets benötigt.

Wichtige Altlogik, die bewusst als TODO markiert bleibt: vollständige DFS/HomeDirectory-Berechtigungen, finale Benachrichtigungslogik, produktive Kollisionsprüfung für eindeutige Mailadressen und spätere Hybrid-/Exchange-Online-Erweiterung für migrierte Postfächer.


## Pilotmigration: DistributionGroup.Create und DistributionGroup.Delete

In diesem Migrationsschritt wurden die zwei verbleibenden aktiven Verteilerlisten-UseCases aus dem Originalskript `current-scripts/Process-DistributionsGroupJobs.ps1` in die modulare Framework-Struktur überführt. Damit sind sämtliche in `usecases.json` als `Enabled=true` registrierten DistributionGroup-UseCases vollständig migriert.

| UseCase | Quelle | Pattern | Handler | Service |
|---|---|---|---|---|
| `DistributionGroup.Create` | `current-scripts/Process-DistributionsGroupJobs.ps1` | `*CreateDistributionList*_pshjob_.csv` | `usecases/DistributionGroup/CreateDistributionGroup.psm1` | `shared/DistributionGroupService.psm1` |
| `DistributionGroup.Delete` | `current-scripts/Process-DistributionsGroupJobs.ps1` | `*DeleteDistribList*_pshjob_.csv` | `usecases/DistributionGroup/DeleteDistributionList.psm1` | `shared/DistributionGroupService.psm1` |

### Gateway-Erweiterungen

Die Datei `infrastructure/ExchangeOnPremGateway.psm1` wurde um zwei neue Safe-Funktionen ergänzt:

- `New-OnPremDistributionGroupSafe` — kapselt `New-DistributionGroup`; WhatIfMode-Prüfung vor jeder Cmdlet-Verfügbarkeitsprüfung
- `Remove-OnPremDistributionGroupSafe` — kapselt `Remove-DistributionGroup`; gleiche Konvention

### DistributionGroup.Create — migrierte Logik

Quelle: Block `*CreateDistributionList*_pshjob_.csv` in `current-scripts/Process-DistributionsGroupJobs.ps1`.

Servicefunktion: `New-DistributionGroupFromRequest` in `shared/DistributionGroupService.psm1`.

Migrierte Schritte:

1. Erstellen der Verteilerliste via `New-DistributionGroup` mit `Name`, `PrimarySmtpAddress`, `Alias`, `SamAccountName`, `DisplayName`, `OrganizationalUnit`, `Type=Security`.
2. Setzen von `HiddenFromAddressListsEnabled` anhand des CSV-Felds `HideInAb`. Faithful Migration: `HideInAb='true'` setzt `HiddenFromAddressListsEnabled=$false` (Gruppe im Adressbuch sichtbar), entsprechend der Altlogik.
3. Setzen von `ManagedBy` auf den aus dem CSV-Feld `Manager` extrahierten Account-Namen (Legacy-Action-Token wie `[ADD]` werden vor der Übergabe entfernt). Zusätzlich wird dem Manager die `WriteProperty Member`-Berechtigung über `Add-ADPermission` (Exchange) erteilt.
4. Setzen der AD-Gruppen-Beschreibung via `Set-ADGroup` mit `"Created on <Datum> by <CurrentUserName>"`.
5. Deaktivieren von `RequireSenderAuthenticationEnabled` (externe Absender erlaubt).

### DistributionGroup.Delete — migrierte Logik

Quelle: Block `*DeleteDistribList*_pshjob_.csv` in `current-scripts/Process-DistributionsGroupJobs.ps1`.

Servicefunktion: `Remove-DistributionGroupFromRequest` in `shared/DistributionGroupService.psm1`.

Migrierte Schritte:

1. Verifizieren der Existenz der Verteilerliste via `Get-DistributionGroup`.
2. Übertragen von `ManagedBy` auf das laufende Service-Konto (`[Environment]::UserDomainName\[Environment]::UserName`), damit die Löschung nicht durch Eigentümerschaftsrestriktionen blockiert wird.
3. Löschen via `Remove-DistributionGroup` mit `Confirm=$false`.

### Pflichtfelder (aus usecases.json)

**Create**: `ActionType`, `DisplayName`, `PrimarySmtpAddress`, `AdObjectName`, `OrgUnit`, `HideInAb`, `Manager`, `CurrentUserName`, `CurrentUserDomainName`, `CurrentUserEMailAddress`

**Delete**: `ActionType`, `AdObjectName`, `CurrentUserName`, `CurrentUserDomainName`, `CurrentUserEMailAddress`

### Bewusst offengebliebene TODOs

- **AcceptMessagesOnlyFromSendersOrMembers**: Das Originalskript fügt hardcodiert `'vl0286'` zur Absenderliste der neuen Verteilerliste hinzu. Diese Logik wurde nicht migriert, da die Konfiguration erst parametrisierbar gemacht werden muss. Markierung: `# TODO: Add distribution group to AcceptMessagesOnlyFromSendersOrMembers` in `DistributionGroupService.psm1`.
- **Set-DlTenantState (TenantEnable)**: Das Originalskript ruft nach der Erstellung `Set-DlTenantState -Mode TenantEnable -CloudDomain $cloudDomain` auf, das Tenant-Hybrid-Attribute in AD und ProxyAddresses setzt. Diese Logik ist noch nicht über `shared/TenantState.psm1` implementiert. Markierung: `# TODO: Migrate Set-DlTenantState -Mode TenantEnable` in `DistributionGroupService.psm1`. Ref: `current-scripts/Process-DistributionsGroupJobs.ps1` — `Set-DlTenantState`-Funktion.
- **Automatische VL-Nummernvergabe**: Das Originalskript überschreibt das CSV-Feld `AdObjectName` mit einer automatisch generierten `vl000x`-Bezeichnung via LDAP-Suche. Im neuen Framework liefert die aufrufende Applikation den `AdObjectName` explizit. Die Altlogik (`Enumerate-NextAvailableAdObjectName`) ist als Referenz in `current-scripts/Process-DistributionsGroupJobs.ps1` erhalten.

### WhatIfMode

Im `WhatIfMode` werden keine Exchange- oder AD-Cmdlets ausgeführt. Beide Servicefunktionen geben stattdessen strukturierte `Operations`-Listen mit simulierten Schritten zurück. Die Handler rufen `$Context.Services.DistributionGroup.Create` bzw. `$Context.Services.DistributionGroup.Delete` auf (ServiceContainer-Verdrahtung in `core/JobEngine.psm1` unverändert).

### Tests

Die Datei `tests/Pester/DistributionGroupCreateDeleteMigration.Tests.ps1` enthält 14 Pester-5.7.1-kompatible Tests. Sie verwenden das korrekte `BeforeAll`-Scoping-Muster für Helper-Funktionen. Die Tests prüfen:

- Handler gibt `Succeeded` zurück wenn Service erfolgreich ist
- Handler gibt `Failed` zurück wenn Service fehlschlägt
- Handler gibt `Failed` mit `USECASE_ERROR` zurück bei fehlenden Pflichtfeldern
- Handler akkumuliert Ergebnisse über mehrere Zeilen
- Service gibt simulierte Operationen im `WhatIfMode` zurück
- Service entfernt Legacy-Action-Token aus dem Manager-Feld
- Gateway-Funktionen geben simulierte Ergebnisse zurück ohne Exchange-Cmdlets


## 31. Validierung und Konsistenzkorrektur GenericUser-Handler

Die Handler `GenericUser.RenameAccount`, `GenericUser.ChangeSurname` und `GenericUser.ModifyMailboxFolderAce` verwenden ein einheitliches per-row `$failedResults`-Muster. Service-Rückgaben mit `Success = false` werden nicht mehr als erfolgreiche Zeile gezählt, sondern als fachlicher Zeilenfehler mit dem jeweiligen `ErrorCode` in `FailedRows` aufgenommen. Exceptions pro Zeile werden weiterhin als `ROW_PROCESSING_ERROR` gesammelt, ohne die Verarbeitung der restlichen Zeilen abzubrechen.

Im Service `UserProvisioningService.psm1` wurden die Implementierungen für Rename, Namensänderung und Mailbox-Folder-ACE auf die echten CSV-Felder der aktiven UseCases ausgerichtet. Für Mailbox-Folder-Berechtigungen kapselt `ExchangeOnPremGateway.psm1` nun zusätzlich `Get-MailboxFolderStatistics`, `Add-MailboxFolderPermission` und `Remove-MailboxFolderPermission` mit WhatIf-sicherem Verhalten.

Die fachlichen Restpunkte wie SQL-Zähler, DFS-/HomeDirectory-Umbenennung, Kundenbenachrichtigung und spätere Hybrid-/Exchange-Online-Erweiterung bleiben bewusst als TODOs markiert und werden nicht im Handler direkt umgesetzt.


## 32. Hybrid-Routing für GroupMailbox.AddFmaMembers

Dieser Abschnitt beschreibt die Erweiterung, die FullAccess- und SendAs-Berechtigungen für Gruppenmailboxen automatisch an die korrekte Exchange-Umgebung (On-Prem oder Exchange Online) weiterleitet, abhängig davon, ob das Postfach noch lokal oder bereits in die Cloud migriert wurde.

### Architektur

```
AddGroupMailboxFmaMembers.psm1  (Handler)
  → $Context.Services.GroupMailbox.AddFmaMembers  (ServiceContainer-Closure in JobEngine)
     → Add-GroupMailboxFmaMembers  (GroupMailboxService)
        → Add-MailboxFullAccess / Add-MailboxSendAs  (MailboxPermissionService)
           → Invoke-ResolvedPermissionGateway  (intern)
              → Resolve-MailboxExecutionContext  (HybridMailboxResolver)
                 → Get-OnPremRecipientSafe  (ExchangeOnPremGateway)
                 → Get-ExoRecipientSafe     (ExchangeOnlineGateway, nur wenn nötig)
              → Add-OnPremMailboxPermissionSafe   (ExchangeOnPremGateway, wenn OnPremExchange)
              → Add-ExoMailboxPermissionSafe      (ExchangeOnlineGateway, wenn ExchangeOnline)
```

### HybridMailboxResolver — Routing-Logik

Das Modul `infrastructure/HybridMailboxResolver.psm1` exportiert `Resolve-MailboxExecutionContext`. Es ermittelt auf Basis eines On-Prem-Lookups (und optionalem EXO-Lookup) den `PermissionAuthority` und die empfohlene Aktion:

| RecipientTypeDetails | EXO-Status | EXO-Objekt gefunden | PermissionAuthority | RecommendedAction | IsMigrationTransient |
|---|---|---|---|---|---|
| `SharedMailbox` | beliebig | – | `OnPremExchange` | `Execute` | `$false` |
| `RemoteSharedMailbox` | enabled | ja | `ExchangeOnline` | `Execute` | `$false` |
| `RemoteSharedMailbox` | enabled | nein | `ExchangeOnline` | `Retry` | `$true` |
| `RemoteSharedMailbox` | disabled | – | `ExchangeOnline` | `Fail` | `$false` |
| Nur EXO (kein On-Prem-Objekt) | enabled | ja | `ExchangeOnline` | `Execute` | `$false` |
| Nicht gefunden (weder On-Prem noch EXO) | – | – | `Unknown` | `Fail` | `$false` |

EXO wird nur abgefragt, wenn das Postfach als `RemoteSharedMailbox` erkannt wurde oder kein On-Prem-Objekt gefunden wurde. EXO-Konfiguration wird über `$Config.ExchangeOnline.Enabled` gesteuert.

### MailboxPermissionService — strukturierte Ergebnisse

Das Modul `shared/MailboxPermissionService.psm1` ersetzt direkte Gateway-Aufrufe in Höher-Level-Services durch strukturierte Ergebnisobjekte. Alle vier exportierten Funktionen (`Add-MailboxFullAccess`, `Remove-MailboxFullAccess`, `Add-MailboxSendAs`, `Remove-MailboxSendAs`) geben ein Objekt mit folgenden Feldern zurück:

| Feld | Typ | Bedeutung |
|---|---|---|
| `Success` | `bool` | Ob die Operation erfolgreich war |
| `Changed` | `bool` | Ob tatsächlich eine Änderung stattgefunden hat |
| `RequiresRetry` | `bool` | Ob der Job für einen späteren Retry eingeplant werden soll |
| `RetryAfterMinutes` | `int` | Wartezeit in Minuten bis zum Retry (nur wenn `RequiresRetry=$true`) |
| `Authority` | `string` | `OnPremExchange`, `ExchangeOnline`, `WhatIf` oder `Unknown` |
| `Identity` | `string` | Die Mailbox-Identität |
| `Trustee` | `string` | Der Trustee (SamAccountName) |
| `Operation` | `string` | z. B. `AddFullAccess`, `RemoveSendAs` |
| `Message` | `string` | Lesbare Statusmeldung |
| `ErrorCode` | `string` | Maschinenlesbarer Fehlercode (leer bei Erfolg) |

#### Fehlercodes

| ErrorCode | Bedeutung |
|---|---|
| `MAILBOX_MIGRATION_TRANSIENT` | Postfach wird gerade migriert; EXO-Objekt noch nicht sichtbar |
| `EXO_REQUIRED_BUT_DISABLED` | RemoteSharedMailbox, aber EXO nicht konfiguriert |
| `MAILBOX_NOT_FOUND` | Postfach weder On-Prem noch in EXO gefunden |
| `PERMISSION_AUTHORITY_UNKNOWN` | Routing konnte nicht bestimmt werden |
| `GATEWAY_ERROR` | Ausnahme beim Gateway-Aufruf |
| `UNKNOWN_OPERATION` | Unbekannte Operation (interner Fehler) |

### GroupMailboxService — Add-GroupMailboxFmaMembers

Die Funktion `Add-GroupMailboxFmaMembers` in `shared/GroupMailboxService.psm1` iteriert über die Action-Tokens im CSV-Feld `MemberList`. Für jeden Token:

- `[ADD]` → ruft `Add-MailboxFullAccess` auf; bei gesetztem `SendAs`-Flag zusätzlich `Add-MailboxSendAs`
- `[DEL]` → ruft `Remove-MailboxFullAccess` auf; bei gesetztem `SendAs`-Flag zusätzlich `Remove-MailboxSendAs`

Wenn eine Operation `RequiresRetry=$true` zurückgibt, wird die Schleife sofort abgebrochen und das Retry-Ergebnis weitergegeben. Wenn eine Operation `Success=$false` ohne Retry zurückgibt, wird der Trustee in `FailedMembers` aufgenommen und die Schleife fortgesetzt. Am Ende bestimmt das Vorhandensein von `FailedMembers` ob `Success=$true` oder `Success=$false` (mit `ErrorCode='GROUP_MAILBOX_PERMISSION_PARTIAL_FAILURE'`) zurückgegeben wird.

Im `WhatIfMode` werden keine Exchange-Cmdlets benötigt. Der Service gibt ein simuliertes Ergebnis mit `Simulated=$true` und `Authority='WhatIf'` zurück.

### Handler — RequiresRetry-Propagation

Der Handler `usecases/GroupMailbox/AddGroupMailboxFmaMembers.psm1` prüft nach dem Service-Aufruf, ob `$serviceResult.RequiresRetry = $true` ist. In diesem Fall wird kein `Succeeded`-JobResult erstellt, sondern ein `New-JobRetryResult` mit der konfigurierten `RetryAfter`-Zeit (Standard: 15 Minuten aus `RetryAfterMinutes`). Damit wird der Job automatisch in die Retry-Queue verschoben und nach der Wartezeit erneut verarbeitet, sobald das Postfach in EXO sichtbar ist.

### Konfiguration

Hybrid-Routing wird über `config/environments.hybrid.json` aktiviert:

```json
"ExchangeOnline": {
  "Enabled": true,
  "AppId": "<Entra-App-Id>",
  "CertThumbprint": "<Thumbprint>",
  "Organization": "<tenant>.onmicrosoft.com",
  "TenantDomain": "<tenant>.onmicrosoft.com"
}
```

In `config/appsettings.json` ist `ExchangeOnline.Enabled` standardmässig auf `false` gesetzt. Die Hybrid-Konfigurationsdatei muss explizit beim Start des JobProcessors angegeben werden.

### Tests

Die Datei `tests/Pester/GroupMailboxHybridRouting.Tests.ps1` enthält 26 Pester-5.7.1-kompatible Tests (alle grün). Die Describe-Blöcke decken ab:

1. `HybridMailboxResolver.Resolve-MailboxExecutionContext` — 6 Tests für alle Routing-Szenarien
2. `MailboxPermissionService.Add-MailboxFullAccess` — 6 Tests inkl. Retry-, Fail- und Gateway-Error-Szenarien
3. `MailboxPermissionService.Add-MailboxSendAs` — 2 Tests
4. `MailboxPermissionService.Remove-MailboxFullAccess` — 2 Tests
5. `GroupMailboxService.Add-GroupMailboxFmaMembers` — 7 Tests inkl. WhatIf, DEL-Token, Partial-Failure und RequiresRetry-Propagation
6. `Invoke-AddGroupMailboxFmaMembers Handler` — 3 Tests für RequiresRetry, Succeeded und Failed-Propagation

Mocks verwenden `Mock -ModuleName 'HybridMailboxResolver'` für Gateway-Funktionen innerhalb des Resolvers und `Mock -ModuleName 'MailboxPermissionService'` für den Resolver und die Gateway-Funktionen innerhalb des PermissionServices.

---

## 33. Hybrid-Routing für GroupMailbox.ChangeManager

Dieser Abschnitt beschreibt die Erweiterung, die den Gruppen-Mailbox-Manager (FullAccess + SendAs + AD-Manager-Attribut) automatisch an die korrekte Exchange-Umgebung weiterleitet, abhängig davon, ob das Postfach noch On-Prem (SharedMailbox) oder bereits in die Cloud migriert ist (RemoteSharedMailbox / EXO).

### Architektur

```
ChangeManagerGroupMailbox.psm1  (Handler)
  → $Context.Services.GroupMailbox.ChangeManager  (ServiceContainer-Closure in JobEngine)
     → Set-GroupMailboxManager  (GroupMailboxService)
        → Resolve-MailboxExecutionContext  (HybridMailboxResolver)
           → Get-OnPremRecipientSafe  (ExchangeOnPremGateway)
           → Get-ExoRecipientSafe     (ExchangeOnlineGateway, nur bei RemoteSharedMailbox oder kein On-Prem-Objekt)
        — On-Prem-Pfad:
           → Invoke-LegacyMailboxPermissionMutation  (ExchangeOnPremGateway / MailboxPermissionService)
           → Set-AdUserSafe                           (ActiveDirectoryGateway)
        — EXO-Pfad:
           → Add-ExoMailboxPermissionSafe  (ExchangeOnlineGateway)
           → Add-ExoSendAsPermissionSafe   (ExchangeOnlineGateway)
           → Set-AdUserSafe                (ActiveDirectoryGateway, nur wenn ExistsOnPrem=$true)
```

### HybridMailboxResolver — ManagementAuthority

`Resolve-MailboxExecutionContext` gibt jetzt zusätzlich `ManagementAuthority` zurück (identisch mit `PermissionAuthority`). Das Feld steuert den Routing-Entscheid in `Set-GroupMailboxManager`:

| RecipientTypeDetails | EXO-Status | EXO-Objekt gefunden | ManagementAuthority | RecommendedAction |
|---|---|---|---|---|
| `SharedMailbox` | beliebig | – | `OnPremExchange` | `Execute` |
| `RemoteSharedMailbox` | enabled | ja | `ExchangeOnline` | `Execute` |
| `RemoteSharedMailbox` | enabled | nein | `ExchangeOnline` | `Retry` |
| `RemoteSharedMailbox` | disabled | – | `ExchangeOnline` | `Fail` |
| Nur EXO (kein On-Prem-Objekt) | enabled | ja | `ExchangeOnline` | `Execute` |
| Nicht gefunden | – | – | `Unknown` | `Fail` |

### GroupMailboxService — Set-GroupMailboxManager

Die Funktion `Set-GroupMailboxManager` in `shared/GroupMailboxService.psm1` wurde zu einer hybrid-bewussten Implementierung umgeschrieben:

1. **WhatIf-Early-Return**: kein Resolver-Aufruf, keine Exchange-Cmdlets. Gibt `Simulated=$true`, `Authority='WhatIf'` zurück.
2. **Resolve-MailboxExecutionContext**: bestimmt `ManagementAuthority` und `RecommendedAction`.
3. **Retry-Branch**: Bei `RecommendedAction='Retry'` gibt die Funktion sofort ein Objekt mit `RequiresRetry=$true`, `ErrorCode='MAILBOX_MIGRATION_TRANSIENT'` zurück.
4. **Fail-Branch**: Bei `RecommendedAction='Fail'`:
   - `ManagementAuthority = 'ExchangeOnline'` → `ErrorCode = 'EXO_REQUIRED_BUT_DISABLED'`
   - sonst → `ErrorCode = 'MAILBOX_NOT_FOUND'`
5. **Execute-Branch** (switch auf `ManagementAuthority`):
   - `OnPremExchange`: `Invoke-LegacyMailboxPermissionMutation` (FullAccess + SendAs On-Prem) + `Set-AdUserSafe`
   - `ExchangeOnline`: `Add-ExoMailboxPermissionSafe` + `Add-ExoSendAsPermissionSafe` + `Set-AdUserSafe` (nur wenn `ExistsOnPrem=$true`)
   - `default`: `ErrorCode = 'PERMISSION_AUTHORITY_UNKNOWN'`
6. **Erfolg**: gibt `Success=$true`, `Changed=$true`, `Authority=$resolution.ManagementAuthority` zurück.

**Besonderheit EXO-only-Mailboxen**: Wenn `ExistsOnPrem=$false` (reines EXO-Postfach ohne On-Prem-Proxy), wird `Set-AdUserSafe` **nicht** aufgerufen, da kein AD-Objekt existiert.

### Handler — RequiresRetry-Propagation

Der Handler `usecases/GroupMailbox/ChangeManagerGroupMailbox.psm1` prüft nach dem Service-Aufruf ob `$serviceResult.RequiresRetry = $true`. Bei Retry wird sofort `New-JobRetryResult` zurückgegeben — bei Multi-Row-Jobs werden verbleibende Zeilen **nicht** weiterverarbeitet (erste RequiresRetry-Zeile gewinnt).

### ExchangeOnlineGateway — Set-ExoMailboxManagerSafe

Das Modul `infrastructure/ExchangeOnlineGateway.psm1` wurde um `Set-ExoMailboxManagerSafe` erweitert. Die Funktion folgt dem bestehenden Gateway-Muster (WhatIf-Guard → `Assert-ExchangeOnlineEnabled` → cmdlet check → `Set-Mailbox`).

### Fehlercodes

| ErrorCode | Bedeutung |
|---|---|
| `MAILBOX_MIGRATION_TRANSIENT` | Postfach in Migrationstransiente; EXO-Objekt noch nicht sichtbar |
| `EXO_REQUIRED_BUT_DISABLED` | RemoteSharedMailbox, aber EXO nicht konfiguriert |
| `MAILBOX_NOT_FOUND` | Postfach weder On-Prem noch in EXO gefunden |
| `PERMISSION_AUTHORITY_UNKNOWN` | Routing-Autorität unbekannt (interner Fehler) |
| `GROUP_MAILBOX_MANAGER_CHANGE_FAILED` | Ausnahme beim Gateway-Aufruf |

### Tests

Die Datei `tests/Pester/GroupMailboxChangeManagerHybridRouting.Tests.ps1` enthält 11 Pester-5.7.1-kompatible Tests. Die Describe-Blöcke decken ab:

1. `GroupMailboxService.Set-GroupMailboxManager` — 8 Tests:
   - WhatIf: kein Resolver-Aufruf, kein Exchange
   - On-Prem: `Invoke-LegacyMailboxPermissionMutation` + `Set-AdUserSafe` aufgerufen
   - EXO: `Add-ExoMailboxPermissionSafe` + `Add-ExoSendAsPermissionSafe` + `Set-AdUserSafe` aufgerufen
   - Retry: `RequiresRetry=$true`, `ErrorCode='MAILBOX_MIGRATION_TRANSIENT'`
   - EXO disabled: `ErrorCode='EXO_REQUIRED_BUT_DISABLED'`
   - Not found: `ErrorCode='MAILBOX_NOT_FOUND'`
   - Gateway-Exception: `ErrorCode='GROUP_MAILBOX_MANAGER_CHANGE_FAILED'`
   - WhatIf (EXO enabled): kein EXO-Aufruf

2. `Invoke-ChangeManagerGroupMailbox handler` — 5 Tests:
   - RequiresRetry → `Status='Retry'`
   - Success → `Status='Succeeded'`
   - Failure → `Status='Failed'`
   - Validation failure → `ErrorCode='USECASE_ERROR'`
   - Partial failure (Multi-Row) → `Status='Failed'`
   - RequiresRetry stoppt weitere Zeilen (nur 1 Service-Aufruf bei 2 Zeilen)

Mocks verwenden `Mock -ModuleName 'GroupMailboxService'` für alle Resolver- und Gateway-Funktionen innerhalb des Services.

---

## 34. Hybrid-Autoritätslogik für GenericUser (RenameAccount / ChangeSurname / AddEmailNickname)

Dieser Abschnitt beschreibt die Erweiterung, die die drei GenericUser-Operationen hybrid-bewusst macht: Sie routen Exchange-Befehle automatisch an On-Prem (`Set-Mailbox` oder `Set-RemoteMailbox`) und geben bei Cloud-only-Postfächern einen definierten Fehler zurück.

### Designprinzipien

- **AD-Attribute** bleiben immer On-Prem (Entra Connect synchronisiert sie in die Cloud). `Set-ADUser` wird für alle Typen verwendet.
- **`UserMailbox`** (On-Prem): Exchange-Attribute via `Set-Mailbox` On-Prem.
- **`RemoteUserMailbox`** (Benutzerpostfach migriert nach EXO, Proxy-Objekt On-Prem): Synchronisierte Empfänger-Attribute (PrimarySmtpAddress, proxyAddresses) via `Set-RemoteMailbox` On-Prem — kein EXO-Aufruf nötig.
- **Cloud-only** (kein On-Prem-Proxy): → `CLOUD_ONLY_NOT_SUPPORTED`. GenericUser-Operationen setzen ein AD-Objekt voraus.
- **EXO-Lookup** wird für `RemoteUserMailbox` **nicht** ausgelöst — nur für `RemoteSharedMailbox` (GroupMailbox-Szenarien).

### Neue HybridMailboxResolver-Felder

`Resolve-MailboxExecutionContext` gibt nun vier zusätzliche Felder zurück:

| Feld | Typ | Bedeutung |
|---|---|---|
| `IdentityAuthority` | `string` | `OnPremAD` / `ExchangeOnline` / `Unknown` — wo das Identity-Objekt lebt |
| `RecipientAuthority` | `string` | `OnPremExchange` / `ExchangeOnline` / `Unknown` — wo die Exchange-Befehle für Empfänger-Attribute ausgeführt werden |
| `IsSynchronized` | `bool` | `$true` bei `RemoteUserMailbox`/`RemoteSharedMailbox` (Entra-Connect-Sync) |
| `IsCloudOnly` | `bool` | `$true` bei EXO-only-Objekten ohne On-Prem-Proxy |

### Erweiterte Routing-Tabelle

| `RecipientTypeDetails` | `RecipientAuthority` | `PermissionAuthority` | `IsSynchronized` | `IsCloudOnly` | `RecommendedAction` |
|---|---|---|---|---|---|
| `UserMailbox` (On-Prem) | `OnPremExchange` | `OnPremExchange` | `$false` | `$false` | `Execute` |
| `RemoteUserMailbox` (On-Prem-Proxy) | `OnPremExchange` | `ExchangeOnline` | `$true` | `$false` | `Execute` |
| `SharedMailbox` (On-Prem) | `OnPremExchange` | `OnPremExchange` | `$false` | `$false` | `Execute` |
| `RemoteSharedMailbox` + EXO sichtbar | `OnPremExchange` | `ExchangeOnline` | `$true` | `$false` | `Execute` |
| `RemoteSharedMailbox` + EXO unsichtbar | `OnPremExchange` | `ExchangeOnline` | `$true` | `$false` | `Retry` |
| EXO-only (kein On-Prem-Objekt) | `ExchangeOnline` | `ExchangeOnline` | `$false` | `$true` | `Execute` |
| Nicht gefunden | `Unknown` | `Unknown` | `$false` | `$false` | `Fail` |

### Neue Gateway-Funktionen (ExchangeOnPremGateway)

| Funktion | Exchange-Cmdlet | Zweck |
|---|---|---|
| `Get-OnPremRemoteMailboxSafe` | `Get-RemoteMailbox` | Liest RemoteUserMailbox-Objekt für Primär-SMTP-Prüfung |
| `Set-OnPremRemoteMailboxSafe` | `Set-RemoteMailbox` | Setzt PrimarySmtpAddress / EmailAddressPolicyEnabled für RemoteUserMailbox |

Beide Funktionen folgen dem bestehenden Gateway-Muster: WhatIf-Guard → `Assert-OnPremCmdlet` → Cmdlet-Aufruf mit `-ErrorAction Stop`.

### Geänderte UserProvisioningService-Funktionen

#### `Rename-GenericUser`

1. WhatIf → simuliertes Ergebnis (kein Resolver).
2. Falls `NewPrimaryEMailAddress` gesetzt: `Resolve-MailboxExecutionContext` → bei `IsCloudOnly` → `CLOUD_ONLY_NOT_SUPPORTED`; bei `Fail`+`Unknown` → `RECIPIENT_NOT_FOUND`.
3. AD-Objekt per `Get-AdUserBySamAccountNameSafe` laden. Nicht gefunden → `AD_OBJECT_NOT_FOUND`.
4. Optionales AD-Rename via `Rename-AdObjectSafe`.
5. AD-Attribute via `Set-AdUserSafe` (GivenName, Surname, DisplayName, SamAccountName, EmailAddress, UPN).
6. Exchange-Attribute: `RecipientTypeDetails = 'RemoteUserMailbox'` → `Set-OnPremRemoteMailboxSafe`; sonst → `Set-OnPremMailboxSafe`.

#### `Set-GenericUserSurname`

Gleiche Struktur wie `Rename-GenericUser`, ohne AD-Rename-Schritt.

#### `Add-GenericUserEmailNickname`

1. WhatIf → simuliertes Ergebnis.
2. `Resolve-MailboxExecutionContext` → `IsCloudOnly` → `CLOUD_ONLY_NOT_SUPPORTED`; `Retry` → `RequiresRetry=$true`; `Fail` → `EXO_REQUIRED_BUT_DISABLED` oder `RECIPIENT_NOT_FOUND`.
3. Postfach abrufen: `RemoteUserMailbox` → `Get-OnPremRemoteMailboxSafe`; sonst → `Get-OnPremMailboxSafe`.
4. **No-Change-Prüfung**: `$currentPrimary -eq $newPrimaryEmailAddress` → `Success=$true`, `Changed=$false`, kein Set-Aufruf.
5. PrimarySmtpAddress setzen: `RemoteUserMailbox` → `Set-OnPremRemoteMailboxSafe`; sonst → `Set-OnPremMailboxSafe`.

### Handler — RequiresRetry-Propagation

Alle drei Handler (`RenameUserAccount.psm1`, `ChangeAccountSurname.psm1`, `AddEmailNickname.psm1`) prüfen nach dem Service-Aufruf das Feld `RequiresRetry`. Bei `$true` wird sofort `New-JobRetryResult` zurückgegeben. Für GenericUser-Operationen ist `RequiresRetry` aktuell immer `$false` (RemoteUserMailbox-Attribute gehen via On-Prem Exchange ohne EXO-Sichtbarkeitsprüfung), aber der Handler ist für zukünftige Erweiterungen vorbereitet.

### Fehlercodes

| ErrorCode | Bedeutung |
|---|---|
| `CLOUD_ONLY_NOT_SUPPORTED` | EXO-only-Postfach; GenericUser-Operationen erfordern ein AD-Objekt |
| `RECIPIENT_NOT_FOUND` | Postfach weder On-Prem noch in EXO gefunden |
| `EXO_REQUIRED_BUT_DISABLED` | RemoteSharedMailbox, aber EXO-Verbindung nicht konfiguriert |
| `MAILBOX_MIGRATION_TRANSIENT` | Postfach in Migrationstransiente (Retry-Zustand) |
| `AD_OBJECT_NOT_FOUND` | AD-Benutzer nicht gefunden |
| `MAILBOX_GET_FAILED` | Resolver- oder Mailbox-Abruf-Fehler |
| `RENAME_GENERIC_USER_FAILED` | Ausnahme in Rename-GenericUser |
| `CHANGE_SURNAME_FAILED` | Ausnahme in Set-GenericUserSurname |
| `SET_PRIMARY_SMTP_FAILED` | Ausnahme beim Setzen der PrimarySmtpAddress |

### Tests

Die Datei `tests/Pester/GenericUserHybridAuthority.Tests.ps1` enthält Pester-5.7.1-kompatible Tests. Die Describe-Blöcke decken ab:

1. **`HybridMailboxResolver` — GenericUser-Typen** (4 Contexts, 6 Tests):
   - `UserMailbox`: `RecipientAuthority=OnPremExchange`, `Execute`, `IsSynchronized=$false`
   - `RemoteUserMailbox`: `RecipientAuthority=OnPremExchange`, `Execute`, `IsSynchronized=$true`, kein EXO-Lookup
   - EXO-only: `IsCloudOnly=$true`, `IdentityAuthority=ExchangeOnline`
   - Nicht gefunden: `Unknown`, `Fail`, `IdentityAuthority=Unknown`

2. **`Rename-GenericUser`** (6 Contexts, 7 Tests):
   - WhatIf, UserMailbox→Set-Mailbox, RemoteUserMailbox→Set-RemoteMailbox, Cloud-only, Nicht gefunden, AD nicht gefunden

3. **`Set-GenericUserSurname`** (5 Contexts, 6 Tests):
   - WhatIf, UserMailbox, RemoteUserMailbox, Cloud-only, Nicht gefunden

4. **`Add-GenericUserEmailNickname`** (7 Contexts, 8 Tests):
   - WhatIf, UserMailbox, RemoteUserMailbox, No-Change, Cloud-only, EXO disabled, Retry, Nicht gefunden

5. **Handler `Invoke-RenameUserAccount`** (4 Contexts, 4 Tests):
   - RequiresRetry→Retry, Success→Succeeded, Failure→Failed, Validierungsfehler→USECASE_ERROR

6. **Handler `Invoke-ChangeAccountSurname`** (2 Contexts, 2 Tests):
   - RequiresRetry→Retry, Success→Succeeded

7. **Handler `Invoke-AddEmailNickname`** (4 Contexts, 4 Tests):
   - RequiresRetry→Retry, Success→Succeeded, No-Change→Succeeded, Failure→Failed

