Set-StrictMode -Version Latest

function ConvertTo-HashtableDeep {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$InputObject)

    if ($null -eq $InputObject) { return $null }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $hash = @{}
        foreach ($key in $InputObject.Keys) {
            $hash[$key] = ConvertTo-HashtableDeep -InputObject $InputObject[$key]
        }
        return $hash
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $list = @()
        foreach ($item in $InputObject) {
            $list += ,(ConvertTo-HashtableDeep -InputObject $item)
        }
        return $list
    }

    if ($InputObject -is [psobject]) {
        $props = @($InputObject.PSObject.Properties)
        if ($props.Count -gt 0) {
            $hash = @{}
            foreach ($prop in $props) {
                $hash[$prop.Name] = ConvertTo-HashtableDeep -InputObject $prop.Value
            }
            return $hash
        }
    }

    return $InputObject
}

function Merge-Hashtable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Base,
        [Parameter(Mandatory = $true)][hashtable]$Override
    )

    $result = @{}
    foreach ($key in $Base.Keys) {
        $result[$key] = $Base[$key]
    }

    foreach ($key in $Override.Keys) {
        if ($result.ContainsKey($key) -and ($result[$key] -is [hashtable]) -and ($Override[$key] -is [hashtable])) {
            $result[$key] = Merge-Hashtable -Base $result[$key] -Override $Override[$key]
        }
        else {
            $result[$key] = $Override[$key]
        }
    }

    $result
}

function Read-JsonAsHashtable {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -Path $Path -PathType Leaf)) {
        throw "JSON file not found: $Path"
    }

    $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return @{}
    }

    $obj = $raw | ConvertFrom-Json -ErrorAction Stop
    ConvertTo-HashtableDeep -InputObject $obj
}

function New-ServiceContainer {
    [CmdletBinding()]
    param()

    @{
        UserProvisioning = [pscustomobject]@{
            NewUser                     = { param($Context, $Data) New-GenericUser -Context $Context -Data $Data }
            EnableUser                  = { param($Context, $Data) Enable-GenericUser -Context $Context -Data $Data }
            DisableUser                 = { param($Context, $Data) Disable-GenericUser -Context $Context -Data $Data }
            RenameUser                  = { param($Context, $Data) Rename-GenericUser -Context $Context -Data $Data }
            SetSurname                  = { param($Context, $Data) Set-GenericUserSurname -Context $Context -Data $Data }
            AddEmailNickname            = { param($Context, $Data) Add-GenericUserEmailNickname -Context $Context -Data $Data }
            EnableWithGracePeriod       = { param($Context, $Data) Enable-GenericUserWithGracePeriod -Context $Context -Data $Data }
            SetMobilePhoneNumber        = { param($Context, $Data) Set-GenericUserMobilePhoneNumber -Context $Context -Data $Data }
            SetMailboxFolderAce         = { param($Context, $Data) Set-GenericUserMailboxFolderAce -Context $Context -Data $Data }
        }
        MailboxPermission = [pscustomobject]@{
            AddFullAccess    = { param($Context, $Data) Add-MailboxFullAccess -Context $Context -Data $Data }
            RemoveFullAccess = { param($Context, $Data) Remove-MailboxFullAccess -Context $Context -Data $Data }
            AddSendAs        = { param($Context, $Data) Add-MailboxSendAs -Context $Context -Data $Data }
            RemoveSendAs     = { param($Context, $Data) Remove-MailboxSendAs -Context $Context -Data $Data }
        }
    }
}

function Convert-ResultToQueueStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Status)

    switch ($Status) {
        'Succeeded' { 'done' }
        'Skipped'   { 'done' }
        'Failed'    { 'failed' }
        'Retry'     { 'retry' }
        'Paused'    { 'paused' }
        default     { 'failed' }
    }
}

