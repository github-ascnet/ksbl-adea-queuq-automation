Set-StrictMode -Version Latest


function Get-HospisDataValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Data,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Data.PSObject.Properties[$Name]) {
        return [string]$Data.$Name
    }

    return ''
}

function New-HospisPersonResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$Success,
        [bool]$Changed = $false,
        [bool]$Simulated = $false,
        [string]$Action,
        [string]$PersId,
        [string]$DisplayName,
        [string]$Message,
        [string]$ErrorCode,
        [object]$Output
    )

    [pscustomobject]@{
        Success     = $Success
        Changed     = $Changed
        Simulated   = $Simulated
        Action      = $Action
        PersId      = $PersId
        DisplayName = $DisplayName
        Message     = $Message
        ErrorCode   = $ErrorCode
        Output      = $Output
    }
}

function ConvertTo-SqlLiteral {
    [CmdletBinding()]
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return '' }
    return $Value.Replace("'", "''")
}

function Get-HospisArchiveFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context
    )

    $archiveRoot = 'D:\IAM\Archive'
    if ($Context.Config -and $Context.Config.ContainsKey('Hospis') -and $Context.Config.Hospis.ContainsKey('ArchiveRoot')) {
        $archiveRoot = [string]$Context.Config.Hospis.ArchiveRoot
    }

    $fileName = [System.IO.Path]::GetFileName([string]$Context.SourceFile)
    if ([string]::IsNullOrWhiteSpace($fileName)) {
        $fileName = [System.IO.Path]::GetFileName([string]$Context.WorkingFile)
    }

    return (Join-Path -Path $archiveRoot -ChildPath $fileName)
}

function Get-HospisRequestor {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][psobject]$Data)

    return "$($Data.CurrentUserDomainName)\$($Data.CurrentUserName)"
}

function Get-HospisSqlConnectionSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $settings = @{
        ConnectionString = $null
        ServerInstance   = $null
        Database         = 'KSBL_Hospis_Staging'
    }

    if ($Context.Config -and $Context.Config.ContainsKey('Hospis')) {
        $hospis = $Context.Config.Hospis
        if ($hospis.ContainsKey('ConnectionString')) { $settings.ConnectionString = [string]$hospis.ConnectionString }
        if ($hospis.ContainsKey('SqlServerInstance')) { $settings.ServerInstance = [string]$hospis.SqlServerInstance }
        if ($hospis.ContainsKey('Database')) { $settings.Database = [string]$hospis.Database }
    }

    return $settings
}

function Invoke-HospisSqlNonQuery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$Query
    )

    $settings = Get-HospisSqlConnectionSettings -Context $Context
    Invoke-SqlNonQuerySafe -Query $Query -ConnectionString $settings.ConnectionString -ServerInstance $settings.ServerInstance -Database $settings.Database -WhatIfMode:$Context.WhatIfMode
}

function New-HospisPersonTransactionSql {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][psobject]$Data,
        [Parameter(Mandatory = $true)][string]$ArchiveFilePath
    )

    $action = Get-HospisDataValue -Data $Data -Name 'ActionType'
    $persId = ConvertTo-SqlLiteral (Get-HospisDataValue -Data $Data -Name 'PersId')
    $refUserId = ConvertTo-SqlLiteral (Get-HospisDataValue -Data $Data -Name 'RefUserId')
    $refUserDomain = ConvertTo-SqlLiteral (Get-HospisDataValue -Data $Data -Name 'RefUserDomain')
    $migrateUser = ConvertTo-SqlLiteral (Get-HospisDataValue -Data $Data -Name 'MigrateUser')
    $locationName = ConvertTo-SqlLiteral (Get-HospisDataValue -Data $Data -Name 'LocationName')
    $requestor = ConvertTo-SqlLiteral (Get-HospisRequestor -Data $Data)
    $archive = ConvertTo-SqlLiteral -Value $ArchiveFilePath

    switch -Regex ($action) {
        '^Erstellen$' {
            return "EXEC KSBL_Hospis_Staging.dbo.usp_create_erstellen_transaction '$persId','$refUserId','$refUserDomain','$requestor','$archive'"
        }
        '^Aktivieren$' {
            return "EXEC KSBL_Hospis_Staging.dbo.usp_create_aktivieren_transaction '$persId','$refUserId','$refUserDomain','$migrateUser','$requestor','$archive'"
        }
        '^(Inaktivieren|Terminieren)$' {
            return "EXEC KSBL_Hospis_Staging.dbo.usp_create_terminieren_transaction '$persId','$requestor','$archive'"
        }
        '^Standortwechsel$' {
            return "EXEC KSBL_Hospis_Staging.dbo.usp_create_standortwechsel_transaction '$persId','$refUserId','$refUserDomain','$locationName','$migrateUser','$requestor'"
        }
        '^(UebertrittM2|ÜbertrittM2)$' {
            return "EXEC KSBL_Hospis_Staging.dbo.usp_create_uebertritt_m1_to_m2_transaction '$persId','$refUserId','$refUserDomain','$archive','$requestor'"
        }
        '^(UebertrittM1|ÜbertrittM1)$' {
            return "EXEC KSBL_Hospis_Staging.dbo.usp_create_uebertritt_m2_to_m1_transaction '$persId','$refUserId','$refUserDomain','$archive','$requestor'"
        }
        default {
            throw "Unsupported HospisPerson ActionType '$action'."
        }
    }
}

