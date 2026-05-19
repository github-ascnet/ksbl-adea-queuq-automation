Set-StrictMode -Version Latest

$script:AllowedJobResultStatus = @('Succeeded', 'Failed', 'Retry', 'Paused', 'Skipped')

function New-JobResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,
        [string]$Message = '',
        [string]$ErrorCode,
        [System.Exception]$Exception,
        [datetime]$RetryAfter,
        [datetime]$ResumeAfter,
        [string]$PauseReason,
        [object]$Output
    )

    if ($script:AllowedJobResultStatus -notcontains $Status) {
        throw "Invalid JobResult status '$Status'. Allowed values: $($script:AllowedJobResultStatus -join ', ')."
    }

    [pscustomobject]@{
        Status      = $Status
        Message     = $Message
        ErrorCode   = $ErrorCode
        Exception   = $Exception
        RetryAfter  = $RetryAfter
        ResumeAfter = $ResumeAfter
        PauseReason = $PauseReason
        Output      = $Output
        CreatedAt   = (Get-Date)
    }
}

function New-JobSucceededResult {
    [CmdletBinding()]
    param(
        [string]$Message = 'Job completed successfully.',
        [object]$Output
    )

    New-JobResult -Status 'Succeeded' -Message $Message -Output $Output
}

function New-JobFailedResult {
    [CmdletBinding()]
    param(
        [string]$Message = 'Job failed.',
        [string]$ErrorCode = 'GENERAL_FAILURE',
        [System.Exception]$Exception,
        [object]$Output
    )

    New-JobResult -Status 'Failed' -Message $Message -ErrorCode $ErrorCode -Exception $Exception -Output $Output
}

function New-JobRetryResult {
    [CmdletBinding()]
    param(
        [string]$Message = 'Job needs retry.',
        [datetime]$RetryAfter = (Get-Date).AddMinutes(5),
        [object]$Output
    )

    New-JobResult -Status 'Retry' -Message $Message -RetryAfter $RetryAfter -Output $Output
}

function New-JobPausedResult {
    [CmdletBinding()]
    param(
        [string]$Message = 'Job paused.',
        [datetime]$ResumeAfter,
        [string]$PauseReason = 'ManualPause',
        [object]$Output
    )

    New-JobResult -Status 'Paused' -Message $Message -ResumeAfter $ResumeAfter -PauseReason $PauseReason -Output $Output
}

function New-JobSkippedResult {
    [CmdletBinding()]
    param(
        [string]$Message = 'Job skipped.',
        [object]$Output
    )

    New-JobResult -Status 'Skipped' -Message $Message -Output $Output
}

Export-ModuleMember -Function @(
    'New-JobResult',
    'New-JobSucceededResult',
    'New-JobFailedResult',
    'New-JobRetryResult',
    'New-JobPausedResult',
    'New-JobSkippedResult'
)
