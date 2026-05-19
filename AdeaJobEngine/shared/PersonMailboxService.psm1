Set-StrictMode -Version Latest

function New-PersonMailboxResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$Success,
        [bool]$Changed = $false,
        [bool]$Simulated = $false,
        [string]$Action,
        [string]$AdObjectName,
        [string]$Message,
        [string]$ErrorCode,
        [object]$Output,
        [bool]$RetryRecommended = $false,
        [bool]$PauseRecommended = $false
    )

    [pscustomobject]@{
        Success          = $Success
        Changed          = $Changed
        Simulated        = $Simulated
        Action           = $Action
        AdObjectName     = $AdObjectName
        Message          = $Message
        ErrorCode        = $ErrorCode
        Output           = $Output
        RetryRecommended = $RetryRecommended
        PauseRecommended = $PauseRecommended
    }
}

function Get-ObjectValue {
    [CmdletBinding()]
    param([object]$Object, [string]$Name, [object]$DefaultValue = $null)
    if ($null -eq $Object) { return $DefaultValue }
    if ($Object.PSObject.Properties[$Name]) { return $Object.$Name }
    return $DefaultValue
}



function Get-ConfigValueSafe {
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

function Resolve-NonStandardPersonMailboxTargetOu {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Data,
        [string]$EmployeeType,
        [string]$ServiceAccountType
    )

    $targetOu = [string](Get-ObjectValue -Object $Data -Name 'TargetUserDomainOU')
    if ([string]::IsNullOrWhiteSpace($targetOu)) { $targetOu = [string](Get-ObjectValue -Object $Data -Name 'TargetDomainUserOU') }
    if (-not [string]::IsNullOrWhiteSpace($targetOu)) { return $targetOu }

    $actionType = [string](Get-ObjectValue -Object $Data -Name 'ActionType')
    switch ($actionType) {
        'CreateManagedServiceAccount' { return [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','ManagedServiceUserOu') -DefaultValue '') }
        'CreateServiceAccount'        { return [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','ServiceUserOu') -DefaultValue '') }
        'CreateWpaServiceAccount'     { return [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','ServiceUserOu') -DefaultValue '') }
    }

    switch ($EmployeeType) {
        'A' { return [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','AdminUserOu') -DefaultValue '') }
        'S' {
            if ($ServiceAccountType -eq 'MANAGED_SERVICE') { return [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','ManagedServiceUserOu') -DefaultValue '') }
            return [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','ServiceUserOu') -DefaultValue '')
        }
        'E' { return [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','ExternalUserOu') -DefaultValue '') }
        'HNP' { return [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','ExternalUserOu') -DefaultValue '') }
        default { return [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','InternalUserOu') -DefaultValue '') }
    }
}

function Resolve-NonStandardPersonMailboxTargetDomain {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$Data
    )

    $targetDomain = [string](Get-ObjectValue -Object $Data -Name 'TargetDomain')
    if (-not [string]::IsNullOrWhiteSpace($targetDomain)) { return $targetDomain }

    $targetDomain = [string](Get-ConfigValueSafe -Config $Context.Config -Path @('PersonMailbox','UpnDomainName') -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($targetDomain)) { return $targetDomain }

    $targetDomain = [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','UpnDomainName') -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($targetDomain)) { return $targetDomain }

    return [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ActiveDirectory','DefaultDomain') -DefaultValue '')
}

function Get-ExchangeAdministrativeGroupDnFromConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $dn = [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ExchangeOnPrem','ExchangeAdministrativeGroupDn') -DefaultValue '')
    if (-not [string]::IsNullOrWhiteSpace($dn)) { return $dn }

    $template = [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ExchangeOnPrem','ExchangeAdministrativeGroupDnTemplate') -DefaultValue '')
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

function Get-ConfiguredMailboxDatabaseCandidates {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $configured = @(Get-ConfigValueSafe -Config $Context.Config -Path @('ExchangeOnPrem','DefaultMailboxDatabases') -DefaultValue @())
    if ($configured.Count -gt 0) { return $configured }

    if ($Context.WhatIfMode) { return @() }

    $filter = [string](Get-ConfigValueSafe -Config $Context.Config -Path @('ExchangeOnPrem','MailboxDatabaseLdapFilter') -DefaultValue '')
    if ([string]::IsNullOrWhiteSpace($filter)) { return @() }

    $adminGroupDn = Get-ExchangeAdministrativeGroupDnFromConfig -Context $Context
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

function ConvertTo-LegacyPersonMailboxNamePart {
    [CmdletBinding()]
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) { return $Value }
    $result = $Value
    $replacements = @{
        '.'=''; ' ' = '-'; "'"=''; '_'='-'; '/'='-'; '\'='-';
        'ä'='ae'; 'Ä'='Ae'; 'ö'='oe'; 'Ö'='Oe'; 'ü'='ue'; 'Ü'='Ue'; 'ß'='ss';
        'à'='a'; 'á'='a'; 'â'='a'; 'ã'='a'; 'å'='a'; 'æ'='ae';
        'ç'='c'; 'è'='e'; 'é'='e'; 'ê'='e'; 'ë'='e';
        'ì'='i'; 'í'='i'; 'î'='i'; 'ï'='i';
        'ñ'='n'; 'ò'='o'; 'ó'='o'; 'ô'='o'; 'õ'='o'; 'ø'='o';
        'ù'='u'; 'ú'='u'; 'û'='u'; 'ý'='y'; 'ÿ'='y'
    }
    foreach ($key in $replacements.Keys) { $result = $result.Replace($key, $replacements[$key]) }
    return $result
}

function Get-NonStandardPersonMailboxDisplayName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Data)

    $employeeType = [string](Get-ObjectValue -Object $Data -Name 'TargetUserAdEmployeeType')
    $givenName = ConvertTo-LegacyPersonMailboxNamePart -Value ([string](Get-ObjectValue -Object $Data -Name 'TargetUserAdGivenname'))
    $surname   = ConvertTo-LegacyPersonMailboxNamePart -Value ([string](Get-ObjectValue -Object $Data -Name 'TargetUserAdSurname'))

    switch ($employeeType) {
        'S' { return ('{0} {1}' -f $givenName, $surname).Trim() }
        'A' { return ('Admin {0} {1}' -f $surname, $givenName).Trim() }
        default { return ('{0} {1}' -f $surname, $givenName).Trim() }
    }
}

function Get-NonStandardPersonMailboxLocationAttributes {
    [CmdletBinding()]
    param([string]$TargetLocation)

    switch ($TargetLocation) {
        'BH' { return [pscustomobject]@{ City='Bruderholz'; ZipCode='4101'; StreetAddress='Bruderholz' } }
        'LA' { return [pscustomobject]@{ City='Laufen'; ZipCode='4242'; StreetAddress='Lochbruggstrasse 39' } }
        'LI' { return [pscustomobject]@{ City='Liestal'; ZipCode='4410'; StreetAddress='Rheinstrasse 26' } }
        'KSBL' { return [pscustomobject]@{ City='Liestal'; ZipCode='4410'; StreetAddress='Rheinstrasse 26' } }
        default { return [pscustomobject]@{ City=$null; ZipCode=$null; StreetAddress=$null } }
    }
}

function Get-NonStandardPersonMailboxServiceAccountType {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Data)

    if ([string](Get-ObjectValue -Object $Data -Name 'TargetUserAdEmployeeType') -ne 'S') { return 'NONE' }
    switch ([string](Get-ObjectValue -Object $Data -Name 'ActionType')) {
        'CreateServiceAccount'        { 'SERVICE' }
        'CreateManagedServiceAccount' { 'MANAGED_SERVICE' }
        'CreateWpaServiceAccount'     { 'WLAN_SERVICE' }
        default                       { 'SERVICE' }
    }
}

function New-NonStandardPersonMailboxLdapFilter {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Data)

    $ldapSearchUserId = [string](Get-ObjectValue -Object $Data -Name 'LdapSearchUserId')
    if (-not [string]::IsNullOrWhiteSpace($ldapSearchUserId)) {
        return "(&(sAMAccountType=805306368)(samaccountname=$ldapSearchUserId))"
    }

    $employeeId = [string](Get-ObjectValue -Object $Data -Name 'TargetUserAdEmployeeId')
    if (-not [string]::IsNullOrWhiteSpace($employeeId)) {
        return "(&(sAMAccountType=805306368)(employeeid=$employeeId))"
    }

    $employeeType = [string](Get-ObjectValue -Object $Data -Name 'TargetUserAdEmployeeType')
    $targetAdObjectName = [string](Get-ObjectValue -Object $Data -Name 'TargetAdObjectName')
    $givenName = ConvertTo-LegacyPersonMailboxNamePart -Value ([string](Get-ObjectValue -Object $Data -Name 'TargetUserAdGivenname'))
    $surname = ConvertTo-LegacyPersonMailboxNamePart -Value ([string](Get-ObjectValue -Object $Data -Name 'TargetUserAdSurname'))
    $birthday = [string](Get-ObjectValue -Object $Data -Name 'TargetUserBirtdayDate')

    switch ($employeeType) {
        'P' {
            if (-not [string]::IsNullOrWhiteSpace($givenName) -and -not [string]::IsNullOrWhiteSpace($surname) -and -not [string]::IsNullOrWhiteSpace($birthday)) {
                return "(&(sAMAccountType=805306368)(displayName=*$surname*$givenName*)(extensionAttribute14=$birthday))"
            }
            return $null
        }
        'E' {
            if (-not [string]::IsNullOrWhiteSpace($targetAdObjectName)) { return "(&(sAMAccountType=805306368)(samaccountname=$targetAdObjectName)(employeeType=E))" }
            return $null
        }
        'A' {
            if (-not [string]::IsNullOrWhiteSpace($employeeId)) { return "(&(sAMAccountType=805306368)(employeeid=$employeeId))" }
            return $null
        }
        'HNP' {
            if (-not [string]::IsNullOrWhiteSpace($givenName) -and -not [string]::IsNullOrWhiteSpace($surname)) {
                return "(&(sAMAccountType=805306368)(displayName=*$surname*$givenName*)(employeeType=HNP))"
            }
            return $null
        }
        'S' {
            if ([string]::IsNullOrWhiteSpace($targetAdObjectName)) { return $null }
            $serviceType = Get-NonStandardPersonMailboxServiceAccountType -Data $Data
            if ($serviceType -eq 'MANAGED_SERVICE') { return "(&(sAMAccountType=805306368)(samaccountname=$targetAdObjectName`$)(employeeType=S))" }
            return "(&(sAMAccountType=805306368)(samaccountname=$targetAdObjectName)(employeeType=S))"
        }
        default { return $null }
    }
}

function New-NonStandardPersonMailboxEmailAddress {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][object]$Data)

    $domain = $null
    if ($Context.Config -and $Context.Config.ContainsKey('PersonMailbox') -and $Context.Config.PersonMailbox.ContainsKey('PrimaryMailDomain')) {
        $domain = [string]$Context.Config.PersonMailbox.PrimaryMailDomain
    }
    elseif ($Context.Config -and $Context.Config.ContainsKey('ExchangeOnPrem') -and $Context.Config.ExchangeOnPrem.ContainsKey('PrimaryMailDomain')) {
        $domain = [string]$Context.Config.ExchangeOnPrem.PrimaryMailDomain
    }
    if ([string]::IsNullOrWhiteSpace($domain)) { $domain = 'example.test' }

    $givenName = ConvertTo-LegacyPersonMailboxNamePart -Value ([string](Get-ObjectValue -Object $Data -Name 'TargetUserAdGivenname'))
    $surname = ConvertTo-LegacyPersonMailboxNamePart -Value ([string](Get-ObjectValue -Object $Data -Name 'TargetUserAdSurname'))
    if ([string]::IsNullOrWhiteSpace($givenName)) { $givenName = [string](Get-ObjectValue -Object $Data -Name 'TargetAdObjectName') }
    if ([string]::IsNullOrWhiteSpace($surname)) { $surname = 'mailbox' }
    ('{0}.{1}@{2}' -f $givenName, $surname, $domain).ToLowerInvariant()
}

function New-NonStandardPersonMailboxPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][object]$Data)

    $employeeType = [string](Get-ObjectValue -Object $Data -Name 'TargetUserAdEmployeeType')
    $targetAdObjectName = [string](Get-ObjectValue -Object $Data -Name 'TargetAdObjectName')

    $displayName = Get-NonStandardPersonMailboxDisplayName -Data $Data
    $location = Get-NonStandardPersonMailboxLocationAttributes -TargetLocation ([string](Get-ObjectValue -Object $Data -Name 'TargetLocation'))
    $ldapFilter = New-NonStandardPersonMailboxLdapFilter -Data $Data
    $serviceAccountType = Get-NonStandardPersonMailboxServiceAccountType -Data $Data
    $targetOu = Resolve-NonStandardPersonMailboxTargetOu -Context $Context -Data $Data -EmployeeType $employeeType -ServiceAccountType $serviceAccountType
    $targetDomain = Resolve-NonStandardPersonMailboxTargetDomain -Context $Context -Data $Data
    $mailboxEnableRaw = [string](Get-ObjectValue -Object $Data -Name 'MailboxEnable')
    $mailboxEnable = $false
    if (-not [string]::IsNullOrWhiteSpace($mailboxEnableRaw)) {
        $mailboxEnable = $mailboxEnableRaw -match '^(1|true|yes|ja)$'
    }

    [pscustomobject]@{
        TargetAdObjectName = $targetAdObjectName
        TargetDomain = $targetDomain
        TargetUserDomainOU = $targetOu
        DisplayName = $displayName
        GivenName = ConvertTo-LegacyPersonMailboxNamePart -Value ([string](Get-ObjectValue -Object $Data -Name 'TargetUserAdGivenname'))
        Surname = ConvertTo-LegacyPersonMailboxNamePart -Value ([string](Get-ObjectValue -Object $Data -Name 'TargetUserAdSurname'))
        EmployeeType = $employeeType
        ServiceAccountType = $serviceAccountType
        TargetLocation = [string](Get-ObjectValue -Object $Data -Name 'TargetLocation')
        Location = $location
        MailboxEnable = $mailboxEnable
        PrimarySmtpAddress = New-NonStandardPersonMailboxEmailAddress -Context $Context -Data $Data
        LdapFilter = $ldapFilter
        RequiresScheduledTaskPause = ($employeeType -in @('P','HNP'))
        CanUpdateExistingMatch = ($employeeType -notin @('A','E'))
        RequestedBy = [string](Get-ObjectValue -Object $Data -Name 'CurrentUserName')
        RequestedByDomain = [string](Get-ObjectValue -Object $Data -Name 'CurrentUserDomainName')
        RequestedByEmail = [string](Get-ObjectValue -Object $Data -Name 'CurrentUserEMailAddress')
        ScheduledTaskName = [string](Get-ConfigValueSafe -Config $Context.Config -Path @('PersonMailbox','ScheduledTaskName') -DefaultValue '')
        PrincipalsAllowedToRetrieveManagedPassword = [string](Get-ConfigValueSafe -Config $Context.Config -Path @('PersonMailbox','PrincipalsAllowedToRetrieveManagedPassword') -DefaultValue '')
        CloudDomain = [string](Get-ConfigValueSafe -Config $Context.Config -Path @('PersonMailbox','CloudDomain') -DefaultValue '')
        UserProfileDirectoryShares = @(Get-ConfigValueSafe -Config $Context.Config -Path @('PersonMailbox','UserProfileDirectoryShares') -DefaultValue @())
    }
}

function Resolve-NonStandardPersonMailboxExistingAccount {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][object]$Plan)

    if ([string]::IsNullOrWhiteSpace($Plan.LdapFilter)) {
        return New-PersonMailboxResult -Success $true -Changed $false -Action 'ResolveExistingAccount' -AdObjectName $Plan.TargetAdObjectName -Message 'No LDAP filter could be derived from the request.' -Output $null
    }

    if ($Context.WhatIfMode) {
        return New-PersonMailboxResult -Success $true -Changed $false -Simulated $true -Action 'ResolveExistingAccount' -AdObjectName $Plan.TargetAdObjectName -Message "WhatIf: would search AD using LDAP filter '$($Plan.LdapFilter)'." -Output $null
    }

    try {
        if (Get-Command -Name Search-AdUserByLdapFilterSafe -ErrorAction SilentlyContinue) {
            $result = Search-AdUserByLdapFilterSafe -LdapFilter $Plan.LdapFilter -Properties @('samaccountname','displayName','distinguishedName','extensionAttribute11','mail','employeeType')
            $first = @($result | Select-Object -First 1)
            return New-PersonMailboxResult -Success $true -Changed $false -Action 'ResolveExistingAccount' -AdObjectName $Plan.TargetAdObjectName -Message 'Existing account lookup completed.' -Output $first
        }
        return New-PersonMailboxResult -Success $false -Changed $false -Action 'ResolveExistingAccount' -AdObjectName $Plan.TargetAdObjectName -Message 'Search-AdUserByLdapFilterSafe is not available.' -ErrorCode 'AD_SEARCH_NOT_AVAILABLE'
    }
    catch {
        return New-PersonMailboxResult -Success $false -Changed $false -Action 'ResolveExistingAccount' -AdObjectName $Plan.TargetAdObjectName -Message $_.Exception.Message -ErrorCode 'AD_LOOKUP_FAILED'
    }
}

function Invoke-PrepareNonStandardPersonMailboxAdAccount {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][object]$Data)

    $plan = New-NonStandardPersonMailboxPlan -Context $Context -Data $Data
    $operations = @()

    $operations += [pscustomobject]@{ Action='BuildPlan'; Plan=$plan }
    $existing = Resolve-NonStandardPersonMailboxExistingAccount -Context $Context -Plan $plan
    $operations += $existing
    if (-not $existing.Success) { return $existing }

    if ($Context.WhatIfMode) {
        if ($plan.RequiresScheduledTaskPause) {
            $operations += [pscustomobject]@{ Simulated=$true; Action='CheckScheduledTask'; ScheduledTaskName=$plan.ScheduledTaskName; Reason='Legacy script paused while the IAM user sync task was running. Framework models this as a non-blocking step.' }
        }
        if ($plan.CanUpdateExistingMatch) {
            $operations += [pscustomobject]@{ Simulated=$true; Action='UpdateExistingOrCreateAdUser'; Identity=$plan.TargetAdObjectName; DisplayName=$plan.DisplayName; OU=$plan.TargetUserDomainOU; EmployeeType=$plan.EmployeeType }
        }
        else {
            $operations += [pscustomobject]@{ Simulated=$true; Action='CreateAdUser'; Identity=$plan.TargetAdObjectName; DisplayName=$plan.DisplayName; OU=$plan.TargetUserDomainOU; EmployeeType=$plan.EmployeeType }
        }
        if ($plan.EmployeeType -eq 'HNP') {
            $operations += [pscustomobject]@{ Simulated=$true; Action='ApplyHnpAttributes'; PasswordNeverExpires=$true; Title='Hausarzt'; AccountExpirationDate='yesterday' }
        }
        if ($plan.ServiceAccountType -eq 'MANAGED_SERVICE') {
            $operations += [pscustomobject]@{ Simulated=$true; Action='CreateOrUpdateGroupManagedServiceAccount'; Identity=$plan.TargetAdObjectName; Path=$plan.TargetUserDomainOU; PrincipalsAllowedToRetrieveManagedPassword=$plan.PrincipalsAllowedToRetrieveManagedPassword }
        }
        if ($plan.EmployeeType -in @('P','E','HNP')) {
            $operations += [pscustomobject]@{ Simulated=$true; Action='SetBadgeAttributes'; Identity=$plan.TargetAdObjectName }
        }
        return New-PersonMailboxResult -Success $true -Changed $true -Simulated $true -Action 'PrepareAdAccount' -AdObjectName $plan.TargetAdObjectName -Message "WhatIf: would prepare non-standard person AD account '$($plan.TargetAdObjectName)'." -Output $operations
    }

    try {
        # The legacy script either updated a matching resource-forest account or created a new external account.
        # The framework keeps this as a controlled service operation and delegates all writes to AD gateways.
        $description = "Erstellt/aktualisiert am $(Get-Date -Format 'yyyy-MM-dd') von $($plan.RequestedBy)"
        $existingUser = $null
        try { $existingUser = Get-AdUserBySamAccountNameSafe -SamAccountName $plan.TargetAdObjectName -Properties @('distinguishedName') } catch { $existingUser = $null }

        if ($existingUser) {
            Set-AdUserSafe -Parameters @{ Identity=$plan.TargetAdObjectName; DisplayName=$plan.DisplayName; GivenName=$plan.GivenName; Surname=$plan.Surname; Description=$description; Replace=@{ employeeType=$plan.EmployeeType } } -WhatIfMode:$false | Out-Null
        }
        else {
            $password = New-RandomPassword -Length 20 -MinSpecial 2 | ConvertTo-SecureString -AsPlainText -Force
            $params = @{ Name=$plan.TargetAdObjectName; SamAccountName=$plan.TargetAdObjectName; DisplayName=$plan.DisplayName; GivenName=$plan.GivenName; Surname=$plan.Surname; AccountPassword=$password; Enabled=$true; Description=$description }
            if (-not [string]::IsNullOrWhiteSpace($plan.TargetDomain)) { $params['UserPrincipalName'] = "$($plan.TargetAdObjectName)@$($plan.TargetDomain)" }
            if (-not [string]::IsNullOrWhiteSpace($plan.TargetUserDomainOU)) { $params['Path'] = $plan.TargetUserDomainOU }
            New-AdUserSafe -Parameters $params -WhatIfMode:$false | Out-Null
            Set-AdUserSafe -Parameters @{ Identity=$plan.TargetAdObjectName; Replace=@{ employeeType=$plan.EmployeeType } } -WhatIfMode:$false | Out-Null
        }

        if ($plan.Location.City) { Set-AdUserSafe -Parameters @{ Identity=$plan.TargetAdObjectName; City=$plan.Location.City; PostalCode=$plan.Location.ZipCode; StreetAddress=$plan.Location.StreetAddress } -WhatIfMode:$false | Out-Null }
        if ($plan.EmployeeType -eq 'HNP') {
            Set-AdUserSafe -Parameters @{ Identity=$plan.TargetAdObjectName; PasswordNeverExpires=$true; Title='Hausarzt'; AccountExpirationDate=(Get-Date).AddDays(-1) } -WhatIfMode:$false | Out-Null
        }
        if ($plan.EmployeeType -in @('P','E','HNP')) {
            Set-AdUserSafe -Parameters @{ Identity=$plan.TargetAdObjectName; Replace=@{ hrmsBadgeFirstName=$plan.GivenName; hrmsBadgeLastName=$plan.Surname } } -WhatIfMode:$false | Out-Null
        }

        return New-PersonMailboxResult -Success $true -Changed $true -Action 'PrepareAdAccount' -AdObjectName $plan.TargetAdObjectName -Message "Prepared non-standard person AD account '$($plan.TargetAdObjectName)'." -Output $operations
    }
    catch {
        return New-PersonMailboxResult -Success $false -Changed $false -Action 'PrepareAdAccount' -AdObjectName $plan.TargetAdObjectName -Message $_.Exception.Message -ErrorCode 'PERSONMAILBOX_AD_PREPARE_FAILED'
    }
}

function Invoke-PrepareNonStandardPersonMailboxMailbox {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][object]$Data)

    $plan = New-NonStandardPersonMailboxPlan -Context $Context -Data $Data
    if (-not $plan.MailboxEnable) {
        return New-PersonMailboxResult -Success $true -Changed $false -Action 'PrepareMailbox' -AdObjectName $plan.TargetAdObjectName -Message 'MailboxEnable is false; mailbox preparation skipped.' -Output @{ MailboxEnable = $false }
    }

    $dbs = @(Get-ConfiguredMailboxDatabaseCandidates -Context $Context)
    $selectedDb = if ($dbs.Count -gt 0) { $dbs | Get-Random } else { $null }

    if ($Context.WhatIfMode) {
        $ops = @([pscustomobject]@{ Simulated=$true; Action='Enable-Mailbox'; Identity=$plan.TargetAdObjectName; Database=$selectedDb; PrimarySmtpAddress=$plan.PrimarySmtpAddress; DisplayName=$plan.DisplayName })
        return New-PersonMailboxResult -Success $true -Changed $true -Simulated $true -Action 'PrepareMailbox' -AdObjectName $plan.TargetAdObjectName -Message "WhatIf: would enable mailbox '$($plan.TargetAdObjectName)' with primary SMTP '$($plan.PrimarySmtpAddress)'." -Output $ops
    }

    try {
        $params = @{ Identity=$plan.TargetAdObjectName; PrimarySmtpAddress=$plan.PrimarySmtpAddress; DisplayName=$plan.DisplayName }
        if (-not [string]::IsNullOrWhiteSpace($selectedDb)) { $params['Database'] = $selectedDb }
        Enable-OnPremMailboxSafe -Parameters $params -WhatIfMode:$false | Out-Null
        return New-PersonMailboxResult -Success $true -Changed $true -Action 'PrepareMailbox' -AdObjectName $plan.TargetAdObjectName -Message "Mailbox enabled for '$($plan.TargetAdObjectName)'." -Output $params
    }
    catch {
        return New-PersonMailboxResult -Success $false -Changed $false -Action 'PrepareMailbox' -AdObjectName $plan.TargetAdObjectName -Message $_.Exception.Message -ErrorCode 'PERSONMAILBOX_MAILBOX_PREPARE_FAILED'
    }
}

function Test-NonStandardPersonMailboxVisibility {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][object]$Data)

    $plan = New-NonStandardPersonMailboxPlan -Context $Context -Data $Data
    if (-not $plan.MailboxEnable) {
        return New-PersonMailboxResult -Success $true -Changed $false -Action 'TestMailboxVisibility' -AdObjectName $plan.TargetAdObjectName -Message 'MailboxEnable is false; mailbox visibility is not required.' -Output @{ IsVisible = $true; MailboxEnable = $false }
    }

    if ($Context.WhatIfMode) {
        return New-PersonMailboxResult -Success $true -Changed $false -Simulated $true -Action 'TestMailboxVisibility' -AdObjectName $plan.TargetAdObjectName -Message "WhatIf: assuming mailbox '$($plan.TargetAdObjectName)' is visible." -Output @{ IsVisible = $true; Simulated = $true }
    }

    try {
        $mailbox = Get-OnPremMailboxSafe -Identity $plan.TargetAdObjectName
        if ($mailbox) {
            return New-PersonMailboxResult -Success $true -Changed $false -Action 'TestMailboxVisibility' -AdObjectName $plan.TargetAdObjectName -Message 'Mailbox is visible.' -Output @{ IsVisible = $true; Mailbox = $mailbox }
        }
        return New-PersonMailboxResult -Success $true -Changed $false -Action 'TestMailboxVisibility' -AdObjectName $plan.TargetAdObjectName -Message 'Mailbox is not visible yet.' -Output @{ IsVisible = $false } -RetryRecommended $true
    }
    catch {
        return New-PersonMailboxResult -Success $true -Changed $false -Action 'TestMailboxVisibility' -AdObjectName $plan.TargetAdObjectName -Message 'Mailbox is not visible yet.' -Output @{ IsVisible = $false; Error = $_.Exception.Message } -RetryRecommended $true
    }
}

function Invoke-ApplyNonStandardPersonMailboxAttributes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][object]$Data)

    $plan = New-NonStandardPersonMailboxPlan -Context $Context -Data $Data
    $ops = @()

    if ($Context.WhatIfMode) {
        $ops += [pscustomobject]@{ Simulated=$true; Action='Set-ADUser'; Identity=$plan.TargetAdObjectName; Enabled=$true; DisplayName=$plan.DisplayName; Location=$plan.Location }
        if ($plan.MailboxEnable) {
            $ops += [pscustomobject]@{ Simulated=$true; Action='Set-Mailbox'; Identity=$plan.TargetAdObjectName; HiddenFromAddressListsEnabled=$false }
            $ops += [pscustomobject]@{ Simulated=$true; Action='Set-MailboxJunkEmailConfiguration'; Identity=$plan.TargetAdObjectName; Enabled=$false }
            if ($plan.TargetAdObjectName.StartsWith('us')) { $ops += [pscustomobject]@{ Simulated=$true; Action='Set-CASMailbox'; Identity=$plan.TargetAdObjectName; OWAEnabled=$true; ActiveSyncEnabled=$true } }
        }
        return New-PersonMailboxResult -Success $true -Changed $true -Simulated $true -Action 'ApplyMailboxAttributes' -AdObjectName $plan.TargetAdObjectName -Message "WhatIf: would apply final AD and mailbox attributes for '$($plan.TargetAdObjectName)'." -Output $ops
    }

    try {
        Enable-AdAccountSafe -Identity $plan.TargetAdObjectName -WhatIfMode:$false | Out-Null
        Set-AdUserSafe -Parameters @{ Identity=$plan.TargetAdObjectName; DisplayName=$plan.DisplayName; GivenName=$plan.GivenName; Surname=$plan.Surname } -WhatIfMode:$false | Out-Null
        if ($plan.Location.City) { Set-AdUserSafe -Parameters @{ Identity=$plan.TargetAdObjectName; City=$plan.Location.City; PostalCode=$plan.Location.ZipCode; StreetAddress=$plan.Location.StreetAddress } -WhatIfMode:$false | Out-Null }
        if ($plan.MailboxEnable) {
            $mailbox = Get-OnPremMailboxSafe -Identity $plan.TargetAdObjectName
            Set-OnPremMailboxSafe -Parameters @{ Identity=$mailbox.Identity; HiddenFromAddressListsEnabled=$false } -WhatIfMode:$false | Out-Null
            Set-OnPremMailboxJunkEmailConfigurationSafe -Parameters @{ Identity=$mailbox.Identity; Enabled=$false } -WhatIfMode:$false | Out-Null
            if ($plan.TargetAdObjectName.StartsWith('us')) { Set-OnPremCASMailboxSafe -Parameters @{ Identity=$mailbox.Identity; OWAEnabled=$true; ActiveSyncEnabled=$true } -WhatIfMode:$false | Out-Null }
        }
        return New-PersonMailboxResult -Success $true -Changed $true -Action 'ApplyMailboxAttributes' -AdObjectName $plan.TargetAdObjectName -Message "Applied non-standard person mailbox attributes for '$($plan.TargetAdObjectName)'."
    }
    catch {
        return New-PersonMailboxResult -Success $false -Changed $false -Action 'ApplyMailboxAttributes' -AdObjectName $plan.TargetAdObjectName -Message $_.Exception.Message -ErrorCode 'PERSONMAILBOX_APPLY_ATTRIBUTES_FAILED'
    }
}

