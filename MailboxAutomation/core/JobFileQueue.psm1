Set-StrictMode -Version Latest

function New-JobId {
    [CmdletBinding()]
    param()

    [guid]::NewGuid().ToString('N')
}

function Get-QueuePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$QueueRoot,
        [Parameter(Mandatory = $true)][ValidateSet('incoming', 'processing', 'retry', 'paused', 'done', 'failed', 'archive')][string]$Status
    )

    Join-Path -Path (Join-Path -Path $RootPath -ChildPath $QueueRoot) -ChildPath $Status
}

function Ensure-QueueFolders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$QueueRoot
    )

    foreach ($status in @('incoming', 'processing', 'retry', 'paused', 'done', 'failed', 'archive')) {
        $path = Get-QueuePath -RootPath $RootPath -QueueRoot $QueueRoot -Status $status
        if (-not (Test-Path -Path $path -PathType Container)) {
            New-Item -Path $path -ItemType Directory -Force | Out-Null
        }
    }
}

function Get-JobMetadataPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$FilePath)

    "$FilePath.meta.json"
}

function Get-StableJobKey {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$FilePath)

    [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
}

function Read-JobMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $metadataPath = Get-JobMetadataPath -FilePath $FilePath
    if (-not (Test-Path -Path $metadataPath -PathType Leaf)) {
        return $null
    }

    try {
        Get-Content -Path $metadataPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Metadata file '$metadataPath' is invalid or unreadable. $($_.Exception.Message)"
    }
}

function Get-NonConflictingPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    # A path is only considered free if neither the CSV nor its .meta.json sidecar exist.
    # This prevents creating a CSV next to an orphaned .meta.json from a prior run.
    $metaPath = "$Path.meta.json"
    if (-not (Test-Path -Path $Path) -and -not (Test-Path -Path $metaPath)) {
        return $Path
    }

    $dir = [System.IO.Path]::GetDirectoryName($Path)
    $base = [System.IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [System.IO.Path]::GetExtension($Path)
    $ts = (Get-Date).ToString('yyyyMMdd_HHmmss')
    $sfx = [guid]::NewGuid().ToString('N').Substring(0, 4)
    return Join-Path $dir "$base`__${ts}_${sfx}$ext"
}

function Save-JobMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][psobject]$Metadata
    )

    $metadataPath = Get-JobMetadataPath -FilePath $FilePath
    $Metadata | ConvertTo-Json -Depth 8 | Set-Content -Path $metadataPath -Encoding UTF8
    $metadataPath
}

