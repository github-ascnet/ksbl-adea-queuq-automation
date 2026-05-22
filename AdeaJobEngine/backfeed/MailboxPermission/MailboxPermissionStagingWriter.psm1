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
    param(
        [Parameter(Mandatory = $true)][object]$Row,
        [Parameter(Mandatory = $true)][string]$BackfeedRunId
    )

    @{
        BackfeedRunId           = $BackfeedRunId
        SourceSystem            = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'SourceSystem' -DefaultValue '')
        PermissionType          = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'PermissionType' -DefaultValue '')
        MailboxKey              = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'MailboxKey' -DefaultValue '')
        MailboxName             = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'MailboxName' -DefaultValue '')
        TrusteeKey              = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'TrusteeKey' -DefaultValue '')
        TrusteeName             = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'TrusteeName' -DefaultValue '')
        TrusteeDomain           = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'TrusteeDomain' -DefaultValue '')
        ObjectClass             = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'ObjectClass' -DefaultValue '')
        AcePermissions          = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'AcePermissions' -DefaultValue '')
        DistinguishedName       = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'DistinguishedName' -DefaultValue '')
        ExchHideFromAddressLists = Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'ExchHideFromAddressLists'
        AdReferenceObjectGuid   = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'AdReferenceObjectGuid' -DefaultValue '')
        IsInherited             = Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'IsInherited'
        Deny                    = Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'Deny'
        AccessRights            = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'AccessRights' -DefaultValue '')
        RowHash                 = [string](Get-MailboxPermissionBackfeedPropertyValue -InputObject $Row -Name 'RowHash' -DefaultValue '')
    }
}

function Resolve-MailboxPermissionBackfeedRunId {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $candidate = ''
    if ($Context.PSObject.Properties['BackfeedRunId']) {
        $candidate = [string]$Context.BackfeedRunId
    }

    if ([string]::IsNullOrWhiteSpace($candidate) -and $Context.PSObject.Properties['CorrelationId']) {
        $candidate = [string]$Context.CorrelationId
    }

    $parsed = [guid]::Empty
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and [guid]::TryParse($candidate, [ref]$parsed)) {
        return $parsed.ToString()
    }

    [guid]::NewGuid().ToString()
}

function Get-ShouldEnsureMailboxPermissionBackfeedTable {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $config = $Context.Config
    if ($null -eq $config) { return $true }

    if ($config.PSObject.Properties['BackfeedTypes'] -and $config.BackfeedTypes.PSObject.Properties['MailboxPermission']) {
        $mailboxPermission = $config.BackfeedTypes.MailboxPermission
        if ($mailboxPermission.PSObject.Properties['EnsureBackfeedStagingTable']) {
            return [bool]$mailboxPermission.EnsureBackfeedStagingTable
        }
    }

    $true
}

function Invoke-MailboxPermissionBackfeedSqlWrite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Rows,
        [Parameter(Mandatory = $true)][string]$BackfeedRunId
    )

    $createScriptPath = Get-MailboxPermissionStagingSqlScriptPath -ScriptName 'create-stg-mailbox-permissions-backfeed.sql'
    $insertScriptPath = Get-MailboxPermissionStagingSqlScriptPath -ScriptName 'insert-stg-mailbox-permission-backfeed-row.sql'

    if (Get-ShouldEnsureMailboxPermissionBackfeedTable -Context $Context) {
        $null = Invoke-MailboxPermissionBackfeedSqlScript -Context $Context -ScriptPath $createScriptPath
    }

    $stagedCount = 0
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $parameters = ConvertTo-MailboxPermissionStagingSqlParameters -Row $row -BackfeedRunId $BackfeedRunId
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
    $backfeedRunId = Resolve-MailboxPermissionBackfeedRunId -Context $BackfeedContext

    if ($rowCount -eq 0) {
        return [pscustomobject]@{
            Success       = $true
            BackfeedRunId = $backfeedRunId
            StagedCount   = 0
            FailedCount   = 0
            Message       = "No rows to stage. BackfeedRunId=$backfeedRunId"
            ErrorCode     = $null
            Errors        = @()
        }
    }

    $stagedCount = 0
    try {
        $writeResult = Invoke-MailboxPermissionBackfeedSqlWrite -Context $BackfeedContext -Rows $Rows -BackfeedRunId $backfeedRunId
        if ($null -ne $writeResult -and $writeResult.PSObject.Properties.Name -contains 'StagedCount') {
            $stagedCount = [int]$writeResult.StagedCount
        }
        else {
            $stagedCount = $rowCount
        }

        [pscustomobject]@{
            Success       = $true
            BackfeedRunId = $backfeedRunId
            StagedCount   = $stagedCount
            FailedCount   = 0
            Message       = "Rows staged. BackfeedRunId=$backfeedRunId"
            ErrorCode     = $null
            Errors        = @()
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        $failedCount = $rowCount - $stagedCount
        if ($failedCount -lt 1) { $failedCount = 1 }

        [pscustomobject]@{
            Success       = $false
            BackfeedRunId = $backfeedRunId
            StagedCount   = $stagedCount
            FailedCount   = $failedCount
            Message       = "BackfeedRunId=$backfeedRunId; $errorMessage"
            ErrorCode     = 'MAILBOX_PERMISSION_STAGE_FAILED'
            Errors        = @([pscustomobject]@{ Message = $errorMessage; ErrorCode = 'MAILBOX_PERMISSION_STAGE_FAILED'; BackfeedRunId = $backfeedRunId })
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
    'Invoke-MailboxPermissionBackfeedSqlScript',
    'Resolve-MailboxPermissionBackfeedRunId'
)