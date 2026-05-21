Set-StrictMode -Version Latest

# Zentraler In-Memory-Zustand für die OnPrem-Sessionverwaltung.
# Der State lebt pro PowerShell-Prozess und wird zwischen Gateway-Aufrufen wiederverwendet.
#
# Felder:
# - Session: aktive Remote-PSSession (falls vorhanden)
# - SessionInfo: Metadaten zur Session (CreatedAt, LastUsedAt, ...)
# - ImportedModuleName: Name eines optional importierten Proxy-Moduls (Import-PSSession-Modus)
# - RuntimeConfig: zuletzt gesetzte Laufzeitkonfiguration (aus JobEngine)
$script:ExchangeOnPremSessionState = @{
    Session            = $null
    SessionInfo        = $null
    ImportedModuleName = $null
    RuntimeConfig      = $null
}

# Setzt die Runtime-Konfiguration für dieses Gateway explizit.
# Die JobEngine ruft diese Funktion nach dem Merge von appsettings + environment auf.
function Set-ExchangeOnPremRuntimeConfig {
    [CmdletBinding()]
    param([hashtable]$Config)

    $script:ExchangeOnPremSessionState.RuntimeConfig = $Config
}

# Liest einen Konfigurationsknoten robust aus Hashtable oder PSCustomObject.
# Damit funktionieren sowohl native Hashtables als auch ConvertFrom-Json-Objekte.
function Get-ConfigNode {
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

# Prüft, ob ein Konfigurationsschlüssel vorhanden ist (Hashtable oder Objekt).
function Test-ConfigKey {
    param(
        [Parameter(Mandatory = $true)][object]$Source,
        [Parameter(Mandatory = $true)][string]$Key
    )

    if ($null -eq $Source) { return $false }
    if ($Source -is [hashtable]) { return $Source.ContainsKey($Key) }
    return $null -ne $Source.PSObject.Properties[$Key]
}

# Liefert einen Konfigurationswert mit Fallback-Default.
function Get-ConfigValue {
    param(
        [Parameter(Mandatory = $true)][object]$Source,
        [Parameter(Mandatory = $true)][string]$Key,
        [object]$Default = $null
    )

    $node = Get-ConfigNode -Source $Source -Key $Key
    if ($null -eq $node) { return $Default }
    return $node
}

# Liest und validiert ExchangeOnPrem.RemotePowerShell aus Context/Config/RuntimeState.
#
# Auflösung in dieser Reihenfolge:
# 1) Context.Config
# 2) explizit übergebene Config
# 3) zuvor gesetzte RuntimeConfig
#
# Die Funktion erzwingt Pflichtfelder und setzt robuste Defaults für optionale Werte.
function Get-ExchangeOnPremRemotePowerShellConfig {
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [object]$Context
    )

    $effectiveConfig = $null
    if ($Context -and (Test-ConfigKey -Source $Context -Key 'Config')) {
        $effectiveConfig = Get-ConfigNode -Source $Context -Key 'Config'
    }
    elseif ($Config) {
        $effectiveConfig = $Config
    }
    elseif ($script:ExchangeOnPremSessionState.RuntimeConfig) {
        $effectiveConfig = $script:ExchangeOnPremSessionState.RuntimeConfig
    }

    if (-not $effectiveConfig) {
        throw 'Exchange On-Prem configuration is missing. No runtime configuration is available.'
    }

    $exchangeOnPrem = Get-ConfigNode -Source $effectiveConfig -Key 'ExchangeOnPrem'
    if (-not $exchangeOnPrem) {
        throw "Exchange On-Prem configuration section 'ExchangeOnPrem' is missing."
    }

    $remotePowerShell = Get-ConfigNode -Source $exchangeOnPrem -Key 'RemotePowerShell'
    if (-not $remotePowerShell) {
        throw "Exchange On-Prem configuration section 'ExchangeOnPrem.RemotePowerShell' is missing."
    }

    $enabled = [bool](Get-ConfigValue -Source $remotePowerShell -Key 'Enabled' -Default $false)
    if (-not $enabled) {
        throw 'Exchange On-Prem RemotePowerShell is disabled by configuration (ExchangeOnPrem.RemotePowerShell.Enabled=false).'
    }

    $user = [string](Get-ConfigValue -Source $remotePowerShell -Key 'User' -Default '')
    $secretPath = [string](Get-ConfigValue -Source $remotePowerShell -Key 'SecretPath' -Default '')
    $connectionUri = [string](Get-ConfigValue -Source $remotePowerShell -Key 'ConnectionUri' -Default '')

    if ([string]::IsNullOrWhiteSpace($user)) {
        throw "Exchange On-Prem RemotePowerShell configuration value 'User' is missing."
    }
    if ([string]::IsNullOrWhiteSpace($secretPath)) {
        throw "Exchange On-Prem RemotePowerShell configuration value 'SecretPath' is missing."
    }
    if ([string]::IsNullOrWhiteSpace($connectionUri)) {
        throw "Exchange On-Prem RemotePowerShell configuration value 'ConnectionUri' is missing."
    }

    $authentication = [string](Get-ConfigValue -Source $remotePowerShell -Key 'Authentication' -Default 'Kerberos')
    $reuseSession = [bool](Get-ConfigValue -Source $remotePowerShell -Key 'ReuseSession' -Default $true)
    $useImportPSSession = [bool](Get-ConfigValue -Source $remotePowerShell -Key 'UseImportPSSession' -Default $false)
    $executionMode = [string](Get-ConfigValue -Source $remotePowerShell -Key 'ExecutionMode' -Default 'InvokeCommand')
    $sessionIdleTimeoutMinutes = [int](Get-ConfigValue -Source $remotePowerShell -Key 'SessionIdleTimeoutMinutes' -Default 120)
    $maxSessionAgeMinutes = [int](Get-ConfigValue -Source $remotePowerShell -Key 'MaxSessionAgeMinutes' -Default 240)
    $reconnectOnFailure = [bool](Get-ConfigValue -Source $remotePowerShell -Key 'ReconnectOnFailure' -Default $true)
    $maxReconnectAttempts = [int](Get-ConfigValue -Source $remotePowerShell -Key 'MaxReconnectAttempts' -Default 1)

    if ($executionMode -ne 'InvokeCommand' -and $executionMode -ne 'ImportPSSession') {
        throw "Exchange On-Prem RemotePowerShell configuration value 'ExecutionMode' is invalid: '$executionMode'. Allowed values: InvokeCommand, ImportPSSession."
    }

    return [ordered]@{
        Enabled                   = $enabled
        User                      = $user
        SecretPath                = $secretPath
        ConnectionUri             = $connectionUri
        Authentication            = $authentication
        ReuseSession              = $reuseSession
        UseImportPSSession        = $useImportPSSession
        ExecutionMode             = $executionMode
        SessionIdleTimeoutMinutes = $sessionIdleTimeoutMinutes
        MaxSessionAgeMinutes      = $maxSessionAgeMinutes
        ReconnectOnFailure        = $reconnectOnFailure
        MaxReconnectAttempts      = $maxReconnectAttempts
    }
}

