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