function Get-OrCreateJobMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$UseCaseName,
        [Parameter(Mandatory = $true)][string]$Queue
    )

    $now = (Get-Date).ToString('o')
    $fileName = [System.IO.Path]::GetFileName($FilePath)
    $stableKey = Get-StableJobKey -FilePath $FilePath
    $loadedMetadata = Read-JobMetadata -FilePath $FilePath
    $loadedPropNames = @()
    if ($loadedMetadata) {
        $loadedPropNames = @($loadedMetadata.PSObject.Properties.Name)
    }

    $jobId = if ($loadedMetadata -and ($loadedPropNames -contains 'JobId') -and $loadedMetadata.JobId) { [string]$loadedMetadata.JobId } else { New-JobId }
    $createdAt = if ($loadedMetadata -and ($loadedPropNames -contains 'CreatedAt') -and $loadedMetadata.CreatedAt) { [string]$loadedMetadata.CreatedAt } else { $now }
    $attempts = 0
    if ($loadedMetadata -and ($loadedPropNames -contains 'Attempts') -and $loadedMetadata.Attempts -ne $null) {
        $attempts = [int]$loadedMetadata.Attempts
    }

    $resolvedUseCaseName = if ($loadedMetadata -and ($loadedPropNames -contains 'UseCaseName') -and $loadedMetadata.UseCaseName) { [string]$loadedMetadata.UseCaseName } else { $UseCaseName }
    $resolvedQueue = if ($loadedMetadata -and ($loadedPropNames -contains 'Queue') -and $loadedMetadata.Queue) { [string]$loadedMetadata.Queue } else { $Queue }
    $resolvedStatus = if ($loadedMetadata -and ($loadedPropNames -contains 'Status') -and $loadedMetadata.Status) { [string]$loadedMetadata.Status } elseif ($loadedMetadata -and ($loadedPropNames -contains 'LastStatus') -and $loadedMetadata.LastStatus) { [string]$loadedMetadata.LastStatus } else { 'incoming' }
    $lastMessage = if ($loadedMetadata -and ($loadedPropNames -contains 'LastMessage') -and $loadedMetadata.LastMessage) { [string]$loadedMetadata.LastMessage } elseif ($loadedMetadata -and ($loadedPropNames -contains 'Message') -and $loadedMetadata.Message) { [string]$loadedMetadata.Message } else { $null }
    $lastErrorCode = if ($loadedMetadata -and ($loadedPropNames -contains 'LastErrorCode') -and $loadedMetadata.LastErrorCode) { [string]$loadedMetadata.LastErrorCode } elseif ($loadedMetadata -and ($loadedPropNames -contains 'ErrorCode') -and $loadedMetadata.ErrorCode) { [string]$loadedMetadata.ErrorCode } else { $null }
    $currentFileName = if ($loadedMetadata -and ($loadedPropNames -contains 'CurrentFileName') -and $loadedMetadata.CurrentFileName) { [string]$loadedMetadata.CurrentFileName } elseif ($loadedMetadata -and ($loadedPropNames -contains 'CurrentFile') -and $loadedMetadata.CurrentFile) { [System.IO.Path]::GetFileName([string]$loadedMetadata.CurrentFile) } else { $fileName }
    $originalFileName = if ($loadedMetadata -and ($loadedPropNames -contains 'OriginalFileName') -and $loadedMetadata.OriginalFileName) { [string]$loadedMetadata.OriginalFileName } else { $fileName }

    $metadata = [pscustomobject]@{
        JobId            = $jobId
        StableJobKey     = if ($loadedMetadata -and ($loadedPropNames -contains 'StableJobKey') -and $loadedMetadata.StableJobKey) { [string]$loadedMetadata.StableJobKey } else { $stableKey }
        OriginalFileName = $originalFileName
        CurrentFileName  = $currentFileName
        UseCaseName      = $resolvedUseCaseName
        Queue            = $resolvedQueue
        Status           = $resolvedStatus
        RetryAfter       = if ($loadedMetadata -and ($loadedPropNames -contains 'RetryAfter') -and $loadedMetadata.RetryAfter) { [string]$loadedMetadata.RetryAfter } else { $null }
        ResumeAfter      = if ($loadedMetadata -and ($loadedPropNames -contains 'ResumeAfter') -and $loadedMetadata.ResumeAfter) { [string]$loadedMetadata.ResumeAfter } else { $null }
        PauseReason      = if ($loadedMetadata -and ($loadedPropNames -contains 'PauseReason') -and $loadedMetadata.PauseReason) { [string]$loadedMetadata.PauseReason } else { $null }
        Attempts         = $attempts
        CreatedAt        = $createdAt
        UpdatedAt        = $now
        ClaimedAt        = if ($loadedMetadata -and ($loadedPropNames -contains 'ClaimedAt') -and $loadedMetadata.ClaimedAt) { [string]$loadedMetadata.ClaimedAt } else { $null }
        CompletedAt      = if ($loadedMetadata -and ($loadedPropNames -contains 'CompletedAt') -and $loadedMetadata.CompletedAt) { [string]$loadedMetadata.CompletedAt } else { $null }
        FailedAt         = if ($loadedMetadata -and ($loadedPropNames -contains 'FailedAt') -and $loadedMetadata.FailedAt) { [string]$loadedMetadata.FailedAt } else { $null }
        LastMessage      = $lastMessage
        LastErrorCode    = $lastErrorCode
    }

    Save-JobMetadata -FilePath $FilePath -Metadata $metadata | Out-Null
    $metadata
}

function Remove-JobMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$FilePath)

    $metadataPath = Get-JobMetadataPath -FilePath $FilePath
    if (Test-Path -Path $metadataPath -PathType Leaf) {
        Remove-Item -Path $metadataPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-JobDue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][ValidateSet('incoming', 'retry', 'paused')][string]$Status
    )

    if ($Status -eq 'incoming') {
        return $true
    }

    $metadata = Read-JobMetadata -FilePath $FilePath
    if (-not $metadata) {
        return $true
    }

    $now = Get-Date

    if ($Status -eq 'retry' -and $metadata.RetryAfter) {
        $retryAfter = [datetime]::MinValue
        if ([datetime]::TryParse([string]$metadata.RetryAfter, [ref]$retryAfter)) {
            if ($retryAfter -gt $now) {
                return $false
            }
        }
    }

    if ($Status -eq 'paused' -and $metadata.ResumeAfter) {
        $resumeAfter = [datetime]::MinValue
        if ([datetime]::TryParse([string]$metadata.ResumeAfter, [ref]$resumeAfter)) {
            if ($resumeAfter -gt $now) {
                return $false
            }
        }
    }

    return $true
}

