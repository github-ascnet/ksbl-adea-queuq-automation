Set-StrictMode -Version Latest

# ─────────────────────────────────────────────────────────────────────────────
# Zentraler In-Memory-Zustand für die EXO-Sessionverwaltung.
# Der State lebt pro PowerShell-Prozess und wird zwischen Gateway-Aufrufen
# wiederverwendet (ReuseSession=true) oder erzwingt Neuverbindung (false).
#
# Felder:
# - Connected     : $true wenn zuletzt erfolgreicher Connect bestätigt wurde
# - RuntimeConfig : zuletzt gesetzte Laufzeitkonfiguration (aus JobEngine)
# ─────────────────────────────────────────────────────────────────────────────
$script:ExchangeOnlineSessionState = @{
    Connected     = $false
    RuntimeConfig = $null
}

# Setzt die Runtime-Konfiguration für dieses Gateway explizit.
# Die JobEngine ruft diese Funktion nach dem Merge von appsettings + environment auf.
function Set-ExchangeOnlineRuntimeConfig {
    [CmdletBinding()]
    param([hashtable]$Config)

    $script:ExchangeOnlineSessionState.RuntimeConfig = $Config
}

# ─────────────────────────────────────────────────────────────────────────────
# Config-Hilfsfunktionen (für EXO-Modul isoliert, analog ExchangeOnPremGateway)
# Unterstützen sowohl native Hashtables als auch ConvertFrom-Json-PSCustomObjects.
# ─────────────────────────────────────────────────────────────────────────────

function Get-EXOConfigNode {
    param(
        [Parameter(Mandatory = $true)][object]$Source,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if ($null -eq $Source) { return $null }
    if ($Source -is [hashtable]) {
        if ($Source.ContainsKey($Key)) { return $Source[$Key] }
        return $null
    }
    $prop = $Source.PSObject.Properties[$Key]
    if ($prop) { return $prop.Value }
    return $null
}

function Test-EXOConfigKey {
    param(
        [Parameter(Mandatory = $true)][object]$Source,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if ($null -eq $Source) { return $false }
    if ($Source -is [hashtable]) { return $Source.ContainsKey($Key) }
    return $null -ne $Source.PSObject.Properties[$Key]
}

function Get-EXOConfigValue {
    param(
        [Parameter(Mandatory = $true)][object]$Source,
        [Parameter(Mandatory = $true)][string]$Key,
        [object]$Default = $null
    )

    $node = Get-EXOConfigNode -Source $Source -Key $Key
    if ($null -eq $node) { return $Default }
    return $node
}

# ─────────────────────────────────────────────────────────────────────────────
# Wrapper-Funktionen (keine Fachlogik, nur technische Aufrufe)
# Erlauben sauberes Mocken in Pester ohne echte EXO-Verbindung.
# ─────────────────────────────────────────────────────────────────────────────

function Import-ExchangeOnlineManagementModuleInternal {
    [CmdletBinding()]
    param()
    Import-Module -Name ExchangeOnlineManagement -ErrorAction Stop
}

function Get-ExchangeOnlineModuleInternal {
    [CmdletBinding()]
    param()
    Get-Module -Name ExchangeOnlineManagement -ErrorAction SilentlyContinue
}

function Get-ExchangeOnlineModuleAvailableInternal {
    [CmdletBinding()]
    param()
    Get-Module -Name ExchangeOnlineManagement -ListAvailable -ErrorAction SilentlyContinue
}

function Connect-ExchangeOnlineInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters)
    Connect-ExchangeOnline @Parameters
}

function Disconnect-ExchangeOnlineInternal {
    [CmdletBinding()]
    param()
    Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
}

function Get-ExchangeOnlineConnectionInformationInternal {
    [CmdletBinding()]
    param()
    Get-ConnectionInformation
}

function Get-ExchangeOnlineCertificateInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Thumbprint,
        [Parameter(Mandatory = $true)][string]$StoreLocation
    )
    Get-ChildItem -Path "Cert:\$StoreLocation\My" -ErrorAction SilentlyContinue |
    Where-Object { $_.Thumbprint -eq $Thumbprint }
}

function Invoke-ExchangeOnlineValidationCommandInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][int]$ResultSize
    )
    & $Command -ResultSize $ResultSize -ErrorAction Stop
}

function Get-EXODateInternal {
    [CmdletBinding()]
    param()
    Get-Date
}

function Import-ExchangeConnectionHealthModuleInternal {
    [CmdletBinding()]
    param()
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'ExchangeConnectionHealth.psm1') -ErrorAction Stop
}

function Ensure-ExchangeConnectionHealthModule {
    [CmdletBinding()]
    param()

    $loaded = Get-Module -Name ExchangeConnectionHealth -ErrorAction SilentlyContinue
    if (-not $loaded) {
        Import-ExchangeConnectionHealthModuleInternal
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Konfiguration lesen und validieren
#
# Auflösung in dieser Reihenfolge:
# 1) Context.Config
# 2) explizit übergebene Config
# 3) zuvor gesetzte RuntimeConfig
#
# Organization hat Vorrang vor TenantDomain; mindestens einer der beiden muss gesetzt sein.
# ─────────────────────────────────────────────────────────────────────────────
function Get-ExchangeOnlineRemotePowerShellConfig {
    [CmdletBinding()]
    param(
        [hashtable]$Config = $null,
        [object]$Context = $null
    )

    $effectiveConfig = $null
    if ($null -ne $Context -and (Test-EXOConfigKey -Source $Context -Key 'Config')) {
        $effectiveConfig = Get-EXOConfigNode -Source $Context -Key 'Config'
    }
    elseif ($null -ne $Config) {
        $effectiveConfig = $Config
    }
    elseif ($null -ne $script:ExchangeOnlineSessionState.RuntimeConfig) {
        $effectiveConfig = $script:ExchangeOnlineSessionState.RuntimeConfig
    }

    if (-not $effectiveConfig) {
        throw 'Exchange Online Konfiguration fehlt. Keine Runtime-Konfiguration verfügbar.'
    }

    $exoNode = Get-EXOConfigNode -Source $effectiveConfig -Key 'ExchangeOnline'
    if (-not $exoNode) {
        throw "Exchange Online Konfigurationsabschnitt 'ExchangeOnline' fehlt."
    }

    $enabled = [bool](Get-EXOConfigValue -Source $exoNode -Key 'Enabled' -Default $false)
    if (-not $enabled) {
        throw 'Exchange Online ist deaktiviert (ExchangeOnline.Enabled=false). Setze Enabled=true, um EXO-Operationen auszuführen.'
    }

    $appId = [string](Get-EXOConfigValue -Source $exoNode -Key 'AppId' -Default '')
    if ([string]::IsNullOrWhiteSpace($appId)) {
        throw "Exchange Online Konfigurationswert 'AppId' fehlt."
    }

    $organization = [string](Get-EXOConfigValue -Source $exoNode -Key 'Organization'  -Default '')
    $tenantDomain = [string](Get-EXOConfigValue -Source $exoNode -Key 'TenantDomain'  -Default '')
    $effectiveOrg = if (-not [string]::IsNullOrWhiteSpace($organization)) { $organization } else { $tenantDomain }

    if ([string]::IsNullOrWhiteSpace($effectiveOrg)) {
        throw "Exchange Online Konfiguration erfordert entweder 'Organization' oder 'TenantDomain'."
    }

    $thumbprint = [string](Get-EXOConfigValue -Source $exoNode -Key 'CertificateThumbprint' -Default '')
    if ([string]::IsNullOrWhiteSpace($thumbprint)) {
        throw "Exchange Online Konfigurationswert 'CertificateThumbprint' fehlt."
    }

    $showBanner = [bool]  (Get-EXOConfigValue -Source $exoNode -Key 'ShowBanner'                    -Default $false)
    $reuseSession = [bool]  (Get-EXOConfigValue -Source $exoNode -Key 'ReuseSession'                  -Default $true)
    $reconnectOnFailure = [bool]  (Get-EXOConfigValue -Source $exoNode -Key 'ReconnectOnFailure'            -Default $true)
    $maxReconnect = [int]   (Get-EXOConfigValue -Source $exoNode -Key 'MaxReconnectAttempts'          -Default 1)
    $validateWithCmd = [bool]  (Get-EXOConfigValue -Source $exoNode -Key 'ValidateConnectionWithCommand' -Default $false)
    $validationCmd = [string](Get-EXOConfigValue -Source $exoNode -Key 'ConnectionValidationCommand'   -Default 'Get-EXORecipient')
    $validationResultSize = [int]   (Get-EXOConfigValue -Source $exoNode -Key 'ConnectionValidationResultSize' -Default 1)

    return [ordered]@{
        Enabled                        = $enabled
        AppId                          = $appId
        Organization                   = $effectiveOrg
        CertificateThumbprint          = $thumbprint
        ShowBanner                     = $showBanner
        ReuseSession                   = $reuseSession
        ReconnectOnFailure             = $reconnectOnFailure
        MaxReconnectAttempts           = $maxReconnect
        ValidateConnectionWithCommand  = $validateWithCmd
        ConnectionValidationCommand    = $validationCmd
        ConnectionValidationResultSize = $validationResultSize
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Modulverwaltung
# ─────────────────────────────────────────────────────────────────────────────

function Import-ExchangeOnlineManagementModule {
    [CmdletBinding()]
    param()

    $loaded = Get-ExchangeOnlineModuleInternal
    if ($loaded) { return }

    $available = Get-ExchangeOnlineModuleAvailableInternal
    if (-not $available) {
        throw 'Das ExchangeOnlineManagement-Modul ist nicht installiert. Führe aus: Install-Module ExchangeOnlineManagement'
    }

    try {
        Import-ExchangeOnlineManagementModuleInternal
    }
    catch {
        throw "ExchangeOnlineManagement-Modul konnte nicht importiert werden. $($_.Exception.Message)"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Zertifikatsprüfung
#
# Prüft lokal im Zertifikatsspeicher:
# - Zertifikat vorhanden (LocalMachine\My, dann CurrentUser\My)
# - HasPrivateKey = true
# - Nicht abgelaufen
#
# Das Gateway importiert keine PFX-Dateien. Es prüft nur die Runtime-Bereitschaft.
# Klare Diagnose bei Private-Key-Problemen ("Der Schlüsselsatz ist nicht vorhanden").
# ─────────────────────────────────────────────────────────────────────────────
function Test-ExchangeOnlineCertificate {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Thumbprint)

    $cert = $null
    foreach ($store in @('LocalMachine', 'CurrentUser')) {
        $found = Get-ExchangeOnlineCertificateInternal -Thumbprint $Thumbprint -StoreLocation $store
        if ($found) { $cert = $found; break }
    }

    if (-not $cert) {
        throw "Exchange Online App-only Authentication: Zertifikat mit Thumbprint '$Thumbprint' wurde nicht gefunden in Cert:\LocalMachine\My oder Cert:\CurrentUser\My."
    }

    if (-not $cert.HasPrivateKey) {
        throw "Exchange Online App-only Authentication konnte das Zertifikat finden, aber der private Schlüssel ist nicht vorhanden. Thumbprint: '$Thumbprint'. Prüfe, ob das Zertifikat als PFX mit Private Key im Zertifikatsspeicher liegt. Prüfe HasPrivateKey. Prüfe Private-Key-Leserecht für das ausführende Servicekonto."
    }

    $now = Get-EXODateInternal
    if ($cert.NotAfter -lt $now) {
        throw "Exchange Online App-only Authentication: Zertifikat mit Thumbprint '$Thumbprint' ist abgelaufen (NotAfter: $($cert.NotAfter))."
    }

    return $cert
}

# ─────────────────────────────────────────────────────────────────────────────
# Sessionprüfung via Get-ConnectionInformation
#
# Gibt $true zurück wenn eine aktive EXO-Verbindung besteht.
# Gibt $false zurück wenn keine Verbindung besteht – wirft keine Exception.
# Optional: leichter Validierungsbefehl wenn ValidateConnectionWithCommand=true.
# ─────────────────────────────────────────────────────────────────────────────
function Test-ExchangeOnlineSession {
    [CmdletBinding()]
    param(
        [hashtable]$Config = $null,
        [object]$Context = $null
    )

    try {
        $connectionInfo = Get-ExchangeOnlineConnectionInformationInternal
        if (-not $connectionInfo) { return $false }

        $active = @($connectionInfo | Where-Object {
                ($_.State -eq 'Connected') -or
                ($null -ne $_.ConnectionUri -and $_.ConnectionUri -like '*office365.com*')
            })
        if ($active.Count -eq 0) { return $false }

        if ($null -ne $Config -or $null -ne $Context) {
            try {
                $exoConfig = Get-ExchangeOnlineRemotePowerShellConfig -Config $Config -Context $Context
                if ($exoConfig.ValidateConnectionWithCommand) {
                    Invoke-ExchangeOnlineValidationCommandInternal `
                        -Command $exoConfig.ConnectionValidationCommand `
                        -ResultSize $exoConfig.ConnectionValidationResultSize | Out-Null
                }
            }
            catch {
                return $false
            }
        }

        return $true
    }
    catch {
        return $false
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Verbindungsaufbau (App-only, Zertifikat-basiert)
#
# Reihenfolge:
# 1) Konfiguration laden und validieren
# 2) ExchangeOnlineManagement-Modul sicherstellen
# 3) Zertifikat lokal prüfen (HasPrivateKey, Ablaufdatum)
# 4) Connect-ExchangeOnline mit AppId, Organization, CertificateThumbprint
#
# Keine interaktive Anmeldung. Keine Secrets im Code.
# Klare Diagnose bei Private-Key-Fehler "Der Schlüsselsatz ist nicht vorhanden".
# ─────────────────────────────────────────────────────────────────────────────
function Connect-ExchangeOnlineSession {
    [CmdletBinding()]
    param(
        [hashtable]$Config = $null,
        [object]$Context = $null
    )

    $exoConfig = Get-ExchangeOnlineRemotePowerShellConfig -Config $Config -Context $Context

    Import-ExchangeOnlineManagementModule

    try {
        Test-ExchangeOnlineCertificate -Thumbprint $exoConfig.CertificateThumbprint | Out-Null
    }
    catch {
        $certMsg = $_.Exception.Message
        if ($certMsg -match 'private.*Schlüssel|HasPrivateKey|private.*key|keyset|Schlüsselsatz') {
            throw "Exchange Online App-only Authentication konnte das Zertifikat finden, aber der private Schlüssel ist nicht nutzbar. Thumbprint: '$($exoConfig.CertificateThumbprint)'. Prüfe, ob das Zertifikat als PFX mit Private Key im Zertifikatsspeicher liegt. Prüfe HasPrivateKey. Prüfe Private-Key-Leserecht für das ausführende Servicekonto. Details: $certMsg"
        }
        throw
    }

    $connectParams = @{
        AppId                 = $exoConfig.AppId
        CertificateThumbprint = $exoConfig.CertificateThumbprint
        Organization          = $exoConfig.Organization
        ShowBanner            = $exoConfig.ShowBanner
        ErrorAction           = 'Stop'
    }

    try {
        Connect-ExchangeOnlineInternal -Parameters $connectParams
        $script:ExchangeOnlineSessionState.Connected = $true
    }
    catch {
        $script:ExchangeOnlineSessionState.Connected = $false
        $connectMsg = $_.Exception.Message
        if ($connectMsg -match 'Schlüsselsatz|keyset does not exist|Der Schlüsselsatz|private.*key|certificate.*private') {
            throw "Exchange Online App-only Authentication konnte das Zertifikat finden, aber der private Schlüssel ist nicht nutzbar. Thumbprint: '$($exoConfig.CertificateThumbprint)'. Prüfe, ob das Zertifikat als PFX mit Private Key im Zertifikatsspeicher liegt. Prüfe HasPrivateKey. Prüfe Private-Key-Leserecht für das ausführende Servicekonto. Details: $connectMsg"
        }
        throw "Exchange Online Connect-ExchangeOnline fehlgeschlagen (Organisation: $($exoConfig.Organization), AppId: $($exoConfig.AppId)). $connectMsg"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Session sicherstellen (zentraler Einstiegspunkt vor jedem EXO-Befehl)
#
# - Wenn Enabled=false: kontrollierten Fehler werfen (via Get-ExchangeOnlineRemotePowerShellConfig)
# - Wenn ReuseSession=true und aktive Verbindung: wiederverwenden
# - Sonst: Connect-ExchangeOnlineSession aufrufen
# - Nach Connect: Verbindung erneut prüfen
# ─────────────────────────────────────────────────────────────────────────────
function Ensure-ExchangeOnlineSession {
    [CmdletBinding()]
    param(
        [hashtable]$Config = $null,
        [object]$Context = $null
    )

    $exoConfig = Get-ExchangeOnlineRemotePowerShellConfig -Config $Config -Context $Context

    if ($exoConfig.ReuseSession -and (Test-ExchangeOnlineSession -Config $Config -Context $Context)) {
        return
    }

    Connect-ExchangeOnlineSession -Config $Config -Context $Context

    if (-not (Test-ExchangeOnlineSession -Config $Config -Context $Context)) {
        throw 'Exchange Online Verbindung konnte nicht aufgebaut werden. Get-ConnectionInformation liefert nach Connect-ExchangeOnline keine aktive Verbindung.'
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Session beenden (Reset: hart, intern)
# ─────────────────────────────────────────────────────────────────────────────
function Reset-ExchangeOnlineSession {
    [CmdletBinding()]
    param()

    try {
        Disconnect-ExchangeOnlineInternal
    }
    catch {
        # Reset muss robust und idempotent sein.
    }
    $script:ExchangeOnlineSessionState.Connected = $false
}

# Öffentliche, robuste Disconnect-Funktion (idempotent).
function Disconnect-ExchangeOnlineSession {
    [CmdletBinding()]
    param()

    try {
        Reset-ExchangeOnlineSession
    }
    catch {
        # Disconnect muss robust und idempotent sein.
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# Zentraler Ausführungs-Wrapper mit Reconnect-Logik
#
# Ablauf:
# 1) Ensure-ExchangeOnlineSession
# 2) ScriptBlock lokal ausführen (EXO-Cmdlets über Modul verfügbar)
# 3) Bei EXO-Verbindungsfehler und ReconnectOnFailure=true:
#    Reset-ExchangeOnlineSession, einmal erneut versuchen
#
# Exchange Online Cmdlets werden lokal über ExchangeOnlineManagement bereitgestellt.
# Kein New-PSSession / Invoke-Command Modell (OnPrem-Muster).
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-ExchangeOnlineCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [hashtable]$Config = $null,
        [object]$Context = $null
    )

    $exoConfig = Get-ExchangeOnlineRemotePowerShellConfig -Config $Config -Context $Context
    $maxReconnect = [Math]::Max(0, [int]$exoConfig.MaxReconnectAttempts)
    $totalAttempts = if ($exoConfig.ReconnectOnFailure) { 1 + $maxReconnect } else { 1 }

    for ($attempt = 1; $attempt -le $totalAttempts; $attempt++) {
        try {
            Ensure-ExchangeOnlineSession -Config $Config -Context $Context
            return (& $ScriptBlock)
        }
        catch {
            $errMsg = $_.Exception.Message
            $isConnErr = $errMsg -match (
                'not connected|connection.*lost|session.*expired|unauthorized|The pipeline|WinRM|token.*expired|' +
                'authentication.*failed|Schließen der Pipeline|pipeline.*stopped|Verbindung.*unterbrochen|' +
                'ExchangeOnline.*Verbindung|cannot.*connect|ConnectExchangeOnline'
            )
            $canRetry = $isConnErr -and $exoConfig.ReconnectOnFailure -and ($attempt -lt $totalAttempts)
            if ($canRetry) {
                Reset-ExchangeOnlineSession
                continue
            }
            throw "Exchange Online Befehl fehlgeschlagen. $errMsg"
        }
    }

    throw 'Exchange Online Befehl fehlgeschlagen nach Reconnect-Versuchen.'
}

# ─────────────────────────────────────────────────────────────────────────────
# Health- und Diagnosefunktion fuer Exchange Online
#
# - Baut keine Verbindung auf, ausser EnsureConnected ist gesetzt.
# - Prueft Modulverfuegbarkeit, Zertifikat und ConnectionInformation.
# - Optional: validiert eine leichte EXO-Abfrage mit ValidateCommand.
#
# Liefert ein ExchangeConnectionHealth-Resultobjekt.
# ─────────────────────────────────────────────────────────────────────────────
function Test-ExchangeOnlineConnectionHealth {
    [CmdletBinding()]
    param(
        [hashtable]$Config = $null,
        [object]$Context = $null,
        [switch]$EnsureConnected,
        [switch]$ValidateCommand
    )

    Ensure-ExchangeConnectionHealthModule

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $checkedAt = Get-ExchangeConnectionCurrentTimeInternal

    $target = 'ExchangeOnline'
    $connectionType = 'ExchangeOnlineManagementAppOnly'

    $effectiveConfig = $null
    if ($null -ne $Context -and (Test-EXOConfigKey -Source $Context -Key 'Config')) {
        $effectiveConfig = Get-EXOConfigNode -Source $Context -Key 'Config'
    }
    elseif ($null -ne $Config) {
        $effectiveConfig = $Config
    }
    elseif ($null -ne $script:ExchangeOnlineSessionState.RuntimeConfig) {
        $effectiveConfig = $script:ExchangeOnlineSessionState.RuntimeConfig
    }

    if (-not $effectiveConfig) {
        return New-ExchangeConnectionHealthResult -Target $target -ConnectionType $connectionType `
            -Enabled $false -IsConnected $false -IsUsable $false -Status 'NotConfigured' `
            -Message 'Exchange Online configuration missing.' -CheckedAt $checkedAt `
            -DurationMilliseconds $stopwatch.ElapsedMilliseconds
    }

    $exoNode = Get-EXOConfigNode -Source $effectiveConfig -Key 'ExchangeOnline'
    if (-not $exoNode) {
        return New-ExchangeConnectionHealthResult -Target $target -ConnectionType $connectionType `
            -Enabled $false -IsConnected $false -IsUsable $false -Status 'NotConfigured' `
            -Message "Exchange Online configuration section 'ExchangeOnline' missing." -CheckedAt $checkedAt `
            -DurationMilliseconds $stopwatch.ElapsedMilliseconds
    }

    $enabled = [bool](Get-EXOConfigValue -Source $exoNode -Key 'Enabled' -Default $false)
    if (-not $enabled) {
        return New-ExchangeConnectionHealthResult -Target $target -ConnectionType $connectionType `
            -Enabled $false -IsConnected $false -IsUsable $false -Status 'Disabled' `
            -Message 'Exchange Online disabled by configuration.' -CheckedAt $checkedAt `
            -DurationMilliseconds $stopwatch.ElapsedMilliseconds
    }

    $appId = [string](Get-EXOConfigValue -Source $exoNode -Key 'AppId' -Default '')
    $organization = [string](Get-EXOConfigValue -Source $exoNode -Key 'Organization' -Default '')
    $tenantDomain = [string](Get-EXOConfigValue -Source $exoNode -Key 'TenantDomain' -Default '')
    $effectiveOrg = if (-not [string]::IsNullOrWhiteSpace($organization)) { $organization } else { $tenantDomain }
    $thumbprint = [string](Get-EXOConfigValue -Source $exoNode -Key 'CertificateThumbprint' -Default '')

    $moduleLoaded = Get-ExchangeOnlineModuleInternal
    $moduleAvailable = Get-ExchangeOnlineModuleAvailableInternal
    if (-not $moduleLoaded -and -not $moduleAvailable) {
        return New-ExchangeConnectionHealthResult -Target $target -ConnectionType $connectionType `
            -Enabled $true -IsConnected $false -IsUsable $false -Status 'MissingModule' `
            -Message 'ExchangeOnlineManagement module not installed.' -CheckedAt $checkedAt `
            -DurationMilliseconds $stopwatch.ElapsedMilliseconds -Organization $effectiveOrg -AppId $appId
    }

    if (-not [string]::IsNullOrWhiteSpace($thumbprint)) {
        try {
            Test-ExchangeOnlineCertificate -Thumbprint $thumbprint | Out-Null
        }
        catch {
            $msg = $_.Exception.Message
            $status = 'Failed'
            if ($msg -match 'nicht gefunden') { $status = 'CertificateMissing' }
            elseif ($msg -match 'private.*Schluessel|private.*key|HasPrivateKey|Schlüssel') { $status = 'CertificatePrivateKeyMissing' }
            elseif ($msg -match 'abgelaufen') { $status = 'CertificateExpired' }

            return New-ExchangeConnectionHealthResult -Target $target -ConnectionType $connectionType `
                -Enabled $true -IsConnected $false -IsUsable $false -Status $status `
                -Message $msg -CheckedAt $checkedAt -DurationMilliseconds $stopwatch.ElapsedMilliseconds `
                -Organization $effectiveOrg -AppId $appId -CertificateThumbprint $thumbprint
        }
    }

    if ($EnsureConnected.IsPresent) {
        try {
            Ensure-ExchangeOnlineSession -Config $Config -Context $Context
        }
        catch {
            return New-ExchangeConnectionHealthResult -Target $target -ConnectionType $connectionType `
                -Enabled $true -IsConnected $false -IsUsable $false -Status 'Failed' `
                -Message $_.Exception.Message -CheckedAt $checkedAt `
                -DurationMilliseconds $stopwatch.ElapsedMilliseconds -Organization $effectiveOrg `
                -AppId $appId -CertificateThumbprint $thumbprint
        }
    }

    $connectionInfo = $null
    try {
        $connectionInfo = Get-ExchangeOnlineConnectionInformationInternal
    }
    catch {
        $connectionInfo = $null
    }

    $active = @()
    if ($connectionInfo) {
        $active = @($connectionInfo | Where-Object {
                ($_.State -eq 'Connected') -or
                ($null -ne $_.ConnectionUri -and $_.ConnectionUri -like '*office365.com*')
            })
    }

    if ($active.Count -eq 0) {
        return New-ExchangeConnectionHealthResult -Target $target -ConnectionType $connectionType `
            -Enabled $true -IsConnected $false -IsUsable $false -Status 'NotConnected' `
            -Message 'No active Exchange Online connection.' -CheckedAt $checkedAt `
            -DurationMilliseconds $stopwatch.ElapsedMilliseconds -Organization $effectiveOrg `
            -AppId $appId -CertificateThumbprint $thumbprint
    }

    if ($ValidateCommand.IsPresent) {
        $validationCmd = [string](Get-EXOConfigValue -Source $exoNode -Key 'ConnectionValidationCommand' -Default 'Get-EXORecipient')
        $validationSize = [int](Get-EXOConfigValue -Source $exoNode -Key 'ConnectionValidationResultSize' -Default 1)
        try {
            Invoke-ExchangeOnlineValidationCommandInternal -Command $validationCmd -ResultSize $validationSize | Out-Null
        }
        catch {
            return New-ExchangeConnectionHealthResult -Target $target -ConnectionType $connectionType `
                -Enabled $true -IsConnected $true -IsUsable $false -Status 'Unusable' `
                -Message $_.Exception.Message -CheckedAt $checkedAt -DurationMilliseconds $stopwatch.ElapsedMilliseconds `
                -Organization $effectiveOrg -AppId $appId -CertificateThumbprint $thumbprint
        }
    }

    $connectionUri = $active[0].ConnectionUri
    $sessionState = $active[0].State

    return New-ExchangeConnectionHealthResult -Target $target -ConnectionType $connectionType `
        -Enabled $true -IsConnected $true -IsUsable $true -Status 'Connected' `
        -Message 'Exchange Online connection is active.' -CheckedAt $checkedAt `
        -DurationMilliseconds $stopwatch.ElapsedMilliseconds -Organization $effectiveOrg `
        -AppId $appId -CertificateThumbprint $thumbprint -ConnectionUri $connectionUri `
        -SessionState $sessionState
}

# ─────────────────────────────────────────────────────────────────────────────
# Öffentliche Gateway-Funktionen
#
# Alle Funktionen laufen über Invoke-ExchangeOnlineCommand.
# Invoke-ExchangeOnlineCommand ruft Ensure-ExchangeOnlineSession auf.
# Kein Handler und kein Service muss vorher manuell Connect-ExchangeOnline aufrufen.
#
# GetNewClosure() bindet die lokalen Variablen im ScriptBlock korrekt,
# wenn der Block innerhalb von Invoke-ExchangeOnlineCommand ausgeführt wird.
# ─────────────────────────────────────────────────────────────────────────────

function Get-ExoMailboxSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [object]$Context = $null
    )

    $capturedIdentity = $Identity
    Invoke-ExchangeOnlineCommand -Config $Config -Context $Context -ScriptBlock {
        Get-EXOMailbox -Identity $capturedIdentity -ErrorAction Stop
    }.GetNewClosure()
}

function Set-ExoMailboxSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [object]$Context = $null,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Action = 'Set-Mailbox'; Parameters = $Parameters }
    }

    $capturedParams = $Parameters
    Invoke-ExchangeOnlineCommand -Config $Config -Context $Context -ScriptBlock {
        Set-Mailbox @capturedParams -ErrorAction Stop
    }.GetNewClosure()
}

function Get-ExoRecipientSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [object]$Context = $null
    )

    $capturedIdentity = $Identity
    Invoke-ExchangeOnlineCommand -Config $Config -Context $Context -ScriptBlock {
        Get-EXORecipient -Identity $capturedIdentity -ErrorAction Stop
    }.GetNewClosure()
}

function Add-ExoMailboxPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [object]$Context = $null,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Action = 'Add-MailboxPermission'; Parameters = $Parameters }
    }

    $capturedParams = $Parameters
    Invoke-ExchangeOnlineCommand -Config $Config -Context $Context -ScriptBlock {
        Add-MailboxPermission @capturedParams -ErrorAction Stop
    }.GetNewClosure()
}

function Remove-ExoMailboxPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [object]$Context = $null,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Action = 'Remove-MailboxPermission'; Parameters = $Parameters }
    }

    $capturedParams = $Parameters
    Invoke-ExchangeOnlineCommand -Config $Config -Context $Context -ScriptBlock {
        Remove-MailboxPermission @capturedParams -ErrorAction Stop
    }.GetNewClosure()
}

function Add-ExoSendAsPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [object]$Context = $null,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Action = 'Add-RecipientPermission'; Parameters = $Parameters }
    }

    $capturedParams = $Parameters
    Invoke-ExchangeOnlineCommand -Config $Config -Context $Context -ScriptBlock {
        Add-RecipientPermission @capturedParams -ErrorAction Stop
    }.GetNewClosure()
}

function Remove-ExoSendAsPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [object]$Context = $null,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Action = 'Remove-RecipientPermission'; Parameters = $Parameters }
    }

    $capturedParams = $Parameters
    Invoke-ExchangeOnlineCommand -Config $Config -Context $Context -ScriptBlock {
        Remove-RecipientPermission @capturedParams -ErrorAction Stop
    }.GetNewClosure()
}

function Set-ExoMailboxManagerSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][string]$Manager,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [object]$Context = $null,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated = $true
            Action    = 'Set-Mailbox'
            Identity  = $Identity
            Manager   = $Manager
            Target    = 'ExchangeOnline'
        }
    }

    $capturedIdentity = $Identity
    $capturedManager = $Manager
    Invoke-ExchangeOnlineCommand -Config $Config -Context $Context -ScriptBlock {
        Set-Mailbox -Identity $capturedIdentity -GrantSendOnBehalfTo @{ Add = $capturedManager } -ErrorAction Stop
    }.GetNewClosure()
}

Export-ModuleMember -Function @(
    'Set-ExchangeOnlineRuntimeConfig',
    'Get-ExchangeOnlineRemotePowerShellConfig',
    'Import-ExchangeOnlineManagementModule',
    'Test-ExchangeOnlineCertificate',
    'Test-ExchangeOnlineSession',
    'Connect-ExchangeOnlineSession',
    'Ensure-ExchangeOnlineSession',
    'Reset-ExchangeOnlineSession',
    'Disconnect-ExchangeOnlineSession',
    'Invoke-ExchangeOnlineCommand',
    'Test-ExchangeOnlineConnectionHealth',
    'Get-ExoMailboxSafe',
    'Set-ExoMailboxSafe',
    'Get-ExoRecipientSafe',
    'Add-ExoMailboxPermissionSafe',
    'Remove-ExoMailboxPermissionSafe',
    'Add-ExoSendAsPermissionSafe',
    'Remove-ExoSendAsPermissionSafe',
    'Set-ExoMailboxManagerSafe'
)
