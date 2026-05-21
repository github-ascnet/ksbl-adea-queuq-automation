Set-StrictMode -Version Latest

function Get-ConfigValueSafe {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [Parameter(Mandatory = $true)][string[]]$Path,
        $DefaultValue
    )

    $current = $Config
    foreach ($segment in $Path) {
        if ($current -isnot [hashtable] -or -not $current.ContainsKey($segment)) {
            return $DefaultValue
        }
        $current = $current[$segment]
    }

    if ($null -eq $current) { return $DefaultValue }
    $current
}

function Get-CloudDomainFromConfig {
    param([hashtable]$Config)

    $candidates = @(
        [string](Get-ConfigValueSafe -Config $Config -Path @('ExchangeOnPrem','CloudDomain') -DefaultValue ''),
        [string](Get-ConfigValueSafe -Config $Config -Path @('PersonMailbox','CloudDomain') -DefaultValue ''),
        [string](Get-ConfigValueSafe -Config $Config -Path @('ExchangeOnline','CloudDomain') -DefaultValue '')
    )

    foreach ($value in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim().ToLowerInvariant()
        }
    }

    ''
}

function Get-AdPropertyValue {
    param([object]$AdObject, [string]$Name)

    if ($null -eq $AdObject) { return $null }
    if ($AdObject.PSObject.Properties[$Name]) { return $AdObject.$Name }
    $null
}

function Convert-RecipientTypeDetailsToName {
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return '' }
    $parsed = $null
    if (-not [long]::TryParse([string]$Value, [ref]$parsed)) { return '' }

    switch ($parsed) {
        1 { 'UserMailbox' }
        4 { 'SharedMailbox' }
        2147483648 { 'RemoteUserMailbox' }
        34359738368 { 'RemoteSharedMailbox' }
        default { '' }
    }
}

function Test-IsRemoteMailboxFromAdAttributes {
    param([object]$AdObject, [string]$CloudDomain)

    $remoteRaw = Get-AdPropertyValue -AdObject $AdObject -Name 'msExchRemoteRecipientType'
    $remoteText = if ($null -eq $remoteRaw) { '' } else { [string]$remoteRaw }
    $remoteValue = $null
    $hasRemoteRecipientType = -not [string]::IsNullOrWhiteSpace($remoteText)
    if ($hasRemoteRecipientType) {
        [int]::TryParse($remoteText, [ref]$remoteValue) | Out-Null
    }

    $hasRemoteBit1Or4 = $false
    if ($null -ne $remoteValue) {
        $hasRemoteBit1Or4 = (($remoteValue -band 1) -ne 0) -or (($remoteValue -band 4) -ne 0)
    }

    $targetAddress = [string](Get-AdPropertyValue -AdObject $AdObject -Name 'targetAddress')
    $targetValue = $targetAddress.Trim()
    if ($targetValue -match '^[^:]+:(.+)$') { $targetValue = $matches[1] }

    $isCloudRouted = $false
    if (-not [string]::IsNullOrWhiteSpace($CloudDomain) -and -not [string]::IsNullOrWhiteSpace($targetValue)) {
        $isCloudRouted = $targetValue.ToLowerInvariant().EndsWith('@' + $CloudDomain)
    }

    $isRemote = $hasRemoteRecipientType -or $hasRemoteBit1Or4 -or $isCloudRouted

    [pscustomobject]@{
        RemoteRecipientTypeRaw = $remoteRaw
        RemoteRecipientTypeValue = $remoteValue
        HasRemoteRecipientType = $hasRemoteRecipientType
        HasRemoteBit1Or4 = $hasRemoteBit1Or4
        IsCloudRouted = $isCloudRouted
        IsRemoteMailbox = $isRemote
    }
}

