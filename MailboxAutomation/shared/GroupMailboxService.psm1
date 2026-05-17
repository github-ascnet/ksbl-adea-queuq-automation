Set-StrictMode -Version Latest



function Get-GroupMailboxConfigValueSafe {
    [CmdletBinding()]
    param(
        [object]$Config,
        [string[]]$Path,
        [object]$DefaultValue = $null
    )

    $current = $Config
    foreach ($segment in $Path) {
        if ($null -eq $current) { return $DefaultValue }
        if ($current -is [hashtable]) {
            if (-not $current.ContainsKey($segment)) { return $DefaultValue }
            $current = $current[$segment]
            continue
        }
        if ($current.PSObject.Properties[$segment]) {
            $current = $current.$segment
            continue
        }
        return $DefaultValue
    }

    if ($null -eq $current) { return $DefaultValue }
    return $current
}

function Get-GroupMailboxExchangeAdministrativeGroupDnFromConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $dn = [string](Get-GroupMailboxConfigValueSafe -Config $Context.Config -Path @('ExchangeOnPrem','ExchangeAdministrativeGroupDn') -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($dn)) { return $dn }

    $template = [string](Get-GroupMailboxConfigValueSafe -Config $Context.Config -Path @('ExchangeOnPrem','ExchangeAdministrativeGroupDnTemplate') -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($template)) { return '' }

    if ($template.Contains('{ConfigurationNamingContext}')) {
        try {
            $rootDse = [ADSI]'LDAP://rootdse'
            $configurationNamingContext = [string]$rootDse.ConfigurationNamingContext
            return $template.Replace('{ConfigurationNamingContext}', $configurationNamingContext)
        }
        catch {
            return $template
        }
    }

    return $template
}

function Get-GroupMailboxDatabaseCandidates {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $configured = @(Get-GroupMailboxConfigValueSafe -Config $Context.Config -Path @('ExchangeOnPrem','DefaultMailboxDatabases') -DefaultValue @())
    if ($configured.Count -gt 0) { return $configured }

    if ($Context.WhatIfMode) { return @() }

    $filter = [string](Get-GroupMailboxConfigValueSafe -Config $Context.Config -Path @('ExchangeOnPrem','MailboxDatabaseLdapFilter') -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($filter)) { return @() }

    $adminGroupDn = Get-GroupMailboxExchangeAdministrativeGroupDnFromConfig -Context $Context
    if ([string]::IsNullOrWhiteSpace($adminGroupDn)) { return @() }

    try {
        $searchRoot = [ADSI]("LDAP://CN=Databases,$adminGroupDn")
        $searcher = New-Object System.DirectoryServices.DirectorySearcher($searchRoot, $filter, @('name'))
        return @($searcher.FindAll() | ForEach-Object { $_.Path.Split(',')[0].Split('=')[1] })
    }
    catch {
        Write-LogWarn -Logger $Context.Logger -Message "Mailbox database discovery failed. $($_.Exception.Message)"
        return @()
    }
}

function ConvertFrom-LegacyActionToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Token
    )

    $trimmed = $Token.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    if ($trimmed -match '^(?<Value>.+)\[(?<Action>ADD|DEL)\]$') {
        return [pscustomobject]@{
            Value  = $Matches.Value.Trim()
            Action = $Matches.Action.ToUpperInvariant()
        }
    }

    throw "Invalid legacy action token '$Token'. Expected format '<value>[ADD]' or '<value>[DEL]'."
}

function ConvertTo-LegacyTrusteeName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Trustee)

    if ($Trustee -like '*\*') {
        return $Trustee
    }

    "$([Environment]::UserDomainName)\$Trustee"
}

