Set-StrictMode -Version Latest

function Resolve-ResultBackfeedRunId {
    [CmdletBinding()]
    param([string]$BackfeedRunId)

    $parsed = [guid]::Empty
    if (-not [string]::IsNullOrWhiteSpace($BackfeedRunId) -and [guid]::TryParse([string]$BackfeedRunId, [ref]$parsed)) {
        return $parsed.ToString()
    }

    [guid]::NewGuid().ToString()
}

function New-BackfeedResult {
    [CmdletBinding()]
    param(
        [string]$BackfeedRunId,
        [Parameter(Mandatory = $true)][string]$BackfeedType,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$Status,
        [int]$ReadCount = 0,
        [int]$StagedCount = 0,
        [int]$InsertedCount = 0,
        [int]$UpdatedCount = 0,
        [int]$DeletedCount = 0,
        [int]$UnchangedCount = 0,
        [int]$FailedCount = 0,
        [datetime]$StartedAt = (Get-Date),
        [datetime]$CompletedAt = (Get-Date),
        [double]$DurationSeconds = 0,
        [object[]]$Errors = @()
    )

    $resolvedBackfeedRunId = Resolve-ResultBackfeedRunId -BackfeedRunId $BackfeedRunId

    [pscustomobject]@{
        BackfeedRunId   = $resolvedBackfeedRunId
        BackfeedType    = $BackfeedType
        Mode            = $Mode
        Status          = $Status
        ReadCount       = $ReadCount
        StagedCount     = $StagedCount
        InsertedCount   = $InsertedCount
        UpdatedCount    = $UpdatedCount
        DeletedCount    = $DeletedCount
        UnchangedCount  = $UnchangedCount
        FailedCount     = $FailedCount
        StartedAt       = $StartedAt
        CompletedAt     = $CompletedAt
        DurationSeconds = $DurationSeconds
        Errors          = @($Errors)
    }
}

Export-ModuleMember -Function @('Resolve-ResultBackfeedRunId','New-BackfeedResult')