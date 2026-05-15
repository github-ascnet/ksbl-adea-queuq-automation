Set-StrictMode -Version Latest

function Resolve-MailboxExecutionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    $onPrem = $false
    $exo = $false
    $recipientType = $null
    $reason = 'Checked on-prem only.'

    try {
        $onPremRecipient = Get-OnPremRecipientSafe -Identity $Identity
        if ($onPremRecipient) {
            $onPrem = $true
            $recipientType = $onPremRecipient.RecipientTypeDetails
        }
    }
    catch {
        $reason = "On-prem recipient lookup failed: $($_.Exception.Message)"
    }

    if ($Config.ExchangeOnline.Enabled) {
        try {
            $exoRecipient = Get-ExoRecipientSafe -Identity $Identity -Config $Config
            if ($exoRecipient) {
                $exo = $true
                if (-not $recipientType) { $recipientType = $exoRecipient.RecipientTypeDetails }
            }
            $reason = 'Checked on-prem and Exchange Online.'
        }
        catch {
            $reason = "Exchange Online lookup failed: $($_.Exception.Message)"
        }
    }
    else {
        $reason = 'Exchange Online disabled by configuration.'
    }

    $permissionAuthority = if ($exo) { 'ExchangeOnline' } elseif ($onPrem) { 'OnPrem' } else { 'Unknown' }

    [pscustomobject]@{
        Identity               = $Identity
        ExistsOnPrem           = $onPrem
        ExistsInExchangeOnline = $exo
        RecipientTypeDetails   = $recipientType
        AttributeAuthority     = 'OnPremAD'
        MailboxAuthority       = if ($exo) { 'ExchangeOnline' } else { 'ExchangeOnPrem' }
        PermissionAuthority    = $permissionAuthority
        IsMigrationTransient   = $false
        Reason                 = $reason
    }
}

Export-ModuleMember -Function @('Resolve-MailboxExecutionContext')
