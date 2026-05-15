Set-StrictMode -Version Latest

function Get-ObjectPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $null
}

function New-UserProvisioningResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$Success,
        [bool]$Changed = $false,
        [bool]$Simulated = $false,
        [string]$Action,
        [string]$AdObjectName,
        [string]$Message,
        [string]$ErrorCode,
        [object]$Output
    )

    [pscustomobject]@{
        Success      = $Success
        Changed      = $Changed
        Simulated    = $Simulated
        Action       = $Action
        AdObjectName = $AdObjectName
        Message      = $Message
        ErrorCode    = $ErrorCode
        Output       = $Output
    }
}

function Get-LegacyActivationPassword {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    if ($Context.Config -and $Context.Config.ContainsKey('GenericUser') -and $Context.Config.GenericUser.ContainsKey('DefaultActivationPassword')) {
        return [string]$Context.Config.GenericUser.DefaultActivationPassword
    }

    # Legacy source uses a fixed initial password. This should be moved to a secure configuration source before production use.
    # TODO: Replace legacy default password with secure secret retrieval.
    return 'P@ssw0rd4You'
}

function Get-ConfiguredUserOu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$SamAccountName
    )

    if (-not ($Context.Config -and $Context.Config.ContainsKey('ActiveDirectory'))) {
        return $null
    }

    $adConfig = $Context.Config.ActiveDirectory
    if ($SamAccountName.StartsWith('ex')) {
        if ($adConfig.ContainsKey('ExternalUserOu')) { return [string]$adConfig.ExternalUserOu }
    }
    else {
        if ($adConfig.ContainsKey('InternalUserOu')) { return [string]$adConfig.InternalUserOu }
    }

    return $null
}