function Test-IsOnPremMailboxFromAdAttributes {
    param([object]$AdObject, [bool]$HasRemoteRecipientType)

    $homeMdb = Get-AdPropertyValue -AdObject $AdObject -Name 'homeMDB'
    $mailboxGuid = Get-AdPropertyValue -AdObject $AdObject -Name 'msExchMailboxGuid'
    $recipientDetailsRaw = Get-AdPropertyValue -AdObject $AdObject -Name 'msExchRecipientTypeDetails'

    $hasHomeMdb = -not [string]::IsNullOrWhiteSpace([string]$homeMdb)
    $hasMailboxGuid = $null -ne $mailboxGuid -and -not [string]::IsNullOrWhiteSpace([string]$mailboxGuid)

    $recipientName = Convert-RecipientTypeDetailsToName -Value $recipientDetailsRaw
    $isOnPremFromDetails = $recipientName -in @('UserMailbox','SharedMailbox')

    $isOnPrem = $hasHomeMdb -or $isOnPremFromDetails -or ($hasMailboxGuid -and -not $HasRemoteRecipientType)

    [pscustomobject]@{
        HomeMdb = $homeMdb
        HasHomeMdb = $hasHomeMdb
        MailboxGuid = $mailboxGuid
        HasMailboxGuid = $hasMailboxGuid
        RecipientTypeDetailsRaw = $recipientDetailsRaw
        RecipientTypeDetailsName = $recipientName
        IsOnPremMailbox = $isOnPrem
    }
}

