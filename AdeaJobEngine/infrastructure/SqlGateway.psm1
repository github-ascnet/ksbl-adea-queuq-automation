Set-StrictMode -Version Latest

function New-SqlConnectionString {
    [CmdletBinding()]
    param(
        [string]$ConnectionString,
        [string]$ServerInstance,
        [string]$Database
    )

    if (-not [string]::IsNullOrWhiteSpace($ConnectionString)) {
        return $ConnectionString
    }

    if ([string]::IsNullOrWhiteSpace($ServerInstance)) {
        throw 'No SQL ConnectionString or ServerInstance configured.'
    }

    if ([string]::IsNullOrWhiteSpace($Database)) {
        $Database = 'master'
    }

    return "Server=$ServerInstance;Database=$Database;Integrated Security=True;TrustServerCertificate=True"
}

function Invoke-SqlQuerySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [string]$ConnectionString,
        [string]$ServerInstance,
        [string]$Database,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return @([pscustomobject]@{ Simulated = $true; Query = $Query; ServerInstance = $ServerInstance; Database = $Database })
    }

    $cs = New-SqlConnectionString -ConnectionString $ConnectionString -ServerInstance $ServerInstance -Database $Database

    $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
    try {
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 120
        $connection.Open()
        $reader = $command.ExecuteReader()
        $table = New-Object System.Data.DataTable
        $table.Load($reader)
        return $table
    }
    finally {
        if ($connection.State -ne 'Closed') { $connection.Close() }
        $connection.Dispose()
    }
}

function Invoke-SqlNonQuerySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [string]$ConnectionString,
        [string]$ServerInstance,
        [string]$Database,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Query = $Query; ServerInstance = $ServerInstance; Database = $Database }
    }

    $cs = New-SqlConnectionString -ConnectionString $ConnectionString -ServerInstance $ServerInstance -Database $Database

    $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
    try {
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 120
        $connection.Open()
        $affected = $command.ExecuteNonQuery()
        return [pscustomobject]@{ Success = $true; RowsAffected = $affected; Query = $Query }
    }
    finally {
        if ($connection.State -ne 'Closed') { $connection.Close() }
        $connection.Dispose()
    }
}

function Invoke-SqlNonQueryParameterizedSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [hashtable]$Parameters = @{},
        [string]$ConnectionString,
        [string]$ServerInstance,
        [string]$Database,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{
            Simulated      = $true
            Query          = $Query
            Parameters     = $Parameters
            ServerInstance = $ServerInstance
            Database       = $Database
        }
    }

    $cs = New-SqlConnectionString -ConnectionString $ConnectionString -ServerInstance $ServerInstance -Database $Database

    $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
    try {
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 120

        foreach ($parameterName in @($Parameters.Keys)) {
            $parameter = $command.CreateParameter()
            $parameter.ParameterName = "@$parameterName"
            $value = $Parameters[$parameterName]
            if ($null -eq $value) {
                $parameter.Value = [System.DBNull]::Value
            }
            else {
                $parameter.Value = $value
            }
            [void]$command.Parameters.Add($parameter)
        }

        $connection.Open()
        $affected = $command.ExecuteNonQuery()
        return [pscustomobject]@{ Success = $true; RowsAffected = $affected; Query = $Query }
    }
    finally {
        if ($connection.State -ne 'Closed') { $connection.Close() }
        $connection.Dispose()
    }
}

function Invoke-SqlQueryParameterizedSafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [hashtable]$Parameters = @{},
        [string]$ConnectionString,
        [string]$ServerInstance,
        [string]$Database,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return @([pscustomobject]@{
            Simulated      = $true
            Query          = $Query
            Parameters     = $Parameters
            ServerInstance = $ServerInstance
            Database       = $Database
        })
    }

    $cs = New-SqlConnectionString -ConnectionString $ConnectionString -ServerInstance $ServerInstance -Database $Database

    $connection = New-Object System.Data.SqlClient.SqlConnection($cs)
    try {
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 120

        foreach ($parameterName in @($Parameters.Keys)) {
            $parameter = $command.CreateParameter()
            $parameter.ParameterName = "@$parameterName"
            $value = $Parameters[$parameterName]
            if ($null -eq $value) {
                $parameter.Value = [System.DBNull]::Value
            }
            else {
                $parameter.Value = $value
            }
            [void]$command.Parameters.Add($parameter)
        }

        $connection.Open()
        $reader = $command.ExecuteReader()
        $table = New-Object System.Data.DataTable
        $table.Load($reader)
        return $table
    }
    finally {
        if ($connection.State -ne 'Closed') { $connection.Close() }
        $connection.Dispose()
    }
}

Export-ModuleMember -Function @('Invoke-SqlQuerySafe','Invoke-SqlNonQuerySafe','Invoke-SqlNonQueryParameterizedSafe','Invoke-SqlQueryParameterizedSafe','New-SqlConnectionString')