function New-GenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $targetAdObjectName = [string]$Data.TargetAdObjectName
    $targetDomain = [string]$Data.TargetDomain
    $displayName = [string]$Data.TargetUserAdDisplayname
    $employeeType = [string]$Data.TargetUserAdEmployeeType
    $description = [string]$Data.Description
    $manager = [string]$Data.Manager
    $requestedBy = [string]$Data.CurrentUserName

    Write-LogInfo -Logger $Context.Logger -Message "Migrated legacy logic: creating multifunction generic user '$targetAdObjectName'."

    if ([string]::IsNullOrWhiteSpace($displayName)) {
        $displayName = $targetAdObjectName
    }

    $passwordText = $null
    if ($targetAdObjectName.Length -ge 6) {
        $passwordText = $targetAdObjectName.Substring(0,1).ToUpperInvariant() + $targetAdObjectName.Substring(1,1) + '@' + $targetAdObjectName.Substring($targetAdObjectName.Length - 5, 5)
    }
    else {
        $passwordText = ($targetAdObjectName.Substring(0,1).ToUpperInvariant() + $targetAdObjectName.Substring(1) + '@12345')
    }

    $targetOu = $null
    try { $targetOu = Get-ConfiguredUserOu -Context $Context -SamAccountName $targetAdObjectName } catch { $targetOu = $null }
    if ([string]::IsNullOrWhiteSpace($targetOu)) {
        $targetOu = $null
    }

    $homeDirectoryRoot = $null
    $homeDirectoryDrive = $null
    $applicationDirectoryShare = $null
    $desktopDirectoryShare = $null
    if ($Context.Config -and $Context.Config.ContainsKey('ActiveDirectory')) {
        $adConfig = $Context.Config.ActiveDirectory
        if ($adConfig.ContainsKey('HomeDirectory')) { $homeDirectoryRoot = $adConfig.HomeDirectory }
        if ($adConfig.ContainsKey('HomeDirectoryDrive')) { $homeDirectoryDrive = $adConfig.HomeDirectoryDrive }
        if ($adConfig.ContainsKey('ApplicationDirectoryShare')) { $applicationDirectoryShare = $adConfig.ApplicationDirectoryShare }
        if ($adConfig.ContainsKey('DesktopDirectoryShare')) { $desktopDirectoryShare = $adConfig.DesktopDirectoryShare }
    }

    $operations = @()

    if ($Context.WhatIfMode) {
        $operations += [pscustomobject]@{
            Simulated = $true
            Action = 'Get-ADUser'
            Identity = $targetAdObjectName
        }
        $operations += [pscustomobject]@{
            Simulated = $true
            Action = 'New-ADUser'
            Name = $targetAdObjectName
            SamAccountName = $targetAdObjectName
            UserPrincipalName = "$targetAdObjectName@$targetDomain"
            Path = $targetOu
            Enabled = $true
            ChangePasswordAtLogon = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($manager)) {
            $operations += [pscustomobject]@{ Simulated = $true; Action = 'Set-ADUser'; Identity = $targetAdObjectName; Manager = $manager.Split('[]')[0] }
        }
        $operations += [pscustomobject]@{ Simulated = $true; Action = 'Set-ADUser'; Identity = $targetAdObjectName; Replace = @{ employeeType = $employeeType; kisAccountName = $targetAdObjectName } }
        if (-not [string]::IsNullOrWhiteSpace($homeDirectoryRoot)) {
            $operations += [pscustomobject]@{ Simulated = $true; Action = 'Set-ADUser'; Identity = $targetAdObjectName; HomeDirectory = (Join-Path -Path $homeDirectoryRoot -ChildPath $targetAdObjectName); HomeDrive = $homeDirectoryDrive }
        }
        if (-not [string]::IsNullOrWhiteSpace($applicationDirectoryShare)) {
            $operations += [pscustomobject]@{ Simulated = $true; Action = 'Set-UserApplicationDrivePermissions'; Path = $applicationDirectoryShare; User = $targetAdObjectName }
        }
        if (-not [string]::IsNullOrWhiteSpace($desktopDirectoryShare)) {
            $operations += [pscustomobject]@{ Simulated = $true; Action = 'Set-UserApplicationDrivePermissions'; Path = $desktopDirectoryShare; User = $targetAdObjectName }
        }

        return New-UserProvisioningResult -Success $true -Changed $true -Simulated $true -Action 'CreateMultiFunctionGenericUser' -AdObjectName $targetAdObjectName -Message "WhatIf: would create multifunction generic user '$targetAdObjectName'." -Output $operations
    }

    try {
        $existing = $null
        try {
            $existing = Get-AdUserBySamAccountNameSafe -SamAccountName $targetAdObjectName -Properties @('distinguishedName')
        }
        catch {
            $existing = $null
        }

        if ($existing) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'CreateMultiFunctionGenericUser' -AdObjectName $targetAdObjectName -Message "AD user '$targetAdObjectName' already exists." -ErrorCode 'GENERIC_USER_ALREADY_EXISTS'
        }

        $password = ConvertTo-SecureString -String $passwordText -AsPlainText -Force
        $newUserParams = @{
            Name = $targetAdObjectName
            DisplayName = $targetAdObjectName
            SamAccountName = $targetAdObjectName
            AccountPassword = $password
            ChangePasswordAtLogon = $true
            UserPrincipalName = "$targetAdObjectName@$targetDomain"
            Enabled = $true
        }
        if (-not [string]::IsNullOrWhiteSpace($targetOu)) { $newUserParams['Path'] = $targetOu }

        New-AdUserSafe -Parameters $newUserParams -WhatIfMode:$false | Out-Null

        if (-not [string]::IsNullOrWhiteSpace($manager)) {
            Set-AdUserSafe -Parameters @{ Identity = $targetAdObjectName; Manager = $manager.Split('[]')[0] } -WhatIfMode:$false | Out-Null
        }

        Set-AdUserSafe -Parameters @{ Identity = $targetAdObjectName; Replace = @{ employeeType = $employeeType } } -WhatIfMode:$false | Out-Null

        $descValue = "$description - Erstellt am $(Get-Date -Format 'yyyy-MM-dd') von $requestedBy"
        Set-AdUserSafe -Parameters @{ Identity = $targetAdObjectName; Description = $descValue } -WhatIfMode:$false | Out-Null

        if (-not [string]::IsNullOrWhiteSpace($homeDirectoryRoot)) {
            Set-AdUserSafe -Parameters @{ Identity = $targetAdObjectName; HomeDirectory = (Join-Path -Path $homeDirectoryRoot -ChildPath $targetAdObjectName) } -WhatIfMode:$false | Out-Null
        }

        if (-not [string]::IsNullOrWhiteSpace($homeDirectoryDrive)) {
            Set-AdUserSafe -Parameters @{ Identity = $targetAdObjectName; HomeDrive = $homeDirectoryDrive } -WhatIfMode:$false | Out-Null
        }

        Set-AdUserSafe -Parameters @{ Identity = $targetAdObjectName; Replace = @{ kisAccountName = $targetAdObjectName } } -WhatIfMode:$false | Out-Null

        # TODO: Migrate legacy Get-HomeDrive, Set-UserHomeDirPermissions, Run-DfsUtil and application/desktop permission logic from current-scripts/Process-UserGenericJobs.ps1.
        return New-UserProvisioningResult -Success $true -Changed $true -Action 'CreateMultiFunctionGenericUser' -AdObjectName $targetAdObjectName -Message "Multifunction generic user '$targetAdObjectName' created."
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error creating multifunction generic user '$targetAdObjectName'." -Exception $_.Exception
        return New-UserProvisioningResult -Success $false -Changed $false -Action 'CreateMultiFunctionGenericUser' -AdObjectName $targetAdObjectName -Message "Error while creating multifunction generic user '$targetAdObjectName'. $message" -ErrorCode 'GENERIC_USER_CREATE_MULTIFUNCTION_FAILED'
    }
}



