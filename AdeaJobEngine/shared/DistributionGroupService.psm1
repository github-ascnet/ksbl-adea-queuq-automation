Set-StrictMode -Version Latest

function ConvertFrom-LegacyDistributionActionToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Token)

    $trimmed = $Token.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return $null }

    if ($trimmed -match '^(?<Value>.+)\[(?<Action>ADD|DEL)\]$') {
        return [pscustomobject]@{
            Value  = $Matches.Value.Trim()
            Action = $Matches.Action.ToUpperInvariant()
        }
    }

    throw "Invalid legacy action token '$Token'. Expected format '<value>[ADD]' or '<value>[DEL]'."
}

function ConvertTo-LegacyDistributionTrusteeName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Trustee)

    if ($Trustee -like '*\*') { return $Trustee }
    "$([Environment]::UserDomainName)\$Trustee"
}

function Invoke-LegacyDistributionWriteMembersPermission {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DistributionGroupIdentity,
        [Parameter(Mandatory = $true)][string]$Trustee,
        [Parameter(Mandatory = $true)][ValidateSet('ADD', 'DEL')][string]$Action,
        [bool]$WhatIfMode = $true
    )

    $qualifiedTrustee = ConvertTo-LegacyDistributionTrusteeName -Trustee $Trustee
    if ($Action -eq 'ADD') {
        $params = @{
            Identity     = $DistributionGroupIdentity
            User         = $qualifiedTrustee
            AccessRights = 'WriteProperty'
            Properties   = 'Member'
        }
        Add-OnPremAdPermissionSafe -Parameters $params -WhatIfMode:$WhatIfMode | Out-Null
        return "WriteMembers ADD $qualifiedTrustee"
    }

    $removeParams = @{
        Identity     = $DistributionGroupIdentity
        User         = $qualifiedTrustee
        AccessRights = 'WriteProperty'
        Properties   = 'Member'
        Confirm      = $false
    }
    Remove-OnPremAdPermissionSafe -Parameters $removeParams -WhatIfMode:$WhatIfMode | Out-Null
    "WriteMembers DEL $qualifiedTrustee"
}

function Add-DistributionListResponsibles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $adObjectName = [string]$Data.AdObjectName
    $tokens = @([string]$Data.ManagedByMembers -split '!' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

    Write-LogInfo -Logger $Context.Logger -Message "Migrated legacy logic: mutating responsibles on distribution group '$adObjectName'."

    if ($Context.WhatIfMode) {
        $operations = @()
        foreach ($token in $tokens) {
            $parsed = ConvertFrom-LegacyDistributionActionToken -Token $token
            if ($null -ne $parsed) {
                $operations += [pscustomobject]@{
                    Responsible = $parsed.Value
                    Action      = $parsed.Action
                    ManagedBy   = $true
                    WriteMember = $true
                    Simulated   = $true
                }
            }
        }

        return [pscustomobject]@{
            Success      = $true
            Changed      = ($operations.Count -gt 0)
            Simulated    = $true
            AdObjectName = $adObjectName
            Operations   = $operations
            Message      = "WhatIf: would mutate $($operations.Count) responsible/member-write permission operation(s) on distribution group '$adObjectName'."
            ErrorCode    = $null
        }
    }

    $distributionGroup = $null
    try {
        $distributionGroup = Get-OnPremDistributionGroupSafe -Identity $adObjectName
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error getting distribution group '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Message      = "Distribution group '$adObjectName' could not be found or read. $message"
            ErrorCode    = 'DISTRIBUTION_GROUP_GET_FAILED'
        }
    }

    if (-not $distributionGroup) {
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Message      = "Distribution group '$adObjectName' not found."
            ErrorCode    = 'DISTRIBUTION_GROUP_NOT_FOUND'
        }
    }

    $groupIdentity = if ($distributionGroup.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$distributionGroup.Name)) {
        [string]$distributionGroup.Name
    }
    else {
        $adObjectName
    }

    $operations = @()
    try {
        foreach ($token in $tokens) {
            $parsed = ConvertFrom-LegacyDistributionActionToken -Token $token
            if ($null -eq $parsed) { continue }

            if ($parsed.Action -eq 'ADD') {
                Set-OnPremDistributionGroupSafe -Parameters @{ Identity = $adObjectName; ManagedBy = @{ Add = $parsed.Value }; BypassSecurityGroupManagerCheck = $true } -WhatIfMode:$false | Out-Null
                $operations += "ManagedBy ADD $($parsed.Value)"
            }
            else {
                Set-OnPremDistributionGroupSafe -Parameters @{ Identity = $adObjectName; ManagedBy = @{ Remove = $parsed.Value }; BypassSecurityGroupManagerCheck = $true } -WhatIfMode:$false | Out-Null
                $operations += "ManagedBy DEL $($parsed.Value)"
            }

            $operations += Invoke-LegacyDistributionWriteMembersPermission -DistributionGroupIdentity $groupIdentity -Trustee $parsed.Value -Action $parsed.Action -WhatIfMode:$false
        }
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error mutating responsibles on distribution group '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Message      = "Error while mutating responsibles on distribution group '$adObjectName'. $message"
            ErrorCode    = 'DISTRIBUTION_GROUP_RESPONSIBLE_MUTATION_FAILED'
        }
    }

    return [pscustomobject]@{
        Success      = $true
        Changed      = ($operations.Count -gt 0)
        Simulated    = $false
        AdObjectName = $adObjectName
        Operations   = $operations
        Message      = "Responsibles processed for distribution group '$adObjectName'."
        ErrorCode    = $null
    }
}