# Baut PSCredential aus User + verschlüsseltem Secret-File.
# Das Secret wird bewusst nicht im Code gehalten oder hartcodiert.
function New-ExchangeOnPremCredential {
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [object]$Context
    )

    $remoteConfig = Get-ExchangeOnPremRemotePowerShellConfig -Config $Config -Context $Context

    if (-not (Test-Path -Path $remoteConfig.SecretPath -PathType Leaf)) {
        throw "Exchange On-Prem secret file not found: $($remoteConfig.SecretPath)"
    }

    try {
        $secretRaw = Get-Content -Path $remoteConfig.SecretPath -Raw -ErrorAction Stop
    }
    catch {
        throw "Exchange On-Prem secret file is not readable: $($remoteConfig.SecretPath). $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace($secretRaw)) {
        throw "Exchange On-Prem secret file is empty: $($remoteConfig.SecretPath)"
    }

    try {
        $secure = ConvertTo-SecureString -String $secretRaw
    }
    catch {
        throw "Exchange On-Prem secret content cannot be converted to SecureString from path '$($remoteConfig.SecretPath)'. $($_.Exception.Message)"
    }

    return New-Object System.Management.Automation.PSCredential($remoteConfig.User, $secure)
}

# Dünner Wrapper um New-PSSession für Pester-Mockbarkeit.
function New-ExchangeOnPremPSSessionInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][hashtable]$Parameters)

    New-PSSession @Parameters
}