function Enable-GenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $adObjectName = [string]$Data.AdObjectName
    Write-LogInfo -Logger $Context.Logger -Message "Enabling non-standard person mailbox account '$adObjectName'."

    # Legacy source: current-scripts/Process-UserGenericJobs.ps1, block '*EnableNonStdPersonMailbox*_pshjob_.csv'.
    # Hybrid / Exchange Online routing is intentionally not implemented in this migration step.
    # TODO: Extend this operation for Exchange Online / RemoteMailbox scenario in a later migration step.

    if ($Context.WhatIfMode) {
        return New-UserProvisioningResult -Success $true -Changed $true -Simulated $true -Action 'EnableNonStdPersonMailbox' -AdObjectName $adObjectName -Message "WhatIf: would enable account, unhide mailbox, reset password if needed, clear Hospis2AdDeleted state and move object to configured OU if applicable."
    }

    $user = Get-AdUserBySamAccountNameSafe -SamAccountName $adObjectName -Properties @('mail','proxyAddresses','extensionAttribute6','msDS-cloudExtensionAttribute15','SamAccountName','mailNickname','AccountExpirationDate','homeMdb','extensionAttribute11','Enabled','DistinguishedName')
    if (-not $user) {
        return New-UserProvisioningResult -Success $false -Changed $false -Action 'EnableNonStdPersonMailbox' -AdObjectName $adObjectName -Message "Target AD user '$adObjectName' not found." -ErrorCode 'AD_OBJECT_NOT_FOUND'
    }

    $sam = [string](Get-ObjectPropertyValue -Object $user -Name 'SamAccountName')
    $mailNickname = [string](Get-ObjectPropertyValue -Object $user -Name 'mailNickname')
    $homeMdb = Get-ObjectPropertyValue -Object $user -Name 'homeMdb'
    $extensionAttribute11 = [string](Get-ObjectPropertyValue -Object $user -Name 'extensionAttribute11')
    $isEnabled = [bool](Get-ObjectPropertyValue -Object $user -Name 'Enabled')
    $actions = @()

    if ([string]::IsNullOrWhiteSpace([string]$homeMdb)) {
        # Legacy code calls EnableDisable-Mailbox and waits 30 seconds. The concrete mailbox-enable implementation
        # remains a dedicated migration task because it depends on the legacy helper function.
        # TODO: Migrate legacy EnableDisable-Mailbox implementation here from current-scripts/Process-UserGenericJobs.ps1.
        $actions += 'MailboxEnablePendingLegacyMigration'
    }

    if (-not $isEnabled) {
        $password = ConvertTo-SecureString -AsPlainText (Get-LegacyActivationPassword -Context $Context) -Force
        Set-AdAccountPasswordSafe -Identity $sam -NewPassword $password -WhatIfMode:$false | Out-Null
        Enable-AdAccountSafe -Identity $sam -WhatIfMode:$false | Out-Null
        Set-AdUserSafe -Parameters @{ Identity = $sam; ChangePasswordAtLogon = $true } -WhatIfMode:$false | Out-Null
        Set-AdUserSafe -Parameters @{ Identity = $sam; Description = "Aktiviert am $(Get-Date -Format 'yyyy-MM-dd') von $($Data.CurrentUserName)" } -WhatIfMode:$false | Out-Null
        $actions += 'AccountEnabled'
    }
    else {
        $actions += 'AccountAlreadyEnabled'
    }

    if (-not [string]::IsNullOrWhiteSpace($mailNickname)) {
        Set-MailboxVisibility -MailboxName $adObjectName -Visibility 'Unhide' -WhatIfMode:$false | Out-Null
        $actions += 'MailboxUnhidden'
    }

    if ($extensionAttribute11 -eq 'Hospis2AdDeleted') {
        Update-DfsShareSettingsSafe -SamAccountName $adObjectName -WhatIfMode:$false | Out-Null
        Set-AdUserSafe -Parameters @{ Identity = $sam; Clear = 'extensionAttribute11' } -WhatIfMode:$false | Out-Null
        $actions += 'Hospis2AdDeletedCleared'

        $targetOu = Get-ConfiguredUserOu -Context $Context -SamAccountName $adObjectName
        if (-not [string]::IsNullOrWhiteSpace($targetOu)) {
            $dn = [string](Get-ObjectPropertyValue -Object $user -Name 'DistinguishedName')
            if (-not [string]::IsNullOrWhiteSpace($dn)) {
                Move-AdObjectSafe -Identity $dn -TargetPath $targetOu -WhatIfMode:$false | Out-Null
                $actions += 'MovedToConfiguredOu'
            }
        }
        else {
            $actions += 'MoveOuSkippedMissingConfiguration'
        }
    }

    return New-UserProvisioningResult -Success $true -Changed $true -Action 'EnableNonStdPersonMailbox' -AdObjectName $adObjectName -Message "Account '$adObjectName' enable processing completed." -Output $actions
}

