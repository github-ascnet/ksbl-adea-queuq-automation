Set-StrictMode -Version Latest

function Invoke-ChangeAccountSurname {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    try {
        $rows = @($Context.Payload)
        Assert-RequiredCsvFields -Rows $rows -RequiredFields @(
            'ActionType',
            'AdObjectName',
            'GivenName',
            'SurName',
            'NewPrimaryEMailAddress',
            'CurrentUserName',
            'CurrentUserDomainName',
            'CurrentUserEMailAddress'
        )

        $failedResults = @()
        $successResults = @()
        $successCount = 0

        foreach ($row in $rows) {
            try {
                $result = & $Context.Services.UserProvisioning.SetSurname $Context $row

                # RequiresRetry: mailbox in transient migration state — schedule job retry
                if ($result -and $result.PSObject.Properties['RequiresRetry'] -and [bool]$result.RequiresRetry) {
                    $retryMinutes = if ($result.PSObject.Properties['RetryAfterMinutes'] -and $result.RetryAfterMinutes) { [int]$result.RetryAfterMinutes } else { 15 }
                    $retryAfter = (Get-Date).AddMinutes($retryMinutes)
                    Write-LogWarn -Logger $Context.Logger -Message "Invoke-ChangeAccountSurname: transient migration state for '$($row.AdObjectName)'. Scheduling retry after $retryMinutes minutes."
                    return New-JobRetryResult `
                        -Message "GenericUser.ChangeSurname: transient migration state for '$($row.AdObjectName)'. $($result.Message)" `
                        -RetryAfter $retryAfter `
                        -Output @{ SuccessCount = $successCount; FailedCount = $failedResults.Count; SuccessResults = $successResults; FailedRows = $failedResults }
                }

                if ($result -and $result.PSObject.Properties['Success'] -and (-not [bool]$result.Success)) {
                    $failedResults += [pscustomobject]@{
                        Row          = $row
                        AdObjectName = $row.AdObjectName
                        Message      = $result.Message
                        ErrorCode    = if ($result.ErrorCode) { $result.ErrorCode } else { 'ROW_FAILED' }
                        Result       = $result
                    }

                    Write-LogWarn -Logger $Context.Logger -Message "Invoke-ChangeAccountSurname failed for '$($row.AdObjectName)': $($result.Message)"
                    continue
                }

                $successCount++
                $successResults += [pscustomobject]@{
                    AdObjectName = $row.AdObjectName
                    SurName      = $row.SurName
                    Message      = if ($result -and $result.PSObject.Properties['Message']) { $result.Message } else { "Row processed successfully." }
                    Result       = $result
                }

                Write-LogInfo -Logger $Context.Logger -Message "Invoke-ChangeAccountSurname succeeded for '$($row.AdObjectName)'."
            }
            catch {
                $failedResults += [pscustomobject]@{
                    Row          = $row
                    AdObjectName = $row.AdObjectName
                    Message      = $_.Exception.Message
                    ErrorCode    = 'ROW_PROCESSING_ERROR'
                }

                Write-LogError -Logger $Context.Logger -Message "Invoke-ChangeAccountSurname failed for '$($row.AdObjectName)'." -Exception $_.Exception
            }
        }

        if ($failedResults.Count -gt 0) {
            return New-JobFailedResult `
                -Message "$($failedResults.Count) row(s) failed, $successCount row(s) succeeded." `
                -ErrorCode 'PARTIAL_FAILURE' `
                -Output @{
                    SuccessCount   = $successCount
                    FailedCount    = $failedResults.Count
                    SuccessResults = $successResults
                    FailedRows     = $failedResults
                }
        }

        return New-JobSucceededResult `
            -Message "$successCount row(s) processed successfully." `
            -Output @{
                SuccessCount   = $successCount
                FailedCount    = 0
                SuccessResults = $successResults
                FailedRows     = @()
            }
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Invoke-ChangeAccountSurname failed." -Exception $_.Exception
        return New-JobFailedResult -Message $_.Exception.Message -ErrorCode 'USECASE_ERROR' -Exception $_.Exception
    }
}

Export-ModuleMember -Function @('Invoke-ChangeAccountSurname')
