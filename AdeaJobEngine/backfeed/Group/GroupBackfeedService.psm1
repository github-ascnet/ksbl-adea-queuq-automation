Set-StrictMode -Version Latest

function Invoke-GroupBackfeed {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $startedAt = if ($Context.StartedAt) { [datetime]$Context.StartedAt } else { Get-Date }
    $completedAt = Get-Date

    New-BackfeedResult -BackfeedType 'Group' -Mode ([string]$Context.Mode) -Status 'NotImplemented' -StartedAt $startedAt -CompletedAt $completedAt -DurationSeconds ([math]::Round(($completedAt - $startedAt).TotalSeconds, 3))
}

Export-ModuleMember -Function @('Invoke-GroupBackfeed')