function Disable-GenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $adObjectName = [string]$Data.AdObjectName
    Write-LogInfo -Logger $Context.Logger -Message "Disabling non-standard person mailbox account '$adObjectName'."

    # Legacy source: current-scripts/Process-UserGenericJobs.ps1, block '*DisableNonStdPersonMailbox*_pshjob_.csv'.
    # TODO: Extend this operation for Exchange Online / RemoteMailbox scenario in a later migration step.

    if ($Context.WhatIfMode) {
        return New-UserProvisioningResult -Success $true -Changed $true -Simulated $true -Action 'DisableNonStdPersonMailbox' -AdObjectName $adObjectName -Message "WhatIf: would disable account, mark Entra sync state as disabled, hide mailbox and update description."
    }

    $user = Get-AdUserBySamAccountNameSafe -SamAccountName $adObjectName -Properties @('mail','proxyAddresses','extensionAttribute6','msDS-cloudExtensionAttribute15','SamAccountName','mailNickname','AccountExpirationDate','homeMdb','extensionAttribute11','Enabled')
    if (-not $user) {
        return New-UserProvisioningResult -Success $false -Changed $false -Action 'DisableNonStdPersonMailbox' -AdObjectName $adObjectName -Message "Target AD user '$adObjectName' not found." -ErrorCode 'AD_OBJECT_NOT_FOUND'
    }

    $sam = [string](Get-ObjectPropertyValue -Object $user -Name 'SamAccountName')
    $mailNickname = [string](Get-ObjectPropertyValue -Object $user -Name 'mailNickname')
    $homeMdb = Get-ObjectPropertyValue -Object $user -Name 'homeMdb'
    $isEnabled = [bool](Get-ObjectPropertyValue -Object $user -Name 'Enabled')
    $actions = @()

    if ($isEnabled) {
        Disable-AdAccountSafe -Identity $sam -WhatIfMode:$false | Out-Null
        Set-AdUserSafe -Parameters @{ Identity = $sam; Description = "Inaktiviert am $(Get-Date -Format 'yyyy-MM-dd') von $($Data.CurrentUserName)" } -WhatIfMode:$false | Out-Null
        $actions += 'AccountDisabled'

        # Legacy code calls Set-TenantState -Mode TenantDisable. The full tenant sync-control implementation is still a TODO.
        # TODO: Migrate legacy Set-TenantState TenantDisable implementation here.
        $actions += 'TenantDisablePendingLegacyMigration'
    }
    else {
        $actions += 'AccountAlreadyDisabled'
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$homeMdb) -or -not [string]::IsNullOrWhiteSpace($mailNickname)) {
        Set-MailboxVisibility -MailboxName $adObjectName -Visibility 'Hide' -WhatIfMode:$false | Out-Null
        $actions += 'MailboxHidden'
    }

    return New-UserProvisioningResult -Success $true -Changed $true -Action 'DisableNonStdPersonMailbox' -AdObjectName $adObjectName -Message "Account '$adObjectName' disable processing completed." -Output $actions
}

