Set-StrictMode -Version Latest

function Resolve-BackfeedRunId {
    [CmdletBinding()]
    param(
        [string]$BackfeedRunId,
        [string]$CorrelationId
    )

    $parsed = [guid]::Empty
    if (-not [string]::IsNullOrWhiteSpace($BackfeedRunId) -and [guid]::TryParse([string]$BackfeedRunId, [ref]$parsed)) {
        return $parsed.ToString()
    }

    if (-not [string]::IsNullOrWhiteSpace($CorrelationId) -and [guid]::TryParse([string]$CorrelationId, [ref]$parsed)) {
        return $parsed.ToString()
    }

    [guid]::NewGuid().ToString()
}

function New-BackfeedContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][object]$Logger,
        [Parameter(Mandatory = $true)][datetime]$StartedAt,
        [Parameter(Mandatory = $true)][string]$CorrelationId,
        [Parameter(Mandatory = $true)][string]$BackfeedType,
        [Parameter(Mandatory = $true)][string]$Mode,
        [string]$BackfeedRunId
    )

    $resolvedBackfeedRunId = Resolve-BackfeedRunId -BackfeedRunId $BackfeedRunId -CorrelationId $CorrelationId

    [pscustomobject]@{
        Environment   = $Environment
        Config        = $Config
        Logger        = $Logger
        StartedAt     = $StartedAt
        CorrelationId = $CorrelationId
        BackfeedRunId = $resolvedBackfeedRunId
        BackfeedType  = $BackfeedType
        Mode          = $Mode
        WhatIfMode    = $true
    }
}

Export-ModuleMember -Function @('Resolve-BackfeedRunId', 'New-BackfeedContext')