function Set-DistributionGroupManager {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $adObjectName = [string]$Data.AdObjectName
    $manager = [string]$Data.ManagerAdObjectName

    Write-LogInfo -Logger $Context.Logger -Message "Migrated legacy logic: changing manager on distribution group '$adObjectName' to '$manager'."

    if ($Context.WhatIfMode) {
        return [pscustomobject]@{
            Success      = $true
            Changed      = $true
            Simulated    = $true
            AdObjectName = $adObjectName
            Manager      = $manager
            Operations   = @('Set DistributionGroup ManagedBy', 'Set ADGroup ManagedBy', 'Add WriteMembers permission')
            Message      = "WhatIf: would set manager and write-members permission for distribution group '$adObjectName'."
            ErrorCode    = $null
        }
    }

    $distributionGroup = $null
    try {
        $distributionGroup = Get-OnPremDistributionGroupSafe -Identity $adObjectName
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error getting distribution group '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Manager      = $manager
            Message      = "Distribution group '$adObjectName' could not be found or read. $message"
            ErrorCode    = 'DISTRIBUTION_GROUP_GET_FAILED'
        }
    }

    if (-not $distributionGroup) {
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Manager      = $manager
            Message      = "Distribution group '$adObjectName' not found."
            ErrorCode    = 'DISTRIBUTION_GROUP_NOT_FOUND'
        }
    }

    $groupIdentity = if ($distributionGroup.PSObject.Properties['Name'] -and -not [string]::IsNullOrWhiteSpace([string]$distributionGroup.Name)) {
        [string]$distributionGroup.Name
    }
    else {
        $adObjectName
    }

    $ownerList = @()
    if ($distributionGroup.PSObject.Properties['ManagedBy'] -and $distributionGroup.ManagedBy) {
        foreach ($existingManager in @($distributionGroup.ManagedBy)) {
            if ($null -ne $existingManager -and -not [string]::IsNullOrWhiteSpace([string]$existingManager)) {
                $ownerList += [string]$existingManager
            }
        }
    }
    if ($ownerList -notcontains $manager) {
        $ownerList += $manager
    }

    try {
        Set-OnPremDistributionGroupSafe -Parameters @{ Identity = $groupIdentity; ManagedBy = $ownerList; BypassSecurityGroupManagerCheck = $true } -WhatIfMode:$false | Out-Null
        Set-AdGroupSafe -Parameters @{ Identity = $adObjectName; ManagedBy = $manager } -WhatIfMode:$false | Out-Null
        Invoke-LegacyDistributionWriteMembersPermission -DistributionGroupIdentity $groupIdentity -Trustee $manager -Action 'ADD' -WhatIfMode:$false | Out-Null
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error changing manager on distribution group '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Manager      = $manager
            Message      = "Error while changing manager on distribution group '$adObjectName'. $message"
            ErrorCode    = 'DISTRIBUTION_GROUP_MANAGER_CHANGE_FAILED'
        }
    }

    return [pscustomobject]@{
        Success      = $true
        Changed      = $true
        Simulated    = $false
        AdObjectName = $adObjectName
        Manager      = $manager
        Message      = "Manager changed for distribution group '$adObjectName'."
        ErrorCode    = $null
    }
}

