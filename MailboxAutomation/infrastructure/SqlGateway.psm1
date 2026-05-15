Set-StrictMode -Version Latest

function Invoke-SqlQuerySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [string]$ConnectionString,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return @([pscustomobject]@{ Simulated = $true; Query = $Query })
    }

    # TODO: Migrate legacy logic here
    throw 'Invoke-SqlQuerySafe is a placeholder. Implement production SQL query execution.'
}

function Invoke-SqlNonQuerySafe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Query,
        [string]$ConnectionString,
        [bool]$WhatIfMode = $true
    )

    if ($WhatIfMode) {
        return [pscustomobject]@{ Simulated = $true; Query = $Query }
    }

    # TODO: Migrate legacy logic here
    throw 'Invoke-SqlNonQuerySafe is a placeholder. Implement production SQL write execution.'
}

Export-ModuleMember -Function @('Invoke-SqlQuerySafe','Invoke-SqlNonQuerySafe')
