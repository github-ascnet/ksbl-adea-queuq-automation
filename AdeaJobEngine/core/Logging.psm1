Set-StrictMode -Version Latest

function New-Logger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Config,
        [string]$RunId,
        [switch]$VerboseLogging
    )

    $paths = $Config.Paths
    $logPath = Join-Path -Path $Config.RootPath -ChildPath $paths.LogPath
    if (-not (Test-Path -Path $logPath)) {
        New-Item -Path $logPath -ItemType Directory -Force | Out-Null
    }

    $logFileName = if ($Config.Logging.LogFileName) { $Config.Logging.LogFileName } else { 'jobprocessor.log' }
    $logFile = Join-Path -Path $logPath -ChildPath $logFileName

    [pscustomobject]@{
        RunId           = $RunId
        LogFile         = $logFile
        ConsoleEnabled  = [bool]$Config.Logging.ConsoleEnabled
        FileEnabled     = [bool]$Config.Logging.FileEnabled
        EventLogEnabled = [bool]$Config.Logging.EventLogEnabled
        EventLogName    = if ($Config.EventLog.LogName) { $Config.EventLog.LogName } else { 'Application' }
        EventSource     = if ($Config.EventLog.Source) { $Config.EventLog.Source } else { 'AdeaJobEngine' }
        VerboseLogging  = [bool]($VerboseLogging.IsPresent -or $Config.Logging.VerboseLogging)
    }
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Logger,
        [Parameter(Mandatory = $true)]
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [string]$Message,
        [System.Exception]$Exception
    )

    if ($Level -eq 'DEBUG' -and -not $Logger.VerboseLogging) {
        return
    }

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff')
    $line = "[$timestamp] [$Level] [RunId=$($Logger.RunId)] $Message"

    if ($Exception) {
        $line = "$line | Exception: $($Exception.Message)"
    }

    if ($Logger.FileEnabled) {
        Add-Content -Path $Logger.LogFile -Value $line
    }

    if ($Logger.ConsoleEnabled) {
        Write-Host $line
    }

    if ($Logger.EventLogEnabled) {
        try {
            if (-not [System.Diagnostics.EventLog]::SourceExists($Logger.EventSource)) {
                New-EventLog -LogName $Logger.EventLogName -Source $Logger.EventSource -ErrorAction Stop
            }

            $entryType = switch ($Level) {
                'ERROR' { 'Error' }
                'WARN' { 'Warning' }
                default { 'Information' }
            }

            Write-EventLog -LogName $Logger.EventLogName -Source $Logger.EventSource -EntryType $entryType -EventId 1000 -Message $line
        }
        catch {
            if ($Logger.FileEnabled) {
                Add-Content -Path $Logger.LogFile -Value "[$timestamp] [WARN] EventLog write failed: $($_.Exception.Message)"
            }
        }
    }
}

function Write-LogDebug {
    [CmdletBinding()]
    param([object]$Logger, [string]$Message)
    Write-Log -Logger $Logger -Level 'DEBUG' -Message $Message
}

function Write-LogInfo {
    [CmdletBinding()]
    param([object]$Logger, [string]$Message)
    Write-Log -Logger $Logger -Level 'INFO' -Message $Message
}

function Write-LogWarn {
    [CmdletBinding()]
    param([object]$Logger, [string]$Message)
    Write-Log -Logger $Logger -Level 'WARN' -Message $Message
}

function Write-LogError {
    [CmdletBinding()]
    param([object]$Logger, [string]$Message, [System.Exception]$Exception)
    Write-Log -Logger $Logger -Level 'ERROR' -Message $Message -Exception $Exception
}

Export-ModuleMember -Function @(
    'New-Logger',
    'Write-Log',
    'Write-LogDebug',
    'Write-LogInfo',
    'Write-LogWarn',
    'Write-LogError'
)