function Complete-NonStandardPersonMailboxProvisioning {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][object]$Data)

    $plan = New-NonStandardPersonMailboxPlan -Context $Context -Data $Data
    if ($Context.WhatIfMode) {
        $ops = @(
            [pscustomobject]@{ Simulated=$true; Action='Update-DfsShareSettings'; Identity=$plan.TargetAdObjectName },
            [pscustomobject]@{ Simulated=$true; Action='Send-Notification'; To=$plan.RequestedByEmail; Subject="Auftrag - Erstellen eines nicht standardisierten Benutzerkontos" }
        )
        return New-PersonMailboxResult -Success $true -Changed $true -Simulated $true -Action 'Finalize' -AdObjectName $plan.TargetAdObjectName -Message "WhatIf: would finalize non-standard person mailbox provisioning for '$($plan.TargetAdObjectName)'." -Output $ops
    }

    try {
        # Migrated from current-scripts/Process-PersonMailboxJobs.ps1:
        # Update-DfsShareSettings -> Get-HomeDrive -> Set-UserHomeDirPermissions
        # -> Run-DfsUtil link add -> Set-UserApplicationDrivePermissions for
        # application and desktop shares. The technical operations are now
        # delegated to UserHomeDirectoryService / DfsGateway / FileSystemGateway.
        $finalizeData = [pscustomobject]@{
            Identity            = $plan.TargetAdObjectName
            SamAccountName      = $plan.TargetAdObjectName
            AdObjectName        = $plan.TargetAdObjectName
            TargetAdObjectName  = $plan.TargetAdObjectName
            TargetDomain        = $plan.TargetDomain
            UserPrincipalDomain = $plan.TargetDomain
        }

        $dfsResult = $null
        if ($Context.Services -and $Context.Services.PSObject.Properties['UserHomeDirectory']) {
            $dfsResult = & $Context.Services.UserHomeDirectory.UpdateDfsShares $Context $finalizeData
        }
        elseif (Get-Command -Name Update-UserLegacyDfsShareSettings -ErrorAction SilentlyContinue) {
            $dfsResult = Update-UserLegacyDfsShareSettings -Context $Context -Data $finalizeData
        }
        elseif (Get-Command -Name Update-DfsShareSettingsSafe -ErrorAction SilentlyContinue) {
            $dfsResult = Update-DfsShareSettingsSafe -SamAccountName $plan.TargetAdObjectName -Config $Context.Config -UserPrincipalDomain $plan.TargetDomain -WhatIfMode:$Context.WhatIfMode
        }
        else {
            return New-PersonMailboxResult -Success $false -Changed $false -Action 'Finalize' -AdObjectName $plan.TargetAdObjectName -Message 'No DFS/HomeDirectory finalization service is available.' -ErrorCode 'PERSONMAILBOX_DFS_FINALIZE_NOT_AVAILABLE'
        }

        if ($dfsResult -and $dfsResult.PSObject.Properties['Success'] -and -not $dfsResult.Success) {
            return New-PersonMailboxResult -Success $false -Changed $false -Action 'Finalize' -AdObjectName $plan.TargetAdObjectName -Message $dfsResult.Message -ErrorCode $dfsResult.ErrorCode -Output $dfsResult
        }

        return New-PersonMailboxResult -Success $true -Changed $true -Simulated $Context.WhatIfMode -Action 'Finalize' -AdObjectName $plan.TargetAdObjectName -Message "Finalized non-standard person mailbox provisioning for '$($plan.TargetAdObjectName)'." -Output $dfsResult
    }
    catch {
        return New-PersonMailboxResult -Success $false -Changed $false -Action 'Finalize' -AdObjectName $plan.TargetAdObjectName -Message $_.Exception.Message -ErrorCode 'PERSONMAILBOX_FINALIZE_FAILED'
    }
}

Export-ModuleMember -Function @(
    'New-PersonMailboxResult',
    'ConvertTo-LegacyPersonMailboxNamePart',
    'Get-NonStandardPersonMailboxDisplayName',
    'Get-NonStandardPersonMailboxLocationAttributes',
    'Get-NonStandardPersonMailboxServiceAccountType',
    'New-NonStandardPersonMailboxLdapFilter',
    'New-NonStandardPersonMailboxEmailAddress',
    'Resolve-NonStandardPersonMailboxTargetOu',
    'Resolve-NonStandardPersonMailboxTargetDomain',
    'Get-ConfiguredMailboxDatabaseCandidates',
    'New-NonStandardPersonMailboxPlan',
    'Resolve-NonStandardPersonMailboxExistingAccount',
    'Invoke-PrepareNonStandardPersonMailboxAdAccount',
    'Invoke-PrepareNonStandardPersonMailboxMailbox',
    'Test-NonStandardPersonMailboxVisibility',
    'Invoke-ApplyNonStandardPersonMailboxAttributes',
    'Complete-NonStandardPersonMailboxProvisioning'
)
