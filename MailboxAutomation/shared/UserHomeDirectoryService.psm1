Set-StrictMode -Version Latest

function Set-UserHomeDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # TODO: Migrate legacy logic here
    [pscustomobject]@{ Simulated = $Context.WhatIfMode; HomePath = $Data.HomePath }
}

function Set-UserHomeDirectoryPermissions {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Context, [Parameter(Mandatory = $true)][psobject]$Data)

    # TODO: Migrate legacy logic here
    [pscustomobject]@{ Simulated = $Context.WhatIfMode; Target = $Data.HomePath; User = $Data.Identity }
}

Export-ModuleMember -Function @('Set-UserHomeDirectory','Set-UserHomeDirectoryPermissions')
