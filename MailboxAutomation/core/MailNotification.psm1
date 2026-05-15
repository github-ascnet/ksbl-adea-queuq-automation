Set-StrictMode -Version Latest

function Send-JobNotification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string]$Subject,
        [Parameter(Mandatory = $true)][string]$Body,
        [object]$Logger
    )

    if (-not $Config.Notifications.Enabled) {
        if ($Logger) { Write-LogDebug -Logger $Logger -Message 'Notifications disabled.' }
        return
    }

    # TODO: Migrate legacy logic here
    if ($Logger) { Write-LogInfo -Logger $Logger -Message "Notification prepared: $Subject" }
}

function Send-JobFailureNotification {
    [CmdletBinding()]
    param([hashtable]$Config, [string]$UseCaseName, [string]$Message, [object]$Logger)

    Send-JobNotification -Config $Config -Subject "Job failed: $UseCaseName" -Body $Message -Logger $Logger
}

function Send-JobSuccessNotification {
    [CmdletBinding()]
    param([hashtable]$Config, [string]$UseCaseName, [string]$Message, [object]$Logger)

    Send-JobNotification -Config $Config -Subject "Job succeeded: $UseCaseName" -Body $Message -Logger $Logger
}

Export-ModuleMember -Function @('Send-JobNotification','Send-JobFailureNotification','Send-JobSuccessNotification')