# Dünner Wrapper um Invoke-Command für Pester-Mockbarkeit.
function Invoke-ExchangeOnPremCommandInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList
    )

    Invoke-Command -Session $Session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList -ErrorAction Stop
}

# Dünner Wrapper um Import-PSSession für Pester-Mockbarkeit.
# Wird nur verwendet, wenn explizit in der Konfiguration angefordert.
function Import-ExchangeOnPremPSSessionInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Session)

    Import-PSSession -Session $Session -AllowClobber -DisableNameChecking -ErrorAction Stop
}

# Dünner Wrapper um Remove-PSSession für Pester-Mockbarkeit.
function Remove-ExchangeOnPremPSSessionInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Session)

    Remove-PSSession -Session $Session -ErrorAction SilentlyContinue
}

# Stellt eine neue Exchange-OnPrem-Remote-PowerShell-Session her und cached sie.
#
# Standardmodus:
# - ExecutionMode = InvokeCommand
# - UseImportPSSession = false
#
# Optional kann Import-PSSession aktiviert werden (Kompatibilitätsmodus).
function Connect-ExchangeOnPremSession {
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [object]$Context
    )

    $remoteConfig = Get-ExchangeOnPremRemotePowerShellConfig -Config $Config -Context $Context
    $credential = New-ExchangeOnPremCredential -Config $Config -Context $Context

    $newPSSessionParams = @{
        ConfigurationName = 'Microsoft.Exchange'
        ConnectionUri     = $remoteConfig.ConnectionUri
        Authentication    = $remoteConfig.Authentication
        Credential        = $credential
        ErrorAction       = 'Stop'
    }

    if ($remoteConfig.SessionIdleTimeoutMinutes -gt 0) {
        $idleTimeoutMillis = [Math]::Min(($remoteConfig.SessionIdleTimeoutMinutes * 60 * 1000), [int]::MaxValue)
        $newPSSessionParams['SessionOption'] = (New-PSSessionOption -IdleTimeout $idleTimeoutMillis)
    }

    $session = New-ExchangeOnPremPSSessionInternal -Parameters $newPSSessionParams
    $now = Get-Date

    $script:ExchangeOnPremSessionState.Session = $session
    $script:ExchangeOnPremSessionState.SessionInfo = [ordered]@{
        CreatedAt     = $now
        LastUsedAt    = $now
        ConnectionUri = $remoteConfig.ConnectionUri
        User          = $remoteConfig.User
        ExecutionMode = $remoteConfig.ExecutionMode
    }
    $script:ExchangeOnPremSessionState.ImportedModuleName = $null

    if ($remoteConfig.UseImportPSSession -or $remoteConfig.ExecutionMode -eq 'ImportPSSession') {
        $imported = Import-ExchangeOnPremPSSessionInternal -Session $session
        if ($imported -and $imported.Name) {
            $script:ExchangeOnPremSessionState.ImportedModuleName = [string]$imported.Name
        }
    }

    return $session
}

# Prüft, ob die aktuell gecachte Session weiterverwendet werden kann.
# Kriterien:
# - Session + SessionInfo vorhanden
# - Session.State = Opened
# - MaxSessionAgeMinutes nicht überschritten
function Test-ExchangeOnPremSession {
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [object]$Context
    )

    $remoteConfig = Get-ExchangeOnPremRemotePowerShellConfig -Config $Config -Context $Context
    $session = $script:ExchangeOnPremSessionState.Session
    $sessionInfo = $script:ExchangeOnPremSessionState.SessionInfo

    if (-not $session -or -not $sessionInfo) { return $false }
    if ($session.State -ne 'Opened') { return $false }

    if ($remoteConfig.MaxSessionAgeMinutes -gt 0) {
        $ageMinutes = ((Get-Date) - [datetime]$sessionInfo.CreatedAt).TotalMinutes
        if ($ageMinutes -gt $remoteConfig.MaxSessionAgeMinutes) {
            return $false
        }
    }

    return $true
}

