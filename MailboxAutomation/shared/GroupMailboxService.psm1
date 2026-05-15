Set-StrictMode -Version Latest

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

    Write-LogInfo -Logger $Context.Logger -Message "Migrated legacy logic: mutating FullAccess/SendAs members for group mailbox '$adObjectName'."

    if ($Context.WhatIfMode) {
        $simulatedOperations = @()
        foreach ($token in $tokens) {
            $parsed = ConvertFrom-LegacyActionToken -Token $token
            if ($null -ne $parsed) {
                $simulatedOperations += [pscustomobject]@{
                    Trustee      = $parsed.Value
                    Action       = $parsed.Action
                    FullAccess   = $true
                    SendAs       = $enableSendAs
                    Simulated    = $true
                }
            }
        }

        return [pscustomobject]@{
            Success       = $true
            Changed       = ($simulatedOperations.Count -gt 0)
            Simulated     = $true
            AdObjectName  = $adObjectName
            Operations    = $simulatedOperations
            Message       = "WhatIf: would mutate $($simulatedOperations.Count) FullAccess/SendAs member operation(s) on group mailbox '$adObjectName'."
            ErrorCode     = $null
        }
    }

    $mailbox = $null
    try {
        $mailbox = Get-OnPremMailboxSafe -Identity $adObjectName
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error getting group mailbox '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Message      = "Group mailbox '$adObjectName' could not be found or read. $message"
            ErrorCode    = 'GROUP_MAILBOX_GET_FAILED'
        }
    }

    if (-not $mailbox) {
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Message      = "Group mailbox '$adObjectName' not found."
            ErrorCode    = 'GROUP_MAILBOX_NOT_FOUND'
        }
    }

    $mailboxIdentity = if ($mailbox.PSObject.Properties['DistinguishedName'] -and -not [string]::IsNullOrWhiteSpace([string]$mailbox.DistinguishedName)) {
        [string]$mailbox.DistinguishedName
    }
    else {
        $adObjectName
    }

    $operations = @()
    try {
        foreach ($token in $tokens) {
            $parsed = ConvertFrom-LegacyActionToken -Token $token
            if ($null -eq $parsed) { continue }
            $ops = Invoke-LegacyMailboxPermissionMutation -MailboxIdentity $mailboxIdentity -Trustee $parsed.Value -Action $parsed.Action -EnableSendAs:$enableSendAs -WhatIfMode:$false -Logger $Context.Logger
            $operations += $ops
        }
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error mutating FullAccess/SendAs members for group mailbox '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Message      = "Error while mutating permissions on group mailbox '$adObjectName'. $message"
            ErrorCode    = 'GROUP_MAILBOX_PERMISSION_MUTATION_FAILED'
        }
    }

    return [pscustomobject]@{
        Success      = $true
        Changed      = ($operations.Count -gt 0)
        Simulated    = $false
        AdObjectName = $adObjectName
        Operations   = $operations
        Message      = "FullAccess/SendAs permissions processed for group mailbox '$adObjectName'."
        ErrorCode    = $null
    }
}

function Set-GroupMailboxManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $adObjectName = [string]$Data.AdObjectName
    $manager = [string]$Data.ManagerAdObjectName

    Write-LogInfo -Logger $Context.Logger -Message "Migrated legacy logic: changing manager on group mailbox '$adObjectName' to '$manager'."

    if ($Context.WhatIfMode) {
        return [pscustomobject]@{
            Success      = $true
            Changed      = $true
            Simulated    = $true
            AdObjectName = $adObjectName
            Manager      = $manager
            Operations   = @('Add FullAccess', 'Add SendAs', 'Set AD user manager')
            Message      = "WhatIf: would add manager permissions and set AD manager for group mailbox '$adObjectName'."
            ErrorCode    = $null
        }
    }

    $mailbox = $null
    try {
        $mailbox = Get-OnPremMailboxSafe -Identity $adObjectName
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error getting group mailbox '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Manager      = $manager
            Message      = "Group mailbox '$adObjectName' could not be found or read. $message"
            ErrorCode    = 'GROUP_MAILBOX_GET_FAILED'
        }
    }

    if (-not $mailbox) {
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Manager      = $manager
            Message      = "Group mailbox '$adObjectName' not found."
            ErrorCode    = 'GROUP_MAILBOX_NOT_FOUND'
        }
    }

    $mailboxIdentity = if ($mailbox.PSObject.Properties['DistinguishedName'] -and -not [string]::IsNullOrWhiteSpace([string]$mailbox.DistinguishedName)) {
        [string]$mailbox.DistinguishedName
    }
    else {
        $adObjectName
    }

    try {
        Invoke-LegacyMailboxPermissionMutation -MailboxIdentity $mailboxIdentity -Trustee $manager -Action 'ADD' -EnableSendAs:$true -WhatIfMode:$false -Logger $Context.Logger | Out-Null
        Set-AdUserSafe -Parameters @{ Identity = $adObjectName; Manager = $manager } -WhatIfMode:$false | Out-Null
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error changing manager on group mailbox '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Manager      = $manager
            Message      = "Error while changing group mailbox manager on '$adObjectName'. $message"
            ErrorCode    = 'GROUP_MAILBOX_MANAGER_CHANGE_FAILED'
        }
    }

    return [pscustomobject]@{
        Success      = $true
        Changed      = $true
        Simulated    = $false
        AdObjectName = $adObjectName
        Manager      = $manager
        Message      = "Manager changed for group mailbox '$adObjectName'."
        ErrorCode    = $null
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

        if ($Context.Config -and $Context.Config.ContainsKey('ExchangeOnPrem')) {
            $exchangeConfig = $Context.Config.ExchangeOnPrem
            if ($exchangeConfig -and $exchangeConfig.ContainsKey('DefaultMailboxDatabases')) {
                $dbs = @($exchangeConfig.DefaultMailboxDatabases)
                if ($dbs.Count -gt 0) {
                    $newMailboxParams['Database'] = Get-Random -InputObject $dbs
                }
            }
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