function Find-UseCaseJobFiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$QueueRoot,
        [Parameter(Mandatory = $true)][string]$Pattern,
        # IncludePaused: scan the paused queue and return files where ResumeAfter is
        # empty or already due. Intended for operators who want visibility/re-processing.
        [switch]$IncludePaused,
        # ResumePaused: deliberate resumption — also scans paused and applies the same
        # ResumeAfter-due check. Semantically distinct from IncludePaused to make the
        # call-site intent explicit in handler or engine code.
        [switch]$ResumePaused
    )

    # paused is never scanned by default; it must be requested explicitly.
    $statuses = @('incoming', 'retry')
    if ($IncludePaused -or $ResumePaused) {
        $statuses += 'paused'
    }

    $files = New-Object System.Collections.Generic.List[object]
    foreach ($status in $statuses) {
        $folder = Get-QueuePath -RootPath $RootPath -QueueRoot $QueueRoot -Status $status
        if (-not (Test-Path -Path $folder -PathType Container)) {
            continue
        }

        $candidates = Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.csv' -and $_.Name -like $Pattern -and $_.Name -notlike '*.meta.json' -and $_.Name -notlike '*.lock' }

        foreach ($candidate in $candidates) {
            # Skip files that are currently locked by another runner.
            if (Test-Path -Path "$($candidate.FullName).lock" -PathType Leaf) {
                continue
            }

            # For retry: only return files where RetryAfter is empty or already due.
            # For paused: only return files where ResumeAfter is empty or already due.
            # Test-JobDue encapsulates both checks.
            if (Test-JobDue -FilePath $candidate.FullName -Status $status) {
                $files.Add($candidate)
            }
        }
    }

    $files | Sort-Object LastWriteTime
}

function Claim-JobFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$QueueRoot,
        [Parameter(Mandatory = $true)][string]$UseCaseName,
        [Parameter(Mandatory = $true)][string]$Queue,
        [int]$StaleLockMinutes = 60
    )

    if (-not (Test-Path -Path $FilePath -PathType Leaf)) {
        return $null
    }

    # New-FileLock returns $null on a normal lock conflict (another runner owns the file)
    # and throws on unexpected errors (access denied, invalid path, etc.).
    $lockPath = New-FileLock -TargetPath $FilePath -StaleLockMinutes $StaleLockMinutes
    if (-not $lockPath) {
        return $null
    }

    try {
        $processingPath = Get-QueuePath -RootPath $RootPath -QueueRoot $QueueRoot -Status 'processing'
        $rawTarget = Join-Path -Path $processingPath -ChildPath ([System.IO.Path]::GetFileName($FilePath))
        $targetPath = Get-NonConflictingPath -Path $rawTarget

        $sourceMetadata = Get-OrCreateJobMetadata -FilePath $FilePath -UseCaseName $UseCaseName -Queue $Queue
        Move-Item -Path $FilePath -Destination $targetPath -ErrorAction Stop

        $now = (Get-Date).ToString('o')
        $targetMetadata = [pscustomobject]@{
            JobId            = [string]$sourceMetadata.JobId
            StableJobKey     = [string]$sourceMetadata.StableJobKey
            OriginalFileName = [string]$sourceMetadata.OriginalFileName
            CurrentFileName  = [System.IO.Path]::GetFileName($targetPath)
            UseCaseName      = $UseCaseName
            Queue            = $Queue
            Status           = 'processing'
            RetryAfter       = $null
            ResumeAfter      = $null
            PauseReason      = $null
            Attempts         = ([int]$sourceMetadata.Attempts + 1)
            CreatedAt        = [string]$sourceMetadata.CreatedAt
            UpdatedAt        = $now
            ClaimedAt        = $now
            CompletedAt      = $null
            FailedAt         = $null
            LastMessage      = $null
            LastErrorCode    = $null
        }

        $targetMetadataPath = Save-JobMetadata -FilePath $targetPath -Metadata $targetMetadata
        Remove-JobMetadata -FilePath $FilePath

        [pscustomobject]@{
            JobId        = $targetMetadata.JobId
            StableJobKey = $targetMetadata.StableJobKey
            SourceFile   = $FilePath
            WorkingFile  = $targetPath
            MetadataPath = $targetMetadataPath
            Metadata     = $targetMetadata
        }
    }
    catch {
        throw
    }
    finally {
        Remove-FileLock -TargetPath $FilePath
    }
}

