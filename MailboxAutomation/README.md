# MailboxAutomation

## 1. Ziel der Loesung
Dieses Projekt refaktoriert eine historisch gewachsene AD-/Exchange-On-Prem-Automation in ein modulares, testbares und erweiterbares JobProcessor-Framework.

## 2. Warum die Alt-Skripte refaktoriert werden
Die bisherigen Prozess-Skripte sind ueber viele Jahre gewachsen. Ziel ist die Reduktion von Duplikaten, klare Verantwortlichkeiten pro UseCase und sichere Kapselung produktiver Aenderungen ueber Gateways.

## 3. Projektstruktur
- config: Laufzeitkonfiguration und UseCase-Registry
- core: Engine, Queue, Context, Result, Logging, Validation, CSV, State
- infrastructure: AD/Exchange/SQL/DFS/Dateisystem-Gateways
- shared: wiederverwendbare Services
- usecases: ein Handler pro UseCase
- queues: incoming, processing, retry, paused, done, failed, archive
- state: Persistenz fuer longRunning-Zustaende
- tests: Pester-Tests 
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
Stellen mit "TODO: Migrate legacy logic here" markieren gezielt die Punkte, an denen bestehende Fachlogik aus current-scripts uebernommen werden soll.

## 17. Welche TODO-Stellen ersetzt werden muessen
- Fachlogik in UseCase-Handlern ohne direkte Infrastrukturzugriffe
- SQL- und DFS-Produktivzugriffe
- Erweiterte User- und Mailbox-Sonderregeln
- Detailierte Benachrichtigungslogik
- Verfeinerte State-Machine-Regeln fuer PersonMailbox.CreateNonStandard
- Vollstaendige Migration von Schritt 10-60 in CreateNonStdPersonMailbox.psm1