function Submit-HospisPersonTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $archiveFilePath = Get-HospisArchiveFilePath -Context $Context
    $sql = New-HospisPersonTransactionSql -Data $Data -ArchiveFilePath $archiveFilePath

    Write-LogInfo -Logger $Context.Logger -Message "Submitting Hospis person transaction '$($Data.ActionType)' for PersId '$($Data.PersId)'."

    $sqlResult = Invoke-HospisSqlNonQuery -Context $Context -Query $sql

    $simulated = $false
    if ($sqlResult -and $sqlResult.PSObject.Properties['Simulated']) {
        $simulated = [bool]$sqlResult.Simulated
    }

    New-HospisPersonResult `
        -Success $true `
        -Changed $true `
        -Simulated:$simulated `
        -Action (Get-HospisDataValue -Data $Data -Name 'ActionType') `
        -PersId (Get-HospisDataValue -Data $Data -Name 'PersId') `
        -DisplayName (Get-HospisDataValue -Data $Data -Name 'DisplayName') `
        -Message "Hospis AD transaction '$($Data.ActionType)' submitted." `
        -Output @{ Sql = $sql; SqlResult = $sqlResult; ArchiveFilePath = $archiveFilePath }
}

function New-UrgentHospisInactivationSql {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][psobject]$Data)

    $persId = ConvertTo-SqlLiteral (Get-HospisDataValue -Data $Data -Name 'PersId')
    $requestor = ConvertTo-SqlLiteral (Get-HospisRequestor -Data $Data)
    return "EXEC KSBL_Hospis_Staging.dbo.usp_create_urgent_inaktivieren_transaction '$persId','$requestor'"
}

function Disable-HospisResourceForestUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][object]$User,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    $sam = [string]$User.SamAccountName
    $mailNickname = $null
    if ($User.PSObject.Properties['mailNickname']) { $mailNickname = [string]$User.mailNickname }

    $actions = @()

    $actions += Disable-AdAccountSafe -Identity $sam -WhatIfMode:$Context.WhatIfMode

    $hasMailbox = $false
    if ($User.PSObject.Properties['homeMdb'] -and -not [string]::IsNullOrWhiteSpace([string]$User.homeMdb)) {
        $hasMailbox = $true
    }

    if ($hasMailbox) {
        if (-not [string]::IsNullOrWhiteSpace($mailNickname)) {
            $actions += Set-MailboxVisibility -MailboxName $mailNickname -Visibility Hide -WhatIfMode:$Context.WhatIfMode
        }

        $autoReply = @{
            Identity       = $sam
            AutoReplyState = 'Enabled'
        }

        if ($Context.Config -and $Context.Config.ContainsKey('Hospis')) {
            if ($Context.Config.Hospis.ContainsKey('AustrittOOOExternalMessage')) {
                $autoReply['ExternalMessage'] = [string]$Context.Config.Hospis.AustrittOOOExternalMessage
            }
            if ($Context.Config.Hospis.ContainsKey('AustrittOOOInternalMessage')) {
                $autoReply['InternalMessage'] = [string]$Context.Config.Hospis.AustrittOOOInternalMessage
            }
        }

        $actions += Set-OnPremMailboxAutoReplyConfigurationSafe -Parameters $autoReply -WhatIfMode:$Context.WhatIfMode

        $revocationSql = "UPDATE [KSBL_Hospis_Staging].[dbo].[EMailRevocations] SET [ValidTo] = GetDate() WHERE [Personalnummer] = '$(ConvertTo-SqlLiteral (Get-HospisDataValue -Data $Data -Name 'PersId'))'"
        $actions += Invoke-HospisSqlNonQuery -Context $Context -Query $revocationSql
    }

    if ($User.PSObject.Properties['memberof'] -and $User.memberof) {
        foreach ($groupDn in @($User.memberof)) {
            $groupDnText = [string]$groupDn
            if ($groupDnText.StartsWith('CN=TPL-') -or
                $groupDnText.StartsWith('CN=GG-KSBL-VDI-Remote') -or
                $groupDnText.StartsWith('CN=GG-OneSign')) {

                $actions += Remove-AdGroupMemberSafe -Identity $groupDnText -Members @($sam) -ConfirmRemoval:$false -WhatIfMode:$Context.WhatIfMode
            }
        }
    }

    # Legacy source disables Entra sync by clearing extensionAttribute6 and msDS-cloudExtensionAttribute15.
    $actions += Set-AdUserSafe -Parameters @{ Identity = $sam; Clear = @('extensionAttribute6','msDS-cloudExtensionAttribute15') } -WhatIfMode:$Context.WhatIfMode
    $actions += Set-AdUserSafe -Parameters @{ Identity = $sam; Description = "Inaktiviert (Urgent) am $(Get-Date -Format 'yyyy-MM-dd') von $($Data.CurrentUserName)" } -WhatIfMode:$Context.WhatIfMode

    return [pscustomobject]@{
        SamAccountName = $sam
        HasMailbox     = $hasMailbox
        Actions        = $actions
    }
}