function Update-DistributionGroupManagedByMembers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $groupIdentity = if ($Data.PSObject.Properties['GroupIdentity']) { [string]$Data.GroupIdentity } else { [string]$Data.AdObjectName }
    $ownerValue = if ($Data.PSObject.Properties['OwnerIdentity']) { $Data.OwnerIdentity } else { $Data.ManagedByMembers }

    if ([string]::IsNullOrWhiteSpace($groupIdentity)) {
        return [pscustomobject]@{
            Success       = $false
            Changed       = $false
            GroupIdentity = $groupIdentity
            Message       = 'GroupIdentity is required.'
            ErrorCode     = 'DISTRIBUTION_GROUP_OWNER_INVALID_INPUT'
        }
    }

    $tokens = @()
    if ($ownerValue -is [System.Collections.IEnumerable] -and -not ($ownerValue -is [string])) {
        $tokens = @($ownerValue)
    }
    else {
        $tokens = @([string]$ownerValue -split '!' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    if (-not $tokens -or $tokens.Count -eq 0) {
        return [pscustomobject]@{
            Success       = $false
            Changed       = $false
            GroupIdentity = $groupIdentity
            Message       = 'OwnerIdentity must contain at least one [ADD] or [DEL] token.'
            ErrorCode     = 'DISTRIBUTION_GROUP_OWNER_INVALID_INPUT'
        }
    }

    $operations = @()
    $errors = @()

    foreach ($token in $tokens) {
        try {
            $parsed = ConvertFrom-LegacyDistributionActionToken -Token $token
            if ($null -eq $parsed) { continue }

            if ($parsed.Action -eq 'ADD') {
                Set-OnPremDistributionGroupSafe -Parameters @{ Identity = $groupIdentity; ManagedBy = @{ Add = $parsed.Value }; BypassSecurityGroupManagerCheck = $true } -WhatIfMode:$Context.WhatIfMode | Out-Null
                $operations += "ManagedBy ADD $($parsed.Value)"
                Write-LogInfo -Logger $Context.Logger -Message "DistributionGroup.ManagedBy ADD '$($parsed.Value)' on '$groupIdentity'."
            }
            else {
                Set-OnPremDistributionGroupSafe -Parameters @{ Identity = $groupIdentity; ManagedBy = @{ Remove = $parsed.Value }; BypassSecurityGroupManagerCheck = $true } -WhatIfMode:$Context.WhatIfMode | Out-Null
                $operations += "ManagedBy DEL $($parsed.Value)"
                Write-LogInfo -Logger $Context.Logger -Message "DistributionGroup.ManagedBy DEL '$($parsed.Value)' on '$groupIdentity'."
            }
        }
        catch {
            $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
            $errors += $message
            Write-LogError -Logger $Context.Logger -Message "Failed to update ManagedBy on '$groupIdentity' for token '$token'. $message" -Exception $_.Exception
        }
    }

    if ($errors.Count -gt 0) {
        return [pscustomobject]@{
            Success       = $false
            Changed       = ($operations.Count -gt 0)
            GroupIdentity = $groupIdentity
            Operations    = $operations
            Message       = "ManagedBy updates failed for $($errors.Count) token(s)."
            ErrorCode     = 'DISTRIBUTION_GROUP_OWNER_CHANGE_FAILED'
            Errors        = $errors
        }
    }

    return [pscustomobject]@{
        Success       = $true
        Changed       = ($operations.Count -gt 0)
        Simulated     = $Context.WhatIfMode
        GroupIdentity = $groupIdentity
        Operations    = $operations
        Message       = "ManagedBy updates completed for '$groupIdentity'."
        ErrorCode     = $null
    }
}

function New-DistributionGroupFromRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $displayName = [string]$Data.DisplayName
    $primarySmtp = [string]$Data.PrimarySmtpAddress
    $adObjectName = [string]$Data.AdObjectName
    $orgUnit = [string]$Data.OrgUnit
    $hideInAb = [string]$Data.HideInAb
    # Manager field may carry a legacy action token (e.g. "johndoe[ADD]") — strip the bracket suffix to get the pure SAM account name.
    $manager = ([string]$Data.Manager -replace '\[.*\]', '').Trim()
    $createdBy = [string]$Data.CurrentUserName

    Write-LogInfo -Logger $Context.Logger -Message "Migrated legacy logic: creating distribution group '$displayName' with SMTP '$primarySmtp' as '$adObjectName'."

    if ($Context.WhatIfMode) {
        $operations = @(
            [pscustomobject]@{ Action = 'New-DistributionGroup'; Identity = $adObjectName; DisplayName = $displayName; PrimarySmtpAddress = $primarySmtp; OrganizationalUnit = $orgUnit; Type = 'Security'; Simulated = $true }
            [pscustomobject]@{ Action = 'Set-DistributionGroup-HideInAb'; Identity = $adObjectName; HideInAb = $hideInAb; Simulated = $true }
            [pscustomobject]@{ Action = 'Set-DistributionGroup-ManagedBy'; Identity = $adObjectName; Manager = $manager; Simulated = $true }
            [pscustomobject]@{ Action = 'Add-WriteMembers-Permission'; Identity = $adObjectName; Manager = $manager; Simulated = $true }
            [pscustomobject]@{ Action = 'Set-ADGroup-Description'; Identity = $adObjectName; Simulated = $true }
            [pscustomobject]@{ Action = 'Set-DistributionGroup-RequireSenderAuth'; Identity = $adObjectName; Simulated = $true }
            # TODO: AcceptMessagesOnlyFromSendersOrMembers – adds hardcoded 'vl0286' in legacy script; must be made configurable.
            # Ref: current-scripts/Process-DistributionsGroupJobs.ps1 — CreateDistributionList block.
            # TODO: Set-DlTenantState -Mode TenantEnable. Use shared/TenantState.psm1 once Set-TenantState is fully implemented.
            # Ref: current-scripts/Process-DistributionsGroupJobs.ps1 — Set-DlTenantState function.
        )
        return [pscustomobject]@{
            Success      = $true
            Changed      = $true
            Simulated    = $true
            AdObjectName = $adObjectName
            DisplayName  = $displayName
            Operations   = $operations
            Message      = "WhatIf: would create distribution group '$displayName' as '$adObjectName'."
            ErrorCode    = $null
        }
    }

    # Step 1: Create distribution group via Exchange On-Prem
    $distList = $null
    try {
        $createParams = @{
            Name               = $displayName
            PrimarySmtpAddress = $primarySmtp
            Alias              = $adObjectName
            SamAccountName     = $adObjectName
            DisplayName        = $displayName
            OrganizationalUnit = $orgUnit
            Type               = 'Security'
        }
        $distList = New-OnPremDistributionGroupSafe -Parameters $createParams -WhatIfMode:$false
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Failed to create distribution group '$displayName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            DisplayName  = $displayName
            Message      = "Failed to create distribution group '$displayName' with SMTP '$primarySmtp'. $message"
            ErrorCode    = 'DISTRIBUTION_GROUP_CREATE_FAILED'
        }
    }

    if (-not $distList) {
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            DisplayName  = $displayName
            Message      = "Distribution group '$displayName' was not found after creation."
            ErrorCode    = 'DISTRIBUTION_GROUP_CREATE_NOT_FOUND'
        }
    }

    # Step 2: Set HiddenFromAddressListsEnabled.
    # Faithful migration: in the legacy script HideInAb='true' sets HiddenFromAddressListsEnabled=$false (group is visible in AB).
    # The semantics appear: HideInAb=true → "user chose to show in AB" → hidden=false.
    try {
        $hiddenValue = $hideInAb -ine 'true'
        Set-OnPremDistributionGroupSafe -Parameters @{ Identity = $adObjectName; HiddenFromAddressListsEnabled = $hiddenValue } -WhatIfMode:$false | Out-Null
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogWarn -Logger $Context.Logger -Message "Warning: failed to set HiddenFromAddressListsEnabled on '$adObjectName'. $message"
    }

    # Step 3: Set ManagedBy and grant WriteMembers (Member property) permission to manager
    if (-not [string]::IsNullOrWhiteSpace($manager)) {
        try {
            Set-OnPremDistributionGroupSafe -Parameters @{ Identity = $adObjectName; ManagedBy = $manager; BypassSecurityGroupManagerCheck = $true } -WhatIfMode:$false | Out-Null
            Invoke-LegacyDistributionWriteMembersPermission -DistributionGroupIdentity $adObjectName -Trustee $manager -Action 'ADD' -WhatIfMode:$false | Out-Null
        }
        catch {
            $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
            Write-LogWarn -Logger $Context.Logger -Message "Warning: failed to set ManagedBy or WriteMembers on '$adObjectName'. $message"
        }
    }

    # Step 4: Set description on the AD group object
    try {
        $description = "Created on $((Get-Date).ToString('yyyy-MM-dd HH:mm')) by $createdBy"
        Set-AdGroupSafe -Parameters @{ Identity = $adObjectName; Description = $description } -WhatIfMode:$false | Out-Null
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogWarn -Logger $Context.Logger -Message "Warning: failed to set Description on '$adObjectName'. $message"
    }

    # Step 5: Allow external senders (disable required sender authentication)
    try {
        Set-OnPremDistributionGroupSafe -Parameters @{ Identity = $adObjectName; RequireSenderAuthenticationEnabled = $false } -WhatIfMode:$false | Out-Null
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogWarn -Logger $Context.Logger -Message "Warning: failed to set RequireSenderAuthenticationEnabled on '$adObjectName'. $message"
    }

    # TODO: Add distribution group to AcceptMessagesOnlyFromSendersOrMembers of a relay/gateway list.
    # Legacy script adds hardcoded 'vl0286'; this must be made configurable before implementing.
    # Ref: current-scripts/Process-DistributionsGroupJobs.ps1 — CreateDistributionList block.

    # TODO: Migrate Set-DlTenantState -Mode TenantEnable -CloudDomain logic.
    # Use shared/TenantState.psm1 (Set-TenantState) once it is fully implemented.
    # Ref: current-scripts/Process-DistributionsGroupJobs.ps1 — Set-DlTenantState function.

    return [pscustomobject]@{
        Success      = $true
        Changed      = $true
        Simulated    = $false
        AdObjectName = $adObjectName
        DisplayName  = $displayName
        Message      = "Distribution group '$displayName' created with SMTP '$primarySmtp' as '$adObjectName'."
        ErrorCode    = $null
    }
}