function New-MailboxExecutionContextFromAdObject {
    param(
        [string]$Identity,
        [object]$AdObject,
        [hashtable]$Config,
        [string]$Mode
    )

    $cloudDomain = Get-CloudDomainFromConfig -Config $Config
    $remoteInfo = Test-IsRemoteMailboxFromAdAttributes -AdObject $AdObject -CloudDomain $cloudDomain
    $onPremInfo = Test-IsOnPremMailboxFromAdAttributes -AdObject $AdObject -HasRemoteRecipientType $remoteInfo.HasRemoteRecipientType

    $isAmbiguous = $remoteInfo.IsRemoteMailbox -and $onPremInfo.IsOnPremMailbox

    $mailboxLocation = 'Unknown'
    $permissionTarget = 'Unknown'
    $recipientAuthority = 'Unknown'
    $confidence = 'Low'
    $requiresRemoteValidation = $false
    $errorCode = 'None'
    $message = ''

    if ($isAmbiguous) {
        $mailboxLocation = 'Ambiguous'
        $permissionTarget = 'Unknown'
        $recipientAuthority = 'Unknown'
        $confidence = 'Low'
        $requiresRemoteValidation = $true
        $errorCode = 'AmbiguousHybridState'
        $message = 'Remote and on-prem mailbox indicators were both detected.'
    }
    elseif ($remoteInfo.IsRemoteMailbox) {
        $mailboxLocation = 'ExchangeOnline'
        $permissionTarget = 'ExchangeOnline'
        $recipientAuthority = 'ExchangeOnPrem'
        $confidence = if ($remoteInfo.HasRemoteRecipientType -or $remoteInfo.HasRemoteBit1Or4) { 'High' } else { 'Medium' }
        $message = 'Remote mailbox indicators detected in AD.'
    }
    elseif ($onPremInfo.IsOnPremMailbox) {
        $mailboxLocation = 'OnPrem'
        $permissionTarget = 'ExchangeOnPrem'
        $recipientAuthority = 'ExchangeOnPrem'
        $confidence = 'High'
        $message = 'On-prem mailbox indicators detected in AD.'
    }
    else {
        $mailboxLocation = 'None'
        $permissionTarget = 'None'
        $recipientAuthority = 'ActiveDirectory'
        $confidence = 'Medium'
        $message = 'AD object found, but no mailbox indicators were detected.'
    }

    $recipientTypeDetails = $onPremInfo.RecipientTypeDetailsName
    if ([string]::IsNullOrWhiteSpace($recipientTypeDetails) -and $remoteInfo.IsRemoteMailbox) {
        $recipientTypeDetails = 'RemoteUserMailbox'
    }
    elseif ([string]::IsNullOrWhiteSpace($recipientTypeDetails) -and $onPremInfo.IsOnPremMailbox) {
        $recipientTypeDetails = 'UserMailbox'
    }

    if ($recipientTypeDetails -eq 'RemoteSharedMailbox') {
        $requiresRemoteValidation = $true
    }

    $permissionAuthority = switch ($permissionTarget) {
        'ExchangeOnline' { 'ExchangeOnline' }
        'ExchangeOnPrem' { 'OnPremExchange' }
        default { 'Unknown' }
    }

    $featureAuthority = if ($remoteInfo.IsRemoteMailbox -or $onPremInfo.IsOnPremMailbox) { 'OnPremExchange' } else { 'Unknown' }

    $exoEnabled = (
        $Config.ContainsKey('ExchangeOnline') -and
        $Config['ExchangeOnline'] -is [hashtable] -and
        $Config['ExchangeOnline'].ContainsKey('Enabled') -and
        [bool]$Config['ExchangeOnline']['Enabled']
    )

    $recommendedAction = 'Execute'
    if ($permissionTarget -eq 'None' -or $permissionTarget -eq 'Unknown') {
        $recommendedAction = 'Fail'
    }
    elseif ($permissionTarget -eq 'ExchangeOnline' -and -not $exoEnabled) {
        if ($recipientTypeDetails -eq 'RemoteSharedMailbox') {
            $recommendedAction = 'Fail'
            $message = "Exchange Online is required for '$Identity', but ExchangeOnline.Enabled is false."
        }
        else {
            $recommendedAction = 'Execute'
        }
    }

    [pscustomobject]@{
        Identity                   = $Identity
        SearchMode                 = $Mode
        AdObjectFound              = $true
        DistinguishedName          = [string](Get-AdPropertyValue -AdObject $AdObject -Name 'distinguishedName')
        SamAccountName             = [string](Get-AdPropertyValue -AdObject $AdObject -Name 'sAMAccountName')
        UserPrincipalName          = [string](Get-AdPropertyValue -AdObject $AdObject -Name 'userPrincipalName')
        PrimarySmtpAddress         = [string](Get-AdPropertyValue -AdObject $AdObject -Name 'mail')
        TargetAddress              = [string](Get-AdPropertyValue -AdObject $AdObject -Name 'targetAddress')
        ProxyAddresses             = @(Get-AdPropertyValue -AdObject $AdObject -Name 'proxyAddresses')
        ObjectGuid                 = Get-AdPropertyValue -AdObject $AdObject -Name 'objectGUID'
        RecipientTypeDetailsRaw    = $onPremInfo.RecipientTypeDetailsRaw
        RemoteRecipientTypeRaw     = $remoteInfo.RemoteRecipientTypeRaw
        MailboxGuid                = $onPremInfo.MailboxGuid
        HomeMdb                    = $onPremInfo.HomeMdb
        HasHomeMdb                 = $onPremInfo.HasHomeMdb
        HasMailboxGuid             = $onPremInfo.HasMailboxGuid
        HasRemoteRecipientType     = $remoteInfo.HasRemoteRecipientType
        IsRemoteMailbox            = $remoteInfo.IsRemoteMailbox
        IsOnPremMailbox            = $onPremInfo.IsOnPremMailbox
        IsCloudRouted              = $remoteInfo.IsCloudRouted
        MailboxLocation            = $mailboxLocation
        PermissionExecutionTarget  = $permissionTarget
        RecipientAttributeAuthority = $recipientAuthority
        AccountAuthority           = 'ActiveDirectory'
        Confidence                 = $confidence
        RequiresRemoteValidation   = $requiresRemoteValidation
        IsAmbiguous                = $isAmbiguous
        ErrorCode                  = $errorCode
        Message                    = $message
        RetrievedAt                = Get-Date

        ExistsOnPrem               = $true
        ExistsInExchangeOnline     = $false
        RecipientTypeDetails       = $recipientTypeDetails
        IdentityAuthority          = 'OnPremAD'
        AttributeAuthority         = 'OnPremAD'
        RecipientAuthority         = if ($recipientAuthority -eq 'ExchangeOnPrem') { 'OnPremExchange' } elseif ($recipientAuthority -eq 'ExchangeOnline') { 'ExchangeOnline' } elseif ($recipientAuthority -eq 'ActiveDirectory') { 'OnPremAD' } else { 'Unknown' }
        MailboxAuthority           = if ($permissionAuthority -eq 'OnPremExchange') { 'OnPremExchange' } elseif ($permissionAuthority -eq 'ExchangeOnline') { 'ExchangeOnline' } else { 'Unknown' }
        ManagementAuthority        = $permissionAuthority
        PermissionAuthority        = $permissionAuthority
        FeatureAuthority           = $featureAuthority
        IsSynchronized             = $remoteInfo.IsRemoteMailbox
        IsCloudOnly                = $false
        IsMigrationTransient       = $false
        RecommendedAction          = $recommendedAction
        RetryAfterMinutes          = 15
        Reason                     = $message
    }
}

