# Aktiviert den strikten PowerShell-Modus für dieses Modul.
# Zweck:
# - nicht initialisierte Variablen fallen früh auf
# - fehlende Properties werden nicht still ignoriert
# - die JobEngine verhält sich dadurch berechenbarer und produktionsnäher
# Wichtig:
# - deshalb werden später optionale JobResult-Properties explizit geprüft,
#   bevor darauf zugegriffen wird.
Set-StrictMode -Version Latest


# ---------------------------------------------------------------------------
# ConvertTo-HashtableDeep
# ---------------------------------------------------------------------------
# Zweck:
# ConvertFrom-Json liefert in Windows PowerShell häufig PSCustomObject-Strukturen.
# Für die Engine sind echte Hashtables praktischer, weil Konfigurationen später
# mit ContainsKey(), rekursivem Merge und punktuellen Overrides verarbeitet werden.
#
# Diese Funktion konvertiert deshalb ein beliebiges Objekt rekursiv:
# - IDictionary        -> Hashtable
# - IEnumerable        -> Array/Liste, ausser String
# - PSCustomObject     -> Hashtable anhand der Properties
# - einfacher Wert     -> unverändert
#
# Einsatz:
# Wird von Read-JsonAsHashtable verwendet, um appsettings, environments und
# usecases.json in ein robustes internes Format zu überführen.
function ConvertTo-HashtableDeep {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-HashtableDeep -InputObject $InputObject[$key]
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += , (ConvertTo-HashtableDeep -InputObject $item)
        }
        return $list
    }

    if ($InputObject -is [psobject]) {
        $props = @($InputObject.PSObject.Properties)
        if ($props.Count -gt 0) {
            $hash = @{}
            foreach ($prop in $props) {
                $hash[$prop.Name] = ConvertTo-HashtableDeep -InputObject $prop.Value
            }
            return $hash
        }
    }

    return $InputObject
}


# ---------------------------------------------------------------------------
# Merge-Hashtable
# ---------------------------------------------------------------------------
# Zweck:
# Führt zwei Konfigurationen zusammen:
# - Base     = allgemeine Basiskonfiguration, z.B. appsettings.json
# - Override = umgebungsspezifische Konfiguration, z.B. environments.onprem.json
#
# Logik:
# - einfache Werte im Override ersetzen Base-Werte
# - verschachtelte Hashtables werden rekursiv gemerged
#
# Damit kann z.B. ExchangeOnline.Enabled in der Basis deaktiviert sein,
# aber im Hybrid-Environment gezielt überschrieben werden.
function Merge-Hashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Base,
        [Parameter(Mandatory = $true)][hashtable]$Override
    )

    $result = @{}
    foreach ($key in $Base.Keys) {
        $result[$key] = $Base[$key]
    }

    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and ($result[$key] -is [hashtable]) -and ($Override[$key] -is [hashtable])) {
            $result[$key] = Merge-Hashtable -Base $result[$key] -Override $Override[$key]
        }
        else {
            $result[$key] = $Override[$key]
        }
    }

    $result
}


# ---------------------------------------------------------------------------
# Read-JsonAsHashtable
# ---------------------------------------------------------------------------
# Zweck:
# Liest eine JSON-Datei ein und gibt sie als echte Hashtable-Struktur zurück.
#
# Wird verwendet für:
# - appsettings.json
# - environments.*.json
# - usecases.json
#
# Fehlerverhalten:
# - fehlende JSON-Dateien sind fatal und führen zu throw
# - leere JSON-Dateien werden als leere Hashtable behandelt
# - ungültiges JSON führt durch ConvertFrom-Json -ErrorAction Stop zu einem Fehler
function Read-JsonAsHashtable {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{}
    }

    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    ConvertTo-HashtableDeep -InputObject $obj
}


