Set-StrictMode -Version Latest

function Get-JobStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$StatePath,
        [string]$StableJobKey,
        [string]$JobId
    )

    if ([string]::IsNullOrWhiteSpace($StableJobKey) -and [string]::IsNullOrWhiteSpace($JobId)) {
        throw 'Either StableJobKey or JobId must be provided.'
    }

    $folder = Join-Path -Path $RootPath -ChildPath $StatePath
    if (-not (Test-Path -Path $folder)) {
        New-Item -Path $folder -ItemType Directory -Force | Out-Null
    }

    $stateKey = if (-not [string]::IsNullOrWhiteSpace($StableJobKey)) { $StableJobKey } else { $JobId }
    Join-Path -Path $folder -ChildPath ("$stateKey.state.json")
}

function Get-JobState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$StateFilePath)

    if (-not (Test-Path -Path $StateFilePath -PathType Leaf)) {
        return $null
    }

    (Get-Content -Path $StateFilePath -Raw -ErrorAction Stop) | ConvertFrom-Json
}

function Save-JobState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$StateFilePath,
        [Parameter(Mandatory = $true)][object]$State
    )

    $State.UpdatedAt = Get-Date
    $json = $State | ConvertTo-Json -Depth 10
    Set-Content -Path $StateFilePath -Value $json -Encoding UTF8
    $State
}

function Initialize-JobState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$JobId,
        [string]$StableJobKey,
        [Parameter(Mandatory = $true)][string]$UseCase,
        [int]$CurrentStep = 10
    )

    [pscustomobject]@{
        JobId                = $JobId
        StableJobKey         = $StableJobKey
        UseCase              = $UseCase
        CurrentStep          = $CurrentStep
        PreviousStep         = $null
        CurrentStepAttempts  = 0
        CurrentStepStartedAt = (Get-Date)
        Status               = 'Active'
        Attempts             = 0
        ResumeAfter          = $null
        LastMessage          = 'Initialized'
        UpdatedAt            = (Get-Date)
        CreatedAt            = (Get-Date)
        CompletedAt          = $null
    }
}

function Set-JobStateStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][int]$Step,
        [string]$Message = 'Step changed'
    )

    if ($State.CurrentStep -ne $Step) {
        $State.PreviousStep         = $State.CurrentStep
        $State.CurrentStep          = $Step
        $State.CurrentStepAttempts  = 0
        $State.CurrentStepStartedAt = Get-Date
    }
    $State.LastMessage = $Message
    $State.UpdatedAt   = Get-Date
    $State
}

function Increment-JobStateStepAttempt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [string]$Message
    )

    $State.CurrentStepAttempts = [int]$State.CurrentStepAttempts + 1
    $State.Attempts            = [int]$State.Attempts + 1
    if ($PSBoundParameters.ContainsKey('Message') -and -not [string]::IsNullOrWhiteSpace($Message)) {
        $State.LastMessage = $Message
    }
    $State.UpdatedAt = Get-Date
    $State
}

function Complete-JobState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [string]$Message = 'Completed.'
    )

    $State.Status      = 'Completed'
    $State.CompletedAt = Get-Date
    $State.LastMessage = $Message
    $State.UpdatedAt   = Get-Date
    $State
}

function Remove-JobState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$StateFilePath)

    if (Test-Path -Path $StateFilePath) {
        Remove-Item -Path $StateFilePath -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function @(
    'Get-JobStatePath',
    'Get-JobState',
    'Save-JobState',
    'Initialize-JobState',
    'Set-JobStateStep',
    'Increment-JobStateStepAttempt',
    'Complete-JobState',
    'Remove-JobState'
)