# Entfernt Session und optionale Import-PSSession-Artefakte vollständig aus dem State.
# Diese Funktion ist der zentrale "harte Reset" vor Reconnect oder Shutdown.
function Reset-ExchangeOnPremSession {
    [CmdletBinding()]
    param()

    if ($script:ExchangeOnPremSessionState.ImportedModuleName) {
        Remove-Module -Name $script:ExchangeOnPremSessionState.ImportedModuleName -ErrorAction SilentlyContinue
    }

    if ($script:ExchangeOnPremSessionState.Session) {
        Remove-ExchangeOnPremPSSessionInternal -Session $script:ExchangeOnPremSessionState.Session
    }

    $script:ExchangeOnPremSessionState.Session = $null
    $script:ExchangeOnPremSessionState.SessionInfo = $null
    $script:ExchangeOnPremSessionState.ImportedModuleName = $null
}

# Öffentliche, robuste Disconnect-Funktion (idempotent).
# Fehler beim Aufräumen werden bewusst unterdrückt.
function Disconnect-ExchangeOnPremSession {
    [CmdletBinding()]
    param()

    try {
        Reset-ExchangeOnPremSession
    }
    catch {
        # Disconnect muss robust und idempotent sein.
    }
}

# Liefert eine gültige Session entsprechend der Reuse-Strategie.
# - ReuseSession=false: immer neue Session
# - ReuseSession=true: vorhandene Session testen und ggf. neu aufbauen
function Get-ExchangeOnPremSession {
    [CmdletBinding()]
    param(
        [hashtable]$Config,
        [object]$Context
    )

    $remoteConfig = Get-ExchangeOnPremRemotePowerShellConfig -Config $Config -Context $Context

    if (-not $remoteConfig.ReuseSession) {
        Reset-ExchangeOnPremSession
        return Connect-ExchangeOnPremSession -Config $Config -Context $Context
    }

    if (Test-ExchangeOnPremSession -Config $Config -Context $Context) {
        return $script:ExchangeOnPremSessionState.Session
    }

    Reset-ExchangeOnPremSession
    return Connect-ExchangeOnPremSession -Config $Config -Context $Context
}

# Heuristik zur Klassifikation, ob ein Fehler wahrscheinlich ein Session-/Transportfehler ist.
# Diese Information steuert, ob ein Reconnect-Retry durchgeführt werden darf.
function Test-IsExchangeOnPremSessionFailure {
    param([Parameter(Mandatory = $true)]$ErrorRecord)

    if (-not $ErrorRecord) { return $false }

    $exception = $ErrorRecord.Exception
    if ($exception -is [System.Management.Automation.Remoting.PSRemotingTransportException]) {
        return $true
    }

    $message = [string]$exception.Message
    if ($message -match 'PSSession|WSMan|WinRM|remote session|Runspace state is not valid|The client cannot connect') {
        return $true
    }

    return $false
}

# Führt einen Exchange-OnPrem-Befehl robust über Invoke-Command aus.
#
# Ablauf:
# 1) gültige Session holen
# 2) ScriptBlock remote ausführen
# 3) LastUsedAt aktualisieren
# 4) bei Sessionfehlern optional reconnecten und erneut versuchen
function Invoke-ExchangeOnPremCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [object[]]$ArgumentList,
        [hashtable]$Config,
        [object]$Context
    )

    $remoteConfig = Get-ExchangeOnPremRemotePowerShellConfig -Config $Config -Context $Context
    $maxReconnectAttempts = [Math]::Max(0, $remoteConfig.MaxReconnectAttempts)
    $totalAttempts = if ($remoteConfig.ReconnectOnFailure) { 1 + $maxReconnectAttempts } else { 1 }

    for ($attempt = 1; $attempt -le $totalAttempts; $attempt++) {
        try {
            $session = Get-ExchangeOnPremSession -Config $Config -Context $Context
            $result = Invoke-ExchangeOnPremCommandInternal -Session $session -ScriptBlock $ScriptBlock -ArgumentList $ArgumentList
            if ($script:ExchangeOnPremSessionState.SessionInfo) {
                $script:ExchangeOnPremSessionState.SessionInfo.LastUsedAt = Get-Date
            }
            return $result
        }
        catch {
            $isSessionFailure = Test-IsExchangeOnPremSessionFailure -ErrorRecord $_
            $canRetry = $isSessionFailure -and $remoteConfig.ReconnectOnFailure -and ($attempt -lt $totalAttempts)
            if ($canRetry) {
                Reset-ExchangeOnPremSession
                continue
            }

            throw "Exchange On-Prem command execution failed. $($_.Exception.Message)"
        }
    }

    throw 'Exchange On-Prem command execution failed after reconnect attempts.'
}