function Invoke-UrgentHospisPersonInactivation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][psobject]$Data
    )

    Write-LogInfo -Logger $Context.Logger -Message "Processing urgent Hospis inactivation for PersId '$($Data.PersId)'."

    $output = @{
        Users = @()
        Sql   = $null
    }

    if ($Context.WhatIfMode) {
        $simulatedUser = [pscustomobject]@{
            SamAccountName = "whatif-$($Data.PersId)"
            mailNickname   = "whatif-$($Data.PersId)"
            homeMdb        = 'WHATIF-MDB'
            memberof       = @('CN=TPL-WHATIF,OU=Groups,DC=example,DC=test')
        }
        $output.Users += Disable-HospisResourceForestUser -Context $Context -User $simulatedUser -Data $Data
    }
    else {
        $users = @(Get-AdUsersByEmployeeIdSafe -EmployeeId (Get-HospisDataValue -Data $Data -Name 'PersId') -Properties @('mail','proxyAddresses','extensionAttribute6','msDS-cloudExtensionAttribute15','SamAccountName','mailNickname','AccountExpirationDate','homeMdb','memberof','extensionAttribute11'))
        if ($users.Count -eq 0) {
            return New-HospisPersonResult -Success $false -Changed $false -Action (Get-HospisDataValue -Data $Data -Name 'ActionType') -PersId (Get-HospisDataValue -Data $Data -Name 'PersId') -DisplayName (Get-HospisDataValue -Data $Data -Name 'DisplayName') -Message "No AD user found for PersId '$($Data.PersId)'." -ErrorCode 'HOSPIS_USER_NOT_FOUND'
        }

        foreach ($user in $users) {
            $output.Users += Disable-HospisResourceForestUser -Context $Context -User $user -Data $Data
        }
    }

    if ([string]$Data.ActionType -eq 'Inaktivieren') {
        $sql = New-UrgentHospisInactivationSql -Data $Data
        $output.Sql = Invoke-HospisSqlNonQuery -Context $Context -Query $sql
    }

    New-HospisPersonResult `
        -Success $true `
        -Changed $true `
        -Simulated:$Context.WhatIfMode `
        -Action (Get-HospisDataValue -Data $Data -Name 'ActionType') `
        -PersId (Get-HospisDataValue -Data $Data -Name 'PersId') `
        -DisplayName (Get-HospisDataValue -Data $Data -Name 'DisplayName') `
        -Message "Urgent Hospis person inactivation processed." `
        -Output $output
}

Export-ModuleMember -Function @(
    'Submit-HospisPersonTransaction',
    'Invoke-UrgentHospisPersonInactivation',
    'New-HospisPersonTransactionSql',
    'New-UrgentHospisInactivationSql'
)