function Move-JobFileToStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WorkingFile,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$QueueRoot,
        [Parameter(Mandatory = $true)][ValidateSet('done', 'failed', 'retry', 'paused', 'archive')][string]$Status,
        [datetime]$RetryAfter,
        [datetime]$ResumeAfter,
        [string]$PauseReason,
        [string]$Message,
        [string]$ErrorCode,
        [object]$JobResult,
        [switch]$AllowMetadataFallback
    )

    # Step 1: Read metadata before computing target path, so Get-NonConflictingPath
    # can check both CSV and .meta.json sidecar for conflicts.
    $metadata = Read-JobMetadata -FilePath $WorkingFile
    if (-not $metadata) {
        if (-not $AllowMetadataFallback) {
            throw "Metadata file missing for working file '$WorkingFile'."
        }
        $metadata = Get-OrCreateJobMetadata -FilePath $WorkingFile -UseCaseName 'Unknown.UseCase' -Queue 'unknown'
    }

    # Step 2: Determine a non-conflicting target path (checks both CSV and .meta.json).
    $targetFolder = Get-QueuePath -RootPath $RootPath -QueueRoot $QueueRoot -Status $Status
    $rawTarget = Join-Path -Path $targetFolder -ChildPath ([System.IO.Path]::GetFileName($WorkingFile))
    $targetPath = Get-NonConflictingPath -Path $rawTarget

    # Step 4: Move CSV to target.
    Move-Item -Path $WorkingFile -Destination $targetPath -ErrorAction Stop

    # Step 3: Build target metadata object.
    $now = (Get-Date).ToString('o')
    $jobResultProps = @()
    if ($JobResult) {
        $jobResultProps = @($JobResult.PSObject.Properties.Name)
    }

    $messageValue = if ($JobResult -and ($jobResultProps -contains 'Message') -and $JobResult.Message) { [string]$JobResult.Message } elseif ($PSBoundParameters.ContainsKey('Message')) { $Message } else { $null }
    $errorCodeValue = if ($JobResult -and ($jobResultProps -contains 'ErrorCode') -and $JobResult.ErrorCode) { [string]$JobResult.ErrorCode } elseif ($PSBoundParameters.ContainsKey('ErrorCode')) { $ErrorCode } else { $null }
    $retryAfterValue = $null
    if ($JobResult -and ($jobResultProps -contains 'RetryAfter') -and $JobResult.RetryAfter) {
        $retryAfterValue = ([datetime]$JobResult.RetryAfter).ToString('o')
    }
    elseif ($PSBoundParameters.ContainsKey('RetryAfter')) {
        $retryAfterValue = $RetryAfter.ToString('o')
    }

    $resumeAfterValue = $null
    if ($JobResult -and ($jobResultProps -contains 'ResumeAfter') -and $JobResult.ResumeAfter) {
        $resumeAfterValue = ([datetime]$JobResult.ResumeAfter).ToString('o')
    }
    elseif ($PSBoundParameters.ContainsKey('ResumeAfter')) {
        $resumeAfterValue = $ResumeAfter.ToString('o')
    }

    $pauseReasonValue = if ($JobResult -and ($jobResultProps -contains 'PauseReason') -and $JobResult.PauseReason) { [string]$JobResult.PauseReason } elseif ($PSBoundParameters.ContainsKey('PauseReason')) { $PauseReason } else { $null }

    $movedMetadata = [pscustomobject]@{
        JobId            = [string]$metadata.JobId
        StableJobKey     = [string]$metadata.StableJobKey
        OriginalFileName = [string]$metadata.OriginalFileName
        CurrentFileName  = [System.IO.Path]::GetFileName($targetPath)
        UseCaseName      = [string]$metadata.UseCaseName
        Queue            = [string]$metadata.Queue
        Status           = $Status
        RetryAfter       = if ($Status -eq 'retry') { $retryAfterValue } else { $null }
        ResumeAfter      = if ($Status -eq 'paused') { $resumeAfterValue } else { $null }
        PauseReason      = if ($Status -eq 'paused') { $pauseReasonValue } else { $null }
        Attempts         = [int]$metadata.Attempts
        CreatedAt        = [string]$metadata.CreatedAt
        UpdatedAt        = $now
        ClaimedAt        = [string]$metadata.ClaimedAt
        CompletedAt      = if ($Status -eq 'done') { $now } elseif ($metadata.CompletedAt) { [string]$metadata.CompletedAt } else { $null }
        FailedAt         = if ($Status -eq 'failed') { $now } elseif ($metadata.FailedAt) { [string]$metadata.FailedAt } else { $null }
        LastMessage      = $messageValue
        LastErrorCode    = $errorCodeValue
    }

    # Step 5: Write .meta.json next to the newly moved CSV.
    # If this write fails the exception propagates — do not swallow silently.
    Save-JobMetadata -FilePath $targetPath -Metadata $movedMetadata | Out-Null

    # Step 6: Remove the old .meta.json from the working (source) location.
    Remove-JobMetadata -FilePath $WorkingFile

    $targetPath
}