# ---------------------------------------------------------------------------
# New-ServiceContainer
# ---------------------------------------------------------------------------
# Zweck:
# Baut die zentrale Service-Fassade für alle UseCase-Handler.
#
# Architektur:
# Handler sollen keine Fachservices direkt hart verdrahten und keine Gateways
# direkt aufrufen. Stattdessen erhalten sie über den JobContext ein Services-
# Objekt:
#
#   $Context.Services.UserProvisioning.RenameUser
#   $Context.Services.GroupMailbox.AddFmaMembers
#   $Context.Services.DistributionGroup.Create
#
# Jede Methode ist ein ScriptBlock, der den aktuellen Context und die Zeilendaten
# an die eigentliche Service-Funktion im shared/-Bereich weiterleitet.
#
# Vorteil:
# - Handler bleiben schlank
# - Tests können Services leichter mocken oder ersetzen
# - Fachlogik bleibt in shared/*Service.psm1
# - technische Systemzugriffe bleiben in infrastructure/*Gateway.psm1
function New-ServiceContainer {
    [CmdletBinding()]
    param()

    @{
        # Services für GenericUser-UseCases:
        # - Erstellen von Generic-/Multifunktionsusern
        # - Aktivieren/Deaktivieren
        # - Rename / Namensänderung
        # - E-Mail-Nickname
        # - Grace Period
        # - Mobile Number
        # - Mailbox-Folder-ACE
        UserProvisioning  = [pscustomobject]@{
            NewUser               = { param($Context, $Data) New-GenericUser -Context $Context -Data $Data }
            EnableUser            = { param($Context, $Data) Enable-GenericUser -Context $Context -Data $Data }
            DisableUser           = { param($Context, $Data) Disable-GenericUser -Context $Context -Data $Data }
            RenameUser            = { param($Context, $Data) Rename-GenericUser -Context $Context -Data $Data }
            SetSurname            = { param($Context, $Data) Set-GenericUserSurname -Context $Context -Data $Data }
            AddEmailNickname      = { param($Context, $Data) Add-GenericUserEmailNickname -Context $Context -Data $Data }
            EnableWithGracePeriod = { param($Context, $Data) Enable-GenericUserWithGracePeriod -Context $Context -Data $Data }
            SetMobilePhoneNumber  = { param($Context, $Data) Set-GenericUserMobilePhoneNumber -Context $Context -Data $Data }
            SetMailboxFolderAce   = { param($Context, $Data) Set-GenericUserMailboxFolderAce -Context $Context -Data $Data }
        }
        # Zentrale Mailbox-Berechtigungsservices.
        # Diese Ebene ist bewusst separat, weil FullAccess und SendAs später
        # On-Prem oder Exchange Online betreffen können.
        MailboxPermission = [pscustomobject]@{
            AddFullAccess    = { param($Context, $Data) Add-MailboxFullAccess -Context $Context -Data $Data }
            RemoveFullAccess = { param($Context, $Data) Remove-MailboxFullAccess -Context $Context -Data $Data }
            AddSendAs        = { param($Context, $Data) Add-MailboxSendAs -Context $Context -Data $Data }
            RemoveSendAs     = { param($Context, $Data) Remove-MailboxSendAs -Context $Context -Data $Data }
        }
        # Services für Gruppenmailboxen:
        # - Erstellung
        # - FullAccess-/SendAs-Mitglieder
        # - Verantwortlichen-/Managerwechsel
        GroupMailbox      = [pscustomobject]@{
            Create        = { param($Context, $Data) New-GroupMailbox -Context $Context -Data $Data }
            AddFmaMembers = { param($Context, $Data) Add-GroupMailboxFmaMembers -Context $Context -Data $Data }
            ChangeManager = { param($Context, $Data) Set-GroupMailboxManager -Context $Context -Data $Data }
        }
        # Services für Verteilerlisten:
        # - Verantwortliche / ManagedBy
        # - Managerwechsel
        # - Erstellung
        # - Löschung
        DistributionGroup = [pscustomobject]@{
            AddResponsibles = { param($Context, $Data) Add-DistributionListResponsibles -Context $Context -Data $Data }
            ChangeManager   = { param($Context, $Data) Set-DistributionGroupManager -Context $Context -Data $Data }
            Create          = { param($Context, $Data) New-DistributionGroupFromRequest -Context $Context -Data $Data }
            Delete          = { param($Context, $Data) Remove-DistributionGroupFromRequest -Context $Context -Data $Data }
        }
        # Services für Hospis-/Personenprozesse:
        # - normale Hospis-Transaktion
        # - dringende Inaktivierung
        HospisPerson      = [pscustomobject]@{
            SubmitTransaction  = { param($Context, $Data) Submit-HospisPersonTransaction -Context $Context -Data $Data }
            UrgentInactivation = { param($Context, $Data) Invoke-UrgentHospisPersonInactivation -Context $Context -Data $Data }
        }
        # Services für den einzigen LongRunning-UseCase:
        # PersonMailbox.CreateNonStandard.
        #
        # Diese Funktionen entsprechen den State-Machine-Schritten:
        # BuildPlan -> PrepareAdAccount -> PrepareMailbox -> TestVisibility
        # -> ApplyAttributes -> Finalize
        PersonMailbox     = [pscustomobject]@{
            BuildPlan        = { param($Context, $Data) New-NonStandardPersonMailboxPlan -Context $Context -Data $Data }
            PrepareAdAccount = { param($Context, $Data) Invoke-PrepareNonStandardPersonMailboxAdAccount -Context $Context -Data $Data }
            PrepareMailbox   = { param($Context, $Data) Invoke-PrepareNonStandardPersonMailboxMailbox -Context $Context -Data $Data }
            TestVisibility   = { param($Context, $Data) Test-NonStandardPersonMailboxVisibility -Context $Context -Data $Data }
            ApplyAttributes  = { param($Context, $Data) Invoke-ApplyNonStandardPersonMailboxAttributes -Context $Context -Data $Data }
            Finalize         = { param($Context, $Data) Complete-NonStandardPersonMailboxProvisioning -Context $Context -Data $Data }
        }
    }
}