function Rename-GenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $params = @{ Identity = $Data.Identity; NewName = $Data.NewName }
    Rename-AdObjectSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode
}

function Set-GenericUserSurname {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $params = @{ Identity = $Data.Identity; Surname = $Data.Surname }
    Set-AdUserSafe -Parameters $params -WhatIfMode:$Context.WhatIfMode
}

function Add-GenericUserEmailNickname {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Context,

        [Parameter(Mandatory = $true)]
        [psobject]$Data
    )

    $adObjectName = [string]$Data.AdObjectName
    $newPrimaryEmailAddress = [string]$Data.NewPrimaryEMailAddress
    $requestedBy = [string]$Data.CurrentUserName
    $requestedByDomain = [string]$Data.CurrentUserDomainName
    $requestedByEmail = [string]$Data.CurrentUserEMailAddress

    Write-LogInfo -Logger $Context.Logger -Message "Adding email nickname for '$adObjectName'. RequestedBy='$requestedByDomain\$requestedBy' NewPrimarySmtpAddress='$newPrimaryEmailAddress'."

    # Legacy source: current-scripts/Process-UserGenericJobs.ps1, block '*AddEMailNickName*_pshjob_.csv'.
    # The legacy process reads the mailbox by AdObjectName, remembers the current PrimarySmtpAddress,
    # then calls Set-Mailbox <Alias> -PrimarySmtpAddress <NewPrimaryEMailAddress> -EmailAddressPolicyEnabled $false.
    # Hybrid / Exchange Online routing is intentionally not implemented in this first migration step.
    # TODO: Extend this operation for Exchange Online / RemoteMailbox scenario in a later migration step.

    if ($Context.WhatIfMode) {
        $params = @{
            Identity                  = $adObjectName
            PrimarySmtpAddress        = $newPrimaryEmailAddress
            EmailAddressPolicyEnabled = $false
        }

        return [pscustomobject]@{
            Success                 = $true
            Changed                 = $true
            Simulated               = $true
            Action                  = 'Set-Mailbox'
            AdObjectName            = $adObjectName
            NewPrimaryEMailAddress  = $newPrimaryEmailAddress
            RequestedBy             = $requestedBy
            RequestedByDomain       = $requestedByDomain
            RequestedByEmail        = $requestedByEmail
            Parameters              = $params
            Message                 = "WhatIf: would set primary SMTP address for '$adObjectName' to '$newPrimaryEmailAddress'."
            ErrorCode               = $null
        }
    }

    $mailbox = $null
    try {
        $mailbox = Get-OnPremMailboxSafe -Identity $adObjectName
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error getting mailbox for '$adObjectName'." -Exception $_.Exception

        return [pscustomobject]@{
            Success                = $false
            Changed                = $false
            AdObjectName           = $adObjectName
            NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy
            RequestedByDomain      = $requestedByDomain
            RequestedByEmail       = $requestedByEmail
            Message                = "Target mailbox '$adObjectName' could not be found or read. $message"
            ErrorCode              = 'MAILBOX_GET_FAILED'
        }
    }

    if (-not $mailbox) {
        return [pscustomobject]@{
            Success                = $false
            Changed                = $false
            AdObjectName           = $adObjectName
            NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy
            RequestedByDomain      = $requestedByDomain
            RequestedByEmail       = $requestedByEmail
            Message                = "Target mailbox '$adObjectName' not found."
            ErrorCode              = 'MAILBOX_NOT_FOUND'
        }
    }

    $currentPrimary = $null
    if ($mailbox.PSObject.Properties['PrimarySmtpAddress']) {
        $currentPrimary = [string]$mailbox.PrimarySmtpAddress
    }

    if ([string]::IsNullOrWhiteSpace($currentPrimary)) {
        return [pscustomobject]@{
            Success                = $false
            Changed                = $false
            AdObjectName           = $adObjectName
            NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy
            RequestedByDomain      = $requestedByDomain
            RequestedByEmail       = $requestedByEmail
            Message                = "Mailbox '$adObjectName' has no current PrimarySmtpAddress."
            ErrorCode              = 'PRIMARY_SMTP_MISSING'
        }
    }

    $identity = if ($mailbox.PSObject.Properties['Alias'] -and -not [string]::IsNullOrWhiteSpace([string]$mailbox.Alias)) {
        [string]$mailbox.Alias
    }
    else {
        $adObjectName
    }

    $setParams = @{
        Identity                  = $identity
        PrimarySmtpAddress        = $newPrimaryEmailAddress
        EmailAddressPolicyEnabled = $false
    }

    try {
        Set-OnPremMailboxSafe -Parameters $setParams -WhatIfMode:$false | Out-Null
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error setting PrimarySmtpAddress for '$adObjectName'." -Exception $_.Exception

        return [pscustomobject]@{
            Success                = $false
            Changed                = $false
            AdObjectName           = $adObjectName
            CurrentPrimaryAddress  = $currentPrimary
            NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy
            RequestedByDomain      = $requestedByDomain
            RequestedByEmail       = $requestedByEmail
            Message                = "Error while setting PrimarySmtpAddress on mailbox '$adObjectName'. $message"
            ErrorCode              = 'SET_PRIMARY_SMTP_FAILED'
        }
    }

    return [pscustomobject]@{
        Success                = $true
        Changed                = $true
        Simulated              = $false
        AdObjectName           = $adObjectName
        CurrentPrimaryAddress  = $currentPrimary
        NewPrimaryEMailAddress = $newPrimaryEmailAddress
        RequestedBy            = $requestedBy
        RequestedByDomain      = $requestedByDomain
        RequestedByEmail       = $requestedByEmail
        Message                = "Primary SMTP address changed from '$currentPrimary' to '$newPrimaryEmailAddress' for mailbox '$adObjectName'."
        ErrorCode              = $null
    }
}