function Remove-DistributionGroupFromRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $adObjectName = [string]$Data.AdObjectName

    Write-LogInfo -Logger $Context.Logger -Message "Migrated legacy logic: deleting distribution group '$adObjectName'."

    if ($Context.WhatIfMode) {
        return [pscustomobject]@{
            Success      = $true
            Changed      = $true
            Simulated    = $true
            AdObjectName = $adObjectName
            Operations   = @(
                [pscustomobject]@{ Action = 'Get-DistributionGroup'; Identity = $adObjectName; Simulated = $true }
                [pscustomobject]@{ Action = 'Set-DistributionGroup-ManagedBy'; Identity = $adObjectName; Simulated = $true }
                [pscustomobject]@{ Action = 'Remove-DistributionGroup'; Identity = $adObjectName; Simulated = $true }
            )
            Message      = "WhatIf: would delete distribution group '$adObjectName'."
            ErrorCode    = $null
        }
    }

    # Step 1: Verify the distribution group exists before attempting deletion
    $distList = $null
    try {
        $distList = Get-OnPremDistributionGroupSafe -Identity $adObjectName
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error getting distribution group '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Message      = "Distribution group '$adObjectName' could not be found or read. $message"
            ErrorCode    = 'DISTRIBUTION_GROUP_GET_FAILED'
        }
    }

    if (-not $distList) {
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Message      = "Distribution group '$adObjectName' not found."
            ErrorCode    = 'DISTRIBUTION_GROUP_NOT_FOUND'
        }
    }

    # Step 2: Reassign ManagedBy to the running service account so deletion is not blocked by ownership restrictions.
    # Faithful migration: legacy script used "$env:USERDOMAIN\$env:UserName" (the IAM service account).
    try {
        $serviceOwner = "$([Environment]::UserDomainName)\$([Environment]::UserName)"
        Set-OnPremDistributionGroupSafe -Parameters @{ Identity = $adObjectName; ManagedBy = @($serviceOwner); BypassSecurityGroupManagerCheck = $true } -WhatIfMode:$false | Out-Null
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogWarn -Logger $Context.Logger -Message "Warning: failed to reassign ManagedBy before deletion of '$adObjectName'. $message"
    }

    # Step 3: Remove the distribution group
    try {
        Remove-OnPremDistributionGroupSafe -Parameters @{ Identity = $adObjectName; Confirm = $false } -WhatIfMode:$false | Out-Null
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error removing distribution group '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success      = $false
            Changed      = $false
            AdObjectName = $adObjectName
            Message      = "Failed to remove distribution group '$adObjectName'. $message"
            ErrorCode    = 'DISTRIBUTION_GROUP_DELETE_FAILED'
        }
    }

    # Note: Set-DlTenantState for the delete case was commented out in the original legacy script.
    # Ref: current-scripts/Process-DistributionsGroupJobs.ps1 — DeleteDistribList block.

    return [pscustomobject]@{
        Success      = $true
        Changed      = $true
        Simulated    = $false
        AdObjectName = $adObjectName
        Message      = "Distribution group '$adObjectName' deleted."
        ErrorCode    = $null
    }
}

Export-ModuleMember -Function @('Add-DistributionListResponsibles', 'Set-DistributionGroupManager', 'Update-DistributionGroupManagedByMembers', 'New-DistributionGroupFromRequest', 'Remove-DistributionGroupFromRequest')
