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
    $isMigrationTransient = $false
    $reason = 'No lookup completed.'
    $permissionAuthority = 'Unknown'
    $recipientAuthority = 'Unknown'
    $isSynchronized = $false
    $isCloudOnly = $false
    $featureAuthority = 'Unknown'
    $recommendedAction = 'Fail'
    $retryAfterMinutes = 15

    # Safe check: ExchangeOnline.Enabled only if key exists and is a hashtable
    $exoEnabled = (
        $Config.ContainsKey('ExchangeOnline') -and
        $Config['ExchangeOnline'] -is [hashtable] -and
        $Config['ExchangeOnline'].ContainsKey('Enabled') -and
        [bool]$Config['ExchangeOnline']['Enabled']
    )

    # Step 1: On-Prem lookup (always attempted)
    try {
        $onPremRecipient = Get-OnPremRecipientSafe -Identity $Identity
        if ($onPremRecipient) {
            $onPrem = $true
            $recipientType = [string]$onPremRecipient.RecipientTypeDetails
        }
        $reason = 'On-prem recipient lookup completed.'
    }
    catch {
        $reason = "On-prem recipient lookup failed: $($_.Exception.Message)"
    }

    # Step 2: Determine whether EXO lookup is needed.
    # RemoteSharedMailbox = on-prem proxy object for a mailbox that was migrated to M365.
    $isRemote = ($onPrem -and $recipientType -eq 'RemoteSharedMailbox')
    $needsExoLookup = $isRemote -or (-not $onPrem)

    # Step 3: EXO lookup when required
    if ($needsExoLookup) {
        if ($exoEnabled) {
            try {
                $exoRecipient = Get-ExoRecipientSafe -Identity $Identity -Config $Config
                if ($exoRecipient) {
                    $exo = $true
                    if (-not $recipientType) { $recipientType = [string]$exoRecipient.RecipientTypeDetails }
                }
                $reason = 'Checked on-prem and Exchange Online.'
            }
            catch {
                $reason = "Exchange Online lookup failed: $($_.Exception.Message)"
            }
        }
        else {
            $reason = if ($isRemote) {
                "RemoteSharedMailbox found on-prem for '$Identity' but Exchange Online is disabled by configuration."
            }
            else {
                "Identity '$Identity' not found on-prem and Exchange Online is disabled by configuration."
            }
        }
    }
    else {
        $reason = "On-prem recipient found for '$Identity'. No Exchange Online lookup required."
    }

    # Step 4: Routing decision based on mailbox type and location
    if ($onPrem -and $recipientType -in @('UserMailbox', 'SharedMailbox')) {
        # On-Prem mailbox — all Exchange operations (permissions, recipient attributes, features) go to On-Prem Exchange
        $permissionAuthority = 'OnPremExchange'
        $recipientAuthority = 'OnPremExchange'
        $featureAuthority = 'OnPremExchange'
        $recommendedAction = 'Execute'
        $isSynchronized = $false
        $isCloudOnly = $false
    }
    elseif ($onPrem -and $recipientType -eq 'RemoteUserMailbox') {
        # AD-synchronized user mailbox hosted in Exchange Online.
        # Synchronized recipient attributes (PrimarySmtpAddress, proxyAddresses, etc.) are set via
        # Set-RemoteMailbox On-Prem and synced to EXO via Entra Connect. No EXO connectivity needed.
        # Mailbox features (e.g. HideFromAddressLists) are also managed via Set-RemoteMailbox On-Prem.
        $permissionAuthority = 'ExchangeOnline'
        $recipientAuthority = 'OnPremExchange'
        $featureAuthority = 'OnPremExchange'
        $recommendedAction = 'Execute'
        $isSynchronized = $true
        $isCloudOnly = $false
        $reason = "RemoteUserMailbox found for '$Identity'. Synchronized attributes can be managed via On-Prem Exchange."
    }
    elseif ($onPrem -and $recipientType -eq 'RemoteSharedMailbox') {
        # Mailbox was migrated to Exchange Online; on-prem object is a proxy.
        # Permission changes require EXO reachability. Synchronized features (e.g. HideFromAddressLists)
        # can be managed via Set-RemoteMailbox On-Prem without EXO connectivity.
        $recipientAuthority = 'OnPremExchange'
        $permissionAuthority = 'ExchangeOnline'
        $featureAuthority = 'OnPremExchange'
        $isSynchronized = $true
        $isCloudOnly = $false
        if (-not $exoEnabled) {
            $recommendedAction = 'Fail'
            $reason = "RemoteSharedMailbox found on-prem for '$Identity' but Exchange Online is disabled by configuration. Enable ExchangeOnline.Enabled to manage this mailbox."
        }
        elseif ($exo) {
            # EXO mailbox is reachable and ready
            $recommendedAction = 'Execute'
            $isMigrationTransient = $false
            $reason = "RemoteSharedMailbox confirmed in Exchange Online for '$Identity'."
        }
        else {
            # EXO enabled but mailbox not yet visible — migration sync in progress
            $recommendedAction = 'Retry'
            $isMigrationTransient = $true
            $reason = "RemoteSharedMailbox found on-prem for '$Identity' but Exchange Online mailbox not yet visible. Transient migration sync state. Retry after $retryAfterMinutes minutes."
        }
    }
    elseif ($exo -and -not $onPrem) {
        # EXO-only mailbox (no on-prem proxy object) — all operations including features must go through EXO
        $permissionAuthority = 'ExchangeOnline'
        $recipientAuthority = 'ExchangeOnline'
        $featureAuthority = 'ExchangeOnline'
        $recommendedAction = 'Execute'
        $isSynchronized = $false
        $isCloudOnly = $true
        $reason = "EXO-only mailbox found for '$Identity'."
    }
    else {
        # Not found anywhere
        $permissionAuthority = 'Unknown'
        $recipientAuthority = 'Unknown'
        $isSynchronized = $false
        $isCloudOnly = $false
        $recommendedAction = 'Fail'
        if ($reason -eq 'On-prem recipient lookup completed.' -or $reason -eq 'Checked on-prem and Exchange Online.') {
            $reason = "Identity '$Identity' not found on-prem or in Exchange Online."
        }
    }

    [pscustomobject]@{
        Identity               = $Identity
        ExistsOnPrem           = $onPrem
        ExistsInExchangeOnline = $exo
        RecipientTypeDetails   = $recipientType
        IdentityAuthority      = if ($onPrem) { 'OnPremAD' } elseif ($exo) { 'ExchangeOnline' } else { 'Unknown' }
        AttributeAuthority     = if ($onPrem) { 'OnPremAD' } else { 'ExchangeOnline' }
        RecipientAuthority     = $recipientAuthority
        MailboxAuthority       = if ($exo) { 'ExchangeOnline' } elseif ($onPrem) { 'OnPremExchange' } else { 'Unknown' }
        ManagementAuthority    = $permissionAuthority
        PermissionAuthority    = $permissionAuthority
        FeatureAuthority       = $featureAuthority
        IsSynchronized         = $isSynchronized
        IsCloudOnly            = $isCloudOnly
        IsMigrationTransient   = $isMigrationTransient
        RecommendedAction      = $recommendedAction
        RetryAfterMinutes      = $retryAfterMinutes
        Reason                 = $reason
    }
}

Export-ModuleMember -Function @('Resolve-MailboxExecutionContext')
