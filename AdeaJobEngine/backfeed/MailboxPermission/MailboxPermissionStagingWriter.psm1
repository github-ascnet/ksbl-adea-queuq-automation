Set-StrictMode -Version Latest

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineRoot = Split-Path -Parent (Split-Path -Parent $moduleRoot)
Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'shared\Backfeed\BackfeedSqlScriptRunner.psm1') -Force -DisableNameChecking

function Get-MailboxPermissionStagingSqlScriptPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ScriptName)

    Join-Path -Path $engineRoot -ChildPath (Join-Path -Path 'sql\backfeed\mailbox-permission' -ChildPath $ScriptName)
}

function Get-MailboxPermissionBackfeedPropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$InputObject,
        [Parameter(Mandatory = $true)][string]$Name,
        [object]$DefaultValue = $null
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $DefaultValue
    }

    $property.Value
}

function ConvertTo-MailboxPermissionStagingSqlParameters {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Row)

    @{
        Name                    = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'MailboxName' -DefaultValue '')
        TrusteeName             = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'TrusteeName' -DefaultValue '')
        TrusteeDomain           = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'TrusteeDomain' -DefaultValue '')
        ObjectClass             = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'ObjectClass' -DefaultValue '')
        AcePermissions          = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'AcePermissions' -DefaultValue '')
        DistinguishedName       = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'DistinguishedName' -DefaultValue '')
        ExchHideFromAddressLists = Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'ExchHideFromAddressLists'
        AdReferenceObjectGuid   = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'AdReferenceObjectGuid' -DefaultValue '')
    }
}

function Get-ShouldTruncateMailboxPermissionStaging {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $config = $Context.Config
    if ($null -eq $config) { return $false }

    if ($config.PSObject.Properties['Backfeed'] -and $config.Backfeed.PSObject.Properties['TruncateMailboxPermissionStaging']) {
        return [bool]$config.Backfeed.TruncateMailboxPermissionStaging
    }

    if ($config.PSObject.Properties['BackfeedTypes'] -and $config.BackfeedTypes.PSObject.Properties['MailboxPermission']) {
        $mailboxPermission = $config.BackfeedTypes.MailboxPermission
        if ($mailboxPermission.PSObject.Properties['TruncateStagingBeforeInsert']) {
            return [bool]$mailboxPermission.TruncateStagingBeforeInsert
        }
    }

    $false
}

function Invoke-MailboxPermissionBackfeedSqlWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows
    )

    $insertScriptPath = Get-MailboxPermissionStagingSqlScriptPath -ScriptName 'insert-stg-mailbox-permission-row.sql'
    $truncateScriptPath = Get-MailboxPermissionStagingSqlScriptPath -ScriptName 'truncate-stg-mailbox-permissions.sql'

    if (Get-ShouldTruncateMailboxPermissionStaging -Context $Context) {
        $null = Invoke-MailboxPermissionBackfeedSqlScript -Context $Context -ScriptPath $truncateScriptPath
    }

    $stagedCount = 0
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $parameters = ConvertTo-MailboxPermissionStagingSqlParameters -Row $row
        $null = Invoke-MailboxPermissionBackfeedSqlScript -Context $Context -ScriptPath $insertScriptPath -Parameters $parameters
        $stagedCount++
    }

    [pscustomobject]@{ Success = $true; StagedCount = $stagedCount }
}

function Write-MailboxPermissionBackfeedStaging {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$BackfeedContext,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows
    )

    $rowCount = @($Rows).Count
    if ($rowCount -eq 0) {
        return [pscustomobject]@{
            Success     = $true
            StagedCount = 0
            FailedCount = 0
            Message     = 'No rows to stage.'
            ErrorCode   = $null
            Errors      = @()
        }
    }

    $stagedCount = 0
    try {
        $writeResult = Invoke-MailboxPermissionBackfeedSqlWrite -Context $BackfeedContext -Rows $Rows
        if ($null -ne $writeResult -and $writeResult.PSObject.Properties.Name -contains 'StagedCount') {
            $stagedCount = [int]$writeResult.StagedCount
        }
        else {
            $stagedCount = $rowCount
        }

        [pscustomobject]@{
            Success     = $true
            StagedCount = $stagedCount
            FailedCount = 0
            Message     = 'Rows staged.'
            ErrorCode   = $null
            Errors      = @()
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $failedCount = $rowCount - $stagedCount
        if ($failedCount -lt 1) { $failedCount = 1 }

        [pscustomobject]@{
            Success     = $false
            StagedCount = $stagedCount
            FailedCount = $failedCount
            Message     = $errorMessage
            ErrorCode   = 'MAILBOX_PERMISSION_STAGE_FAILED'
            Errors      = @([pscustomobject]@{ Message = $errorMessage; ErrorCode = 'MAILBOX_PERMISSION_STAGE_FAILED' })
        }
    }
}

function Invoke-MailboxPermissionBackfeedSqlScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    Invoke-BackfeedSqlScript -Context $Context -ScriptPath $ScriptPath -Parameters $Parameters
}

Export-ModuleMember -Function @(
    'Write-MailboxPermissionBackfeedStaging',
    'Invoke-MailboxPermissionBackfeedSqlWrite',
    'ConvertTo-MailboxPermissionStagingSqlParameters',
    'Invoke-MailboxPermissionBackfeedSqlScript'
)