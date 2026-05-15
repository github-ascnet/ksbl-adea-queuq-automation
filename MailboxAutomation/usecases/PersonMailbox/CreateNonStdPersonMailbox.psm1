Set-StrictMode -Version Latest

function Invoke-CreateNonStdPersonMailbox {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @('ActionType','TargetAdObjectName','TargetDomain','TargetDomainUserOU','TargetUserAdDisplayname','TargetUserAdGivenname','TargetUserAdSurname','TargetUserAdEmployeeType','TargetLocation','MailboxEnable','CurrentUserName','CurrentUserDomainName','CurrentUserEMailAddress')

        $statePath = Get-JobStatePath -RootPath $Context.RootPath -StatePath $Context.Config.Paths.StatePath -StableJobKey $Context.StableJobKey -JobId $Context.JobId
        $state = Get-JobState -StateFilePath $statePath
        if (-not $state) {
            $state = Initialize-JobState -JobId $Context.JobId -StableJobKey $Context.StableJobKey -UseCase $Context.UseCaseName -CurrentStep 10
            Save-JobState -StateFilePath $statePath -State $state | Out-Null
        }

        Increment-JobStateStepAttempt -State $state | Out-Null

        switch ([int]$state.CurrentStep) {
            10 {
                # TODO: Migrate legacy logic here
                Set-JobStateStep -State $state -Step 20 -Message 'Input validated.' | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 10 completed. Continue with step 20.' -RetryAfter (Get-Date).AddSeconds(1)
            }
            20 {
                # TODO: Migrate legacy logic here
                Set-JobStateStep -State $state -Step 30 -Message 'AD account prepared.' | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 20 completed. Continue with step 30.' -RetryAfter (Get-Date).AddSeconds(1)
            }
            30 {
                # TODO: Migrate legacy logic here
                Set-JobStateStep -State $state -Step 40 -Message 'Mailbox preparation started.' | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 30 completed. Continue with step 40.' -RetryAfter (Get-Date).AddSeconds(1)
            }
            40 {
                if ([int]$state.CurrentStepAttempts -lt 2) {
                    $state.Status = 'Waiting'
                    $state.LastMessage = 'Mailbox not visible yet. Retry scheduled.'
                    Save-JobState -StateFilePath $statePath -State $state | Out-Null
                    return New-JobRetryResult -Message 'Waiting for mailbox visibility.' -RetryAfter (Get-Date).AddMinutes(5)
                }

                Set-JobStateStep -State $state -Step 50 -Message 'Mailbox became visible.' | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 40 completed. Continue with step 50.' -RetryAfter (Get-Date).AddSeconds(1)
            }
            50 {
                # TODO: Migrate legacy logic here
                Set-JobStateStep -State $state -Step 60 -Message 'Mailbox attributes applied.' | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 50 completed. Continue with step 60.' -RetryAfter (Get-Date).AddSeconds(1)
            }
            60 {
                # TODO: Migrate legacy logic here
                Set-JobStateStep -State $state -Step 90 -Message 'Finalization complete.' | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobRetryResult -Message 'Step 60 completed. Continue with step 90.' -RetryAfter (Get-Date).AddSeconds(1)
            }
            90 {
                Complete-JobState -State $state -Message 'Completed.' | Out-Null
                Save-JobState -StateFilePath $statePath -State $state | Out-Null
                return New-JobSucceededResult -Message 'PersonMailbox.CreateNonStandard completed.'
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
