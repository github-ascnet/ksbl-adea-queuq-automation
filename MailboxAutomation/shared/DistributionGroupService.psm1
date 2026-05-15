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
        [Parameter(Mandatory = $true)][ValidateSet('ADD','DEL')][string]$Action,
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

Export-ModuleMember -Function @('Add-DistributionListResponsibles','Set-DistributionGroupManager')