function New-MailboxExecutionContextNotFound {
    param([string]$Identity, [string]$Mode, [bool]$AllowRemoteValidation)

    [pscustomobject]@{
        Identity                    = $Identity
        SearchMode                  = $Mode
        AdObjectFound               = $false
        DistinguishedName           = ''
        SamAccountName              = ''
        UserPrincipalName           = ''
        PrimarySmtpAddress          = ''
        TargetAddress               = ''
        ProxyAddresses              = @()
        ObjectGuid                  = $null
        RecipientTypeDetailsRaw     = $null
        RemoteRecipientTypeRaw      = $null
        MailboxGuid                 = $null
        HomeMdb                     = $null
        HasHomeMdb                  = $false
        HasMailboxGuid              = $false
        HasRemoteRecipientType      = $false
        IsRemoteMailbox             = $false
        IsOnPremMailbox             = $false
        IsCloudRouted               = $false
        MailboxLocation             = 'Unknown'
        PermissionExecutionTarget   = 'Unknown'
        RecipientAttributeAuthority = 'Unknown'
        AccountAuthority            = 'Unknown'
        Confidence                  = 'Low'
        RequiresRemoteValidation    = $AllowRemoteValidation
        IsAmbiguous                 = $false
        ErrorCode                   = 'NotFound'
        Message                     = "Identity '$Identity' not found in AD."
        RetrievedAt                 = Get-Date

        ExistsOnPrem                = $false
        ExistsInExchangeOnline      = $false
        RecipientTypeDetails        = ''
        IdentityAuthority           = 'Unknown'
        AttributeAuthority          = 'Unknown'
        RecipientAuthority          = 'Unknown'
        MailboxAuthority            = 'Unknown'
        ManagementAuthority         = 'Unknown'
        PermissionAuthority         = 'Unknown'
        FeatureAuthority            = 'Unknown'
        IsSynchronized              = $false
        IsCloudOnly                 = $false
        IsMigrationTransient        = $false
        RecommendedAction           = 'Fail'
        RetryAfterMinutes           = 15
        Reason                      = "Identity '$Identity' not found in AD."
    }
}