function Get-UseCaseLockPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$QueueRoot,
        [Parameter(Mandatory = $true)][string]$UseCaseName
    )

    $queueBasePath = Join-Path -Path $RootPath -ChildPath $QueueRoot
    $lockFolder = Join-Path -Path $queueBasePath -ChildPath '.locks'
    if (-not (Test-Path -Path $lockFolder -PathType Container)) {
        New-Item -Path $lockFolder -ItemType Directory -Force | Out-Null
    }

    $safeUseCaseName = ($UseCaseName -replace '[^a-zA-Z0-9._-]', '_')
    Join-Path -Path $lockFolder -ChildPath "$safeUseCaseName.lock"
}

function Enter-UseCaseLock {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RootPath,
        [Parameter(Mandatory = $true)][string]$QueueRoot,
        [Parameter(Mandatory = $true)][string]$UseCaseName,
        [int]$StaleLockMinutes = 60
    )

    $lockPath = Get-UseCaseLockPath -RootPath $RootPath -QueueRoot $QueueRoot -UseCaseName $UseCaseName
    if (Test-Path -Path $lockPath -PathType Leaf) {
        $lockInfo = Get-Item -Path $lockPath -ErrorAction SilentlyContinue
        if ($lockInfo) {
            $ageMinutes = ((Get-Date) - $lockInfo.LastWriteTime).TotalMinutes
            if ($ageMinutes -ge $StaleLockMinutes) {
                Remove-Item -Path $lockPath -Force -ErrorAction SilentlyContinue
            }
        }

        if (Test-Path -Path $lockPath -PathType Leaf) {
            return $null
        }
    }

    try {
        $stream = [System.IO.File]::Open(
            $lockPath,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None
        )
        try {
            $content = "Pid=$PID;CreatedAt=$((Get-Date).ToString('o'))"
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
            $stream.Write($bytes, 0, $bytes.Length)
        }
        finally {
            $stream.Dispose()
        }
        $lockPath
    }
    catch [System.IO.IOException] {
        # Normal lock conflict — another runner holds this use-case lock.
        $null
    }
    catch {
        # Unexpected error — propagate so the engine can log the real cause.
        throw
    }
}

function Exit-UseCaseLock {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$LockPath)

    if (Test-Path -Path $LockPath -PathType Leaf) {
        Remove-Item -Path $LockPath -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function @(
    'New-JobId',
    'Get-QueuePath',
    'Ensure-QueueFolders',
    'Get-JobMetadataPath',
    'Get-StableJobKey',
    'Read-JobMetadata',
    'Save-JobMetadata',
    'Get-OrCreateJobMetadata',
    'Remove-JobMetadata',
    'Get-NonConflictingPath',
    'Test-JobDue',
    'Find-UseCaseJobFiles',
    'Claim-JobFile',
    'Move-JobFileToStatus',
    'Get-UseCaseLockPath',
    'Enter-UseCaseLock',
    'Exit-UseCaseLock'
)
