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
        [string]$Authority = '',
        [string]$AdObjectName,
        [string]$Message,
        [string]$ErrorCode,
        [object]$Output
    )

    [pscustomobject]@{
        Success           = $Success
        Changed           = $Changed
        Simulated         = $Simulated
        RequiresRetry     = $false
        RetryAfterMinutes = 0
        Action            = $Action
        Authority         = $Authority
        AdObjectName      = $AdObjectName
        Message           = $Message
        ErrorCode         = $ErrorCode
        Output            = $Output
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

    if ($Context.WhatIfMode) {
        return New-UserProvisioningResult -Success $true -Changed $true -Simulated $true -Action 'EnableNonStdPersonMailbox' -AdObjectName $adObjectName -Message "WhatIf: would enable account, unhide mailbox, reset password if needed, clear Hospis2AdDeleted state and move object to configured OU if applicable."
    }

    try {
        $user = Get-AdUserBySamAccountNameSafe -SamAccountName $adObjectName -Properties @('mail','proxyAddresses','extensionAttribute6','msDS-cloudExtensionAttribute15','SamAccountName','mailNickname','AccountExpirationDate','homeMdb','extensionAttribute11','Enabled','DistinguishedName')
        if (-not $user) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'EnableNonStdPersonMailbox' -AdObjectName $adObjectName -Message "Target AD user '$adObjectName' not found." -ErrorCode 'AD_OBJECT_NOT_FOUND'
        }

        $sam                  = [string](Get-ObjectPropertyValue -Object $user -Name 'SamAccountName')
        $mailNickname         = [string](Get-ObjectPropertyValue -Object $user -Name 'mailNickname')
        $homeMdb              = Get-ObjectPropertyValue -Object $user -Name 'homeMdb'
        $extensionAttribute11 = [string](Get-ObjectPropertyValue -Object $user -Name 'extensionAttribute11')
        $isEnabled            = [bool](Get-ObjectPropertyValue -Object $user -Name 'Enabled')
        $mailAddress          = [string](Get-ObjectPropertyValue -Object $user -Name 'mail')
        $actions              = @()

        # Hybrid-Routing: resolve mailbox execution context when a mail-enabled user exists.
        # Identity: prefer mail attribute (SMTP), fall back to SamAccountName (alias-resolved on-prem).
        $resolution = $null
        $hasMailbox = (-not [string]::IsNullOrWhiteSpace($mailNickname))
        if ($hasMailbox) {
            $resolveIdentity = if (-not [string]::IsNullOrWhiteSpace($mailAddress)) { $mailAddress } else { $adObjectName }
            try {
                $resolution = Resolve-MailboxExecutionContext -Identity $resolveIdentity -Config $Context.Config
            }
            catch {
                Write-LogWarn -Logger $Context.Logger -Message "Mailbox context resolution failed for '$adObjectName': $($_.Exception.Message). Proceeding with On-Prem defaults."
            }
        }

        # Cloud-only recipients are not supported: AD-based Enable requires an on-prem AD object.
        if ($resolution -and $resolution.IsCloudOnly) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'EnableNonStdPersonMailbox' -AdObjectName $adObjectName `
                -Message "GenericUser.Enable is not supported for cloud-only (EXO-only) recipients. Identity: '$adObjectName'." `
                -ErrorCode 'CLOUD_ONLY_NOT_SUPPORTED'
        }

        # Migration transient: EXO mailbox not yet visible; defer and retry.
        if ($resolution -and $resolution.RecommendedAction -eq 'Retry') {
            $retryMinutes = if ($resolution.RetryAfterMinutes -and $resolution.RetryAfterMinutes -gt 0) { [int]$resolution.RetryAfterMinutes } else { 15 }
            return [pscustomobject]@{
                Success           = $false
                Changed           = $false
                Simulated         = $false
                RequiresRetry     = $true
                RetryAfterMinutes = $retryMinutes
                Authority         = 'OnPremExchange'
                Action            = 'EnableNonStdPersonMailbox'
                AdObjectName      = $adObjectName
                Message           = "GenericUser.Enable for '$adObjectName' deferred: $($resolution.Reason)"
                ErrorCode         = 'MAILBOX_MIGRATION_TRANSIENT'
                Output            = $null
            }
        }

        # EXO required but disabled by configuration.
        if ($resolution -and $resolution.RecommendedAction -eq 'Fail' -and
            $resolution.FeatureAuthority -eq 'ExchangeOnline' -and -not $resolution.IsCloudOnly) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'EnableNonStdPersonMailbox' -AdObjectName $adObjectName `
                -Message "GenericUser.Enable for '$adObjectName' requires Exchange Online for mailbox features, but Exchange Online is disabled by configuration." `
                -ErrorCode 'EXO_REQUIRED_BUT_DISABLED'
        }

        # === On-Prem AD operations — always executed regardless of mailbox location ===
        if ([string]::IsNullOrWhiteSpace([string]$homeMdb)) {
            # Legacy code calls EnableDisable-Mailbox and waits 30 seconds. The concrete mailbox-enable
            # implementation remains a dedicated migration task.
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

        # === Mailbox visibility routing via MailboxFeatureService ===
        # UserMailbox/SharedMailbox      → Set-Mailbox On-Prem
        # RemoteUserMailbox/SharedMailbox → Set-RemoteMailbox On-Prem (synchronized HideFromAddressLists)
        if (-not [string]::IsNullOrWhiteSpace($mailNickname)) {
            Set-MailboxVisibility -MailboxName $adObjectName -Visibility 'Unhide' -WhatIfMode:$false -Resolution $resolution | Out-Null
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

        $authority = if ($resolution -and -not [string]::IsNullOrWhiteSpace($resolution.FeatureAuthority)) { $resolution.FeatureAuthority } else { 'OnPremExchange' }
        return New-UserProvisioningResult -Success $true -Changed $true -Action 'EnableNonStdPersonMailbox' -AdObjectName $adObjectName -Authority $authority -Message "Account '$adObjectName' enable processing completed." -Output $actions
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Enable-GenericUser failed for '$adObjectName'." -Exception $_.Exception
        return New-UserProvisioningResult -Success $false -Changed $false -Action 'EnableNonStdPersonMailbox' -AdObjectName $adObjectName -Message $_.Exception.Message -ErrorCode 'ENABLE_GENERIC_USER_FAILED'
    }
}

