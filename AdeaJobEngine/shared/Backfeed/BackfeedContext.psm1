Set-StrictMode -Version Latest

function New-BackfeedContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][object]$Config,
        [Parameter(Mandatory = $true)][object]$Logger,
        [Parameter(Mandatory = $true)][datetime]$StartedAt,
        [Parameter(Mandatory = $true)][string]$CorrelationId,
        [Parameter(Mandatory = $true)][string]$BackfeedType,
        [Parameter(Mandatory = $true)][string]$Mode
    )

    [pscustomobject]@{
        Environment   = $Environment
        Config        = $Config
        Logger        = $Logger
        StartedAt     = $StartedAt
        CorrelationId = $CorrelationId
        BackfeedType  = $BackfeedType
        Mode          = $Mode
        WhatIfMode    = $true
    }
}

Export-ModuleMember -Function @('New-BackfeedContext')