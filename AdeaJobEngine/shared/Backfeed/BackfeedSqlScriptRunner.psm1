Set-StrictMode -Version Latest

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$engineRoot = Split-Path -Parent (Split-Path -Parent $moduleRoot)
Import-Module -Name (Join-Path -Path $engineRoot -ChildPath 'infrastructure\SqlGateway.psm1') -Force -DisableNameChecking

function Get-BackfeedSqlConnectionSettings {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context)

    $settings = @{
        ConnectionString = $null
        ServerInstance   = $null
        Database         = $null
    }

    $config = $Context.Config
    if ($null -eq $config) {
        return $settings
    }

    if ($config.PSObject.Properties['Sql']) {
        $sql = $config.Sql
        if ($sql.PSObject.Properties['ConnectionString']) { $settings.ConnectionString = [string]$sql.ConnectionString }
        if ($sql.PSObject.Properties['ServerInstance']) { $settings.ServerInstance = [string]$sql.ServerInstance }
        if ($sql.PSObject.Properties['Database']) { $settings.Database = [string]$sql.Database }
    }

    if ($config.PSObject.Properties['BackfeedSql']) {
        $backfeedSql = $config.BackfeedSql
        if ($backfeedSql.PSObject.Properties['ConnectionString']) { $settings.ConnectionString = [string]$backfeedSql.ConnectionString }
        if ($backfeedSql.PSObject.Properties['ServerInstance']) { $settings.ServerInstance = [string]$backfeedSql.ServerInstance }
        if ($backfeedSql.PSObject.Properties['Database']) { $settings.Database = [string]$backfeedSql.Database }
    }

    if ($config.PSObject.Properties['BackfeedTypes'] -and $config.BackfeedTypes.PSObject.Properties['MailboxPermission']) {
        $mailboxPermission = $config.BackfeedTypes.MailboxPermission
        if ($mailboxPermission.PSObject.Properties['Sql']) {
            $mailboxPermissionSql = $mailboxPermission.Sql
            if ($mailboxPermissionSql.PSObject.Properties['ConnectionString']) { $settings.ConnectionString = [string]$mailboxPermissionSql.ConnectionString }
            if ($mailboxPermissionSql.PSObject.Properties['ServerInstance']) { $settings.ServerInstance = [string]$mailboxPermissionSql.ServerInstance }
            if ($mailboxPermissionSql.PSObject.Properties['Database']) { $settings.Database = [string]$mailboxPermissionSql.Database }
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$settings.Database)) {
        if ($config.PSObject.Properties['Hospis'] -and $config.Hospis.PSObject.Properties['Database']) {
            $settings.Database = [string]$config.Hospis.Database
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$settings.ServerInstance)) {
        if ($config.PSObject.Properties['Hospis'] -and $config.Hospis.PSObject.Properties['SqlServerInstance']) {
            $settings.ServerInstance = [string]$config.Hospis.SqlServerInstance
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$settings.ConnectionString)) {
        if ($config.PSObject.Properties['Hospis'] -and $config.Hospis.PSObject.Properties['ConnectionString']) {
            $settings.ConnectionString = [string]$config.Hospis.ConnectionString
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$settings.Database)) {
        $settings.Database = 'master'
    }

    $settings
}

function Invoke-BackfeedSqlScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    if (-not (Test-Path -Path $ScriptPath)) {
        throw "SQL script not found: $ScriptPath"
    }

    $query = Get-Content -Path $ScriptPath -Raw
    $settings = Get-BackfeedSqlConnectionSettings -Context $Context

    Invoke-SqlNonQueryParameterizedSafe -Query $query -Parameters $Parameters -ConnectionString $settings.ConnectionString -ServerInstance $settings.ServerInstance -Database $settings.Database -WhatIfMode:$Context.WhatIfMode
}

function Invoke-BackfeedSqlQueryScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Context,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [hashtable]$Parameters = @{}
    )

    if (-not (Test-Path -Path $ScriptPath)) {
        throw "SQL script not found: $ScriptPath"
    }

    $query = Get-Content -Path $ScriptPath -Raw
    $settings = Get-BackfeedSqlConnectionSettings -Context $Context

    Invoke-SqlQueryParameterizedSafe -Query $query -Parameters $Parameters -ConnectionString $settings.ConnectionString -ServerInstance $settings.ServerInstance -Database $settings.Database -WhatIfMode:$Context.WhatIfMode
}

Export-ModuleMember -Function @(
    'Get-BackfeedSqlConnectionSettings',
    'Invoke-BackfeedSqlScript',
    'Invoke-BackfeedSqlQueryScript'
)