# Gibt den effektiven OnPrem-Ausführungsmodus zurück.
# Erlaubte Modi: InvokeCommand, ImportPSSession
function Get-OnPremExecutionMode {
    param(
        [hashtable]$Config,
        [object]$Context
    )

    $remoteConfig = Get-ExchangeOnPremRemotePowerShellConfig -Config $Config -Context $Context
    return [string]$remoteConfig.ExecutionMode
}

# Prüft die lokale Verfügbarkeit eines Exchange-Cmdlets.
# Diese Prüfung ist nur im ImportPSSession-Modus wirklich zwingend relevant.
function Assert-OnPremCmdlet {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required Exchange On-Prem cmdlet '$Name' is not available in current session."
    }
}

# Liest eine Mailbox sicher.
# - InvokeCommand-Modus: Remote-Aufruf ohne lokale Proxy-Cmdlets
# - ImportPSSession-Modus: lokale Cmdlet-Nutzung nach Session-Sicherstellung
function Get-OnPremMailboxSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [hashtable]$Config,
        [object]$Context
    )

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteIdentity)
            Get-Mailbox -Identity $remoteIdentity -ErrorAction Stop
        } -ArgumentList @($Identity)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Get-Mailbox'
    Get-Mailbox -Identity $Identity -ErrorAction Stop
}

# Setzt Mailbox-Eigenschaften sicher.
# WhatIfMode simuliert ausschließlich und verhindert produktive Mutation.
function Set-OnPremMailboxSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-Mailbox'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Set-Mailbox @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Set-Mailbox'
    Set-Mailbox @Parameters -ErrorAction Stop
}

# Liest Recipient-Informationen sicher.
function Get-OnPremRecipientSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [hashtable]$Config,
        [object]$Context
    )

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteIdentity)
            Get-Recipient -Identity $remoteIdentity -ErrorAction Stop
        } -ArgumentList @($Identity)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Get-Recipient'
    Get-Recipient -Identity $Identity -ErrorAction Stop
}

# Fügt Mailbox-Berechtigung sicher hinzu.
function Add-OnPremMailboxPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Add-MailboxPermission'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Add-MailboxPermission @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Add-MailboxPermission'
    Add-MailboxPermission @Parameters -ErrorAction Stop
}

# Entfernt Mailbox-Berechtigung sicher.
function Remove-OnPremMailboxPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Remove-MailboxPermission'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Remove-MailboxPermission @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Remove-MailboxPermission'
    Remove-MailboxPermission @Parameters -ErrorAction Stop
}

# Fügt SendAs-Berechtigung sicher hinzu.
function Add-OnPremSendAsPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Add-RecipientPermission'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Add-RecipientPermission @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Add-RecipientPermission'
    Add-RecipientPermission @Parameters -ErrorAction Stop
}

# Entfernt SendAs-Berechtigung sicher.
function Remove-OnPremSendAsPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Remove-RecipientPermission'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Remove-RecipientPermission @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Remove-RecipientPermission'
    Remove-RecipientPermission @Parameters -ErrorAction Stop
}


function Get-OnPremDistributionGroupSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [hashtable]$Config,
        [object]$Context
    )

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteIdentity)
            Get-DistributionGroup -Identity $remoteIdentity -ErrorAction Stop
        } -ArgumentList @($Identity)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Get-DistributionGroup'
    Get-DistributionGroup -Identity $Identity -ErrorAction Stop
}