function Invoke-RemoteValidation {
    param(
        [Parameter(Mandatory = $true)][pscustomobject]$Context,
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][hashtable]$Config
    )

    $exoEnabled = (
        $Config.ContainsKey('ExchangeOnline') -and
        $Config['ExchangeOnline'] -is [hashtable] -and
        $Config['ExchangeOnline'].ContainsKey('Enabled') -and
        [bool]$Config['ExchangeOnline']['Enabled']
    )

    try {
        $onPremRecipient = Get-OnPremRecipientSafe -Identity $Identity
    }
    catch {
        $onPremRecipient = $null
    }

    if ($onPremRecipient) {
        $recipientType = [string]$onPremRecipient.RecipientTypeDetails
        $Context.ExistsOnPrem = $true
        $Context.RecipientTypeDetails = $recipientType
        $Context.IdentityAuthority = 'OnPremAD'
        $Context.AttributeAuthority = 'OnPremAD'

        if ($recipientType -in @('UserMailbox','SharedMailbox')) {
            $Context.MailboxLocation = 'OnPrem'
            $Context.PermissionExecutionTarget = 'ExchangeOnPrem'
            $Context.RecipientAttributeAuthority = 'ExchangeOnPrem'
            $Context.PermissionAuthority = 'OnPremExchange'
            $Context.ManagementAuthority = 'OnPremExchange'
            $Context.FeatureAuthority = 'OnPremExchange'
            $Context.MailboxAuthority = 'OnPremExchange'
            $Context.IsOnPremMailbox = $true
            $Context.IsRemoteMailbox = $false
            $Context.IsCloudOnly = $false
            $Context.IsSynchronized = $false
            $Context.RecommendedAction = 'Execute'
            $Context.RequiresRemoteValidation = $false
            $Context.ErrorCode = 'None'
            $Context.Message = "On-prem mailbox confirmed for '$Identity'."
            $Context.Reason = $Context.Message
            return $Context
        }

        if ($recipientType -in @('RemoteUserMailbox','RemoteSharedMailbox')) {
            $Context.MailboxLocation = 'ExchangeOnline'
            $Context.PermissionExecutionTarget = 'ExchangeOnline'
            $Context.RecipientAttributeAuthority = 'ExchangeOnPrem'
            $Context.PermissionAuthority = 'ExchangeOnline'
            $Context.ManagementAuthority = 'ExchangeOnline'
            $Context.FeatureAuthority = 'OnPremExchange'
            $Context.MailboxAuthority = 'ExchangeOnline'
            $Context.IsOnPremMailbox = $false
            $Context.IsRemoteMailbox = $true
            $Context.IsSynchronized = $true
            $Context.RecipientAuthority = 'OnPremExchange'

            if (-not $exoEnabled -and $recipientType -eq 'RemoteSharedMailbox') {
                $Context.RecommendedAction = 'Fail'
                $Context.Message = "Remote mailbox found for '$Identity' but Exchange Online is disabled by configuration."
                $Context.Reason = $Context.Message
                return $Context
            }

            $exoRecipient = $null
            try {
                $exoRecipient = Get-ExoRecipientSafe -Identity $Identity -Config $Config
            }
            catch {
                $exoRecipient = $null
            }

            if ($exoRecipient) {
                $Context.ExistsInExchangeOnline = $true
                $Context.RecommendedAction = 'Execute'
                $Context.IsMigrationTransient = $false
                $Context.Message = "Remote mailbox confirmed in Exchange Online for '$Identity'."
                $Context.Reason = $Context.Message
            }
            else {
                $Context.ExistsInExchangeOnline = $false
                $Context.RecommendedAction = 'Retry'
                $Context.IsMigrationTransient = $true
                $Context.Message = "Remote mailbox found on-prem for '$Identity' but Exchange Online mailbox not yet visible."
                $Context.Reason = $Context.Message
            }

            $Context.RequiresRemoteValidation = $false
            return $Context
        }
    }

    if ($exoEnabled) {
        $exoRecipient = $null
        try {
            $exoRecipient = Get-ExoRecipientSafe -Identity $Identity -Config $Config
        }
        catch {
            $exoRecipient = $null
        }

        if ($exoRecipient) {
            $Context.ExistsInExchangeOnline = $true
            $Context.RecipientTypeDetails = [string]$exoRecipient.RecipientTypeDetails
            $Context.MailboxLocation = 'ExchangeOnline'
            $Context.PermissionExecutionTarget = 'ExchangeOnline'
            $Context.RecipientAttributeAuthority = 'ExchangeOnline'
            $Context.PermissionAuthority = 'ExchangeOnline'
            $Context.ManagementAuthority = 'ExchangeOnline'
            $Context.FeatureAuthority = 'ExchangeOnline'
            $Context.MailboxAuthority = 'ExchangeOnline'
            $Context.IdentityAuthority = 'ExchangeOnline'
            $Context.AttributeAuthority = 'ExchangeOnline'
            $Context.RecipientAuthority = 'ExchangeOnline'
            $Context.IsCloudOnly = $true
            $Context.RecommendedAction = 'Execute'
            $Context.ErrorCode = 'None'
            $Context.Message = "EXO-only mailbox found for '$Identity'."
            $Context.Reason = $Context.Message
            $Context.RequiresRemoteValidation = $false
            return $Context
        }
    }

    $Context.Message = "Identity '$Identity' not found on-prem or in Exchange Online."
    $Context.Reason = $Context.Message
    $Context
}