function Enable-GenericUserWithGracePeriod {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $adObjectName = [string]$Data.AdObjectName
    $gracePeriod = [string]$Data.GracePeriod
    Write-LogInfo -Logger $Context.Logger -Message "Enabling account '$adObjectName' with grace period '$gracePeriod'."

    # Legacy source: current-scripts/Process-PersonMailboxJobs.ps1, block '*EnableAdAccountWithGracePeriod*_pshjob_.csv'.
    # TODO: Extend this operation for Exchange Online / RemoteMailbox scenario in a later migration step.

    if ($Context.WhatIfMode) {
        return New-UserProvisioningResult -Success $true -Changed $true -Simulated $true -Action 'EnableAdAccountWithGracePeriod' -AdObjectName $adObjectName -Message "WhatIf: would enable account if needed, set AccountExpirationDate to '$gracePeriod', set hrmsIsExpired and unhide mailbox."
    }

    $user = Get-AdUserBySamAccountNameSafe -SamAccountName $adObjectName -Properties @('mail','SamAccountName','AccountExpirationDate','mailNickname','Enabled')
    if (-not $user) {
        return New-UserProvisioningResult -Success $false -Changed $false -Action 'EnableAdAccountWithGracePeriod' -AdObjectName $adObjectName -Message "Target AD user '$adObjectName' not found." -ErrorCode 'AD_OBJECT_NOT_FOUND'
    }

    $sam = [string](Get-ObjectPropertyValue -Object $user -Name 'SamAccountName')
    $mailNickname = [string](Get-ObjectPropertyValue -Object $user -Name 'mailNickname')
    $isEnabled = [bool](Get-ObjectPropertyValue -Object $user -Name 'Enabled')
    $expirationDate = [datetime]$gracePeriod
    $actions = @()

    if (-not $isEnabled) {
        $password = ConvertTo-SecureString -AsPlainText (Get-LegacyActivationPassword -Context $Context) -Force
        Set-AdAccountPasswordSafe -Identity $sam -NewPassword $password -WhatIfMode:$false | Out-Null
        Enable-AdAccountSafe -Identity $sam -WhatIfMode:$false | Out-Null
        Set-AdUserSafe -Parameters @{ Identity = $sam; ChangePasswordAtLogon = $true; AccountExpirationDate = $expirationDate } -WhatIfMode:$false | Out-Null
        $actions += 'AccountEnabled'
    }
    else {
        Set-AdUserSafe -Parameters @{ Identity = $sam; AccountExpirationDate = $expirationDate } -WhatIfMode:$false | Out-Null
        $actions += 'AccountAlreadyEnabledExpirationUpdated'
    }

    Set-AdUserSafe -Parameters @{ Identity = $sam; Replace = @{ 'hrmsIsExpired' = $true } } -WhatIfMode:$false | Out-Null
    $actions += 'HrmsIsExpiredSet'

    if (-not [string]::IsNullOrWhiteSpace($mailNickname)) {
        Set-MailboxVisibility -MailboxName $mailNickname -Visibility 'Unhide' -WhatIfMode:$false | Out-Null
        $actions += 'MailboxUnhidden'
    }

    return New-UserProvisioningResult -Success $true -Changed $true -Action 'EnableAdAccountWithGracePeriod' -AdObjectName $adObjectName -Message "Account '$adObjectName' grace-period processing completed." -Output $actions
}