function Invoke-LegacyMailboxPermissionMutation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MailboxIdentity,
        [Parameter(Mandatory = $true)][string]$Trustee,
        [Parameter(Mandatory = $true)][ValidateSet('ADD','DEL')][string]$Action,
        [bool]$EnableSendAs = $false,
        [bool]$WhatIfMode = $true,
        [object]$Logger
    )

    $qualifiedTrustee = ConvertTo-LegacyTrusteeName -Trustee $Trustee
    $operations = @()

    if ($Action -eq 'ADD') {
        $fullAccessParams = @{
            Identity        = $MailboxIdentity
            User            = $qualifiedTrustee
            AccessRights    = 'FullAccess'
            InheritanceType = 'All'
            Automapping     = $true
        }
        Add-OnPremMailboxPermissionSafe -Parameters $fullAccessParams -WhatIfMode:$WhatIfMode | Out-Null
        $operations += "FullAccess ADD $qualifiedTrustee"

        if ($EnableSendAs) {
            $sendAsParams = @{
                Identity       = $MailboxIdentity
                User           = $qualifiedTrustee
                ExtendedRights = 'Send As'
            }
            Add-OnPremAdPermissionSafe -Parameters $sendAsParams -WhatIfMode:$WhatIfMode | Out-Null
            $operations += "SendAs ADD $qualifiedTrustee"
        }
    }
    else {
        $fullAccessParams = @{
            Identity        = $MailboxIdentity
            User            = $qualifiedTrustee
            AccessRights    = 'FullAccess'
            InheritanceType = 'All'
            Confirm         = $false
        }
        Remove-OnPremMailboxPermissionSafe -Parameters $fullAccessParams -WhatIfMode:$WhatIfMode | Out-Null
        $operations += "FullAccess DEL $qualifiedTrustee"

        if ($EnableSendAs) {
            $sendAsParams = @{
                Identity       = $MailboxIdentity
                User           = $qualifiedTrustee
                ExtendedRights = 'Send As'
                Confirm        = $false
            }
            Remove-OnPremAdPermissionSafe -Parameters $sendAsParams -WhatIfMode:$WhatIfMode | Out-Null
            $operations += "SendAs DEL $qualifiedTrustee"
        }
    }

    $operations
}