function Disable-GenericUser {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    $adObjectName = [string]$Data.AdObjectName
    Write-LogInfo -Logger $Context.Logger -Message "Disabling non-standard person mailbox account '$adObjectName'."

    # Legacy source: current-scripts/Process-UserGenericJobs.ps1, block '*DisableNonStdPersonMailbox*_pshjob_.csv'.

    if ($Context.WhatIfMode) {
        return New-UserProvisioningResult -Success $true -Changed $true -Simulated $true -Action 'DisableNonStdPersonMailbox' -AdObjectName $adObjectName -Message "WhatIf: would disable account, mark Entra sync state as disabled, hide mailbox and update description."
    }

    try {
        $user = Get-AdUserBySamAccountNameSafe -SamAccountName $adObjectName -Properties @('mail','proxyAddresses','extensionAttribute6','msDS-cloudExtensionAttribute15','SamAccountName','mailNickname','AccountExpirationDate','homeMdb','extensionAttribute11','Enabled')
        if (-not $user) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'DisableNonStdPersonMailbox' -AdObjectName $adObjectName -Message "Target AD user '$adObjectName' not found." -ErrorCode 'AD_OBJECT_NOT_FOUND'
        }

        $sam          = [string](Get-ObjectPropertyValue -Object $user -Name 'SamAccountName')
        $mailNickname = [string](Get-ObjectPropertyValue -Object $user -Name 'mailNickname')
        $homeMdb      = Get-ObjectPropertyValue -Object $user -Name 'homeMdb'
        $isEnabled    = [bool](Get-ObjectPropertyValue -Object $user -Name 'Enabled')
        $mailAddress  = [string](Get-ObjectPropertyValue -Object $user -Name 'mail')
        $actions      = @()

        # Hybrid-Routing: resolve mailbox execution context when a mail-enabled user exists.
        $resolution = $null
        $hasMailbox = (-not [string]::IsNullOrWhiteSpace($mailNickname))
        if ($hasMailbox) {
            $resolveIdentity = if (-not [string]::IsNullOrWhiteSpace($mailAddress)) { $mailAddress } else { $adObjectName }
            try {
                $resolution = Resolve-MailboxExecutionContext -Identity $resolveIdentity -Config $Context.Config
            }
            catch {
                Write-LogWarn -Logger $Context.Logger -Message "Mailbox context resolution failed for '$adObjectName': $($_.Exception.Message). Proceeding with On-Prem defaults."
            }
        }

        # Cloud-only recipients are not supported.
        if ($resolution -and $resolution.IsCloudOnly) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'DisableNonStdPersonMailbox' -AdObjectName $adObjectName `
                -Message "GenericUser.Disable is not supported for cloud-only (EXO-only) recipients. Identity: '$adObjectName'." `
                -ErrorCode 'CLOUD_ONLY_NOT_SUPPORTED'
        }

        # Migration transient: defer and retry.
        if ($resolution -and $resolution.RecommendedAction -eq 'Retry') {
            $retryMinutes = if ($resolution.RetryAfterMinutes -and $resolution.RetryAfterMinutes -gt 0) { [int]$resolution.RetryAfterMinutes } else { 15 }
            return [pscustomobject]@{
                Success           = $false
                Changed           = $false
                Simulated         = $false
                RequiresRetry     = $true
                RetryAfterMinutes = $retryMinutes
                Authority         = 'OnPremExchange'
                Action            = 'DisableNonStdPersonMailbox'
                AdObjectName      = $adObjectName
                Message           = "GenericUser.Disable for '$adObjectName' deferred: $($resolution.Reason)"
                ErrorCode         = 'MAILBOX_MIGRATION_TRANSIENT'
                Output            = $null
            }
        }

        # EXO required but disabled by configuration.
        if ($resolution -and $resolution.RecommendedAction -eq 'Fail' -and
            $resolution.FeatureAuthority -eq 'ExchangeOnline' -and -not $resolution.IsCloudOnly) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'DisableNonStdPersonMailbox' -AdObjectName $adObjectName `
                -Message "GenericUser.Disable for '$adObjectName' requires Exchange Online for mailbox features, but Exchange Online is disabled by configuration." `
                -ErrorCode 'EXO_REQUIRED_BUT_DISABLED'
        }

        # === On-Prem AD operations — always executed regardless of mailbox location ===
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

        # === Mailbox visibility routing via MailboxFeatureService ===
        # UserMailbox/SharedMailbox       → Set-Mailbox On-Prem
        # RemoteUserMailbox/SharedMailbox → Set-RemoteMailbox On-Prem (synchronized HideFromAddressLists)
        if (-not [string]::IsNullOrWhiteSpace([string]$homeMdb) -or -not [string]::IsNullOrWhiteSpace($mailNickname)) {
            Set-MailboxVisibility -MailboxName $adObjectName -Visibility 'Hide' -WhatIfMode:$false -Resolution $resolution | Out-Null
            $actions += 'MailboxHidden'
        }

        $authority = if ($resolution -and -not [string]::IsNullOrWhiteSpace($resolution.FeatureAuthority)) { $resolution.FeatureAuthority } else { 'OnPremExchange' }
        return New-UserProvisioningResult -Success $true -Changed $true -Action 'DisableNonStdPersonMailbox' -AdObjectName $adObjectName -Authority $authority -Message "Account '$adObjectName' disable processing completed." -Output $actions
    }
    catch {
        Write-LogError -Logger $Context.Logger -Message "Disable-GenericUser failed for '$adObjectName'." -Exception $_.Exception
        return New-UserProvisioningResult -Success $false -Changed $false -Action 'DisableNonStdPersonMailbox' -AdObjectName $adObjectName -Message $_.Exception.Message -ErrorCode 'DISABLE_GENERIC_USER_FAILED'
    }
}