function Set-GenericUserMobilePhoneNumber {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $adObjectName = [string]$Data.AdObjectName
    $mobileNumber = [string]$Data.MobileNumber
    Write-LogInfo -Logger $Context.Logger -Message "Setting smsPasscodeMobile for '$adObjectName'."

    # Legacy source: current-scripts/Process-PersonMailboxJobs.ps1, block '*ModifyMobilePhoneNumber*_pshjob_.csv'.
    # It writes the incoming MobileNumber to AD attribute smsPasscodeMobile.

    if ($Context.WhatIfMode) {
        return New-UserProvisioningResult -Success $true -Changed $true -Simulated $true -Action 'ModifyMobilePhoneNumber' -AdObjectName $adObjectName -Message "WhatIf: would set smsPasscodeMobile to '$mobileNumber'."
    }

    $user = Get-AdUserBySamAccountNameSafe -SamAccountName $adObjectName -Properties @('mail','SamAccountName','extensionattribute3')
    if (-not $user) {
        return New-UserProvisioningResult -Success $false -Changed $false -Action 'ModifyMobilePhoneNumber' -AdObjectName $adObjectName -Message "Target AD user '$adObjectName' not found." -ErrorCode 'AD_OBJECT_NOT_FOUND'
    }

    $sam = [string](Get-ObjectPropertyValue -Object $user -Name 'SamAccountName')

    Set-AdUserSafe -Parameters @{
        Identity = $sam
        Replace  = @{ 'smsPasscodeMobile' = $mobileNumber }
    } -WhatIfMode:$false | Out-Null

    return New-UserProvisioningResult -Success $true -Changed $true -Action 'ModifyMobilePhoneNumber' -AdObjectName $adObjectName -Message "smsPasscodeMobile changed to '$mobileNumber' for '$adObjectName'."
}

function Set-GenericUserMailboxFolderAce {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # TODO: Migrate legacy logic here
    Add-MailboxFullAccess -Context $Context -Data ([pscustomobject]@{ MailboxIdentity = $Data.MailboxIdentity; Trustee = $Data.Trustee })
}

Export-ModuleMember -Function @(
    'New-GenericUser',
    'Enable-GenericUser',
    'Disable-GenericUser',
    'Rename-GenericUser',
    'Set-GenericUserSurname',
    'Add-GenericUserEmailNickname',
    'Enable-GenericUserWithGracePeriod',
    'Set-GenericUserMobilePhoneNumber',
    'Set-GenericUserMailboxFolderAce'
)