function Invoke-JobEngine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter(Mandatory = $true)][string]$UseCaseRegistryPath,
        [Parameter(Mandatory = $true)][string]$EnvironmentPath,
        [Parameter(Mandatory = $true)][ValidateSet('standard','urgent','person-mailbox-longrunning')][string]$Queue,
        [Parameter(Mandatory = $true)][string]$RootPath,
        [bool]$IncludePaused = $false,
        [bool]$ResumePaused = $false,
        [bool]$WhatIfMode,
        [bool]$VerboseLogging
    )

    $runId = [guid]::NewGuid().ToString('N')

    $baseConfig = Read-JsonAsHashtable -Path $ConfigPath
    $environmentConfig = Read-JsonAsHashtable -Path $EnvironmentPath
    $mergedConfig = Merge-Hashtable -Base $baseConfig -Override $environmentConfig
    $mergedConfig['RootPath'] = $RootPath

    $logger = New-Logger -Config $mergedConfig -RunId $runId -VerboseLogging:$VerboseLogging
    Write-LogInfo -Logger $logger -Message "Starting engine. Queue=$Queue WhatIfMode=$WhatIfMode"

    Ensure-QueueFolders -RootPath $RootPath -QueueRoot $mergedConfig.Paths.QueueRoot

    $registry = Read-JsonAsHashtable -Path $UseCaseRegistryPath
    $useCases = @($registry.UseCases | Where-Object { $_.Enabled -eq $true -and $_.Queue -eq $Queue } | Sort-Object Priority)

    Write-LogInfo -Logger $logger -Message "Loaded $($useCases.Count) use case(s) for queue '$Queue'."

    $services = New-ServiceContainer

    $staleLockMinutes = 60
    if ($mergedConfig.ContainsKey('Queue') -and $mergedConfig.Queue -is [hashtable] -and $mergedConfig.Queue.ContainsKey('StaleLockMinutes')) {
        $staleLockMinutes = [int]$mergedConfig.Queue.StaleLockMinutes
    }

    foreach ($useCase in $useCases) {
        $useCaseLockPath = $null
        try {
            if ([int]$useCase.MaxParallelism -le 1) {
                $useCaseLockPath = Enter-UseCaseLock -RootPath $RootPath -QueueRoot $mergedConfig.Paths.QueueRoot -UseCaseName $useCase.Name -StaleLockMinutes $staleLockMinutes
                if (-not $useCaseLockPath) {
                    Write-LogWarn -Logger $logger -Message "Use case '$($useCase.Name)' is already locked by another runner. Skipping this cycle."
                    continue
                }
            }

            $files = Find-UseCaseJobFiles -RootPath $RootPath -QueueRoot $mergedConfig.Paths.QueueRoot -Pattern $useCase.Pattern -IncludePaused:$IncludePaused -ResumePaused:$ResumePaused
        }
        catch {
            Write-LogError -Logger $logger -Message "Failed to enumerate files for use case '$($useCase.Name)'." -Exception $_.Exception
            if ($useCaseLockPath) {
                Exit-UseCaseLock -LockPath $useCaseLockPath
                $useCaseLockPath = $null
            }
            continue
        }

        try {
            foreach ($file in $files) {
                $claimed = $null
                try {
                    $claimed = Claim-JobFile -FilePath $file.FullName -RootPath $RootPath -QueueRoot $mergedConfig.Paths.QueueRoot -UseCaseName $useCase.Name -Queue $useCase.Queue -StaleLockMinutes $staleLockMinutes
                    if (-not $claimed) {
                        Write-LogWarn -Logger $logger -Message "Skipping non-claimable file: $($file.FullName)"
                        continue
                    }

                    Write-LogInfo -Logger $logger -Message "Claimed file '$($claimed.WorkingFile)' for use case '$($useCase.Name)'."

                    $payload = Import-JobCsv -Path $claimed.WorkingFile -Delimiter $mergedConfig.CsvDelimiter
                    $modulePath = Join-Path -Path $RootPath -ChildPath $useCase.Module
                    if (-not (Test-Path -Path $modulePath -PathType Leaf)) {
                        throw "Use case module not found: $modulePath"
                    }

                    Import-Module -Name $modulePath -Force -ErrorAction Stop

                    $context = New-JobContext -JobId $claimed.JobId -StableJobKey $claimed.StableJobKey -RunId $runId -UseCaseName $useCase.Name -Queue $Queue -SourceFile $claimed.SourceFile -WorkingFile $claimed.WorkingFile -MetadataPath $claimed.MetadataPath -JobMetadata $claimed.Metadata -Payload $payload -Config $mergedConfig -Environment $environmentConfig -Services $services -Logger $logger -RootPath $RootPath -WhatIfMode:$WhatIfMode -VerboseLogging:$VerboseLogging

                    $result = & $useCase.Handler -Context $context
                    $resultStatus = if ($result -and $result.PSObject.Properties['Status']) { $result.Status } else { $null }
                    if (-not $resultStatus) {
                        $result = New-JobFailedResult -Message "Handler '$($useCase.Handler)' returned no valid JobResult." -ErrorCode 'INVALID_HANDLER_RESULT'
                        $resultStatus = 'Failed'
                    }

                    # Normalize optional result properties for strict-mode safety
                    $resultMessage  = if ($result.PSObject.Properties['Message'])     { [string]$result.Message }     else { '' }
                    $resultRetry    = if ($result.PSObject.Properties['RetryAfter'])  { $result.RetryAfter }          else { $null }
                    $resultResume   = if ($result.PSObject.Properties['ResumeAfter']) { $result.ResumeAfter }         else { $null }
                    $resultPause    = if ($result.PSObject.Properties['PauseReason']) { $result.PauseReason }         else { $null }
                    $resultErrCode  = if ($result.PSObject.Properties['ErrorCode'])   { $result.ErrorCode }           else { $null }

                    $targetStatus = Convert-ResultToQueueStatus -Status $resultStatus
                    $moveParams = @{
                        WorkingFile = $claimed.WorkingFile
                        RootPath    = $RootPath
                        QueueRoot   = $mergedConfig.Paths.QueueRoot
                        Status      = $targetStatus
                        Message     = $resultMessage
                        JobResult   = $result
                    }
                    if ($resultRetry -and $resultStatus -eq 'Retry') {
                        $moveParams['RetryAfter'] = $resultRetry
                    }
                    if ($resultResume -and $resultStatus -eq 'Paused') {
                        $moveParams['ResumeAfter'] = $resultResume
                    }
                    if ($resultPause -and $resultStatus -eq 'Paused') {
                        $moveParams['PauseReason'] = $resultPause
                    }
                    if ($resultErrCode) {
                        $moveParams['ErrorCode'] = $resultErrCode
                    }

                    $movedPath = Move-JobFileToStatus @moveParams
                    Write-LogInfo -Logger $logger -Message "Job '$($claimed.JobId)' finished with status '$resultStatus'. File moved to '$movedPath'."

                    if ($resultStatus -eq 'Failed') {
                        Send-JobFailureNotification -Config $mergedConfig -UseCaseName $useCase.Name -Message $resultMessage -Logger $logger
                    }
                    elseif ($resultStatus -eq 'Succeeded') {
                        Send-JobSuccessNotification -Config $mergedConfig -UseCaseName $useCase.Name -Message $resultMessage -Logger $logger
                    }
                }
                catch {
                    Write-LogError -Logger $logger -Message "Engine error while processing '$($file.FullName)' for '$($useCase.Name)'." -Exception $_.Exception

                    if ($claimed -and (Test-Path -Path $claimed.WorkingFile)) {
                        try {
                            Move-JobFileToStatus -WorkingFile $claimed.WorkingFile -RootPath $RootPath -QueueRoot $mergedConfig.Paths.QueueRoot -Status 'failed' -Message $_.Exception.Message -ErrorCode 'ENGINE_ERROR' -AllowMetadataFallback | Out-Null
                        }
                        catch {
                            Write-LogError -Logger $logger -Message "Could not move failed file '$($claimed.WorkingFile)' to failed queue." -Exception $_.Exception
                        }
                    }
                }
            }
        }
        finally {
            if ($useCaseLockPath) {
                Exit-UseCaseLock -LockPath $useCaseLockPath
            }
        }
    }

    Write-LogInfo -Logger $logger -Message 'Job engine completed.'
}

Export-ModuleMember -Function @('Invoke-JobEngine')