function Add-GroupMailboxFmaMembers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $adObjectName = [string]$Data.AdObjectName
    $enableSendAs = ([string]$Data.EnableSendAs) -eq 'True'
    $tokens = @([string]$Data.FullAccessMembers -split '!' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    Write-LogInfo -Logger $Context.Logger -Message "Processing hybrid FullAccess/SendAs permissions for group mailbox '$adObjectName'."

    # WhatIf: simulate without calling any Exchange cmdlets or resolver
    if ($Context.WhatIfMode) {
        $simulatedOperations = @()
        foreach ($token in $tokens) {
            $parsed = ConvertFrom-LegacyActionToken -Token $token
            if ($null -ne $parsed) {
                $simulatedOperations += [pscustomobject]@{
                    Trustee    = $parsed.Value
                    Action     = $parsed.Action
                    FullAccess = $true
                    SendAs     = $enableSendAs
                    Simulated  = $true
                }
            }
        }
        return [pscustomobject]@{
            Success           = $true
            Changed           = ($simulatedOperations.Count -gt 0)
            Simulated         = $true
            RequiresRetry     = $false
            RetryAfterMinutes = 0
            AdObjectName      = $adObjectName
            FullAccessCount   = $simulatedOperations.Count
            SendAsCount       = if ($enableSendAs) { $simulatedOperations.Count } else { 0 }
            Authority         = 'WhatIf'
            Operations        = $simulatedOperations
            FailedMembers     = @()
            Message           = "WhatIf: would mutate $($simulatedOperations.Count) FullAccess/SendAs member operation(s) on group mailbox '$adObjectName'."
            ErrorCode         = $null
        }
    }

    # Production: route all permission operations through MailboxPermissionService (hybrid-aware)
    $fullAccessCount = 0
    $sendAsCount     = 0
    $failedMembers   = @()
    $authority       = 'Unknown'

    foreach ($token in $tokens) {
        $parsed = ConvertFrom-LegacyActionToken -Token $token
        if ($null -eq $parsed) { continue }

        $trustee = $parsed.Value
        $action  = $parsed.Action

        # FullAccess (ADD or DEL)
        if ($action -eq 'ADD') {
            $faResult = Add-MailboxFullAccess -Context $Context -MailboxIdentity $adObjectName -Trustee $trustee -AutoMapping $false
        }
        else {
            $faResult = Remove-MailboxFullAccess -Context $Context -MailboxIdentity $adObjectName -Trustee $trustee
        }

        if ($faResult.RequiresRetry) {
            Write-LogWarn -Logger $Context.Logger -Message "Transient migration state for '$adObjectName' / '$trustee'. Retry scheduled after $($faResult.RetryAfterMinutes) minutes."
            return [pscustomobject]@{
                Success           = $false
                Changed           = $false
                RequiresRetry     = $true
                RetryAfterMinutes = $faResult.RetryAfterMinutes
                AdObjectName      = $adObjectName
                FullAccessCount   = $fullAccessCount
                SendAsCount       = $sendAsCount
                Authority         = $faResult.Authority
                FailedMembers     = @($trustee)
                Message           = $faResult.Message
                ErrorCode         = $faResult.ErrorCode
            }
        }

        if (-not $faResult.Success) {
            $failedMembers += $trustee
            Write-LogWarn -Logger $Context.Logger -Message "FullAccess $action failed for '$trustee' on '$adObjectName': $($faResult.Message)"
            continue
        }

        $authority = $faResult.Authority
        $fullAccessCount++

        # SendAs (ADD only when enabled; DEL when enabled)
        if ($enableSendAs) {
            if ($action -eq 'ADD') {
                $saResult = Add-MailboxSendAs -Context $Context -MailboxIdentity $adObjectName -Trustee $trustee
            }
            else {
                $saResult = Remove-MailboxSendAs -Context $Context -MailboxIdentity $adObjectName -Trustee $trustee
            }

            if ($saResult.RequiresRetry) {
                Write-LogWarn -Logger $Context.Logger -Message "Transient migration state (SendAs) for '$adObjectName' / '$trustee'. Retry scheduled after $($saResult.RetryAfterMinutes) minutes."
                return [pscustomobject]@{
                    Success           = $false
                    Changed           = ($fullAccessCount -gt 0)
                    RequiresRetry     = $true
                    RetryAfterMinutes = $saResult.RetryAfterMinutes
                    AdObjectName      = $adObjectName
                    FullAccessCount   = $fullAccessCount
                    SendAsCount       = $sendAsCount
                    Authority         = $saResult.Authority
                    FailedMembers     = @($trustee)
                    Message           = $saResult.Message
                    ErrorCode         = $saResult.ErrorCode
                }
            }

            if (-not $saResult.Success) {
                $failedMembers += "$trustee[SendAs]"
                Write-LogWarn -Logger $Context.Logger -Message "SendAs $action failed for '$trustee' on '$adObjectName': $($saResult.Message)"
            }
            else {
                $sendAsCount++
            }
        }
    }

    if ($failedMembers.Count -gt 0) {
        return [pscustomobject]@{
            Success           = $false
            Changed           = ($fullAccessCount -gt 0 -or $sendAsCount -gt 0)
            RequiresRetry     = $false
            RetryAfterMinutes = 0
            AdObjectName      = $adObjectName
            FullAccessCount   = $fullAccessCount
            SendAsCount       = $sendAsCount
            Authority         = $authority
            FailedMembers     = $failedMembers
            Message           = "FullAccess/SendAs permissions processed for group mailbox '$adObjectName'. $($failedMembers.Count) operation(s) failed."
            ErrorCode         = 'GROUP_MAILBOX_PERMISSION_PARTIAL_FAILURE'
        }
    }

    return [pscustomobject]@{
        Success           = $true
        Changed           = ($fullAccessCount -gt 0 -or $sendAsCount -gt 0)
        RequiresRetry     = $false
        RetryAfterMinutes = 0
        AdObjectName      = $adObjectName
        FullAccessCount   = $fullAccessCount
        SendAsCount       = $sendAsCount
        Authority         = $authority
        FailedMembers     = @()
        Message           = "FullAccess/SendAs permissions processed for group mailbox '$adObjectName' via $authority."
        ErrorCode         = $null
    }
}