# Setzt DistributionGroup-Eigenschaften sicher.
function Set-OnPremDistributionGroupSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-DistributionGroup'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Set-DistributionGroup @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Set-DistributionGroup'
    Set-DistributionGroup @Parameters -ErrorAction Stop
}

# Liest MailboxPermission sicher.
function Get-OnPremMailboxPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [hashtable]$Config,
        [object]$Context
    )

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteIdentity)
            Get-MailboxPermission -Identity $remoteIdentity -ErrorAction Stop
        } -ArgumentList @($Identity)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Get-MailboxPermission'
    Get-MailboxPermission -Identity $Identity -ErrorAction Stop
}

# Liest ADPermission sicher.
function Get-OnPremAdPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [hashtable]$Config,
        [object]$Context
    )

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteIdentity)
            Get-ADPermission -Identity $remoteIdentity -ErrorAction Stop
        } -ArgumentList @($Identity)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Get-ADPermission'
    Get-ADPermission -Identity $Identity -ErrorAction Stop
}

# Fügt ADPermission sicher hinzu.
function Add-OnPremAdPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Add-ADPermission'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Add-ADPermission @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Add-ADPermission'
    Add-ADPermission @Parameters -ErrorAction Stop
}

# Entfernt ADPermission sicher.
function Remove-OnPremAdPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Remove-ADPermission'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Remove-ADPermission @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Remove-ADPermission'
    Remove-ADPermission @Parameters -ErrorAction Stop
}



function Enable-OnPremMailboxSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Enable-Mailbox'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Enable-Mailbox @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Enable-Mailbox'
    Enable-Mailbox @Parameters -ErrorAction Stop
}

# Setzt CASMailbox-Eigenschaften sicher.
function Set-OnPremCASMailboxSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-CASMailbox'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Set-CASMailbox @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Set-CASMailbox'
    Set-CASMailbox @Parameters -ErrorAction Stop
}

# Erstellt Mailbox sicher.
function New-OnPremMailboxSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'New-Mailbox'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            New-Mailbox @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'New-Mailbox'
    New-Mailbox @Parameters -ErrorAction Stop
}

# Setzt Junk-Mailbox-Konfiguration sicher.
function Set-OnPremMailboxJunkEmailConfigurationSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-MailboxJunkEmailConfiguration'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Set-MailboxJunkEmailConfiguration @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Set-MailboxJunkEmailConfiguration'
    Set-MailboxJunkEmailConfiguration @Parameters -ErrorAction Stop
}



function Set-OnPremMailboxAutoReplyConfigurationSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-MailboxAutoReplyConfiguration'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Set-MailboxAutoReplyConfiguration @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Set-MailboxAutoReplyConfiguration'
    Set-MailboxAutoReplyConfiguration @Parameters -ErrorAction Stop
}

# Erstellt DistributionGroup sicher.
function New-OnPremDistributionGroupSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'New-DistributionGroup'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            New-DistributionGroup @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'New-DistributionGroup'
    New-DistributionGroup @Parameters -ErrorAction Stop
}

# Entfernt DistributionGroup sicher.
function Remove-OnPremDistributionGroupSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Remove-DistributionGroup'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Remove-DistributionGroup @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Remove-DistributionGroup'
    Remove-DistributionGroup @Parameters -ErrorAction Stop
}



function Get-OnPremMailboxFolderStatisticsSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [string]$FolderScope,
        [hashtable]$Config,
        [object]$Context
    )

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteIdentity, $remoteFolderScope)
            $remoteParams = @{ Identity = $remoteIdentity; ErrorAction = 'Stop' }
            if (-not [string]::IsNullOrWhiteSpace($remoteFolderScope)) {
                $remoteParams['FolderScope'] = $remoteFolderScope
            }
            Get-MailboxFolderStatistics @remoteParams
        } -ArgumentList @($Identity, $FolderScope)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Get-MailboxFolderStatistics'
    $params = @{ Identity = $Identity; ErrorAction = 'Stop' }
    if (-not [string]::IsNullOrWhiteSpace($FolderScope)) { $params['FolderScope'] = $FolderScope }
    Get-MailboxFolderStatistics @params
}