function Rename-GenericUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $currentUserId = [string]$Data.AdObjectName
    $targetAdObjectName = [string]$Data.TargetAdObjectName
    $newUserId = [string]$Data.NewUserId
    $givenName = [string]$Data.GivenName
    $surName = [string]$Data.SurName
    $newPrimaryEmail = [string]$Data.NewPrimaryEMailAddress

    Write-LogInfo -Logger $Context.Logger -Message "Renaming generic user '$currentUserId' to '$targetAdObjectName' / NewUserId='$newUserId'."

    # Legacy source: current-scripts/Process-UserGenericJobs.ps1, block '*RenameUserAccount*_pshjob_.csv'.
    # The legacy process renames the AD object when requested and updates naming/mail attributes.
    # Some surrounding legacy details (SQL counter update, DFS/home drive rename and customer notification)
    # remain intentionally outside this service and are documented as TODOs for dedicated migration steps.

    if ($Context.WhatIfMode) {
        return New-UserProvisioningResult `
            -Success $true `
            -Changed $true `
            -Simulated $true `
            -Action 'RenameUserAccount' `
            -AdObjectName $currentUserId `
            -Message "WhatIf: would rename '$currentUserId' to '$targetAdObjectName', update SamAccountName/NewUserId, name attributes and primary SMTP address." `
            -Output @{
                CurrentUserId = $currentUserId
                TargetAdObjectName = $targetAdObjectName
                NewUserId = $newUserId
                GivenName = $givenName
                SurName = $surName
                NewPrimaryEMailAddress = $newPrimaryEmail
            }
    }

    try {
        # Step 1: Resolve mailbox/recipient type for hybrid routing (only when email change requested)
        $resolution = $null
        if (-not [string]::IsNullOrWhiteSpace($newPrimaryEmail)) {
            try {
                $resolution = Resolve-MailboxExecutionContext -Identity $currentUserId -Config $Context.Config
            }
            catch {
                Write-LogWarn -Logger $Context.Logger -Message "Resolve-MailboxExecutionContext failed for '$currentUserId': $($_.Exception.Message). Proceeding with AD-only operations."
            }

            if ($resolution) {
                if ($resolution.IsCloudOnly) {
                    return New-UserProvisioningResult `
                        -Success $false -Changed $false `
                        -Action 'RenameUserAccount' -AdObjectName $currentUserId `
                        -Message "Cloud-only recipient '$currentUserId' is not supported by GenericUser.RenameAccount." `
                        -ErrorCode 'CLOUD_ONLY_NOT_SUPPORTED'
                }
                if ($resolution.RecommendedAction -eq 'Fail' -and $resolution.PermissionAuthority -eq 'Unknown') {
                    return New-UserProvisioningResult `
                        -Success $false -Changed $false `
                        -Action 'RenameUserAccount' -AdObjectName $currentUserId `
                        -Message "Recipient '$currentUserId' not found on-prem or in Exchange Online. Cannot update mail attributes." `
                        -ErrorCode 'RECIPIENT_NOT_FOUND'
                }
            }
        }

        # Step 2: Get AD user
        $user = Get-AdUserBySamAccountNameSafe -SamAccountName $currentUserId -Properties @(
            'mail',
            'displayName',
            'sn',
            'givenName',
            'SamAccountName',
            'DistinguishedName',
            'ObjectGUID',
            'homeDirectory'
        )

        if (-not $user) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'RenameUserAccount' -AdObjectName $currentUserId -Message "Target AD user '$currentUserId' not found." -ErrorCode 'AD_OBJECT_NOT_FOUND'
        }

        $actions = @()
        $identityForSet = $currentUserId

        # Step 3: Rename AD object if target name differs
        if (-not [string]::IsNullOrWhiteSpace($targetAdObjectName) -and $targetAdObjectName -ne 'skip' -and $targetAdObjectName -ne $currentUserId) {
            $renameIdentity = if ($user.PSObject.Properties['DistinguishedName'] -and -not [string]::IsNullOrWhiteSpace([string]$user.DistinguishedName)) {
                [string]$user.DistinguishedName
            }
            else {
                $currentUserId
            }

            Rename-AdObjectSafe -Parameters @{
                Identity = $renameIdentity
                NewName  = $targetAdObjectName
            } -WhatIfMode:$false | Out-Null

            $identityForSet = $targetAdObjectName
            $actions += 'AdObjectRenamed'
        }

        # Step 4: Update AD attributes
        $displayName = ("$givenName $surName").Trim()
        $setParams = @{
            Identity    = $identityForSet
            GivenName   = $givenName
            Surname     = $surName
            DisplayName = $displayName
        }

        if (-not [string]::IsNullOrWhiteSpace($newUserId) -and $newUserId -ne 'skip') {
            $setParams['SamAccountName'] = $newUserId
            $actions += 'SamAccountNameUpdated'
        }

        if (-not [string]::IsNullOrWhiteSpace($newPrimaryEmail)) {
            $setParams['EmailAddress'] = $newPrimaryEmail
            $setParams['UserPrincipalName'] = $newPrimaryEmail
            $actions += 'MailAttributesUpdated'
        }

        Set-AdUserSafe -Parameters $setParams -WhatIfMode:$false | Out-Null
        $actions += 'AdAttributesUpdated'

        # Step 5: Update Exchange recipient attributes if email change requested
        if (-not [string]::IsNullOrWhiteSpace($newPrimaryEmail)) {
            $mailboxParams = @{
                Identity                  = $identityForSet
                PrimarySmtpAddress        = $newPrimaryEmail
                EmailAddressPolicyEnabled = $false
            }

            $recipientType = if ($resolution -and $resolution.RecipientTypeDetails) { [string]$resolution.RecipientTypeDetails } else { '' }

            if ($recipientType -eq 'RemoteUserMailbox') {
                # Synchronized mailbox: set recipient attributes via Set-RemoteMailbox On-Prem
                Set-OnPremRemoteMailboxSafe -Parameters $mailboxParams -WhatIfMode:$false | Out-Null
                $actions += 'RemoteMailboxPrimarySmtpUpdated'
            }
            else {
                # On-Prem UserMailbox or SharedMailbox: set via Set-Mailbox
                Set-OnPremMailboxSafe -Parameters $mailboxParams -WhatIfMode:$false | Out-Null
                $actions += 'MailboxPrimarySmtpUpdated'
            }
        }

        # TODO: Migrate SQL user-id counter update, DFS/homeDirectory rename and notification logic from current-scripts/Process-UserGenericJobs.ps1.

        return New-UserProvisioningResult `
            -Success $true `
            -Changed $true `
            -Action 'RenameUserAccount' `
            -AdObjectName $currentUserId `
            -Message "Generic user '$currentUserId' rename processing completed." `
            -Output $actions
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Rename-GenericUser failed for '$currentUserId'." -Exception $_.Exception
        return New-UserProvisioningResult -Success $false -Changed $false -Action 'RenameUserAccount' -AdObjectName $currentUserId -Message $message -ErrorCode 'RENAME_GENERIC_USER_FAILED'
    }
}

function Set-GenericUserSurname {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $adObjectName = [string]$Data.AdObjectName
    $givenName = [string]$Data.GivenName
    $surName = [string]$Data.SurName
    $newPrimaryEmail = [string]$Data.NewPrimaryEMailAddress

    Write-LogInfo -Logger $Context.Logger -Message "Changing name/surname for generic user '$adObjectName'."

    # Legacy source: current-scripts/Process-UserGenericJobs.ps1, block '*ChangeAccountSurname*_pshjob_.csv'.
    # The legacy process updates AD name attributes and the mailbox primary SMTP address.

    if ($Context.WhatIfMode) {
        return New-UserProvisioningResult `
            -Success $true `
            -Changed $true `
            -Simulated $true `
            -Action 'ChangeAccountSurname' `
            -AdObjectName $adObjectName `
            -Message "WhatIf: would update GivenName, SurName, DisplayName and PrimarySmtpAddress for '$adObjectName'." `
            -Output @{
                GivenName = $givenName
                SurName = $surName
                NewPrimaryEMailAddress = $newPrimaryEmail
            }
    }

    try {
        # Resolve mailbox type for hybrid routing of Exchange operations (only when email change requested)
        $resolution = $null
        if (-not [string]::IsNullOrWhiteSpace($newPrimaryEmail)) {
            try {
                $resolution = Resolve-MailboxExecutionContext -Identity $adObjectName -Config $Context.Config
            }
            catch {
                Write-LogWarn -Logger $Context.Logger -Message "Resolve-MailboxExecutionContext failed for '$adObjectName': $($_.Exception.Message). Proceeding with AD-only changes."
            }

            if ($resolution) {
                if ($resolution.IsCloudOnly) {
                    return New-UserProvisioningResult `
                        -Success $false -Changed $false `
                        -Action 'ChangeAccountSurname' -AdObjectName $adObjectName `
                        -Message "Cloud-only recipient '$adObjectName' is not supported by GenericUser.ChangeSurname." `
                        -ErrorCode 'CLOUD_ONLY_NOT_SUPPORTED'
                }
                if ($resolution.RecommendedAction -eq 'Fail' -and $resolution.PermissionAuthority -eq 'Unknown') {
                    return New-UserProvisioningResult `
                        -Success $false -Changed $false `
                        -Action 'ChangeAccountSurname' -AdObjectName $adObjectName `
                        -Message "Recipient '$adObjectName' not found on-prem or in Exchange Online. Cannot update mail attributes." `
                        -ErrorCode 'RECIPIENT_NOT_FOUND'
                }
            }
        }

        $user = Get-AdUserBySamAccountNameSafe -SamAccountName $adObjectName -Properties @('SamAccountName','mail','displayName','sn','givenName')
        if (-not $user) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'ChangeAccountSurname' -AdObjectName $adObjectName -Message "Target AD user '$adObjectName' not found." -ErrorCode 'AD_OBJECT_NOT_FOUND'
        }

        $sam = [string](Get-ObjectPropertyValue -Object $user -Name 'SamAccountName')
        if ([string]::IsNullOrWhiteSpace($sam)) { $sam = $adObjectName }

        $displayName = ("$givenName $surName").Trim()
        $setAdParams = @{
            Identity          = $sam
            GivenName         = $givenName
            Surname           = $surName
            DisplayName       = $displayName
        }
        if (-not [string]::IsNullOrWhiteSpace($newPrimaryEmail)) {
            $setAdParams['EmailAddress']      = $newPrimaryEmail
            $setAdParams['UserPrincipalName'] = $newPrimaryEmail
        }
        Set-AdUserSafe -Parameters $setAdParams -WhatIfMode:$false | Out-Null

        if (-not [string]::IsNullOrWhiteSpace($newPrimaryEmail)) {
            $mailboxParams = @{
                Identity                  = $sam
                PrimarySmtpAddress        = $newPrimaryEmail
                EmailAddressPolicyEnabled = $false
            }

            $recipientType = if ($resolution -and $resolution.RecipientTypeDetails) { [string]$resolution.RecipientTypeDetails } else { '' }

            if ($recipientType -eq 'RemoteUserMailbox') {
                # Synchronized mailbox: set recipient attributes via Set-RemoteMailbox On-Prem
                Set-OnPremRemoteMailboxSafe -Parameters $mailboxParams -WhatIfMode:$false | Out-Null
            }
            else {
                # On-Prem UserMailbox or SharedMailbox: set via Set-Mailbox
                Set-OnPremMailboxSafe -Parameters $mailboxParams -WhatIfMode:$false | Out-Null
            }
        }

        # TODO: Migrate notification text from current-scripts/Process-UserGenericJobs.ps1.

        return New-UserProvisioningResult `
            -Success $true `
            -Changed $true `
            -Action 'ChangeAccountSurname' `
            -AdObjectName $adObjectName `
            -Message "Name and mail attributes updated for '$adObjectName'."
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Set-GenericUserSurname failed for '$adObjectName'." -Exception $_.Exception
        return New-UserProvisioningResult -Success $false -Changed $false -Action 'ChangeAccountSurname' -AdObjectName $adObjectName -Message $message -ErrorCode 'CHANGE_SURNAME_FAILED'
    }
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
    # The legacy process calls Set-Mailbox <Alias> -PrimarySmtpAddress <NewPrimaryEMailAddress>.
    # Hybrid routing: UserMailbox uses Set-Mailbox On-Prem; RemoteUserMailbox uses Set-RemoteMailbox On-Prem.
    # Cloud-only recipients return CLOUD_ONLY_NOT_SUPPORTED.

    if ($Context.WhatIfMode) {
        return [pscustomobject]@{
            Success                = $true
            Changed                = $true
            Simulated              = $true
            RequiresRetry          = $false
            RetryAfterMinutes      = 0
            Action                 = 'Set-Mailbox'
            AdObjectName           = $adObjectName
            NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy
            RequestedByDomain      = $requestedByDomain
            RequestedByEmail       = $requestedByEmail
            Parameters             = @{
                Identity                  = $adObjectName
                PrimarySmtpAddress        = $newPrimaryEmailAddress
                EmailAddressPolicyEnabled = $false
            }
            Message                = "WhatIf: would set primary SMTP address for '$adObjectName' to '$newPrimaryEmailAddress'."
            ErrorCode              = $null
        }
    }

    # Resolve mailbox location and type for hybrid routing
    $resolution = $null
    try {
        $resolution = Resolve-MailboxExecutionContext -Identity $adObjectName -Config $Context.Config
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error resolving mailbox context for '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success                = $false; Changed = $false; RequiresRetry = $false; RetryAfterMinutes = 0
            AdObjectName           = $adObjectName; NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy; RequestedByDomain = $requestedByDomain; RequestedByEmail = $requestedByEmail
            Message                = "Failed to resolve mailbox context for '$adObjectName'. $message"
            ErrorCode              = 'MAILBOX_GET_FAILED'
        }
    }

    # Handle non-Execute resolution states
    if ($resolution.IsCloudOnly) {
        return [pscustomobject]@{
            Success                = $false; Changed = $false; RequiresRetry = $false; RetryAfterMinutes = 0
            AdObjectName           = $adObjectName; NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy; RequestedByDomain = $requestedByDomain; RequestedByEmail = $requestedByEmail
            Message                = "Cloud-only recipient '$adObjectName' is not supported by GenericUser.AddEmailNickname."
            ErrorCode              = 'CLOUD_ONLY_NOT_SUPPORTED'
        }
    }

    if ($resolution.RecommendedAction -eq 'Retry') {
        return [pscustomobject]@{
            Success                = $false; Changed = $false
            RequiresRetry          = $true; RetryAfterMinutes = $resolution.RetryAfterMinutes
            AdObjectName           = $adObjectName; NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy; RequestedByDomain = $requestedByDomain; RequestedByEmail = $requestedByEmail
            Message                = $resolution.Reason
            ErrorCode              = 'MAILBOX_MIGRATION_TRANSIENT'
        }
    }

    if ($resolution.RecommendedAction -eq 'Fail') {
        $errorCode = if ($resolution.PermissionAuthority -eq 'ExchangeOnline' -and -not $resolution.IsCloudOnly) {
            'EXO_REQUIRED_BUT_DISABLED'
        }
        else {
            'RECIPIENT_NOT_FOUND'
        }
        return [pscustomobject]@{
            Success                = $false; Changed = $false; RequiresRetry = $false; RetryAfterMinutes = 0
            AdObjectName           = $adObjectName; NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy; RequestedByDomain = $requestedByDomain; RequestedByEmail = $requestedByEmail
            Message                = $resolution.Reason
            ErrorCode              = $errorCode
        }
    }

    # Execute: retrieve the mailbox object to check the current primary address
    $recipientType = if ($resolution.RecipientTypeDetails) { [string]$resolution.RecipientTypeDetails } else { '' }
    $mailbox = $null
    try {
        if ($recipientType -eq 'RemoteUserMailbox') {
            $mailbox = Get-OnPremRemoteMailboxSafe -Identity $adObjectName
        }
        else {
            $mailbox = Get-OnPremMailboxSafe -Identity $adObjectName
        }
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error getting mailbox for '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success                = $false; Changed = $false; RequiresRetry = $false; RetryAfterMinutes = 0
            AdObjectName           = $adObjectName; NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy; RequestedByDomain = $requestedByDomain; RequestedByEmail = $requestedByEmail
            Message                = "Target mailbox '$adObjectName' could not be found or read. $message"
            ErrorCode              = 'MAILBOX_GET_FAILED'
        }
    }

    if (-not $mailbox) {
        return [pscustomobject]@{
            Success                = $false; Changed = $false; RequiresRetry = $false; RetryAfterMinutes = 0
            AdObjectName           = $adObjectName; NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy; RequestedByDomain = $requestedByDomain; RequestedByEmail = $requestedByEmail
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
            Success                = $false; Changed = $false; RequiresRetry = $false; RetryAfterMinutes = 0
            AdObjectName           = $adObjectName; NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy; RequestedByDomain = $requestedByDomain; RequestedByEmail = $requestedByEmail
            Message                = "Mailbox '$adObjectName' has no current PrimarySmtpAddress."
            ErrorCode              = 'PRIMARY_SMTP_MISSING'
        }
    }

    # No-change: new address is already the current primary
    if ($currentPrimary -eq $newPrimaryEmailAddress) {
        return [pscustomobject]@{
            Success                = $true; Changed = $false; Simulated = $false; RequiresRetry = $false; RetryAfterMinutes = 0
            AdObjectName           = $adObjectName; CurrentPrimaryAddress = $currentPrimary; NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy; RequestedByDomain = $requestedByDomain; RequestedByEmail = $requestedByEmail
            Message                = "Primary SMTP address '$newPrimaryEmailAddress' is already set for '$adObjectName'. No change required."
            ErrorCode              = $null
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
        if ($recipientType -eq 'RemoteUserMailbox') {
            Set-OnPremRemoteMailboxSafe -Parameters $setParams -WhatIfMode:$false | Out-Null
        }
        else {
            Set-OnPremMailboxSafe -Parameters $setParams -WhatIfMode:$false | Out-Null
        }
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Error setting PrimarySmtpAddress for '$adObjectName'." -Exception $_.Exception
        return [pscustomobject]@{
            Success                = $false; Changed = $false; RequiresRetry = $false; RetryAfterMinutes = 0
            AdObjectName           = $adObjectName; CurrentPrimaryAddress = $currentPrimary; NewPrimaryEMailAddress = $newPrimaryEmailAddress
            RequestedBy            = $requestedBy; RequestedByDomain = $requestedByDomain; RequestedByEmail = $requestedByEmail
            Message                = "Error while setting PrimarySmtpAddress on mailbox '$adObjectName'. $message"
            ErrorCode              = 'SET_PRIMARY_SMTP_FAILED'
        }
    }

    return [pscustomobject]@{
        Success                = $true; Changed = $true; Simulated = $false; RequiresRetry = $false; RetryAfterMinutes = 0
        AdObjectName           = $adObjectName; CurrentPrimaryAddress = $currentPrimary; NewPrimaryEMailAddress = $newPrimaryEmailAddress
        RequestedBy            = $requestedBy; RequestedByDomain = $requestedByDomain; RequestedByEmail = $requestedByEmail
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
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $mailboxUserSam = [string]$Data.AdObjectName
    $delegatedUserSam = [string]$Data.DelegatedAdObjectName
    $requestedFolderName = [string]$Data.MailboxFolderName
    $aclActionType = [string]$Data.AclActionType
    $aclEntry = [string]$Data.AclEntry

    Write-LogInfo -Logger $Context.Logger -Message "Modifying mailbox folder ACE. Mailbox='$mailboxUserSam' Delegate='$delegatedUserSam' Folder='$requestedFolderName' Action='$aclActionType' Rights='$aclEntry'."

    # Legacy source: current-scripts/Process-PersonMailboxJobs.ps1, block '*ModifyMailboxFolderAce*_pshjob_.csv'.
    # The legacy process resolves both AD users, finds the mailbox calendar folder and adds/removes folder permissions.

    if ($Context.WhatIfMode) {
        return New-UserProvisioningResult `
            -Success $true `
            -Changed $true `
            -Simulated $true `
            -Action 'ModifyMailboxFolderAce' `
            -AdObjectName $mailboxUserSam `
            -Message "WhatIf: would modify mailbox folder permission '$aclEntry' for '$delegatedUserSam' on '$mailboxUserSam'." `
            -Output @{
                Mailbox = $mailboxUserSam
                Delegate = $delegatedUserSam
                Folder = $requestedFolderName
                AclActionType = $aclActionType
                AclEntry = $aclEntry
            }
    }

    try {
        $delegatedUser = Search-AdUserByLdapFilterSafe -LdapFilter "(&(sAMAccountType=805306368)(samaccountname=$mailboxUserSam))" -Properties @('mailNickname','userPrincipalName')
        $delegatingUser = Search-AdUserByLdapFilterSafe -LdapFilter "(&(sAMAccountType=805306368)(samaccountname=$delegatedUserSam))" -Properties @('mailNickname','userPrincipalName')

        if (-not $delegatedUser) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'ModifyMailboxFolderAce' -AdObjectName $mailboxUserSam -Message "Mailbox user '$mailboxUserSam' not found." -ErrorCode 'MAILBOX_USER_NOT_FOUND'
        }

        if (-not $delegatingUser) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'ModifyMailboxFolderAce' -AdObjectName $mailboxUserSam -Message "Delegated user '$delegatedUserSam' not found." -ErrorCode 'DELEGATED_USER_NOT_FOUND'
        }

        $delegateUpn = [string](Get-ObjectPropertyValue -Object $delegatingUser -Name 'userPrincipalName')
        if ([string]::IsNullOrWhiteSpace($delegateUpn)) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'ModifyMailboxFolderAce' -AdObjectName $mailboxUserSam -Message "Delegated user '$delegatedUserSam' has no userPrincipalName." -ErrorCode 'DELEGATED_USER_UPN_MISSING'
        }

        $mailbox = Get-OnPremMailboxSafe -Identity $mailboxUserSam
        if (-not $mailbox) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'ModifyMailboxFolderAce' -AdObjectName $mailboxUserSam -Message "Mailbox '$mailboxUserSam' not found." -ErrorCode 'MAILBOX_NOT_FOUND'
        }

        $mailboxAlias = if ($mailbox.PSObject.Properties['Alias'] -and -not [string]::IsNullOrWhiteSpace([string]$mailbox.Alias)) {
            [string]$mailbox.Alias
        }
        else {
            $mailboxUserSam
        }

        $folderName = $requestedFolderName
        if ([string]::IsNullOrWhiteSpace($folderName) -or $folderName -eq 'Calendar') {
            $calendarFolder = Get-OnPremMailboxFolderStatisticsSafe -Identity $mailboxAlias -FolderScope 'Calendar' | Select-Object -First 1
            if ($calendarFolder -and $calendarFolder.PSObject.Properties['Name']) {
                $folderName = [string]$calendarFolder.Name
            }
        }

        if ([string]::IsNullOrWhiteSpace($folderName)) {
            return New-UserProvisioningResult -Success $false -Changed $false -Action 'ModifyMailboxFolderAce' -AdObjectName $mailboxUserSam -Message "Could not determine mailbox folder name for '$mailboxUserSam'." -ErrorCode 'MAILBOX_FOLDER_NOT_FOUND'
        }

        $folderIdentity = "${mailboxAlias}:\$folderName"

        if ($aclActionType -eq 'RemovePermissons' -or $aclActionType -eq 'RemovePermissions' -or $aclActionType -eq 'Remove') {
            Remove-OnPremMailboxFolderPermissionSafe -Parameters @{
                Identity = $folderIdentity
                User = $delegateUpn
                Confirm = $false
            } -WhatIfMode:$false | Out-Null

            return New-UserProvisioningResult -Success $true -Changed $true -Action 'ModifyMailboxFolderAce' -AdObjectName $mailboxUserSam -Message "Mailbox folder permission removed for '$delegateUpn' on '$folderIdentity'." -Output @{ FolderIdentity = $folderIdentity; Delegate = $delegateUpn; Action = 'Remove' }
        }

        Add-OnPremMailboxFolderPermissionSafe -Parameters @{
            Identity = $folderIdentity
            User = $delegateUpn
            AccessRights = $aclEntry
        } -WhatIfMode:$false | Out-Null

        return New-UserProvisioningResult -Success $true -Changed $true -Action 'ModifyMailboxFolderAce' -AdObjectName $mailboxUserSam -Message "Mailbox folder permission '$aclEntry' added for '$delegateUpn' on '$folderIdentity'." -Output @{ FolderIdentity = $folderIdentity; Delegate = $delegateUpn; Action = 'Add'; AccessRights = $aclEntry }
    }
    catch {
        $message = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        Write-LogError -Logger $Context.Logger -Message "Set-GenericUserMailboxFolderAce failed for '$mailboxUserSam'." -Exception $_.Exception
        return New-UserProvisioningResult -Success $false -Changed $false -Action 'ModifyMailboxFolderAce' -AdObjectName $mailboxUserSam -Message $message -ErrorCode 'MODIFY_MAILBOX_FOLDER_ACE_FAILED'
    }
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