function Set-GroupMailboxManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $adObjectName = [string]$Data.AdObjectName
    $manager      = [string]$Data.ManagerAdObjectName

    Write-LogInfo -Logger $Context.Logger -Message "Processing GroupMailbox.ChangeManager for '$adObjectName' (new manager: '$manager')."

    # WhatIf: simulate without calling resolver, Exchange or AD cmdlets
    if ($Context.WhatIfMode) {
        return [pscustomobject]@{
            Success             = $true
            Changed             = $true
            Simulated           = $true
            RequiresRetry       = $false
            RetryAfterMinutes   = 0
            AdObjectName        = $adObjectName
            Manager             = $manager
            ManagerAdObjectName = $manager
            Authority           = 'WhatIf'
            Operations          = @('Add FullAccess (WhatIf)', 'Add SendAs (WhatIf)', 'Set AD manager (WhatIf)')
            Message             = "WhatIf: would add manager permissions and set AD manager for group mailbox '$adObjectName'."
            ErrorCode           = $null
        }
    }

    # Resolve mailbox location via HybridMailboxResolver
    $resolution = Resolve-MailboxExecutionContext -Identity $adObjectName -Config $Context.Config

    # Retry: mailbox is being migrated to EXO and not yet visible there
    if ($resolution.RecommendedAction -eq 'Retry') {
        Write-LogWarn -Logger $Context.Logger -Message "GroupMailbox.ChangeManager: transient migration state for '$adObjectName'. Reason: $($resolution.Reason)"
        return [pscustomobject]@{
            Success             = $false
            Changed             = $false
            RequiresRetry       = $true
            RetryAfterMinutes   = $resolution.RetryAfterMinutes
            AdObjectName        = $adObjectName
            Manager             = $manager
            ManagerAdObjectName = $manager
            Authority           = $resolution.ManagementAuthority
            Message             = $resolution.Reason
            ErrorCode           = 'MAILBOX_MIGRATION_TRANSIENT'
        }
    }

    # Fail: EXO required but disabled, or mailbox not found at all
    if ($resolution.RecommendedAction -eq 'Fail') {
        $errorCode = if ($resolution.ManagementAuthority -eq 'ExchangeOnline') {
            'EXO_REQUIRED_BUT_DISABLED'
        }
        else {
            'MAILBOX_NOT_FOUND'
        }
        Write-LogError -Logger $Context.Logger -Message "GroupMailbox.ChangeManager: cannot proceed for '$adObjectName'. Reason: $($resolution.Reason)"
        return [pscustomobject]@{
            Success             = $false
            Changed             = $false
            RequiresRetry       = $false
            RetryAfterMinutes   = 0
            AdObjectName        = $adObjectName
            Manager             = $manager
            ManagerAdObjectName = $manager
            Authority           = $resolution.ManagementAuthority
            Message             = $resolution.Reason
            ErrorCode           = $errorCode
        }
    }

    # Execute: route to the correct authority
    try {
        switch ($resolution.ManagementAuthority) {
            'OnPremExchange' {
                # On-Prem shared mailbox:
                #   1. Grant FullAccess + SendAs via Exchange On-Prem (mirrors legacy AddRemove-MailboxPermissions)
                #   2. Set the AD Manager attribute
                Invoke-LegacyMailboxPermissionMutation `
                    -MailboxIdentity $adObjectName `
                    -Trustee $manager `
                    -Action 'ADD' `
                    -EnableSendAs:$true `
                    -WhatIfMode:$Context.WhatIfMode `
                    -Logger $Context.Logger | Out-Null
                Set-AdUserSafe -Parameters @{ Identity = $adObjectName; Manager = $manager } -WhatIfMode:$Context.WhatIfMode | Out-Null
            }
            'ExchangeOnline' {
                # EXO-hosted mailbox:
                #   1. Grant FullAccess via Exchange Online gateway
                #   2. Grant SendAs via Exchange Online gateway
                #   3. If the on-prem proxy object still exists (RemoteSharedMailbox), set the AD Manager
                #      attribute so Entra Connect can sync it. Skip for pure EXO-only mailboxes.
                $faParams = @{
                    Identity        = $adObjectName
                    User            = $manager
                    AccessRights    = 'FullAccess'
                    InheritanceType = 'All'
                    AutoMapping     = $false
                }
                Add-ExoMailboxPermissionSafe -Parameters $faParams -Config $Context.Config -WhatIfMode:$Context.WhatIfMode | Out-Null

                $saParams = @{
                    Identity     = $adObjectName
                    Trustee      = $manager
                    AccessRights = 'SendAs'
                    Confirm      = $false
                }
                Add-ExoSendAsPermissionSafe -Parameters $saParams -Config $Context.Config -WhatIfMode:$Context.WhatIfMode | Out-Null

                if ($resolution.ExistsOnPrem) {
                    Set-AdUserSafe -Parameters @{ Identity = $adObjectName; Manager = $manager } -WhatIfMode:$Context.WhatIfMode | Out-Null
                }
            }
            default {
                return [pscustomobject]@{
                    Success             = $false
                    Changed             = $false
                    RequiresRetry       = $false
                    RetryAfterMinutes   = 0
                    AdObjectName        = $adObjectName
                    Manager             = $manager
                    ManagerAdObjectName = $manager
                    Authority           = $resolution.ManagementAuthority
                    Message             = "Cannot determine management authority for group mailbox '$adObjectName'. $($resolution.Reason)"
                    ErrorCode           = 'PERMISSION_AUTHORITY_UNKNOWN'
                }
            }
        }
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error changing manager on group mailbox '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success             = $false
            Changed             = $false
            RequiresRetry       = $false
            RetryAfterMinutes   = 0
            AdObjectName        = $adObjectName
            Manager             = $manager
            ManagerAdObjectName = $manager
            Authority           = $resolution.ManagementAuthority
            Message             = "Error while changing group mailbox manager on '$adObjectName'. $message"
            ErrorCode           = 'GROUP_MAILBOX_MANAGER_CHANGE_FAILED'
        }
    }

    return [pscustomobject]@{
        Success             = $true
        Changed             = $true
        Simulated           = $false
        RequiresRetry       = $false
        RetryAfterMinutes   = 0
        AdObjectName        = $adObjectName
        Manager             = $manager
        ManagerAdObjectName = $manager
        Authority           = $resolution.ManagementAuthority
        Message             = "Manager changed for group mailbox '$adObjectName' via $($resolution.ManagementAuthority)."
        ErrorCode           = $null
    }
}


