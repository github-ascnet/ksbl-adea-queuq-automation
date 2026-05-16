# Validierungsbericht AdeaAutomation 18

## Ergebnis

Das Projekt wurde statisch gegen den aktuellen Projektstand validiert. PowerShell/Pester konnte in dieser Umgebung nicht ausgeführt werden, weil kein PowerShell Runtime verfügbar ist.

## Geprüfte Punkte

| Prüffeld | Ergebnis |
|---|---:|
| Aktive UseCases | 19 |
| Deaktivierte UseCases | 9 |
| Aktive Queues | standard, urgent, person-mailbox-longrunning |
| Ungültige aktive Queue longrunning | nicht gefunden |
| SupportsPause aktiv | nur PersonMailbox.CreateNonStandard |
| OutputJson Parameter | vorhanden |
| CorrelationId Parameter | vorhanden |
| ExternalCorrelationId in Metadata-Logik | vorhanden |
| Merge-Konfliktmarker | nicht gefunden |
| Alte Pester-Syntax Should Be | nicht gefunden |
| Operative dfsutil.exe Nutzung | nicht gefunden |
| Manuelle Testdateien je aktivem UseCase | vollständig vorhanden |

## Durchgeführte Anpassungen

1. MailboxAutomation/config/appsettings.json

CsvDelimiter wurde von Semikolon auf Pipe umgestellt, damit die manuellen produktionsnahen Queue-Dateien mit dem Trennzeichen | direkt verarbeitet werden können.

2. manual-job-test-files

Die manuellen Testdateien wurden gegen die UseCase-Registry geprüft. Für die Hospis- und PersonMailbox-Testfälle wurden die fachlichen ActionType-Werte so angepasst, dass sie zur Service-Logik passen, während der Dateiname weiterhin zum UseCase-Pattern passt.

Angepasst wurden insbesondere:

| UseCase | Dateiname bleibt passend zu Pattern | CSV ActionType |
|---|---|---|
| UserPerson.HospisPersonUseCase | HospisPersonUseCase | Erstellen |
| Urgent.InactivateHospisPerson | Inaktivieren_HospisPersonUrgentUseCase | Inaktivieren |
| PersonMailbox.CreateNonStandard | CreateNonStdPersonMailbox | CreateServiceAccount |

3. MANIFEST.csv

Das Manifest wurde erweitert um PatternActionToken und CsvActionType, damit klar ersichtlich ist, welcher Wert für die Dateierkennung und welcher Wert im CSV-Inhalt verwendet wird.

## Hinweis

Die vorhandenen Pester-Tests konnten hier nicht ausgeführt werden. Die letzte vom Projekt gemeldete Gesamtsuite war 327 Passed, 0 Failed. Vor produktiver Nutzung sollte lokal nochmals folgender Lauf ausgeführt werden:

    Invoke-Pester -Path .\tests\Pester
