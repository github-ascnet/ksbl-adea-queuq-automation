Set-StrictMode -Version Latest

function Get-ExchangeConnectionCurrentTimeInternal {
    [CmdletBinding()]
    param()
    Get-Date
}

function New-ExchangeConnectionDiagnosticError {
    [CmdletBinding()]
    param(
        [string]$ErrorCode,
        [string]$ErrorCategory,
        [string]$Message,
        [object]$Details = $null
    )

    [pscustomobject]@{
        ErrorCode     = $ErrorCode
        ErrorCategory = $ErrorCategory
        Message       = $Message
        Details       = $Details
    }
}

function New-ExchangeConnectionHealthResult {
    [CmdletBinding()]
    param(
        [string]$Target,
        [string]$ConnectionType,
        [bool]$Enabled = $false,
        [bool]$IsConnected = $false,
        [bool]$IsUsable = $false,
        [string]$Status,
        [string]$Message,
        [string]$ErrorCode,
        [string]$ErrorCategory,
        [string]$ConnectionUri,
        [string]$Organization,
        [string]$AppId,
        [string]$CertificateThumbprint,
        [string]$User,
        [string]$SessionState,
        [datetime]$CreatedAt,
        [datetime]$LastUsedAt,
        [datetime]$CheckedAt,
        [int]$DurationMilliseconds,
        [object]$Details
    )

    if (-not $CheckedAt) {
        $CheckedAt = Get-ExchangeConnectionCurrentTimeInternal
    }

    [pscustomobject][ordered]@{
        Target                 = $Target
        ConnectionType         = $ConnectionType
        Enabled                = $Enabled
        IsConnected            = $IsConnected
        IsUsable               = $IsUsable
        Status                 = $Status
        Message                = $Message
        ErrorCode              = $ErrorCode
        ErrorCategory          = $ErrorCategory
        ConnectionUri          = $ConnectionUri
        Organization           = $Organization
        AppId                  = $AppId
        CertificateThumbprint  = $CertificateThumbprint
        User                   = $User
        SessionState           = $SessionState
        CreatedAt              = $CreatedAt
        LastUsedAt             = $LastUsedAt
        CheckedAt              = $CheckedAt
        DurationMilliseconds   = $DurationMilliseconds
        Details                = $Details
    }
}

function ConvertTo-ExchangeConnectionHealthJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$HealthResult,
        [int]$Depth = 6
    )

    $HealthResult | ConvertTo-Json -Depth $Depth
}

function Write-ExchangeConnectionHealthLog {
    [CmdletBinding()]
    param(
        [object]$Logger,
        [Parameter(Mandatory = $true)][object]$HealthResult,
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )

    if (-not $Logger) { return }

    $writeLog = Get-Command -Name Write-Log -ErrorAction SilentlyContinue
    if (-not $writeLog) { return }

    $message = "ExchangeConnectionHealth Target=$($HealthResult.Target) Status=$($HealthResult.Status) Message=$($HealthResult.Message)"
    Write-Log -Logger $Logger -Level $Level -Message $message
}

Export-ModuleMember -Function @(
    'Get-ExchangeConnectionCurrentTimeInternal',
    'New-ExchangeConnectionDiagnosticError',
    'New-ExchangeConnectionHealthResult',
    'ConvertTo-ExchangeConnectionHealthJson',
    'Write-ExchangeConnectionHealthLog'
)