function New-GroupMailbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $displayName = [string]$Data.DisplayName
    $firstName = [string]$Data.FirstName
    $lastName = [string]$Data.LastName
    $primarySmtpAddress = [string]$Data.PrimarySmtpAddress
    $newPrimaryEmailAddress = [string]$Data.NewPrimaryEMailAddress
    $requestedSam = [string]$Data.AdObjectName
    $orgUnit = [string]$Data.OrgUnit
    $hideInAb = ([string]$Data.HideInAb) -eq 'True'
    $manager = [string]$Data.Manager
    $fullAccessMembers = [string]$Data.FullAccessMembers
    $requestedBy = [string]$Data.CurrentUserName

    Write-LogInfo -Logger $Context.Logger -Message "Migrated legacy logic: creating group mailbox '$displayName' with primary SMTP '$primarySmtpAddress'."

    $samAccountName = $requestedSam
    if (-not [string]::IsNullOrWhiteSpace($requestedSam)) {
        try {
            $samAccountName = Get-NextAvailableAccountName -BaseName $requestedSam
        }
        catch {
            $samAccountName = $requestedSam
            Write-LogWarn -Logger $Context.Logger -Message "Could not enumerate next available group mailbox SamAccountName. Using CSV value '$requestedSam'."
        }
    }

    $secret = $null
    try {
        $secret = New-RandomPassword
    }
    catch {
        $secret = $null
    }

    if ([string]::IsNullOrWhiteSpace($secret)) {
        $secret = 'LFAVmB2jlq'
    }

    $operations = @()

    if ($Context.WhatIfMode) {
        $operations += [pscustomobject]@{
            Simulated = $true
            Action = 'Get-Mailbox'
            Identity = $primarySmtpAddress
        }
        $operations += [pscustomobject]@{
            Simulated = $true
            Action = 'New-Mailbox'
            SamAccountName = $samAccountName
            Shared = $true
            DisplayName = $displayName
            PrimarySmtpAddress = $primarySmtpAddress
            OrganizationalUnit = $orgUnit
        }
        if ($hideInAb) {
            $operations += [pscustomobject]@{ Simulated = $true; Action = 'Set-Mailbox'; Identity = $samAccountName; HiddenFromAddressListsEnabled = $true }
        }
        if (-not [string]::IsNullOrWhiteSpace($manager)) {
            $managerSam = $manager.Split('[]')[0]
            $operations += [pscustomobject]@{ Simulated = $true; Action = 'Add-MailboxPermission/Add-ADPermission'; Identity = $samAccountName; Trustee = $managerSam; SendAs = $true }
            $operations += [pscustomobject]@{ Simulated = $true; Action = 'Set-ADUser'; Identity = $samAccountName; Manager = $managerSam }
        }
        if (-not [string]::IsNullOrWhiteSpace($fullAccessMembers)) {
            foreach ($item in @($fullAccessMembers -split '!' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
                $trustee = $item.Split('[]')[0]
                $operations += [pscustomobject]@{ Simulated = $true; Action = 'Add-MailboxPermission/Add-ADPermission'; Identity = $samAccountName; Trustee = $trustee; SendAs = $true }
            }
        }
        if (-not [string]::IsNullOrWhiteSpace($newPrimaryEmailAddress)) {
            $operations += [pscustomobject]@{ Simulated = $true; Action = 'Set-Mailbox'; Identity = $samAccountName; PrimarySmtpAddress = $newPrimaryEmailAddress; EmailAddressPolicyEnabled = $false }
        }
        $operations += [pscustomobject]@{ Simulated = $true; Action = 'Add-ADGroupMember'; Identity = 'GG-EV-Users'; Member = $samAccountName }
        $operations += [pscustomobject]@{ Simulated = $true; Action = 'Set-TenantState'; Identity = $samAccountName; Mode = 'TenantEnable' }

        return [pscustomobject]@{
            Success = $true
            Changed = $true
            Simulated = $true
            AdObjectName = $samAccountName
            PrimarySmtpAddress = $primarySmtpAddress
            GeneratedPassword = $secret
            Operations = $operations
            Message = "WhatIf: would create group mailbox '$displayName' as '$samAccountName'."
            ErrorCode = $null
        }
    }

    try {
        $existingMailbox = $null
        try {
            $existingMailbox = Get-OnPremMailboxSafe -Identity $primarySmtpAddress
        }
        catch {
            $existingMailbox = $null
        }

        if ($existingMailbox) {
            return [pscustomobject]@{
                Success = $false
                Changed = $false
                AdObjectName = $samAccountName
                PrimarySmtpAddress = $primarySmtpAddress
                Message = "Mailbox with primary SMTP '$primarySmtpAddress' already exists."
                ErrorCode = 'GROUP_MAILBOX_ALREADY_EXISTS'
            }
        }

        $password = ConvertTo-SecureString $secret -AsPlainText -Force
        $newMailboxParams = @{
            SamAccountName = $samAccountName
            Shared = $true
            Firstname = $firstName
            LastName = $lastName
            DisplayName = $displayName
            UserPrincipalName = "$samAccountName@ksbl.local"
            Alias = $samAccountName
            Name = $samAccountName
            PrimarySmtpAddress = $primarySmtpAddress
            OrganizationalUnit = $orgUnit
            Password = $password
        }

        $dbs = @(Get-GroupMailboxDatabaseCandidates -Context $Context)
        if ($dbs.Count -gt 0) {
            $newMailboxParams['Database'] = Get-Random -InputObject $dbs
        }

        New-OnPremMailboxSafe -Parameters $newMailboxParams -WhatIfMode:$false | Out-Null

        $mailbox = Get-OnPremMailboxSafe -Identity $samAccountName

        Set-OnPremMailboxJunkEmailConfigurationSafe -Parameters @{ Identity = $samAccountName; Enabled = $false } -WhatIfMode:$false | Out-Null

        if ($hideInAb) {
            Set-OnPremMailboxSafe -Parameters @{ Identity = $samAccountName; HiddenFromAddressListsEnabled = $true } -WhatIfMode:$false | Out-Null
        }

        if (-not [string]::IsNullOrWhiteSpace($manager)) {
            $managerSam = $manager.Split('[]')[0]
            Invoke-LegacyMailboxPermissionMutation -MailboxIdentity $mailbox.DistinguishedName -Trustee $managerSam -Action 'ADD' -EnableSendAs:$true -WhatIfMode:$false -Logger $Context.Logger | Out-Null
            Set-AdUserSafe -Parameters @{ Identity = $samAccountName; Description = "Created on $(Get-Date) by $requestedBy - $secret"; Manager = $managerSam } -WhatIfMode:$false | Out-Null
        }
        else {
            Set-AdUserSafe -Parameters @{ Identity = $samAccountName; Description = "Created on $(Get-Date) by $requestedBy - $secret" } -WhatIfMode:$false | Out-Null
        }

        Set-AdUserSafe -Parameters @{ Identity = $samAccountName; Replace = @{ employeeType = 'G' } } -WhatIfMode:$false | Out-Null

        if (-not [string]::IsNullOrWhiteSpace($fullAccessMembers)) {
            foreach ($item in @($fullAccessMembers -split '!' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
                $trustee = $item.Split('[]')[0]
                Invoke-LegacyMailboxPermissionMutation -MailboxIdentity $mailbox.DistinguishedName -Trustee $trustee -Action 'ADD' -EnableSendAs:$true -WhatIfMode:$false -Logger $Context.Logger | Out-Null
            }
        }

        if (-not [string]::IsNullOrWhiteSpace($newPrimaryEmailAddress)) {
            Set-OnPremMailboxSafe -Parameters @{ Identity = $mailbox.Alias; PrimarySmtpAddress = $newPrimaryEmailAddress; EmailAddressPolicyEnabled = $false } -WhatIfMode:$false | Out-Null
        }

        Add-AdGroupMemberSafe -Identity 'GG-EV-Users' -Members @($samAccountName) -WhatIfMode:$false | Out-Null

        try {
            $user = Get-AdUserSafe -Identity $samAccountName -Properties @('*')
            $cloudDomain = $null
            if ($Context.Config -and $Context.Config.ContainsKey('ExchangeOnPrem') -and $Context.Config.ExchangeOnPrem.ContainsKey('CloudDomain')) {
                $cloudDomain = $Context.Config.ExchangeOnPrem.CloudDomain
            }
            # TODO: Adapt TenantState service signature to the legacy Set-TenantState -User/-Mode/-CloudDomain contract.
            Set-TenantState -TenantId $samAccountName -State 'TenantEnable' -WhatIfMode:$false | Out-Null
        }
        catch {
            Write-LogWarn -Logger $Context.Logger -Message "Tenant state could not be set for '$samAccountName'. TODO: verify Set-TenantState migration. $($_.Exception.Message)"
        }

        return [pscustomobject]@{
            Success = $true
            Changed = $true
            Simulated = $false
            AdObjectName = $samAccountName
            PrimarySmtpAddress = $primarySmtpAddress
            GeneratedPassword = $secret
            Message = "Group mailbox '$displayName' created as '$samAccountName'."
            ErrorCode = $null
        }
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error creating group mailbox '$displayName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success = $false
            Changed = $false
            AdObjectName = $samAccountName
            PrimarySmtpAddress = $primarySmtpAddress
            Message = "Error while creating group mailbox '$displayName'. $message"
            ErrorCode = 'GROUP_MAILBOX_CREATE_FAILED'
        }
    }
}


Export-ModuleMember -Function @('Add-GroupMailboxFmaMembers','Set-GroupMailboxManager','New-GroupMailbox')