function Resolve-MailboxExecutionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][hashtable]$Config,
        [ValidateSet('FastAdOnly','ValidateRemote')][string]$Mode = 'FastAdOnly',
        [bool]$AllowRemoteValidation = $false
    )

    $trimmed = $Identity.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        $ctx = New-MailboxExecutionContextNotFound -Identity $Identity -Mode $Mode -AllowRemoteValidation $AllowRemoteValidation
        $ctx.ErrorCode = 'InvalidIdentity'
        $ctx.Message = 'Identity must not be empty.'
        $ctx.Reason = $ctx.Message
        return $ctx
    }

    $adResults = @()
    try {
        $adResults = @(Get-MailboxExecutionAdObject -Identity $trimmed)
    }
    catch {
        $ctx = New-MailboxExecutionContextNotFound -Identity $trimmed -Mode $Mode -AllowRemoteValidation $AllowRemoteValidation
        $ctx.ErrorCode = 'MissingRequiredAttributes'
        $ctx.Message = "AD lookup failed: $($_.Exception.Message)"
        $ctx.Reason = $ctx.Message
        return $ctx
    }

    if (-not $adResults -or $adResults.Count -eq 0) {
        $ctx = New-MailboxExecutionContextNotFound -Identity $trimmed -Mode $Mode -AllowRemoteValidation $AllowRemoteValidation
        if (($Mode -eq 'ValidateRemote') -or $AllowRemoteValidation) {
            return Invoke-RemoteValidation -Context $ctx -Identity $trimmed -Config $Config
        }
        return $ctx
    }

    if ($adResults.Count -gt 1) {
        $ctx = New-MailboxExecutionContextNotFound -Identity $trimmed -Mode $Mode -AllowRemoteValidation $AllowRemoteValidation
        $ctx.AdObjectFound = $true
        $ctx.MailboxLocation = 'Ambiguous'
        $ctx.IsAmbiguous = $true
        $ctx.RequiresRemoteValidation = $true
        $ctx.ErrorCode = 'AmbiguousHybridState'
        $ctx.Message = 'Multiple AD objects matched the identity.'
        $ctx.Reason = $ctx.Message
        if (($Mode -eq 'ValidateRemote') -or $AllowRemoteValidation) {
            return Invoke-RemoteValidation -Context $ctx -Identity $trimmed -Config $Config
        }
        return $ctx
    }

    $ctx = New-MailboxExecutionContextFromAdObject -Identity $trimmed -AdObject $adResults[0] -Config $Config -Mode $Mode
    if ($ctx.RequiresRemoteValidation -and (($Mode -eq 'ValidateRemote') -or $AllowRemoteValidation)) {
        return Invoke-RemoteValidation -Context $ctx -Identity $trimmed -Config $Config
    }

    $ctx
}

Export-ModuleMember -Function @('Resolve-MailboxExecutionContext')