# ---------------------------------------------------------------------------
# Convert-ResultToQueueStatus
# ---------------------------------------------------------------------------
# Zweck:
# Übersetzt den fachlichen JobResult.Status in den technischen Queue-Zielordner.
#
# Fachlicher Status:
# - Succeeded
# - Skipped
# - Failed
# - Retry
# - Paused
#
# Technischer Zielordner:
# - done
# - failed
# - retry
# - paused
#
# Wichtig:
# Diese Funktion ist die zentrale Brücke zwischen Handler-Ergebnis und
# Datei-Lifecycle.
function Convert-ResultToQueueStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Status)

    switch ($Status) {
        'Succeeded' { 'done' }
        'Skipped' { 'done' }
        'Failed' { 'failed' }
        'Retry' { 'retry' }
        'Paused' { 'paused' }
        default { 'failed' }
    }
}


# ---------------------------------------------------------------------------
# Invoke-JobEngine
# ---------------------------------------------------------------------------
# Zweck:
# Zentrale Orchestrierung der gesamten Jobverarbeitung.
#
# Verantwortlichkeiten:
# 1. Konfiguration laden und mergen
# 2. Logger initialisieren
# 3. Queue-Ordner sicherstellen
# 4. UseCases aus usecases.json laden und nach Queue filtern
# 5. ServiceContainer erstellen
# 6. pro UseCase:
#    - MaxParallelism über UseCase-Lock absichern
#    - passende CSV-Dateien finden
#    - Dateien claimen
#    - CSV importieren
#    - Handler-Modul dynamisch laden
#    - JobContext erzeugen
#    - Handler ausführen
#    - JobResult prüfen und normalisieren
#    - Datei nach done/failed/retry/paused verschieben
#    - optional Benachrichtigung senden
#
# Nicht-Verantwortlichkeiten:
# - keine fachliche AD-/Exchange-/SQL-/DFS-Logik
# - keine direkte Business-Entscheidung
# - keine UseCase-spezifische Verarbeitung ausser dynamischem Routing
function Invoke-JobEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$UseCaseRegistryPath,
        [Parameter(Mandatory = $true)][string]$EnvironmentPath,
        [Parameter(Mandatory = $true)][ValidateSet('standard', 'urgent', 'person-mailbox-longrunning')][string]$Queue,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [bool]$IncludePaused = $false,
        [bool]$ResumePaused = $false,
        [bool]$WhatIfMode,
        [bool]$VerboseLogging
    )

    # Eindeutige RunId für diesen Engine-Lauf.
    # Alle Logeinträge können dadurch einem konkreten Durchlauf zugeordnet werden.
    $runId = [guid]::NewGuid().ToString('N')

    # Basiskonfiguration laden, z.B. Pfade, Logging, QueueRoot, CSV-Delimiter.
    $baseConfig = Read-JsonAsHashtable -Path $ConfigPath
    # Umgebungskonfiguration laden, z.B. onprem oder hybrid.
    # Diese Werte überschreiben bei Bedarf die Basiskonfiguration.
    $environmentConfig = Read-JsonAsHashtable -Path $EnvironmentPath
    # Basis- und Environment-Konfiguration rekursiv mergen.
    # Ergebnis ist die zur Laufzeit gültige Gesamtkonfiguration.
    $mergedConfig = Merge-Hashtable -Base $baseConfig -Override $environmentConfig
    # RootPath wird explizit in die Config aufgenommen, damit Services und Gateways
    # bei Bedarf auf den Projektwurzelpfad zugreifen können.
    $mergedConfig['RootPath'] = $RootPath

    # Logger initialisieren.
    # Der Logger kapselt Datei-/Konsolen-/Eventlog-Ausgaben gemäss Konfiguration.
    $logger = New-Logger -Config $mergedConfig -RunId $runId -VerboseLogging:$VerboseLogging
    Write-LogInfo -Logger $logger -Message "Starting engine. Queue=$Queue WhatIfMode=$WhatIfMode"

    # Sicherstellen, dass alle Queue-Ordner existieren:
    # incoming, processing, done, failed, retry, paused, archive sowie ggf. locks.
    Ensure-QueueFolders -RootPath $RootPath -QueueRoot $mergedConfig.Paths.QueueRoot

    # UseCase-Registry laden.
    # Die Registry definiert Pattern, Handler, Modul, Queue, Priority und Aktivstatus.
    $registry = Read-JsonAsHashtable -Path $UseCaseRegistryPath
    # Nur aktivierte UseCases der angeforderten Queue werden verarbeitet.
    # Sortierung nach Priority steuert die Reihenfolge innerhalb derselben Queue.
    $useCases = @($registry.UseCases | Where-Object { $_.Enabled -eq $true -and $_.Queue -eq $Queue } | Sort-Object Priority)

    Write-LogInfo -Logger $logger -Message "Loaded $($useCases.Count) use case(s) for queue '$Queue'."

    # ServiceContainer einmal pro Engine-Lauf erstellen.
    # Dieser Container wird später in jeden JobContext injiziert.
    $services = New-ServiceContainer

    # Standardwert für stale Locks.
    # Alte Lock-Dateien können nach Ablauf dieser Zeit als verwaist betrachtet werden.
    $staleLockMinutes = 60
    # Falls in der Config Queue.StaleLockMinutes gesetzt ist, überschreibt dieser
    # Wert den Standard. Dadurch kann die Lock-Toleranz pro Umgebung angepasst werden.
    if ($mergedConfig.ContainsKey('Queue') -and $mergedConfig.Queue -is [hashtable] -and $mergedConfig.Queue.ContainsKey('StaleLockMinutes')) {
        $staleLockMinutes = [int]$mergedConfig.Queue.StaleLockMinutes
    }

    # Hauptschleife über alle aktiven UseCases der gewählten Queue.
    # Jeder UseCase wird isoliert verarbeitet und erhält bei MaxParallelism <= 1
    # einen eigenen UseCase-Lock.
    foreach ($useCase in $useCases) {
        $useCaseLockPath = $null
        # Zweiter try/finally-Block:
        # Stellt sicher, dass ein gesetzter UseCase-Lock auch dann wieder freigegeben
        # wird, wenn einzelne Dateien oder Handler fehlschlagen.
        try {
            # MaxParallelism <= 1 bedeutet:
            # Dieser UseCase darf nicht parallel von mehreren Runnern verarbeitet werden.
            # Die Engine setzt deshalb einen UseCase-Lock.
            if ([int]$useCase.MaxParallelism -le 1) {
                # UseCase-Lock erstellen.
                # Wenn ein anderer Runner denselben UseCase gerade verarbeitet,
                # wird kein Lock zurückgegeben und dieser UseCase wird in diesem Lauf übersprungen.
                $useCaseLockPath = Enter-UseCaseLock -RootPath $RootPath -QueueRoot $mergedConfig.Paths.QueueRoot -UseCaseName $useCase.Name -StaleLockMinutes $staleLockMinutes
                if (-not $useCaseLockPath) {
                    Write-LogWarn -Logger $logger -Message "Use case '$($useCase.Name)' is already locked by another runner. Skipping this cycle."
                    continue
                }
            }

            # Jobdateien anhand des UseCase-Patterns suchen.
            #
            # Standard:
            # - incoming wird gescannt
            # - retry wird nur bei fälligem RetryAfter berücksichtigt
            # - paused wird nur mit IncludePaused oder ResumePaused gescannt
            $files = Find-UseCaseJobFiles -RootPath $RootPath -QueueRoot $mergedConfig.Paths.QueueRoot -Pattern $useCase.Pattern -IncludePaused:$IncludePaused -ResumePaused:$ResumePaused
        }
        # Fehler bei UseCase-Lock oder Dateisuche dürfen nicht die gesamte Engine stoppen.
        # Der betroffene UseCase wird geloggt und übersprungen, danach geht es mit
        # dem nächsten UseCase weiter.
        catch {
            Write-LogError -Logger $logger -Message "Failed to enumerate files for use case '$($useCase.Name)'." -Exception $_.Exception
            if ($useCaseLockPath) {
                Exit-UseCaseLock -LockPath $useCaseLockPath
                $useCaseLockPath = $null
            }
            continue
        }

        # Zweiter try/finally-Block:
        # Stellt sicher, dass ein gesetzter UseCase-Lock auch dann wieder freigegeben
        # wird, wenn einzelne Dateien oder Handler fehlschlagen.
        try {
            # Verarbeitung jeder gefundenen Jobdatei.
            # Jede Datei wird separat geclaimt, importiert, verarbeitet und verschoben.
            foreach ($file in $files) {
                $claimed = $null
                try {
                    # Datei atomar claimen:
                    # - File-Lock setzen
                    # - stabile .meta.json lesen oder erstellen
                    # - CSV nach processing verschieben
                    # - JobId und StableJobKey beibehalten
                    $claimed = Claim-JobFile -FilePath $file.FullName -RootPath $RootPath -QueueRoot $mergedConfig.Paths.QueueRoot -UseCaseName $useCase.Name -Queue $useCase.Queue -StaleLockMinutes $staleLockMinutes
                    # Wenn Claim-JobFile $null liefert, ist die Datei typischerweise
                    # von einem anderen Runner gesperrt oder nicht claimbar.
                    # Das ist kein fataler Fehler.
                    if (-not $claimed) {
                        Write-LogWarn -Logger $logger -Message "Skipping non-claimable file: $($file.FullName)"
                        continue
                    }

                    Write-LogInfo -Logger $logger -Message "Claimed file '$($claimed.WorkingFile)' for use case '$($useCase.Name)'."

                    # CSV-Payload importieren.
                    # Ab hier arbeitet der Handler nicht mehr mit Dateien, sondern nur
                    # noch mit $Context.Payload.
                    $payload = Import-JobCsv -Path $claimed.WorkingFile -Delimiter $mergedConfig.CsvDelimiter
                    # Modulpfad aus RootPath und Registry-Eintrag bilden.
                    # Das Handler-Modul wird dynamisch pro UseCase importiert.
                    $modulePath = Join-Path -Path $RootPath -ChildPath $useCase.Module
                    # Fehlendes Handler-Modul ist ein harter Fehler für diese Datei,
                    # weil der UseCase nicht ausgeführt werden kann.
                    if (-not (Test-Path -Path $modulePath -PathType Leaf)) {
                        throw "Use case module not found: $modulePath"
                    }

                    # Handler-Modul importieren.
                    # -Force sorgt dafür, dass Änderungen während Entwicklung/Test
                    # beim nächsten Lauf neu geladen werden.
                    Import-Module -Name $modulePath -Force -ErrorAction Stop

                    # Standardisierten JobContext erstellen.
                    #
                    # Der Context enthält alles, was ein Handler braucht:
                    # - JobId / StableJobKey
                    # - RunId
                    # - UseCaseName und Queue
                    # - SourceFile / WorkingFile / MetadataPath
                    # - importierter Payload
                    # - gemergte Config und Environment
                    # - ServiceContainer
                    # - Logger
                    # - WhatIfMode
                    $context = New-JobContext -JobId $claimed.JobId -StableJobKey $claimed.StableJobKey -RunId $runId -UseCaseName $useCase.Name -Queue $Queue -SourceFile $claimed.SourceFile -WorkingFile $claimed.WorkingFile -MetadataPath $claimed.MetadataPath -JobMetadata $claimed.Metadata -Payload $payload -Config $mergedConfig -Environment $environmentConfig -Services $services -Logger $logger -RootPath $RootPath -WhatIfMode:$WhatIfMode -VerboseLogging:$VerboseLogging

                    # Handler dynamisch ausführen.
                    # Der Handlername stammt aus usecases.json.
                    # Erwartung: Der Handler gibt ein standardisiertes JobResult zurück.
                    $result = & $useCase.Handler -Context $context
                    # JobResult validieren:
                    # Unter StrictMode darf nicht blind auf .Status zugegriffen werden.
                    # Deshalb wird zuerst geprüft, ob die Property existiert.
                    $resultStatus = if ($result -and $result.PSObject.Properties['Status']) { $result.Status } else { $null }
                    # Falls ein Handler nichts oder kein gültiges JobResult liefert,
                    # wird das Ergebnis in einen kontrollierten Failed-Status umgewandelt.
                    # Dadurch bleibt der Datei-Lifecycle konsistent.
                    if (-not $resultStatus) {
                        $result = New-JobFailedResult -Message "Handler '$($useCase.Handler)' returned no valid JobResult." -ErrorCode 'INVALID_HANDLER_RESULT'
                        $resultStatus = 'Failed'
                    }

                    # Optionale JobResult-Properties normalisieren.
                    # Grund: Unter StrictMode können fehlende Properties Fehler werfen.
                    # Deshalb wird jede optionale Property vor Zugriff geprüft.
                    # Normalize optional result properties for strict-mode safety
                    $resultMessage = if ($result.PSObject.Properties['Message']) { [string]$result.Message }     else { '' }
                    $resultRetry = if ($result.PSObject.Properties['RetryAfter']) { $result.RetryAfter }          else { $null }
                    $resultResume = if ($result.PSObject.Properties['ResumeAfter']) { $result.ResumeAfter }         else { $null }
                    $resultPause = if ($result.PSObject.Properties['PauseReason']) { $result.PauseReason }         else { $null }
                    $resultErrCode = if ($result.PSObject.Properties['ErrorCode']) { $result.ErrorCode }           else { $null }

                    # Fachlichen Result-Status in technischen Queue-Zielstatus übersetzen.
                    # Beispiel: Succeeded -> done, Retry -> retry, Paused -> paused.
                    $targetStatus = Convert-ResultToQueueStatus -Status $resultStatus
                    # Parameter für Move-JobFileToStatus vorbereiten.
                    # Nicht alle optionalen Felder werden immer gesetzt.
                    # RetryAfter wird nur bei Retry übergeben, ResumeAfter/PauseReason
                    # nur bei Paused.
                    $moveParams = @{
                        WorkingFile = $claimed.WorkingFile
                        RootPath    = $RootPath
                        QueueRoot   = $mergedConfig.Paths.QueueRoot
                        Status      = $targetStatus
                        Message     = $resultMessage
                        JobResult   = $result
                    }
                    if ($resultRetry -and $resultStatus -eq 'Retry') {
                        $moveParams['RetryAfter'] = $resultRetry
                    }
                    if ($resultResume -and $resultStatus -eq 'Paused') {
                        $moveParams['ResumeAfter'] = $resultResume
                    }
                    if ($resultPause -and $resultStatus -eq 'Paused') {
                        $moveParams['PauseReason'] = $resultPause
                    }
                    if ($resultErrCode) {
                        $moveParams['ErrorCode'] = $resultErrCode
                    }

                    # Datei und .meta.json in den Zielordner verschieben.
                    # Dabei wird die Metadata aktualisiert, z.B. Status, RetryAfter,
                    # ResumeAfter, LastMessage und ErrorCode.
                    $movedPath = Move-JobFileToStatus @moveParams
                    Write-LogInfo -Logger $logger -Message "Job '$($claimed.JobId)' finished with status '$resultStatus'. File moved to '$movedPath'."

                    # Bei Failed kann eine Fehlerbenachrichtigung versendet werden.
                    # Die konkrete Versandlogik liegt in MailNotification.psm1.
                    if ($resultStatus -eq 'Failed') {
                        Send-JobFailureNotification `
                            -Config      $mergedConfig `
                            -UseCaseName $useCase.Name `
                            -Message     $resultMessage `
                            -JobResult   $result `
                            -Metadata    $claimed.Metadata `
                            -JobId       $claimed.JobId `
                            -Queue       $useCase.Queue `
                            -SourceFile  $claimed.SourceFile `
                            -MovedPath   $movedPath `
                            -Logger      $logger
                    }
                    # Bei Succeeded kann eine Erfolgsbenachrichtigung versendet werden.
                    # Skipped, Retry und Paused erzeugen hier bewusst keine Success-Mail.
                    elseif ($resultStatus -eq 'Succeeded') {
                        Send-JobSuccessNotification `
                            -Config      $mergedConfig `
                            -UseCaseName $useCase.Name `
                            -Message     $resultMessage `
                            -JobResult   $result `
                            -Metadata    $claimed.Metadata `
                            -JobId       $claimed.JobId `
                            -Queue       $useCase.Queue `
                            -SourceFile  $claimed.SourceFile `
                            -MovedPath   $movedPath `
                            -Logger      $logger
                    }
                }
                # Fehler innerhalb einer einzelnen Datei werden abgefangen.
                # Die Engine verarbeitet danach weiterhin die nächste Datei.
                catch {
                    Write-LogError -Logger $logger -Message "Engine error while processing '$($file.FullName)' for '$($useCase.Name)'." -Exception $_.Exception

                    # Wenn die Datei bereits geclaimt wurde und noch im processing-Ordner liegt,
                    # wird versucht, sie sauber nach failed zu verschieben.
                    if ($claimed -and (Test-Path -Path $claimed.WorkingFile)) {
                        try {
                            # Fallback-Fehlerpfad:
                            # Die Datei wird als failed markiert, auch wenn der Fehler
                            # ausserhalb des Handlers entstanden ist, z.B. CSV-Import,
                            # Modulimport oder Context-Erstellung.
                            Move-JobFileToStatus -WorkingFile $claimed.WorkingFile -RootPath $RootPath -QueueRoot $mergedConfig.Paths.QueueRoot -Status 'failed' -Message $_.Exception.Message -ErrorCode 'ENGINE_ERROR' -AllowMetadataFallback | Out-Null
                        }
                        catch {
                            Write-LogError -Logger $logger -Message "Could not move failed file '$($claimed.WorkingFile)' to failed queue." -Exception $_.Exception
                        }
                    }
                }
            }
        }
        # UseCase-Lock immer freigeben, wenn er gesetzt wurde.
        # Dadurch bleiben keine Locks hängen, wenn einzelne Jobs fehlschlagen.
        finally {
            if ($useCaseLockPath) {
                Exit-UseCaseLock -LockPath $useCaseLockPath
            }
        }
    }

    # Abschlusslog für den gesamten Engine-Lauf.
    Write-LogInfo -Logger $logger -Message 'Job engine completed.'
}


# Nur Invoke-JobEngine wird als öffentliche Modulfunktion exportiert.
# Alle anderen Funktionen in dieser Datei sind interne Hilfsfunktionen des Moduls.
Export-ModuleMember -Function @('Invoke-JobEngine')