# Fügt MailboxFolderPermission sicher hinzu.
function Add-OnPremMailboxFolderPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Add-MailboxFolderPermission'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Add-MailboxFolderPermission @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Add-MailboxFolderPermission'
    Add-MailboxFolderPermission @Parameters -ErrorAction Stop
}

# Entfernt MailboxFolderPermission sicher.
function Remove-OnPremMailboxFolderPermissionSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Remove-MailboxFolderPermission'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Remove-MailboxFolderPermission @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Remove-MailboxFolderPermission'
    Remove-MailboxFolderPermission @Parameters -ErrorAction Stop
}

# Liest RemoteMailbox sicher.
function Get-OnPremRemoteMailboxSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [hashtable]$Config,
        [object]$Context
    )

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteIdentity)
            Get-RemoteMailbox -Identity $remoteIdentity -ErrorAction Stop
        } -ArgumentList @($Identity)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Get-RemoteMailbox'
    Get-RemoteMailbox -Identity $Identity -ErrorAction Stop
}

# Setzt RemoteMailbox-Eigenschaften sicher.
function Set-OnPremRemoteMailboxSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Parameters,
        [bool]$WhatIfMode = $true,
        [hashtable]$Config,
        [object]$Context
    )

    # Exportiert die öffentliche Gateway-API.
    # Interne Wrapper-Funktionen bleiben absichtlich privat und werden nur intern/mockbasiert genutzt.
    if ($WhatIfMode) { return [pscustomobject]@{ Simulated = $true; Action = 'Set-RemoteMailbox'; Parameters = $Parameters } }

    if ((Get-OnPremExecutionMode -Config $Config -Context $Context) -eq 'InvokeCommand') {
        return Invoke-ExchangeOnPremCommand -Config $Config -Context $Context -ScriptBlock {
            param($remoteParameters)
            Set-RemoteMailbox @remoteParameters -ErrorAction Stop
        } -ArgumentList @($Parameters)
    }

    $null = Get-ExchangeOnPremSession -Config $Config -Context $Context
    Assert-OnPremCmdlet -Name 'Set-RemoteMailbox'
    Set-RemoteMailbox @Parameters -ErrorAction Stop
}


Export-ModuleMember -Function @(
    'Set-ExchangeOnPremRuntimeConfig',
    'Get-ExchangeOnPremRemotePowerShellConfig',
    'New-ExchangeOnPremCredential',
    'Connect-ExchangeOnPremSession',
    'Test-ExchangeOnPremSession',
    'Get-ExchangeOnPremSession',
    'Invoke-ExchangeOnPremCommand',
    'Reset-ExchangeOnPremSession',
    'Disconnect-ExchangeOnPremSession',
    'Get-OnPremMailboxSafe',
    'New-OnPremMailboxSafe',
    'Set-OnPremCASMailboxSafe',
    'Enable-OnPremMailboxSafe',
    'Set-OnPremMailboxJunkEmailConfigurationSafe',
    'Set-OnPremMailboxAutoReplyConfigurationSafe',
    'Set-OnPremMailboxSafe',
    'Get-OnPremRecipientSafe',
    'Add-OnPremMailboxPermissionSafe',
    'Remove-OnPremMailboxPermissionSafe',
    'Add-OnPremSendAsPermissionSafe',
    'Remove-OnPremSendAsPermissionSafe',
    'Get-OnPremDistributionGroupSafe',
    'Set-OnPremDistributionGroupSafe',
    'New-OnPremDistributionGroupSafe',
    'Remove-OnPremDistributionGroupSafe',
    'Get-OnPremMailboxPermissionSafe',
    'Get-OnPremAdPermissionSafe',
    'Add-OnPremAdPermissionSafe',
    'Remove-OnPremAdPermissionSafe',
    'Get-OnPremMailboxFolderStatisticsSafe',
    'Add-OnPremMailboxFolderPermissionSafe',
    'Remove-OnPremMailboxFolderPermissionSafe',
    'Get-OnPremRemoteMailboxSafe',
    'Set-OnPremRemoteMailboxSafe'
)
