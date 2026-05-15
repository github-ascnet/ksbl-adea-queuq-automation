Set-StrictMode -Version Latest

function New-JobContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$JobId,
        [Parameter(Mandatory = $true)][string]$StableJobKey,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$UseCaseName,
        [Parameter(Mandatory = $true)][string]$Queue,
        [Parameter(Mandatory = $true)][string]$SourceFile,
        [Parameter(Mandatory = $true)][string]$WorkingFile,
        [Parameter(Mandatory = $true)][string]$MetadataPath,
        [Parameter(Mandatory = $true)][object]$JobMetadata,
        [Parameter(Mandatory = $true)][object[]]$Payload,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][hashtable]$Environment,
        [Parameter(Mandatory = $true)][hashtable]$Services,
        [Parameter(Mandatory = $true)][object]$Logger,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [bool]$WhatIfMode,
        [bool]$VerboseLogging
    )

    [pscustomobject]@{
        JobId           = $JobId
        StableJobKey    = $StableJobKey
        RunId           = $RunId
        UseCaseName     = $UseCaseName
        Queue           = $Queue
        SourceFile      = $SourceFile
        WorkingFile     = $WorkingFile
        MetadataPath    = $MetadataPath
        JobMetadata     = $JobMetadata
        Payload         = $Payload
        Config          = $Config
        Environment     = $Environment
        Services        = $Services
        Logger          = $Logger
        StartedAt       = (Get-Date)
        RootPath        = $RootPath
        WhatIfMode      = $WhatIfMode
        VerboseLogging  = $VerboseLogging
    }
}

Export-ModuleMember -Function @('New-JobContext')
