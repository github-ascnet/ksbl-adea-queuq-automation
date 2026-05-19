Set-StrictMode -Version Latest

function Invoke-CreateNonStdPersonMailbox {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @(
            'ActionType',
            'TargetAdObjectName',
            'TargetDomain',
            'TargetUserAdDisplayname',
            'TargetUserAdGivenname',
            'TargetUserAdSurname',
            'TargetUserAdEmployeeType',
            'TargetLocation',
            'MailboxEnable',
            'CurrentUserName',
            'CurrentUserDomainName',
            'CurrentUserEMailAddress'
        )

        foreach ($row in $rows) {
            $hasLegacyOu = $row.PSObject.Properties['TargetUserDomainOU'] -and -not [string]::IsNullOrWhiteSpace([string]$row.TargetUserDomainOU)
            $hasPreviousOuName = $row.PSObject.Properties['TargetDomainUserOU'] -and -not [string]::IsNullOrWhiteSpace([string]$row.TargetDomainUserOU)
            if (-not $hasLegacyOu -and -not $hasPreviousOuName) {
                throw "CSV row for TargetAdObjectName '$($row.TargetAdObjectName)' must contain TargetUserDomainOU. TargetDomainUserOU is accepted only as backwards-compatible alias."
            }
        }

        if ($rows.Count -ne 1) {
            return New-JobFailedResult -Message 'PersonMailbox.CreateNonStandard expects exactly one row per long-running job file.' -ErrorCode 'PERSONMAILBOX_SINGLE_ROW_REQUIRED'
        }

        $data = $rows[0]
        $statePath = Get-JobStatePath -RootPath $Context.RootPath -StatePath $Context.Config.Paths.StatePath -StableJobKey $Context.StableJobKey -JobId $Context.JobId
        $state = Get-JobState -StateFilePath $statePath
        if (-not $state) {
            $state = Initialize-JobState -JobId $Context.JobId -StableJobKey $Context.StableJobKey -UseCase $Context.UseCaseName -CurrentStep 10
            Save-JobState -StateFilePath $statePath -State $state | Out-Null
        }

        Increment-JobStateStepAttempt -State $state -Message "Executing step $($state.CurrentStep)." | Out-Null
        Save-JobState -StateFilePath $statePath -State $state | Out-Null

        switch ([int]$state.CurrentStep) {
            10 {
                $plan = New-NonStandardPersonMailboxPlan -Context $Context -Data $data
                Write-LogInfo -Logger $Context.Logger -Message "PersonMailbox.CreateNonStandard plan built for '$($plan.TargetAdObjectName)' with EmployeeType '$($plan.EmployeeType)' and MailboxEnable '$($plan.MailboxEnable)'."
                Set-JobStateStep -State $state -Step 20 -Message 'Input validated and provisioning plan created.' | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 10 completed. Continue with AD account preparation.' -RetryAfter (Get-Date).AddSeconds(1) -Output $plan
            }
            20 {
                $result = Invoke-PrepareNonStandardPersonMailboxAdAccount -Context $Context -Data $data
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                if (-not $result.Success) { return New-JobFailedResult -Message $result.Message -ErrorCode $result.ErrorCode -Output $result.Output }
                Set-JobStateStep -State $state -Step 30 -Message $result.Message | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 20 completed. Continue with mailbox preparation.' -RetryAfter (Get-Date).AddSeconds(1) -Output $result
            }
            30 {
                $result = Invoke-PrepareNonStandardPersonMailboxMailbox -Context $Context -Data $data
                if (-not $result.Success) { return New-JobFailedResult -Message $result.Message -ErrorCode $result.ErrorCode -Output $result.Output }
                Set-JobStateStep -State $state -Step 40 -Message $result.Message | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 30 completed. Continue with mailbox visibility check.' -RetryAfter (Get-Date).AddSeconds(1) -Output $result
            }
            40 {
                $result = Test-NonStandardPersonMailboxVisibility -Context $Context -Data $data
                if (-not $result.Success) { return New-JobFailedResult -Message $result.Message -ErrorCode $result.ErrorCode -Output $result.Output }
                $isVisible = $true
                if ($result.Output -is [System.Collections.IDictionary] -and $result.Output.ContainsKey('IsVisible')) {
                    $isVisible = [bool]$result.Output['IsVisible']
                }
                elseif ($result.Output -and $result.Output.PSObject.Properties['IsVisible']) {
                    $isVisible = [bool]$result.Output.IsVisible
                }
                if (-not $isVisible) {
                    $state.Status = 'Waiting'
                    $state.LastMessage = $result.Message
                    Save-JobState -StateFilePath $statePath -State $state | Out-Null
                    return New-JobRetryResult -Message $result.Message -RetryAfter (Get-Date).AddMinutes(5) -Output $result
                }
                Set-JobStateStep -State $state -Step 50 -Message $result.Message | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 40 completed. Continue with attribute application.' -RetryAfter (Get-Date).AddSeconds(1) -Output $result
            }
            50 {
                $result = Invoke-ApplyNonStandardPersonMailboxAttributes -Context $Context -Data $data
                if (-not $result.Success) { return New-JobFailedResult -Message $result.Message -ErrorCode $result.ErrorCode -Output $result.Output }
                Set-JobStateStep -State $state -Step 60 -Message $result.Message | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 50 completed. Continue with finalization.' -RetryAfter (Get-Date).AddSeconds(1) -Output $result
            }
            60 {
                $result = Complete-NonStandardPersonMailboxProvisioning -Context $Context -Data $data
                if (-not $result.Success) { return New-JobFailedResult -Message $result.Message -ErrorCode $result.ErrorCode -Output $result.Output }
                Set-JobStateStep -State $state -Step 90 -Message $result.Message | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 60 completed. Continue with state completion.' -RetryAfter (Get-Date).AddSeconds(1) -Output $result
            }
            90 {
                Complete-JobState -State $state -Message 'PersonMailbox.CreateNonStandard completed.' | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobSucceededResult -Message 'PersonMailbox.CreateNonStandard completed.' -Output @{ StatePath = $statePath; State = $state }
            }
            default {
                return New-JobFailedResult -Message "Unknown state step '$($state.CurrentStep)'." -ErrorCode 'INVALID_STATE'
            }
        }
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message 'Invoke-CreateNonStdPersonMailbox failed.' -Exception $_.Exception
        New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'PERSONMAILBOX_STATE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-CreateNonStdPersonMailbox')
